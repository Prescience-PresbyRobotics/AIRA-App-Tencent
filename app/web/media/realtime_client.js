/* AIRA adapter around the official, locally bundled ElevenLabs WebRTC SDK. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const state = {realtimeStatus: 'idle', callMode: 'listening', micMuted: false,
    voiceConversationId: null, userCaption: null, agentCaption: null,
    realtimeError: null, realtimeConnectedAt: null, speakerMuted: false,
    inputLevel: 0, outputLevel: 0, awaitingReply: false, microphoneIssue: null,
    microphoneName: null, selectedMicrophoneId: null, availableMicrophones: [],
    changingMicrophone: false, callTranscript: []};
  let sdkPromise, session, pendingStart, pendingEnd, guard;
  let epoch = 0;
  let deviceChangeListener, microphoneSelectionError;
  const tracks = new Set();

  function prepare() {
    if (window.ElevenLabsClient?.Conversation) return Promise.resolve();
    if (!sdkPromise) sdkPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('vendor/elevenlabs-client-1.28.0.js', base).href;
      script.onload = () => resolve();
      script.onerror = () => { sdkPromise = null; script.remove(); reject(new Error('Voice call software could not load. Please try again.')); };
      document.head.appendChild(script);
    });
    return sdkPromise;
  }
  function cancelled(request) {
    return request !== epoch || document.hidden;
  }
  function stopTracks() {
    for (const track of tracks) { track.enabled = false; track.stop(); }
    tracks.clear();
  }
  function restoreGuard(owner) {
    if (!owner || guard !== owner) return;
    if (navigator.mediaDevices.getUserMedia === owner.wrapper) navigator.mediaDevices.getUserMedia = owner.original;
    guard = null;
  }
  function captureGuard(request) {
    const devices = navigator.mediaDevices;
    const owner = {original: devices.getUserMedia};
    // The SDK currently has no abort signal for a pending permission prompt.
    // Observe only its microphone requests. An ended call refuses future audio
    // requests and immediately releases a stream returned by a late approval.
    owner.wrapper = async function(constraints) {
      if (!constraints?.audio) return owner.original.call(devices, constraints);
      if (cancelled(request)) throw new DOMException('Call ended', 'AbortError');
      const stream = await owner.original.call(devices, constraints);
      if (cancelled(request)) {
        stream.getTracks().forEach(track => track.stop());
        throw new DOMException('Call ended', 'AbortError');
      }
      stream.getAudioTracks().forEach(track => {
        tracks.add(track);
        track.enabled = !state.micMuted;
        track.addEventListener('ended', () => { tracks.delete(track); inspectMicrophone(); }, {once: true});
      });
      return stream;
    };
    guard = owner;
    devices.getUserMedia = owner.wrapper;
    return owner;
  }
  function liveTracks() {
    // The official SDK opens a permission stream, then a distinct LiveKit
    // stream. It stops the first stream itself, without dispatching `ended`.
    // Only the second, still-live stream is evidence of active capture.
    for (const track of tracks) if (track.readyState === 'ended') tracks.delete(track);
    return [...tracks].filter(track => track.readyState !== 'ended');
  }
  function inspectMicrophone() {
    if (state.realtimeStatus !== 'connected' || state.changingMicrophone) return;
    const live = liveTracks();
    const track = live.at(-1);
    state.microphoneName = track?.label || null;
    state.selectedMicrophoneId = track?.getSettings?.().deviceId || state.selectedMicrophoneId;
    state.microphoneIssue = microphoneSelectionError || (!track ? 'Your microphone disconnected. Choose another microphone or start the call again.'
      : !state.micMuted && track.muted ? 'Your device has paused the microphone. Check its microphone permission or choose another input.'
      : !state.micMuted && !track.enabled ? 'Your microphone is not sending audio. Unmute it or choose another input.' : null);
  }
  function level(value) {
    return typeof value === 'number' && Number.isFinite(value)
      ? Math.round(Math.min(1, Math.max(0, value)) * 100) / 100 : 0;
  }
  function snapshot() {
    inspectMicrophone();
    try {
      state.inputLevel = session && !state.micMuted ? level(session.getInputVolume()) : 0;
      state.outputLevel = session && !state.speakerMuted ? level(session.getOutputVolume()) : 0;
    } catch (_) { state.inputLevel = 0; state.outputLevel = 0; }
    return {...state, callTranscript: state.callTranscript.map(entry => ({...entry})), availableMicrophones: state.availableMicrophones.map(device => ({...device}))};
  }
  async function refreshMicrophones() {
    // Enumeration never requests permission. Labels appear only after the
    // user's microphone permission, and are displayed locally, not uploaded.
    if (!navigator.mediaDevices?.enumerateDevices) return;
    const request = epoch;
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      if (request !== epoch || state.realtimeStatus !== 'connected') return;
      state.availableMicrophones = devices.filter(device => device.kind === 'audioinput' && device.deviceId)
        .map((device, index) => ({id: device.deviceId, label: device.label || `Microphone ${index + 1}`}));
      inspectMicrophone();
    } catch (_) { /* Some browsers cannot enumerate devices; default input still works. */ }
  }
  async function changeMicrophone(deviceId) {
    if (!session || state.realtimeStatus !== 'connected' || state.changingMicrophone) return;
    if (typeof deviceId !== 'string' || !deviceId) return;
    const request = epoch;
    state.changingMicrophone = true;
    microphoneSelectionError = null; state.microphoneIssue = null;
    try {
      // The SDK owns publishing/replacing the WebRTC track. WebRTC accepts
      // inputDeviceId only; sampleRate/format options throw in SDK 1.28.0.
      await session.changeInputDevice({inputDeviceId: deviceId});
      if (cancelled(request)) return;
      state.selectedMicrophoneId = deviceId;
    } catch (_) {
      if (!cancelled(request)) microphoneSelectionError = 'That microphone could not connect. Choose another microphone or check device permissions.';
    } finally {
      if (!cancelled(request)) { state.changingMicrophone = false; await refreshMicrophones(); }
    }
  }
  function safeError(error) {
    if (error?.name === 'NotAllowedError') return 'Microphone access was not allowed. You can return to text chat.';
    if (error?.name === 'NotFoundError') return 'No microphone was found. Please connect one or use text chat.';
    if (error?.name === 'NotReadableError') return 'Your microphone is in use or unavailable. Close other calling apps and try again.';
    if (error?.name === 'SecurityError') return 'This browser has blocked microphone access. Allow microphone access in the site settings.';
    return 'The voice call could not connect. Please check your connection and start again.';
  }
  function stop() {
    ++epoch;
    stopTracks();
    const active = session;
    session = null;
    state.realtimeStatus = 'disconnected';
    state.callMode = 'listening';
    state.micMuted = false;
    state.speakerMuted = false;
    state.inputLevel = 0; state.outputLevel = 0; state.awaitingReply = false;
    microphoneSelectionError = null; state.microphoneIssue = null; state.microphoneName = null;
    state.selectedMicrophoneId = null; state.availableMicrophones = []; state.changingMicrophone = false;
    if (deviceChangeListener) navigator.mediaDevices?.removeEventListener?.('devicechange', deviceChangeListener);
    deviceChangeListener = null;
    state.realtimeConnectedAt = null;
    // Keep the completed transcript in memory until Flutter archives it.
    // It is cleared explicitly after handoff or on the next call.
    // On-screen captions disappear when the call ends.
    state.userCaption = null; state.agentCaption = null;
    if (active) {
      try { active.setVolume({volume: 0}); active.setMicMuted(true); } catch (_) {}
      pendingEnd = Promise.resolve().then(() => active.endSession()).catch(() => {}).finally(() => {
        pendingEnd = null;
        if (!pendingStart) restoreGuard(guard);
      });
    } else if (!pendingStart) restoreGuard(guard);
  }
  async function start(config) {
    if (state.realtimeStatus === 'connected' || state.realtimeStatus === 'connecting') throw new Error('A call is already active.');
    if (pendingStart) throw new Error('The previous connection is still closing. Please try again shortly.');
    const request = ++epoch;
    state.voiceConversationId = null; state.callTranscript = [];
    state.realtimeError = null;
    state.realtimeStatus = 'loading';
    state.micMuted = false;
    state.speakerMuted = false; state.awaitingReply = false;
    microphoneSelectionError = null; state.microphoneIssue = null; state.inputLevel = 0; state.outputLevel = 0;
    state.userCaption = null; state.agentCaption = null;
    try {
      await pendingEnd;
      await prepare();
      if (cancelled(request)) return;
      if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw new Error('Microphone needs HTTPS.');
      if (typeof config.conversationToken !== 'string' || !config.conversationToken) throw new Error('The secure call session was not available.');
      const owner = captureGuard(request);
      state.realtimeStatus = 'connecting';
      let created;
      const begin = window.ElevenLabsClient.Conversation.startSession({
        conversationToken: config.conversationToken,
        connectionType: 'webrtc',
        // LiveKit 2.21 defaults to the newer single-PC negotiation, which can
        // fail before capture on WebKit with an unsupported setConfiguration.
        // Use the SDK's supported dual-PC compatibility path (ElevenLabs #960).
        webRtc: {singlePeerConnection: false},
        dynamicVariables: config.dynamicVariables || {},
        useWakeLock: false,
        // Let the app's explicit background policy end the call. Never reconnect
        // or resume capture automatically after a page is hidden.
        onConversationCreated: value => {
          created = value;
          if (cancelled(request)) { value.setVolume({volume: 0}); value.setMicMuted(true); void Promise.resolve().then(() => value.endSession()).catch(() => {}); }
        },
        onConnect: ({conversationId}) => {
          if (cancelled(request)) return;
          state.voiceConversationId = conversationId;
          state.realtimeStatus = 'connected';
          state.realtimeConnectedAt = Date.now();
        },
        onStatusChange: ({status}) => {
          if (!cancelled(request)) state.realtimeStatus = status;
        },
        onModeChange: ({mode}) => {
          if (!cancelled(request)) { state.callMode = mode; if (mode === 'speaking') state.awaitingReply = false; }
        },
        onMessage: ({message, role, source}) => {
          if (cancelled(request) || typeof message !== 'string') return;
          const text = message.slice(0, 6000);
          if (role === 'user' || source === 'user') { state.userCaption = text; state.awaitingReply = true; }
          else if (role === 'agent' || source === 'ai') { state.agentCaption = text; state.awaitingReply = false; }
          else return;
          const speaker = role === 'user' || source === 'user' ? 'user' : 'assistant';
          const last = state.callTranscript.at(-1);
          if (text.trim() && !(last?.role === speaker && last?.text === text)) {
            state.callTranscript.push({role: speaker, text, timeInCallSecs: Math.max(0, Math.floor((Date.now() - (state.realtimeConnectedAt || Date.now())) / 1000))});
            if (state.callTranscript.length > 500) state.callTranscript.shift();
          }
        },
        onInterruption: () => { if (!cancelled(request)) state.callMode = 'listening'; },
        onAgentResponseCorrection: event => {
          if (!cancelled(request) && typeof event?.corrected_agent_response === 'string') {
            state.agentCaption = event.corrected_agent_response.slice(0, 6000);
            const last = state.callTranscript.findLast(entry => entry.role === 'assistant');
            if (last) last.text = state.agentCaption;
          }
        },
        onDisconnect: details => {
          if (cancelled(request)) return;
          if (details?.reason === 'error') state.realtimeError = 'The call was interrupted. Please start again or use text chat.';
          stop();
        },
        onError: () => {
          if (cancelled(request)) return;
          state.realtimeError = 'The call was interrupted. Please start again or use text chat.';
          stop();
        },
      });
      pendingStart = begin;
      try {
        const connected = await begin;
        if (cancelled(request)) {
          connected.setVolume({volume: 0}); connected.setMicMuted(true);
          await connected.endSession().catch(() => {});
          return;
        }
        session = connected;
        state.realtimeStatus = 'connected';
        state.voiceConversationId = connected.getId();
        state.realtimeConnectedAt ??= Date.now();
        // Confirm the provider's actual audio capture, not merely its transport
        // connection. Never leave an apparently listening UI without an input.
        inspectMicrophone();
        deviceChangeListener = () => { void refreshMicrophones(); };
        navigator.mediaDevices.addEventListener?.('devicechange', deviceChangeListener);
        await refreshMicrophones();
      } catch (error) {
        if (created) await created.endSession().catch(() => {});
        throw error;
      } finally {
        pendingStart = null;
        if (cancelled(request) || !session) { stopTracks(); restoreGuard(owner); }
      }
    } catch (error) {
      if (cancelled(request)) return;
      state.realtimeError = safeError(error);
      stop();
      state.realtimeStatus = 'failed';
      throw new Error(state.realtimeError);
    }
  }
  function mute(value) {
    if (!session || state.realtimeStatus !== 'connected') return;
    state.micMuted = Boolean(value);
    for (const track of tracks) track.enabled = !state.micMuted;
    try { session.setMicMuted(state.micMuted); } catch (_) {
      state.realtimeError = 'Microphone control failed. The call has been stopped.'; stop();
    }
  }
  function speakerMute(value) {
    if (!session || state.realtimeStatus !== 'connected') return;
    state.speakerMuted = Boolean(value);
    try { session.setVolume({volume: state.speakerMuted ? 0 : 1}); } catch (_) {
      state.realtimeError = 'Call audio could not be adjusted. Please start the call again.';
    }
  }
  function interrupt() {
    if (!session || state.realtimeStatus !== 'connected') return;
    // User activity asks the server to pause speech. Normal spoken barge-in is
    // handled by ElevenLabs VAD/interruption events and the WebRTC SDK itself.
    session.sendUserActivity();
  }
  function clearTranscript() { state.callTranscript = []; state.voiceConversationId = null; }
  function contextualUpdate(text) {
    if (session && state.realtimeStatus === 'connected' && typeof text === 'string') {
      session.sendContextualUpdate(text.slice(0, 1000));
    }
  }
  window.airaRealtime = Object.freeze({prepare, start, stop, mute, speakerMute, interrupt,
    refreshMicrophones, changeMicrophone, clearTranscript, contextualUpdate, snapshot});
})();
