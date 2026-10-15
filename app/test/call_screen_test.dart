import 'dart:async';
import 'dart:typed_data';
import 'package:aira/controller.dart';
import 'package:aira/media/aira_media.dart';
import 'package:aira/screens/call.dart';
import 'package:aira/services/aira_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeApi extends AiraApi {
  FakeApi()
      : super(SupabaseClient('http://localhost:54321', 'test-only-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  Completer<Map<String, dynamic>>? transcription;
  Completer<Uint8List>? speechResult;
  int transcriptionCalls = 0, speechCalls = 0;
  @override
  Future<Map<String, dynamic>> transcribe(Uint8List bytes, String mime) async {
    transcriptionCalls++;
    return transcription == null
        ? {'text': 'I went for a walk.'}
        : transcription!.future;
  }

  @override
  Future<Uint8List> speech(String token) async {
    speechCalls++;
    return speechResult == null
        ? Uint8List.fromList([1, 2, 3])
        : speechResult!.future;
  }
}

class FakeController extends AiraController {
  FakeController(this.fakeApi) : super(null);
  final FakeApi fakeApi;
  int starts = 0, ends = 0, cancellations = 0;
  Completer<void>? startResult, consentResult;
  Completer<ChatTurn>? replyResult;
  String? sentText, sentFeeling;
  Map<String, dynamic>? sentCue;
  @override
  AiraApi get api => fakeApi;
  @override
  Future<void> beginCall(String mode) async {
    starts++;
    await startResult?.future;
  }

  @override
  Future<void> endCall() async {
    ends++;
  }

  @override
  void cancelSend() {
    cancellations++;
  }

  @override
  Future<void> updatePreference(String key, bool value) async {
    await consentResult?.future;
    preferences[key] = value;
  }

  @override
  Future<ChatTurn> send(String text,
      {String mode = 'text',
      Map<String, dynamic>? cueSummary,
      String? feeling}) async {
    sentText = text;
    sentFeeling = feeling;
    sentCue = cueSummary;
    return replyResult == null
        ? ChatTurn(
            text: 'I am glad you told me.',
            fromAira: true,
            speechToken: 'approved-token')
        : replyResult!.future;
  }
}

class FakeMedia extends AiraMediaController {
  int cameraStarts = 0, recordingStarts = 0, finishes = 0, plays = 0, stops = 0;
  int detectionStarts = 0;
  bool disposed = false;
  void update(AiraMediaState value) {
    state = value;
    notifyListeners();
  }

  @override
  Future<void> startCamera() async {
    cameraStarts++;
    update(const AiraMediaState(camera: 'on'));
  }

  @override
  void stopCamera() => update(const AiraMediaState());
  @override
  void setDetection(bool enabled) {
    if (enabled) detectionStarts++;
    update(AiraMediaState(
        camera: state.camera,
        detectionEnabled: enabled,
        detection: enabled ? 'detecting' : 'off'));
  }

  @override
  Future<void> startRecording() async {
    recordingStarts++;
    update(const AiraMediaState(microphone: 'recording'));
  }

  @override
  Future<RecordedAudio> finishRecording() async {
    finishes++;
    return RecordedAudio(
        bytes: Uint8List.fromList([1, 2]), mimeType: 'audio/webm;codecs=opus');
  }

  @override
  void cancelRecording() {}
  @override
  Future<void> playAudio(Uint8List bytes,
      [String mimeType = 'audio/mpeg']) async {
    plays++;
  }

  @override
  void stopPlayback() {}
  @override
  void stopAll() {
    stops++;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Future<void> openCall(
    WidgetTester tester, FakeController controller, FakeMedia media,
    {bool video = false}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => CallScreen(
                              controller: controller,
                              video: video,
                              mediaController: media))),
                  child: const Text('Launch call'))))));
  await tester.tap(find.text('Launch call'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> accept(WidgetTester tester, {bool video = false}) async {
  await tester.tap(find.text(video ? 'Start video call' : 'Start voice call'));
  await tester.pump();
  await tester.pump();
}

Future<void> transcriptReady(WidgetTester tester, FakeMedia media) async {
  media.update(
      const AiraMediaState(microphone: 'recorded', recordingSeconds: 45));
  await tester.pump();
  await tester.tap(find.text('Finish speaking'));
  await tester.pump();
  await tester.pump();
}

Future<void> closeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('opening does not accept call, capture media or count duration',
      (tester) async {
    final media = FakeMedia(), controller = FakeController(FakeApi());
    await openCall(tester, controller, media);
    await tester.pump(const Duration(seconds: 2));
    expect(controller.starts, 0);
    expect(media.cameraStarts + media.recordingStarts, 0);
    expect(find.text('00:00'), findsNothing);
    await accept(tester);
    expect(controller.starts, 1);
    expect(media.cameraStarts + media.recordingStarts, 0);
    expect(find.text('00:00'), findsOneWidget);
    await closeTree(tester);
  });

  testWidgets('hard-limit clip uses Finish speaking without restarting mic',
      (tester) async {
    final media = FakeMedia(), api = FakeApi();
    await openCall(tester, FakeController(api), media);
    await accept(tester);
    await transcriptReady(tester, media);
    expect(media.finishes, 1);
    expect(media.recordingStarts, 0);
    expect(api.transcriptionCalls, 1);
    expect(find.text('I went for a walk.'), findsOneWidget);
    await closeTree(tester);
  });

  testWidgets('End discards a late transcription and stops media',
      (tester) async {
    final media = FakeMedia(), api = FakeApi()..transcription = Completer();
    final controller = FakeController(api);
    await openCall(tester, controller, media);
    await accept(tester);
    await transcriptReady(tester, media);
    await tester.tap(find.text('End call'));
    await tester.pump();
    api.transcription!.complete({'text': 'This result arrived too late.'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('This result arrived too late.'), findsNothing);
    expect(media.plays, 0);
    expect(media.stops, greaterThan(0));
    expect(controller.ends, greaterThan(0));
    await closeTree(tester);
  });

  testWidgets(
      'Stop reply ignores late model result and cancels controller turn',
      (tester) async {
    final media = FakeMedia(), api = FakeApi();
    final controller = FakeController(api)..replyResult = Completer();
    await openCall(tester, controller, media);
    await accept(tester);
    await transcriptReady(tester, media);
    await tester.tap(find.text('Send to AIRA'));
    await tester.pump();
    await tester.tap(find.text('Stop reply'));
    await tester.pump();
    controller.replyResult!.complete(ChatTurn(
        text: 'Late model reply.', fromAira: true, speechToken: 'token'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Late model reply.'), findsNothing);
    expect(api.speechCalls, 0);
    expect(controller.cancellations, greaterThan(0));
    await closeTree(tester);
  });

  testWidgets('End prevents already-requested speech from playing later',
      (tester) async {
    final media = FakeMedia(), api = FakeApi()..speechResult = Completer();
    final controller = FakeController(api);
    await openCall(tester, controller, media);
    await accept(tester);
    await transcriptReady(tester, media);
    await tester.tap(find.text('Send to AIRA'));
    await tester.pump();
    await tester.pump();
    expect(api.speechCalls, 1);
    await tester.tap(find.text('End call'));
    await tester.pump();
    api.speechResult!.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(media.plays, 0);
    await closeTree(tester);
  });

  testWidgets(
      'background pause discards late transcript and needs explicit restart',
      (tester) async {
    final media = FakeMedia(), api = FakeApi()..transcription = Completer();
    final controller = FakeController(api);
    await openCall(tester, controller, media);
    await accept(tester);
    await transcriptReady(tester, media);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    api.transcription!.complete({'text': 'Late background transcript.'});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Late background transcript.'), findsNothing);
    expect(find.text('Start again'), findsOneWidget);
    expect(controller.starts, 1);
    expect(media.stops, greaterThan(0));
    await closeTree(tester);
  });

  testWidgets('analysis waits until consent is saved', (tester) async {
    final media = FakeMedia(),
        controller = FakeController(FakeApi())..consentResult = Completer();
    await openCall(tester, controller, media, video: true);
    await accept(tester, video: true);
    await tester.tap(find.text('Camera on'));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(media.detectionStarts, 0);
    controller.consentResult!.complete();
    await tester.pump();
    await tester.pump();
    expect(controller.consent('face_cues'), true);
    expect(media.detectionStarts, 1);
    await closeTree(tester);
  });

  testWidgets(
      'self-reported correction is passed separately from fresh facial cue',
      (tester) async {
    final media = FakeMedia(), controller = FakeController(FakeApi());
    controller.preferences['face_cues'] = true;
    await openCall(tester, controller, media, video: true);
    await accept(tester, video: true);
    await transcriptReady(tester, media);
    media.update(AiraMediaState(
        camera: 'on',
        detection: 'ready',
        detectionEnabled: true,
        emotion: 'happy',
        faceCount: 1,
        observedAt: DateTime.now()));
    await tester.pump();
    await tester.tap(find.text('That’s not how I feel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Sad'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('AI-estimated emotion: Happy'), findsOneWidget);
    expect(find.textContaining('You said: Sad'), findsOneWidget);
    await tester.tap(find.text('Send to AIRA'));
    await tester.pump();
    await tester.pump();
    expect(controller.sentText, 'I went for a walk.');
    expect(controller.sentFeeling, 'Sad');
    expect(controller.sentCue?['label'], 'happy');
    await closeTree(tester);
  });
}
