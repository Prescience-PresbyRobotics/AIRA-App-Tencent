# AIRA local facial-expression model

Selected and integrated on 14 October 2026; live box overlay added 16 October 2026. This is an engineering prototype,
not a validated measure of a senior's feelings or wellbeing.

## Source and distribution

- Runtime: [face-api.js 0.22.2](https://github.com/justadudewhohacks/face-api.js/tree/0.22.2).
- Exact upstream commit: `8609b25a15f417398a4d2b95dc91985cd1e0c0c3`.
- Models: Tiny Face Detector; tiny 68-point landmarks for alignment; FaceExpressionNet.
- Both the code and the weights are copied from the **same MIT-licensed upstream
  repository**. The weights are in its `weights/` directory, not an unlicensed
  third-party mirror. No more restrictive per-weight licence was present in that
  directory at this pinned version. The MIT permission and copyright notice are
  retained at `vendor/face-api-LICENSE.txt`.
- The bundled TensorFlow.js core 1.7.0 and tslib notices are preserved at
  `vendor/tensorflow-LICENSE.txt` and `vendor/tslib-LICENSE.txt`.
- `MODEL-ASSETS.json` records each original URL, byte size and SHA-256. Runtime
  and weights total approximately 1.3 MB and are hosted with AIRA. No CDN is used.
- This is an older upstream implementation, selected for its small browser-ready
  inspectable classifier and available weights. Dependency maintenance and model
  evaluation must be revisited before a production release. Availability and
  licensing do not establish suitability for the intended senior population.

## Data flow and preprocessing

Camera and analysis require separate actions. Camera permission alone never starts
inference. Camera frames stay on this device. A canvas resizes a fresh video image
to 320 pixels wide while retaining its aspect ratio. RGB pixels are transferred
to a dedicated Web Worker, where the TensorFlow CPU runtime runs a 224-pixel
Tiny Face Detector, face alignment and the real FaceExpressionNet classifier.
No identity/recognition, age, gender or face descriptor model is loaded or run.

Sampling is at most two frames/second; it automatically slows to avoid overlapping
CPU work. The worker returns a normalized single-face box. The local preview applies
the same aspect-fill crop and front-camera mirror to that box as to the video.
The box and live label clear on no face, multiple faces, stale input or revocation.
Model loading and inference time out explicitly. One usable face is
required (detection score ≥0.65 and crop at least 48×48 at processing resolution).
The last three seconds of scores are averaged, with at least two samples. A
winning score ≥0.55 and a ≥0.15 gap are engineering abstention thresholds, **not
measured accuracy or calibrated emotional certainty**. The UI never shows them
as accuracy percentages. Estimates older than five seconds disappear.

Upstream output categories: neutral, happy, sad, angry, fearful, disgusted,
surprised. The call overlay displays the short expression name, such as **Happy** or **Neutral**. Call settings explain that expressions are uncertain estimates and offer a self-report correction. No face, multiple
faces, unclear/low-quality face, weak/ambiguous output, stale camera, disabled
analysis and model errors are distinct unavailable/unknown/off states. An
unavailable estimate is never converted to neutral.

Turning off analysis terminates the worker, clears scores and leaves the camera
available. Turning off the camera also stops all its tracks and analysis. Ending
the call, backgrounding the page, going offline or disposing the media controller
stops camera, microphone, playback and analysis. A late permission approval cannot
restart an ended call. No camera frame is sent to Supabase, OpenAI or ElevenLabs.
The media module itself neither persists nor sends even the emotion label to a
server. In connected mode the call screen separately saves `face_cues` consent
before enabling analysis, explains that a fresh estimate can help AIRA reply,
and sends only the label and observation time to the active protected call
context, at most once every three seconds (plus immediate clearing). It requires one face and an estimate under five seconds old. Raw scores,
frames, crops and landmarks are not included. A senior's correction is submitted
as separate explicit self-report for the next reply, never substituted for the
facial model result or automatically stored as a mood measurement.

## Interpretation and limitations

Expressions are not proof of internal feelings. This classifier has no validated
accuracy for AIRA's senior users, languages, skin tones, glasses, head poses,
disabilities or lighting conditions. Neutral or smiling output cannot contradict
the senior's own words. The screen's correction must be recorded as **self-report**
in a separate field, without replacing what the facial classifier actually said.
Facial estimates never diagnose, establish loneliness, trigger urgent alerts or
become a remembered personality trait.

## Verification completed and still needed

The automated lifecycle test verifies consent separation, no media on load,
cancellation while permission is pending, track release, background suspension,
unknown/multiple/stale results, late inference after revocation, and bounded audio
recording cleanup. Its controlled classifier messages are test fixtures only.
Seven Flutter widget tests verify explicit live-call acceptance before capture,
timing only after actual connection, late session token/connection after End,
mute, live captions, background stop, saving consent before analysis, and separate
self-report versus facial-cue submission with no-face clearing. The JavaScript
checks verify the mirrored/cropped box projection and late SDK microphone cleanup.

The separate real-model smoke test verifies the packaged asset hashes and executes
the actual worker/runtime/weights against a blank image. A temporary test run also
used upstream `test/images/angry.jpg`, `surprised.jpg` and `faces.jpg` from the pinned
commit: these produced one angry estimate, one surprised estimate and three faces,
respectively. Photos are not bundled in AIRA. Example CPU VM inference times were
about 0.6–1.5 seconds per image on the development host. These are smoke checks, not
a browser benchmark, demographic evaluation or claim of emotion accuracy.

Still required: live camera testing with the intended users/devices, iPhone Safari
and Android Chrome permissions/codecs, low light, occlusion, glasses, head turns,
actual multiple-person scenes, denied/revoked permission, background/device lock,
screen-reader announcements and latency measurements. Flutter native adapters are
explicitly unavailable until separately implemented and tested.

## Flutter integration

Add `web: ^1.1.1` to Flutter dependencies and load
`<script src="media/aira_media.js"></script>` before Flutter bootstrap.
Import `lib/media/aira_media.dart`; use `AiraMediaController` and
`AiraCameraPreview`. The preview itself never starts a camera. Start camera and
live calls only on explicit user actions, and dispose the controller on call exit.

The call screen now uses the official ElevenLabs WebRTC SDK through
`prepareRealtime`, `startRealtime` and `setMicMuted`. See `REALTIME-CALLS.md`.
The older bounded recording/read-aloud utilities remain for other app surfaces,
but the live call screen no longer records a clip or waits for a Send action.
`stopAll()` must accompany cancellation of pending backend requests in the screen.

Run with a Node runtime:

```sh
node app/web/media/test/media_lifecycle_test.cjs
node app/web/media/test/realtime_lifecycle_test.cjs
node app/web/media/test/model_smoke_test.cjs
```
