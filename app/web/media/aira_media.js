/* Browser media for AIRA. No media starts when this script loads. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const state = {
    camera: 'off', microphone: 'off', detection: 'off', detectionEnabled: false,
    emotion: null, reason: 'Detection off', faceCount: 0, observedAt: null,
    faceBox: null, faceObservedAt: null, frameAspect: null,
    inferenceMs: null, playing: false, suspended: false, error: null, recordingStartedAt: null,
    model: 'face-api.js/0.22.2/FaceExpressionNet',
  };
  let cameraStream, microphoneStream, recorder, recordingDone;
  let sourceVideo, preview, previewHost, faceOverlay, faceLabel, previewResize, worker, inferenceTimer, staleTimer, workerTimer;
  let recordingTimer, player, playbackUrl, playbackResolve;
  let cameraEpoch = 0, recordingEpoch = 0, detectionEpoch = 0, playbackEpoch = 0;
  let recordingChunks = [], recordingBytes = 0, recordingType = '';
  let realtimeModule, realtimeEpoch = 0;
  let busy = false, frameId = 0, lastVideoTime = -1, samples = [];
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d', {willReadFrequently: true});
  const labels = ['neutral', 'happy', 'sad', 'angry', 'fearful', 'disgusted', 'surprised'];
  const MAX_AUDIO_BYTES = 5000000;
  const MAX_RECORDING_MS = 45000;

  function clearEmotion(reason, detection = 'unknown') {
    state.emotion = null;
    state.observedAt = null;
    state.reason = reason;
    state.detection = detection;
    samples = [];
    state.faceBox = null; state.faceObservedAt = null;
    drawFace();
  }
  function stopTracks(stream) { stream?.getTracks().forEach(track => track.stop()); }
  function mediaError(error, kind) {
    const denied = error?.name === 'NotAllowedError' || error?.name === 'PermissionDeniedError';
    return denied ? `${kind} permission was not allowed. You can continue with text.`
      : `${kind} is unavailable. Check your device and try again.`;
  }
  function ensureMedia() {
    if (!navigator.mediaDevices?.getUserMedia || !window.isSecureContext) {
      throw new Error('Media needs HTTPS or localhost in a supported browser.');
    }
    state.suspended = false;
    state.error = null;
  }
  // All coordinates originate from the local model, before preview mirroring.
  // Cover cropping and mirroring are applied to the same host as the video.
  function projectFace(box, aspect, width, height) {
    const drawnWidth = Math.max(width, height * aspect);
    const drawnHeight = drawnWidth / aspect;
    return {x: width - ((width - drawnWidth) / 2 + (box.x + box.width) * drawnWidth),
      y: (height - drawnHeight) / 2 + box.y * drawnHeight,
      width: box.width * drawnWidth, height: box.height * drawnHeight};
  }
  function drawFace() {
    if (!faceOverlay || !previewHost) return;
    const box = state.faceBox;
    if (!box || !state.detectionEnabled || state.camera !== 'on') {
      faceOverlay.style.display = 'none'; return;
    }
    const rect = projectFace(box, state.frameAspect, previewHost.clientWidth, previewHost.clientHeight);
    faceOverlay.style.display = 'block';
    faceOverlay.style.left = `${rect.x}px`; faceOverlay.style.top = `${rect.y}px`;
    faceOverlay.style.width = `${rect.width}px`; faceOverlay.style.height = `${rect.height}px`;
    faceLabel.textContent = state.emotion ? `AI estimate: ${state.emotion}`
      : state.detection === 'detecting' ? 'Reading expression…' : 'Expression uncertain';
  }
  function attachPreview(element) {
    if (element !== previewHost) {
      previewResize?.disconnect();
      previewHost = element;
      previewHost.style.cssText = 'position:relative;width:100%;height:100%;overflow:hidden;background:#4f4c60;';
      preview = document.createElement('video');
      preview.autoplay = true; preview.muted = true; preview.playsInline = true;
      preview.setAttribute('aria-label', 'Your private camera preview');
      preview.style.cssText = 'width:100%;height:100%;object-fit:cover;transform:scaleX(-1);';
      faceOverlay = document.createElement('div');
      faceOverlay.style.cssText = 'display:none;position:absolute;box-sizing:border-box;border:2px solid #b7ffd8;border-radius:10px;pointer-events:none;';
      faceLabel = document.createElement('span');
      faceLabel.style.cssText = 'position:absolute;left:-2px;bottom:100%;max-width:260px;white-space:nowrap;border-radius:5px;background:#163c32;color:white;font:600 13px system-ui;padding:4px 7px;';
      faceOverlay.appendChild(faceLabel);
      previewHost.replaceChildren(preview, faceOverlay);
      if (window.ResizeObserver) {
        previewResize = new ResizeObserver(drawFace); previewResize.observe(previewHost);
      }
    }
    if (cameraStream) { preview.srcObject = cameraStream; preview.play().catch(() => {}); }
    drawFace();
  }
  async function startCamera() {
    if (state.camera === 'on' || state.camera === 'starting') return;
    const epoch = ++cameraEpoch;
    try {
      ensureMedia();
      state.camera = 'starting';
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {facingMode: 'user', width: {ideal: 640}, height: {ideal: 480}}, audio: false,
      });
      // Ending a call while the browser permission prompt is open must not
      // result in a late camera start after the user has left.
      if (epoch !== cameraEpoch || document.hidden) { stopTracks(stream); return; }
      cameraStream = stream;
      sourceVideo = document.createElement('video');
      sourceVideo.muted = true;
      sourceVideo.playsInline = true;
      sourceVideo.srcObject = stream;
      await sourceVideo.play();
      if (epoch !== cameraEpoch) { stopTracks(stream); return; }
      stream.getVideoTracks().forEach(track => track.addEventListener('ended', () => {
        if (cameraStream === stream) stopCamera();
      }));
      state.camera = 'on';
      if (previewHost) attachPreview(previewHost);
    } catch (error) {
      if (epoch !== cameraEpoch) return;
      stopCamera();
      state.camera = error?.name === 'NotAllowedError' ? 'denied' : 'error';
      state.error = mediaError(error, 'Camera');
    }
  }
  function stopCamera() {
    ++cameraEpoch;
    setDetection(false);
    stopTracks(cameraStream);
    cameraStream = null;
    if (sourceVideo) { sourceVideo.pause(); sourceVideo.srcObject = null; sourceVideo = null; }
    if (preview) { preview.pause(); preview.srcObject = null; }
    canvas.width = 1; canvas.height = 1;
    state.camera = 'off';
  }
  function stopInference() {
    ++detectionEpoch;
    clearTimeout(inferenceTimer);
    clearTimeout(workerTimer);
    clearInterval(staleTimer);
    worker?.terminate();
    worker = null;
    busy = false;
    samples = [];
    state.faceCount = 0;
    state.inferenceMs = null;
    lastVideoTime = -1;
  }
  function modelUnavailable() {
    stopInference();
    clearEmotion('Model unavailable', 'unavailable');
  }
  function handleResult(result) {
    busy = false;
    clearTimeout(workerTimer);
    state.inferenceMs = result.elapsedMs;
    state.faceCount = result.faces.length;
    const now = Date.now();
    if (now - result.sampledAt > 5000) {
      clearEmotion('Unable to detect — camera result is out of date');
    } else if (result.faces.length !== 1) {
      clearEmotion(result.faces.length > 1 ? 'Unable to detect — more than one face' : 'Unable to detect — no clear face');
    } else {
      const face = result.faces[0];
      if (face.score < 0.65 || face.width < 48 || face.height < 48) {
        clearEmotion('Unable to detect — face is unclear or too far away');
      } else {
        state.faceBox = face.box; state.frameAspect = result.frameAspect;
        state.faceObservedAt = result.sampledAt;
        samples.push({at: result.sampledAt, scores: face.expressions});
        samples = samples.filter(sample => now - sample.at <= 3000);
        const average = labels.map(label => ({label, value: samples.reduce((total, sample) => total + (sample.scores[label] || 0), 0) / samples.length}));
        average.sort((a, b) => b.value - a.value);
        if (samples.length < 2) {
          state.emotion = null; state.observedAt = null;
          state.detection = 'detecting'; state.reason = 'Reading a few expressions…';
        } else if (average[0].value < 0.55 || average[0].value - average[1].value < 0.15) {
          state.emotion = null; state.observedAt = null;
          state.detection = 'unknown'; state.reason = 'Unable to detect — expression is uncertain';
        } else {
          state.emotion = average[0].label;
          state.observedAt = result.sampledAt;
          state.detection = 'ready'; state.reason = null;
        }
      }
    }
    drawFace();
    // Slow devices naturally receive fewer frames; no overlapping inference.
    inferenceTimer = setTimeout(captureFrame, Math.max(500, result.elapsedMs));
  }
  function captureFrame() {
    if (!worker || !state.detectionEnabled || state.camera !== 'on' || busy || document.hidden) return;
    if (!sourceVideo || sourceVideo.readyState < 2 || sourceVideo.currentTime === lastVideoTime) {
      inferenceTimer = setTimeout(captureFrame, 500); return;
    }
    lastVideoTime = sourceVideo.currentTime;
    const width = 320;
    const height = Math.max(1, Math.round(width * sourceVideo.videoHeight / sourceVideo.videoWidth));
    canvas.width = width; canvas.height = height;
    context.drawImage(sourceVideo, 0, 0, width, height);
    const frame = context.getImageData(0, 0, width, height);
    // RGB tensor input avoids exposing browser DOM or media handles to the worker.
    const rgb = new Uint8Array(width * height * 3);
    for (let source = 0, dest = 0; source < frame.data.length; source += 4) {
      rgb[dest++] = frame.data[source]; rgb[dest++] = frame.data[source + 1]; rgb[dest++] = frame.data[source + 2];
    }
    frame.data.fill(0);
    context.clearRect(0, 0, width, height);
    busy = true;
    worker.postMessage({type: 'frame', id: ++frameId, sampledAt: Date.now(), width, height, pixels: rgb.buffer}, [rgb.buffer]);
    workerTimer = setTimeout(modelUnavailable, 15000);
  }
  function setDetection(enabled) {
    stopInference();
    state.detectionEnabled = Boolean(enabled) && state.camera === 'on';
    if (!state.detectionEnabled) { clearEmotion('Detection off', 'off'); return; }
    if (!window.Worker || !context) { modelUnavailable(); return; }
    clearEmotion('Loading the expression model…', 'loading');
    const epoch = detectionEpoch;
    try {
      worker = new Worker(new URL('emotion_worker.js?v=20261016', base));
      worker.onmessage = ({data}) => {
        if (epoch !== detectionEpoch || !state.detectionEnabled) return;
        if (data.type === 'loaded') {
          clearTimeout(workerTimer);
          state.detection = 'detecting'; state.reason = 'Looking for one clear face…';
          captureFrame();
        } else if (data.type === 'result') handleResult(data);
        else if (data.type === 'error') modelUnavailable();
      };
      worker.onerror = modelUnavailable;
      worker.postMessage({type: 'load'});
      workerTimer = setTimeout(modelUnavailable, 30000);
      staleTimer = setInterval(() => {
        if (state.faceObservedAt && Date.now() - state.faceObservedAt > 5000) {
          clearEmotion('Unable to detect — waiting for a fresh camera image');
        }
      }, 250);
    } catch (error) { modelUnavailable(); }
  }
  function cancelRecording() {
    ++recordingEpoch;
    clearTimeout(recordingTimer);
    const active = recorder;
    recorder = null;
    if (active && active.state !== 'inactive') active.stop();
    stopTracks(microphoneStream);
    microphoneStream = null;
    recordingChunks = []; recordingBytes = 0;
    state.microphone = 'off';
    state.recordingStartedAt = null;
  }
  async function startRecording() {
    if (state.microphone === 'recording' || state.microphone === 'requesting') return;
    stopPlayback();
    const epoch = ++recordingEpoch;
    try {
      ensureMedia();
      if (!window.MediaRecorder) throw new Error('Recording is unavailable');
      state.microphone = 'requesting';
      const stream = await navigator.mediaDevices.getUserMedia({audio: {echoCancellation: true, noiseSuppression: true}, video: false});
      if (epoch !== recordingEpoch || document.hidden) { stopTracks(stream); return; }
      microphoneStream = stream;
      const mime = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus', 'audio/webm']
        .find(type => MediaRecorder.isTypeSupported(type));
      if (!mime) throw new Error('No supported audio recording format');
      recorder = new MediaRecorder(stream, {mimeType: mime, audioBitsPerSecond: 64000});
      recordingType = recorder.mimeType || mime;
      recordingChunks = []; recordingBytes = 0;
      const active = recorder;
      recordingDone = new Promise(resolve => {
        active.ondataavailable = ({data}) => {
          if (epoch !== recordingEpoch || !data.size) return;
          recordingBytes += data.size;
          if (recordingBytes > MAX_AUDIO_BYTES) {
            state.error = 'This recording is too large. Please try a shorter message.';
            cancelRecording(); return;
          }
          recordingChunks.push(data);
        };
        active.onstop = resolve;
        active.onerror = () => {
          state.error = 'Recording was interrupted. Please try again.';
          cancelRecording(); resolve();
        };
      });
      active.start(250);
      state.microphone = 'recording';
      state.recordingStartedAt = Date.now();
      stream.getAudioTracks().forEach(track => track.addEventListener('ended', () => {
        if (microphoneStream === stream && state.microphone === 'recording') {
          state.error = 'Microphone access ended. Please start speaking again.'; cancelRecording();
        }
      }));
      recordingTimer = setTimeout(() => {
        if (epoch !== recordingEpoch) return;
        // Stop the microphone at the limit, retaining the completed bounded
        // clip until Finish speaking, or discarding it on End/Stop/background.
        if (active.state !== 'inactive') active.stop();
        stopTracks(microphoneStream); microphoneStream = null;
        state.microphone = 'recorded';
      }, MAX_RECORDING_MS);
    } catch (error) {
      if (epoch !== recordingEpoch) return;
      cancelRecording();
      state.microphone = 'error'; state.error = mediaError(error, 'Microphone');
    }
  }
  async function finishRecording() {
    const epoch = recordingEpoch;
    const active = recorder;
    if (!active) return JSON.stringify({error: 'No recording to transcribe.'});
    clearTimeout(recordingTimer);
    if (active.state !== 'inactive') active.stop();
    stopTracks(microphoneStream); microphoneStream = null;
    state.microphone = 'off';
    state.recordingStartedAt = null;
    await recordingDone;
    if (epoch !== recordingEpoch) return JSON.stringify({error: 'Recording cancelled.'});
    const blob = new Blob(recordingChunks, {type: recordingType});
    recordingChunks = []; recorder = null; recordingBytes = 0;
    if (!blob.size || blob.size > MAX_AUDIO_BYTES) return JSON.stringify({error: 'Please record a short message first.'});
    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (epoch !== recordingEpoch) { bytes.fill(0); return JSON.stringify({error: 'Recording cancelled.'}); }
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    bytes.fill(0);
    return JSON.stringify({base64: btoa(binary), mimeType: blob.type, size: blob.size});
  }
  function stopPlayback() {
    ++playbackEpoch;
    if (player) { player.pause(); player.removeAttribute('src'); player.load(); player = null; }
    if (playbackUrl) URL.revokeObjectURL(playbackUrl);
    playbackUrl = null; state.playing = false;
    playbackResolve?.(); playbackResolve = null;
  }
  async function playAudio(base64, mimeType) {
    // A reply returned after background/offline suspension must never restart
    // sound. Starting a new user-controlled recording/camera session resumes.
    if (document.hidden || state.suspended) return;
    stopPlayback();
    const epoch = playbackEpoch;
    const bytes = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
    playbackUrl = URL.createObjectURL(new Blob([bytes], {type: mimeType}));
    player = new Audio(playbackUrl);
    const active = player;
    try {
      // Resolves when playback ends or is cancelled, not merely when it starts.
      const ended = new Promise(resolve => {
        playbackResolve = resolve;
        active.onended = () => { if (epoch === playbackEpoch) stopPlayback(); };
        active.onerror = () => { state.error = 'Reply audio could not play. You can still read it.'; stopPlayback(); };
      });
      await active.play();
      if (epoch !== playbackEpoch) return;
      state.playing = true;
      await ended;
    } catch (error) {
      if (epoch !== playbackEpoch) return;
      state.error = 'Tap Play reply to hear the response. Your browser blocked automatic playback.';
      stopPlayback();
    }
  }
  function prepareRealtime() {
    if (window.airaRealtime) return window.airaRealtime.prepare();
    if (!realtimeModule) realtimeModule = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('realtime_client.js?v=20261016', base).href;
      script.onload = resolve;
      script.onerror = () => { realtimeModule = null; script.remove(); reject(new Error('Voice software could not load.')); };
      document.head.appendChild(script);
    });
    return realtimeModule.then(() => window.airaRealtime.prepare());
  }
  async function startRealtime(encoded) {
    const request = ++realtimeEpoch;
    try {
      ensureMedia(); stopPlayback(); cancelRecording();
      await prepareRealtime();
      if (request !== realtimeEpoch || document.hidden) return JSON.stringify({cancelled: true});
      await window.airaRealtime.start(JSON.parse(encoded));
      if (request !== realtimeEpoch) return JSON.stringify({cancelled: true});
      return JSON.stringify({connected: window.airaRealtime.snapshot().realtimeStatus === 'connected'});
    } catch (_) {
      return JSON.stringify({error: window.airaRealtime?.snapshot().realtimeError || 'The live call could not start. Please try again.'});
    }
  }
  function stopRealtime() { ++realtimeEpoch; window.airaRealtime?.stop(); }
  function setMicMuted(value) { window.airaRealtime?.mute(value); }
  function stopAll() {
    stopRealtime(); stopCamera(); cancelRecording(); stopPlayback();
  }
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      stopAll(); state.suspended = true;
      state.error = 'Media paused while AIRA was in the background. Start it again when you are ready.';
    }
  });
  window.addEventListener('pagehide', stopAll);
  window.addEventListener('offline', () => { stopAll(); state.suspended = true; state.error = 'The call was interrupted. Please reconnect and start again.'; });
  window.airaMedia = Object.freeze({
    snapshot: () => JSON.stringify({...state, ...window.airaRealtime?.snapshot(),
      playing: state.playing || (window.airaRealtime?.snapshot().realtimeStatus === 'connected' && window.airaRealtime?.snapshot().callMode === 'speaking'), recordingSeconds: state.recordingStartedAt == null
      ? 0 : Math.min(45, Math.floor((Date.now() - state.recordingStartedAt) / 1000))}),
    attachPreview, projectFace, startCamera, stopCamera, prepareRealtime, startRealtime, stopRealtime, setMicMuted,
    setDetection, startRecording, finishRecording, cancelRecording, playAudio, stopPlayback, stopAll,
  });
})();
