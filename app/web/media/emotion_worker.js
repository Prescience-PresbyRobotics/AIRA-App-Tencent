/* Local-only inference. Model and runtime provenance: MODEL-CARD.md. */
'use strict';
importScripts('vendor/face-api-0.22.2.min.js');

// TFJS 1.x does not auto-detect a DedicatedWorkerGlobalScope as a browser.
// Its explicit platform hook provides only local time/encoding and fetch.
faceapi.tf.setPlatform('aira-worker', {
  fetch: self.fetch.bind(self),
  now: () => performance.now(),
  encode: text => new TextEncoder().encode(text),
  decode: bytes => new TextDecoder().decode(bytes),
});

let loaded = false;
// The model's tensor path needs no DOM. Supply constructor types so its input
// guards work in a Worker, and native fetch for same-origin model assets.
class UnusedMediaElement {}
faceapi.env.setEnv({
  Canvas: UnusedMediaElement, Image: UnusedMediaElement,
  Video: UnusedMediaElement, ImageData: UnusedMediaElement,
  createCanvasElement: () => { throw new Error('DOM access is not permitted'); },
  createImageElement: () => { throw new Error('DOM access is not permitted'); },
  fetch: self.fetch.bind(self), readFile: () => { throw new Error('No filesystem'); },
});

self.onmessage = async ({data}) => {
  let tensor;
  try {
    if (data.type === 'load') {
      await faceapi.tf.setBackend('cpu');
      const uri = new URL('models/', self.location.href).href;
      await Promise.all([
        faceapi.nets.tinyFaceDetector.loadFromUri(uri),
        faceapi.nets.faceLandmark68TinyNet.loadFromUri(uri),
        faceapi.nets.faceExpressionNet.loadFromUri(uri),
      ]);
      loaded = true;
      self.postMessage({type: 'loaded'});
      return;
    }
    if (data.type !== 'frame' || !loaded) return;
    const started = performance.now();
    tensor = faceapi.tf.tensor3d(new Uint8Array(data.pixels), [data.height, data.width, 3], 'int32');
    const results = await faceapi.detectAllFaces(tensor,
      new faceapi.TinyFaceDetectorOptions({inputSize: 224, scoreThreshold: 0.5}))
      .withFaceLandmarks(true).withFaceExpressions();
    // Only scores/quality leave this worker. No frames, landmarks or face
    // descriptors are retained, sent to the app backend, or written to storage.
    self.postMessage({type: 'result', id: data.id, sampledAt: data.sampledAt,
      faces: results.map(result => ({
        score: result.detection.score,
        width: result.detection.box.width,
        height: result.detection.box.height,
        expressions: {...result.expressions},
      })), elapsedMs: Math.round(performance.now() - started)});
  } catch (error) {
    self.postMessage({type: 'error', message: 'The facial expression model could not run.'});
  } finally {
    tensor?.dispose();
    if (data.type === 'frame') new Uint8Array(data.pixels).fill(0);
  }
};
