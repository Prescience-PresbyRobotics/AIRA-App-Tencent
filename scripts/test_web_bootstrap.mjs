import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = fs.readFileSync(
  new URL('../app/web/flutter_bootstrap.js', import.meta.url), 'utf8',
).replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '')
  .replace('{{flutter_service_worker_version}}', '"verified-build-2"');

for (const baseURI of [
  'https://aira-app-tencent.web.app/',
  'http://localhost:8080/preview/',
]) {
  let loads = 0;
  const config = { builds: [{ mainJsPath: 'main.dart.js' }] };
  vm.runInNewContext(source, {
    URL, document: { baseURI },
    _flutter: {
      buildConfig: config,
      loader: { load: (...args) => {
        assert.equal(args.length, 0, 'Do not reinstall an offline app-shell cache');
        loads++;
      } },
    },
  });
  assert.equal(loads, 1);
  assert.equal(config.builds[0].mainJsPath,
    `${baseURI}main.dart.js?aira_build=verified-build-2`);
}
console.log('Web bootstrap: versioned entrypoint and base path checks passed.');
