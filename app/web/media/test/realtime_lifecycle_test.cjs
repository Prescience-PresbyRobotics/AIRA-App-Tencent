// Contract/lifecycle mocks exercise real adapter code; they do not claim a provider call.
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../ELEVENLABS-ASSETS.json')));
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname, '../vendor/elevenlabs-client-1.28.0.js'))).digest('hex'), manifest.bundleSha256, 'published SDK bundle hash');
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return {promise,resolve,reject}; };
const flush = async () => { for (let i=0;i<10;i++) await Promise.resolve(); };
function harness({latePermission=false, lateConnect=false}={}) {
  const permission=deferred(), connection=deferred();
  const track={enabled:true,stopped:false,stop(){this.stopped=true;},addEventListener(){}};
  const stream={getTracks:()=>[track],getAudioTracks:()=>[track]};
  let options, requests=0, ends=0, muted=false, volume=1;
  const instance={getId:()=> 'provider-conversation',setMicMuted:v=>{muted=v;},setVolume:v=>{volume=v.volume;},endSession:async()=>{ends++;},sendUserActivity(){}};
  const devices={getUserMedia:()=>{requests++;return latePermission?permission.promise:Promise.resolve(stream);}};
  const original=devices.getUserMedia;
  const context=vm.createContext({URL,DOMException,Date,Promise,Set,
    document:{currentScript:{src:'https://example.test/media/realtime_client.js'},hidden:false},
    navigator:{mediaDevices:devices},isSecureContext:true,
    ElevenLabsClient:{Conversation:{startSession:async config=>{
      options=config;
      await devices.getUserMedia({audio:true});
      if(lateConnect) await connection.promise;
      config.onConversationCreated(instance); config.onConnect({conversationId:instance.getId()});
      return instance;
    }}}
  });
  context.window=context;
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../realtime_client.js'),'utf8'),context);
  return {api:context.airaRealtime,context,devices,original,track,permission,connection,
    get options(){return options;},get requests(){return requests;},get ends(){return ends;},get muted(){return muted;},get volume(){return volume;}};
}
const config={conversationToken:'test-token',customLlmExtraBody:{aira_session_token:'signed-test-session'},dynamicVariables:{aira_name:'Friend'}};
(async()=>{
  const h=harness(); await h.api.prepare(); assert.equal(h.requests,0,'preload must not ask for a microphone');
  await h.api.start(config);
  assert.equal(h.options.connectionType,'webrtc');
  assert.equal(h.options.customLlmExtraBody.aira_session_token,'signed-test-session');
  assert.equal(h.options.useWakeLock,false);
  assert.equal(h.api.snapshot().realtimeStatus,'connected');
  assert.ok(h.api.snapshot().realtimeConnectedAt);
  h.options.onMessage({role:'user',message:'How are you?'});
  h.options.onMessage({role:'agent',message:'I am here.'});
  assert.equal(h.api.snapshot().userCaption,'How are you?');
  assert.equal(h.api.snapshot().agentCaption,'I am here.');
  h.options.onModeChange({mode:'speaking'}); assert.equal(h.api.snapshot().callMode,'speaking');
  h.api.mute(true); assert.equal(h.track.enabled,false);assert.equal(h.muted,true);
  h.api.mute(false); assert.equal(h.track.enabled,true);
  h.api.stop(); assert.equal(h.track.stopped,true); assert.equal(h.volume,0);
  assert.equal(h.api.snapshot().agentCaption,null,'End clears transient captions');
  h.options.onMessage({role:'agent',message:'late'});assert.equal(h.api.snapshot().agentCaption,null);
  await flush(); assert.equal(h.devices.getUserMedia,h.original,'guard restores after session end');

  const p=harness({latePermission:true}); const pending=p.api.start(config);await flush();
  assert.equal(p.requests,1);p.api.stop();p.permission.resolve({getTracks:()=>[p.track],getAudioTracks:()=>[p.track]});
  await pending;assert.equal(p.track.stopped,true,'late permission cannot reopen microphone');
  assert.equal(p.api.snapshot().realtimeStatus,'disconnected');
  assert.equal(p.devices.getUserMedia,p.original);

  const l=harness({lateConnect:true}); const late=l.api.start(config);await flush();l.api.stop();
  assert.equal(l.track.stopped,true,'End stops microphone during connection');l.connection.resolve();await late;
  assert.ok(l.ends>0); assert.equal(l.volume,0,'late session cannot play sound');
  assert.equal(l.api.snapshot().realtimeStatus,'disconnected');

  const b=harness({latePermission:true}); const hidden=b.api.start(config);await flush();
  b.context.document.hidden=true;b.permission.resolve({getTracks:()=>[b.track],getAudioTracks:()=>[b.track]});await hidden;
  assert.equal(b.track.stopped,true,'hidden page cannot accept late mic');
  console.log('PASS: WebRTC options, explicit capture, captions, mute, ended/hidden late permission and late connection cleanup.');
})().catch(error=>{console.error(error);process.exitCode=1;});
