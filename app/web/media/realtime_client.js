/* AIRA adapter around the official, locally bundled ElevenLabs WebRTC SDK. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const state = {realtimeStatus: 'idle', callMode: 'listening', micMuted: false,
    voiceConversationId: null, userCaption: null, agentCaption: null,
    realtimeError: null, realtimeConnectedAt: null};
  let sdkPromise, session, pendingStart, pendingEnd, guard;
  let epoch = 0;
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
        track.addEventListener('ended', () => tracks.delete(track), {once: true});
      });
      return stream;
    };
    guard = owner;
    devices.getUserMedia = owner.wrapper;
    return owner;
  }
  function safeError(error) {
    if (error?.name === 'NotAllowedError') return 'Microphone access was not allowed. You can return to text chat.';
    if (error?.name === 'NotFoundError') return 'No microphone was found. Please connect one or use text chat.';
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
    state.realtimeConnectedAt = null;
    state.voiceConversationId = null;
    // Captions are session-only and disappear when the call ends.
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
    state.realtimeError = null;
    state.realtimeStatus = 'loading';
    state.micMuted = false;
    state.userCaption = null; state.agentCaption = null;
    try {
      await pendingEnd;
      await prepare();
      if (cancelled(request)) return;
      if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw new Error('Microphone needs HTTPS.');
      if (typeof config.conversationToken !== 'string' || !config.conversationToken ||
          typeof config.customLlmExtraBody?.aira_session_token !== 'string') throw new Error('The secure call session was not available.');
      const owner = captureGuard(request);
      state.realtimeStatus = 'connecting';
      let created;
      const begin = window.ElevenLabsClient.Conversation.startSession({
        conversationToken: config.conversationToken,
        connectionType: 'webrtc',
        customLlmExtraBody: {aira_session_token: config.customLlmExtraBody.aira_session_token},
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
          if (!cancelled(request)) state.callMode = mode;
        },
        onMessage: ({message, role, source}) => {
          if (cancelled(request) || typeof message !== 'string') return;
          const text = message.slice(0, 6000);
          if (role === 'user' || source === 'user') state.userCaption = text;
          else if (role === 'agent' || source === 'ai') state.agentCaption = text;
        },
        onInterruption: () => { if (!cancelled(request)) state.callMode = 'listening'; },
        onAgentResponseCorrection: event => {
          if (!cancelled(request) && typeof event?.corrected_agent_response === 'string') {
            state.agentCaption = event.corrected_agent_response.slice(0, 6000);
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
  function interrupt() {
    if (!session || state.realtimeStatus !== 'connected') return;
    // User activity asks the server to pause speech. Normal spoken barge-in is
    // handled by ElevenLabs VAD/interruption events and the WebRTC SDK itself.
    session.sendUserActivity();
  }
  window.airaRealtime = Object.freeze({prepare, start, stop, mute, interrupt,
    snapshot: () => ({...state})});
})();
