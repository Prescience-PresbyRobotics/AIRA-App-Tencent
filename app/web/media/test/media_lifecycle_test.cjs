// Lifecycle fixtures deliberately test control flow, not model accuracy.
// Run: node app/web/media/test/media_lifecycle_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function harness() {
  const intervals = new Map(), timeouts = new Map(), workers = [], pending = [];
  const listeners = {};
  let now = 10000, nextTimer = 0, requests = 0;
  const stream = () => {
    const track = {stopped: false, stop() { this.stopped = true; }, addEventListener() {}};
    return {track, getTracks: () => [track], getVideoTracks: () => [track], getAudioTracks: () => [track]};
  };
  const document = {
    currentScript: {src: 'http://localhost/media/aira_media.js'}, hidden: false,
    addEventListener: (type, callback) => { listeners[type] = callback; },
    createElement: (tag) => tag === 'canvas' ? {
      getContext: () => ({drawImage() {}, clearRect() {}, getImageData: (_, __, w, h) => ({data: new Uint8ClampedArray(w * h * 4)})}),
    } : {readyState: 3, currentTime: 1, videoWidth: 640, videoHeight: 480, play: async () => {}, pause() {}, setAttribute() {}, style: {}},
  };
  class Worker {
    constructor() { this.sent = []; workers.push(this); }
    postMessage(data) { this.sent.push(data); }
    terminate() { this.terminated = true; }
    emit(data) { this.onmessage({data}); }
  }
  class Recorder {
    static isTypeSupported() { return true; }
    constructor(_, opts) { this.mimeType = opts.mimeType; this.state = 'inactive'; }
    start() { this.state = 'recording'; }
    stop() {
      this.state = 'inactive';
      Promise.resolve().then(() => { this.ondataavailable?.({data: new Blob(['audio'])}); this.onstop?.(); });
    }
  }
  const context = vm.createContext({
    console, URL, Blob, Uint8Array, Uint8ClampedArray, MediaRecorder: Recorder,
    Date: {now: () => now}, document, Worker,
    navigator: {mediaDevices: {getUserMedia() { requests++; return new Promise(resolve => pending.push(resolve)); }}},
    setTimeout: (fn) => { const id = ++nextTimer; timeouts.set(id, fn); return id; },
    clearTimeout: id => timeouts.delete(id),
    setInterval: (fn) => { const id = ++nextTimer; intervals.set(id, fn); return id; },
    clearInterval: id => intervals.delete(id),
    isSecureContext: true, addEventListener: (type, fn) => { listeners[type] = fn; },
    btoa: input => Buffer.from(input, 'binary').toString('base64'),
  });
  context.window = context;
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../aira_media.js'), 'utf8'), context);
  return {api: context.airaMedia, snapshot: () => JSON.parse(context.airaMedia.snapshot()),
    workers, pending, stream, document, listeners, intervals, timeouts,
    tick: ms => { now += ms; for (const fn of intervals.values()) fn(); }, requests: () => requests};
}

(async () => {
  const h = harness();
  assert.equal(h.requests(), 0, 'loading cannot start media');
  assert.equal(h.snapshot().detection, 'off');
  h.api.setDetection(true);
  assert.equal(h.workers.length, 0, 'analysis cannot start without camera');

  const late = h.stream();
  const awaitingCamera = h.api.startCamera();
  h.api.stopAll();
  h.pending.shift()(late);
  await awaitingCamera;
  assert.equal(late.track.stopped, true, 'late permission result must stop');
  assert.equal(h.snapshot().camera, 'off');

  const live = h.stream();
  const camera = h.api.startCamera(); h.pending.shift()(live); await camera;
  assert.equal(h.snapshot().camera, 'on');
  assert.equal(h.snapshot().detection, 'off', 'camera permission is not analysis consent');
  h.api.setDetection(true);
  const worker = h.workers.at(-1);
  worker.emit({type: 'loaded'});
  assert.equal(worker.sent.at(-1).type, 'frame');
  const face = {score: 0.9, width: 90, height: 100, expressions: {happy: 0.95, neutral: 0.05}};
  worker.emit({type: 'result', sampledAt: 10000, faces: [face], elapsedMs: 300});
  worker.emit({type: 'result', sampledAt: 10000, faces: [face], elapsedMs: 300});
  assert.equal(h.snapshot().emotion, 'happy');
  h.tick(5100);
  assert.equal(h.snapshot().emotion, null, 'stale label disappears');
  worker.emit({type: 'result', sampledAt: 15100, faces: [face, face], elapsedMs: 300});
  assert.match(h.snapshot().reason, /more than one face/);
  assert.equal(h.snapshot().emotion, null);
  worker.emit({type: 'result', sampledAt: 15100, faces: [], elapsedMs: 300});
  assert.match(h.snapshot().reason, /no clear face/);
  assert.equal(h.snapshot().emotion, null, 'no face is never neutral');
  h.api.setDetection(false);
  worker.emit({type: 'result', sampledAt: 15100, faces: [face], elapsedMs: 300});
  assert.equal(h.snapshot().detection, 'off', 'late inference cannot restore revoked consent');
  assert.equal(worker.terminated, true);
  assert.equal(live.track.stopped, false, 'disabling analysis preserves camera');

  const microphone = h.stream();
  const recording = h.api.startRecording(); h.pending.shift()(microphone); await recording;
  assert.equal(h.snapshot().microphone, 'recording');
  const clip = JSON.parse(await h.api.finishRecording());
  assert.equal(Buffer.from(clip.base64, 'base64').toString(), 'audio');
  assert.equal(microphone.track.stopped, true);
  assert.equal(h.snapshot().microphone, 'off');

  const boundedMic = h.stream();
  const boundedRecording = h.api.startRecording(); h.pending.shift()(boundedMic); await boundedRecording;
  h.tick(45000);
  assert.equal(h.snapshot().recordingSeconds, 45, 'elapsed recording time is visible and bounded');
  for (const callback of [...h.timeouts.values()]) callback();
  await Promise.resolve();
  assert.equal(h.snapshot().microphone, 'recorded', 'hard limit retains clip for Finish speaking');
  assert.equal(boundedMic.track.stopped, true, 'hard limit releases microphone');
  const boundedClip = JSON.parse(await h.api.finishRecording());
  assert.equal(Buffer.from(boundedClip.base64, 'base64').toString(), 'audio');

  const lateMic = h.stream();
  const awaitingMic = h.api.startRecording(); h.api.stopAll(); h.pending.shift()(lateMic); await awaitingMic;
  assert.equal(lateMic.track.stopped, true);
  assert.equal(live.track.stopped, true);
  assert.equal(h.intervals.size, 0);

  const backgroundCam = h.stream();
  const backgroundStart = h.api.startCamera(); h.pending.shift()(backgroundCam); await backgroundStart;
  h.document.hidden = true; h.listeners.visibilitychange();
  assert.equal(backgroundCam.track.stopped, true);
  assert.equal(h.snapshot().suspended, true);
  assert.equal(h.snapshot().camera, 'off');
  console.log('PASS: consent separation, late-permission cancellation, actual track cleanup, stale/no/multiple face handling, recording bytes, and background suspension.');
})().catch(error => { console.error(error); process.exitCode = 1; });
