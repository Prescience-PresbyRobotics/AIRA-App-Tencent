{{flutter_js}}
{{flutter_build_config}}

// Flutter supplies a fresh build ID. Version the entrypoint as well as the
// loader: a browser can otherwise reuse an older main.dart.js after a release.
// AIRA requires a connection; do not install an offline app-shell cache.
const airaBuildVersion = {{flutter_service_worker_version}} || 'aira-online';
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    const entrypoint = new URL(build.mainJsPath, document.baseURI);
    entrypoint.searchParams.set('aira_build', airaBuildVersion);
    build.mainJsPath = entrypoint.href;
  }
}
_flutter.loader.load();
