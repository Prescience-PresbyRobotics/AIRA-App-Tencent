// Run: node app/web/media/test/model_smoke_test.cjs [rgb-fixtures.json]
// Optional JSON fixtures: [{name,width,height,base64,expectedFaces,expectedEmotion}].
// Each base64 value contains raw RGB bytes. No test photos are distributed.
// This runs the actual worker and weights, with local-file fetch in a VM.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'MODEL-ASSETS.json'), 'utf8'));
for (const item of manifest.files) {
  const bytes = fs.readFileSync(path.join(root, item.path));
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), item.sha256, item.path);
  assert.equal(bytes.length, item.bytes, item.path);
}
const messages = [];
const context = vm.createContext({
  console, Uint8Array, Float32Array, Int32Array, Uint8ClampedArray,
  TextEncoder, TextDecoder, URL, ArrayBuffer, performance, setTimeout, clearTimeout,
  location: {href: 'http://localhost/media/emotion_worker.js'},
  fetch: async url => {
    const parsed = new URL(url);
    assert.equal(parsed.origin, 'http://localhost', 'model may only fetch local assets');
    const bytes = fs.readFileSync(path.join(root, parsed.pathname.replace('/media/', '')));
    return {ok: true, status: 200, json: async () => JSON.parse(bytes.toString()),
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)};
  },
  postMessage: data => messages.push(data),
  importScripts: url => vm.runInContext(fs.readFileSync(path.join(root, url), 'utf8'), context),
});
context.self = context;
vm.runInContext(fs.readFileSync(path.join(root, 'emotion_worker.js'), 'utf8'), context);
(async () => {
  await context.onmessage({data: {type: 'load'}});
  assert.equal(messages.at(-1).type, 'loaded');
  const fixtures = [{name: 'blank', width: 320, height: 240, expectedFaces: 0,
    base64: Buffer.alloc(320 * 240 * 3).toString('base64')},
    ...(process.argv[2] ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8')) : [])];
  for (const fixture of fixtures) {
    const pixels = Uint8Array.from(Buffer.from(fixture.base64, 'base64'));
    assert.equal(pixels.length, fixture.width * fixture.height * 3);
    await context.onmessage({data: {type: 'frame', id: fixture.name, sampledAt: Date.now(),
      width: fixture.width, height: fixture.height, pixels: pixels.buffer}});
    const result = messages.at(-1);
    assert.equal(result.type, 'result', fixture.name);
    assert.equal(result.faces.length, fixture.expectedFaces, fixture.name);
    if (fixture.expectedEmotion) {
      const [label] = Object.entries(result.faces[0].expressions).sort((a, b) => b[1] - a[1])[0];
      assert.equal(label, fixture.expectedEmotion, fixture.name);
    }
    console.log(`PASS: ${fixture.name}: ${result.faces.length} faces, ${result.elapsedMs} ms (CPU test, not browser/device benchmark).`);
  }
  console.log('PASS: packaged SHA-256 hashes, real weights loading and inference.');
})().catch(error => { console.error(error); process.exitCode = 1; });
