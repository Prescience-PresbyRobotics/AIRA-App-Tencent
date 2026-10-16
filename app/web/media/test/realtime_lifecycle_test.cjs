// Contract/lifecycle mocks exercise real adapter code; they do not claim a provider call.
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../ELEVENLABS-ASSETS.json')));
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname, '../vendor/elevenlabs-client-1.28.0.js'))).digest('hex'), manifest.bundleSha256, 'published SDK bundle hash');
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return {promise,resolve,reject}; };
const flush = async () => { for (let i=0;i<20;i++) await Promise.resolve(); };
function harness({latePermission=false, lateConnect=false, denied=null, outputSupport=true}={}) {
  const permission=deferred(), connection=deferred();
  const makeTrack = (id, label) => {
    const listeners = {};
    return {enabled:true,muted:false,stopped:false,readyState:'live',label,
      getSettings:()=>({deviceId:id}),
      // Per MediaStreamTrack: programmatic stop does NOT dispatch ended.
      stop(){this.stopped=true;this.readyState='ended';},
      addEventListener(type, callback){listeners[type]=callback;},
      unplug(){this.readyState='ended';listeners.ended?.();}};
  };
  const preliminary=makeTrack('permission','Permission stream');
  const track=makeTrack('built-in','Built-in microphone');
  let alternate=makeTrack('headset','Headset microphone');
  const stream=t=>({getTracks:()=>[t],getAudioTracks:()=>[t]});
  let options, requests=0, ends=0, muted=false, volume=1, input=.23, output=.51, switchOptions, outputOptions;
  const instance={getId:()=> 'provider-conversation',setMicMuted:v=>{muted=v;},setVolume:v=>{volume=v.volume;},
    getInputVolume:()=>input,getOutputVolume:()=>output,
    changeInputDevice:async config=>{switchOptions=config;if(config.inputDeviceId==='unavailable')throw new Error('Unavailable');const next=await devices.getUserMedia({audio:{deviceId:{exact:config.inputDeviceId}}});track.stop();return next;},
    changeOutputDevice:async config=>{outputOptions=config;if(config.outputDeviceId==='unavailable')throw new Error('Unavailable');},
    endSession:async()=>{ends++;},sendUserActivity(){}};
  const deviceListeners = {};
  const devices={
    getUserMedia:()=>{requests++;if(denied)return Promise.reject(denied);if(requests>2 && alternate.readyState==='ended')alternate=makeTrack('headset','Headset microphone');return latePermission&&requests===1?permission.promise:Promise.resolve(stream(requests===1?preliminary:requests===2?track:alternate));},
    enumerateDevices:async()=>[{kind:'audioinput',deviceId:'built-in',label:'Built-in microphone'},{kind:'audioinput',deviceId:'headset',label:'Headset microphone'},{kind:'audiooutput',deviceId:'speakers',label:'Desk speakers'},{kind:'audiooutput',deviceId:'headphones',label:'Headphones'},{kind:'videoinput',deviceId:'camera',label:'Camera'}],
    addEventListener:(type,callback)=>{deviceListeners[type]=callback;},removeEventListener:type=>{delete deviceListeners[type];}};
  const original=devices.getUserMedia;
  const context=vm.createContext({URL,DOMException,Date,Promise,Set,
    document:{currentScript:{src:'https://example.test/media/realtime_client.js'},hidden:false},
    navigator:{mediaDevices:devices},isSecureContext:true,
    HTMLAudioElement: {prototype: outputSupport ? {setSinkId(){}} : {}},
    ElevenLabsClient:{Conversation:{startSession:async config=>{
      options=config;
      // Reproduce the official SDK's real two-stream permission/LiveKit flow.
      const permissionStream=await devices.getUserMedia({audio:true});
      await devices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true}});
      permissionStream.getTracks().forEach(t=>t.stop());
      if(lateConnect) await connection.promise;
      config.onConversationCreated(instance); config.onConnect({conversationId:instance.getId()});
      return instance;
    }}}
  });
  context.window=context;
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../realtime_client.js'),'utf8'),context);
  return {api:context.airaRealtime,context,devices,original,track,preliminary,get alternate(){return alternate;},permission,connection,stream,
    setLevels:(a,b)=>{input=a;output=b;},get switchOptions(){return switchOptions;},
    get outputOptions(){return outputOptions;},
    attachRecycledAudio:()=>{volume=0;options.onDebug({type:'audio_element_ready'});},
    get options(){return options;},get requests(){return requests;},get ends(){return ends;},get muted(){return muted;},get volume(){return volume;}};
}
const config={conversationToken:'test-token',dynamicVariables:{aira_name:'Friend'}};
(async()=>{
  const h=harness(); await h.api.prepare(); assert.equal(h.requests,0,'preload must not ask for a microphone');
  await h.api.start(config);
  assert.equal(h.options.connectionType,'webrtc');
  assert.equal(h.options.outputDeviceId,'default','reset a recycled element\'s previous speaker routing');
  assert.equal(h.options.webRtc.singlePeerConnection,false,'use supported WebKit-compatible dual-PC negotiation');
  assert.equal(h.options.customLlmExtraBody,undefined,'native agent never receives an OpenAI bridge payload');
  assert.equal(h.options.useWakeLock,false);
  assert.equal(h.api.snapshot().realtimeStatus,'connected');
  assert.ok(h.api.snapshot().realtimeConnectedAt);
  assert.equal(h.requests,2,'official SDK owns permission and published capture streams');
  assert.equal(h.preliminary.readyState,'ended');
  assert.equal(h.track.readyState,'live');
  assert.equal(h.api.snapshot().microphoneIssue,null,'SDK preliminary stream stop is not a capture failure');
  assert.equal(h.api.snapshot().microphoneName,'Built-in microphone');
  assert.equal(h.api.snapshot().selectedMicrophoneId,'built-in');
  assert.equal(h.api.snapshot().availableMicrophones.length,2,'camera devices excluded');
  assert.equal(h.api.snapshot().availableSpeakers.length,3,'default plus real audio outputs');
  assert.equal(h.api.snapshot().speakerSelectionSupported,true);
  await h.api.changeSpeaker('headphones');
  assert.deepEqual(JSON.parse(JSON.stringify(h.outputOptions)),{outputDeviceId:'headphones'},'use public SDK output-device API');
  assert.equal(h.api.snapshot().selectedSpeakerId,'headphones');
  assert.equal(h.api.snapshot().speakerName,'Headphones');
  await h.api.changeSpeaker('unavailable');
  assert.match(h.api.snapshot().speakerIssue,/could not connect/);
  assert.equal(h.api.snapshot().selectedSpeakerId,'headphones','failed output choice retains last working speaker');
  await h.api.changeSpeaker('default');
  assert.equal(h.api.snapshot().speakerIssue,null);
  assert.equal(h.api.snapshot().inputLevel,.23,'meter is from actual SDK input');
  assert.equal(h.api.snapshot().outputLevel,.51);
  h.options.onMessage({role:'user',message:'How are you?'});
  assert.ok(h.api.snapshot().lastUserActivityAt,'speech activity is available for noninterrupting camera check-ins');
  assert.equal(h.api.snapshot().awaitingReply,true);
  h.options.onMessage({role:'agent',message:'I am here.'});
  assert.equal(h.api.snapshot().awaitingReply,false);
  assert.equal(h.api.snapshot().userCaption,'How are you?');
  assert.equal(h.api.snapshot().agentCaption,'I am here.');
  h.options.onAgentResponseCorrection({corrected_agent_response:'I am here with you.'});
  assert.equal(h.api.snapshot().callTranscript.length,2);
  assert.equal(h.api.snapshot().callTranscript[1].text,'I am here with you.');
  h.options.onModeChange({mode:'speaking'}); assert.equal(h.api.snapshot().callMode,'speaking');
  h.api.mute(true); assert.equal(h.track.enabled,false);assert.equal(h.muted,true);
  assert.equal(h.api.snapshot().inputLevel,0);assert.equal(h.api.snapshot().microphoneIssue,null);
  h.api.mute(false); assert.equal(h.track.enabled,true);
  h.api.speakerMute(true); assert.equal(h.volume,0);assert.equal(h.api.snapshot().speakerMuted,true);assert.equal(h.api.snapshot().outputLevel,0);
  h.attachRecycledAudio(); assert.equal(h.volume,0,'late track attachment respects current mute');
  h.api.speakerMute(false); assert.equal(h.volume,1);
  h.setLevels(NaN,5);assert.equal(h.api.snapshot().inputLevel,0);assert.equal(h.api.snapshot().outputLevel,1);
  h.track.muted=true; assert.match(h.api.snapshot().microphoneIssue,/device has paused/);
  h.track.muted=false;assert.equal(h.api.snapshot().microphoneIssue,null);
  await h.api.changeMicrophone('unavailable');
  assert.match(h.api.snapshot().microphoneIssue,/could not connect/,'failed choice remains visible after snapshot');
  h.track.unplug();await h.api.changeMicrophone('headset');assert.equal(h.api.snapshot().microphoneIssue,null);
  h.alternate.unplug();assert.match(h.api.snapshot().microphoneIssue,/disconnected/);
  await h.api.changeMicrophone('headset');
  assert.deepEqual(JSON.parse(JSON.stringify(h.switchOptions)),{inputDeviceId:'headset'},'WebRTC cannot accept sampleRate/format options');
  assert.equal(h.api.snapshot().microphoneName,'Headset microphone');
  assert.equal(h.api.snapshot().microphoneIssue,null,'device selection repairs lost capture');
  h.api.stop(); assert.equal(h.alternate.stopped,true); assert.equal(h.volume,0);
  assert.equal(h.api.snapshot().availableMicrophones.length,0,'End clears device labels');
  assert.equal(h.api.snapshot().agentCaption,null,'End clears transient captions');
  assert.equal(h.api.snapshot().callTranscript.length,2,'End preserves final captions for archive handoff');
  assert.equal(h.api.snapshot().voiceConversationId,'provider-conversation');
  h.api.clearTranscript(); assert.equal(h.api.snapshot().callTranscript.length,0);
  assert.equal(h.api.snapshot().voiceConversationId,null);
  h.options.onMessage({role:'agent',message:'late'});assert.equal(h.api.snapshot().agentCaption,null);
  await flush(); assert.equal(h.devices.getUserMedia,h.original,'guard restores after session end');
  await h.api.start({...config,conversationToken:'second-call-token'});
  assert.equal(h.volume,1,'restart restores output muted during previous hangup');
  h.attachRecycledAudio(); assert.equal(h.volume,1,'late recycled audio element is unmuted for second call');
  h.api.stop(); await flush();

  const unsupported=harness({outputSupport:false}); await unsupported.api.start(config);
  assert.equal(unsupported.api.snapshot().speakerSelectionSupported,false);
  assert.equal(unsupported.api.snapshot().availableSpeakers.length,1);
  await unsupported.api.changeSpeaker('speakers');
  assert.equal(unsupported.outputOptions,undefined,'unsupported browser never calls setSinkId');
  assert.match(unsupported.api.snapshot().speakerIssue,/system speaker/);
  unsupported.api.stop(); await flush();

  const p=harness({latePermission:true}); const pending=p.api.start(config);await flush();
  assert.equal(p.requests,1);p.api.stop();p.permission.resolve(p.stream(p.preliminary));
  await pending;assert.equal(p.preliminary.stopped,true,'late permission cannot reopen microphone');
  assert.equal(p.api.snapshot().realtimeStatus,'disconnected');
  assert.equal(p.devices.getUserMedia,p.original);

  const l=harness({lateConnect:true}); const late=l.api.start(config);await flush();l.api.stop();
  assert.equal(l.track.stopped,true,'End stops published microphone during connection');l.connection.resolve();await late;
  assert.ok(l.ends>0); assert.equal(l.volume,0,'late session cannot play sound');
  assert.equal(l.api.snapshot().realtimeStatus,'disconnected');

  const b=harness({latePermission:true}); const hidden=b.api.start(config);await flush();
  b.context.document.hidden=true;b.permission.resolve(b.stream(b.preliminary));await hidden;
  assert.equal(b.preliminary.stopped,true,'hidden page cannot accept late mic');

  const d=harness({denied:new DOMException('Denied','NotAllowedError')});
  await assert.rejects(d.api.start(config),/Microphone access was not allowed/);
  assert.equal(d.api.snapshot().realtimeStatus,'failed');
  assert.equal(d.devices.getUserMedia,d.original);
  console.log('PASS: SDK two-stream capture lifecycle, second-call recycled audio, speaker selection/fallback, true meters, device recovery, mute, captions/activity, permission denial, late permission and cleanup.');
})().catch(error=>{console.error(error);process.exitCode=1;});
