import 'dart:async';

import 'package:aira/controller.dart';
import 'package:aira/media/aira_media.dart';
import 'package:aira/screens/call.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeController extends AiraController {
  FakeController() : super(null);
  int starts = 0, ends = 0, publishes = 0;
  Completer<Map<String, dynamic>>? startResult;
  Completer<void>? consentResult;
  String? sentFeeling;
  Map<String, dynamic>? sentCue;
  @override
  Future<Map<String, dynamic>> beginRealtimeCall(String mode) async {
    starts++;
    return startResult == null
        ? {
            'conversationToken': 'test',
            'customLlmExtraBody': {'aira_session_token': 'signed-test'},
          }
        : startResult!.future;
  }

  @override
  Future<void> publishCallContext({
    Map<String, dynamic>? cueSummary,
    String? selfReportedFeeling,
  }) async {
    publishes++;
    sentCue = cueSummary;
    sentFeeling = selfReportedFeeling;
  }

  @override
  Future<void> endCall() async {
    ends++;
  }

  @override
  Future<void> updatePreference(String key, bool value) async {
    await consentResult?.future;
    preferences[key] = value;
  }
}

class FakeMedia extends AiraMediaController {
  int cameraStarts = 0, realtimeStarts = 0, stops = 0, detectionStarts = 0;
  Completer<void>? connectResult;
  bool disposed = false;
  void update(AiraMediaState value) {
    state = value;
    if (!disposed) notifyListeners();
  }

  void connected({
    bool camera = false,
    bool detection = false,
    bool muted = false,
  }) => update(
    AiraMediaState(
      camera: camera ? 'on' : 'off',
      realtimeStatus: 'connected',
      realtimeConnectedAt: DateTime.now(),
      micMuted: muted,
      detectionEnabled: detection,
      detection: detection ? 'detecting' : 'off',
    ),
  );
  @override
  Future<void> prepareRealtime() async {}
  @override
  Future<void> startRealtime(Map<String, dynamic> config) async {
    realtimeStarts++;
    if (connectResult != null) await connectResult!.future;
    if (!disposed) connected();
  }

  @override
  void setMicMuted(bool muted) => connected(
    camera: state.cameraOn,
    detection: state.detectionEnabled,
    muted: muted,
  );
  @override
  Future<void> startCamera() async {
    cameraStarts++;
    connected(camera: true);
  }

  @override
  void stopCamera() => connected();
  @override
  void setDetection(bool enabled) {
    if (enabled) detectionStarts++;
    connected(camera: true, detection: enabled);
  }

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
  WidgetTester tester,
  FakeController controller,
  FakeMedia media, {
  bool video = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CallScreen(
                  controller: controller,
                  video: video,
                  mediaController: media,
                ),
              ),
            ),
            child: const Text('Launch call'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch call'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> accept(WidgetTester tester, {bool video = false}) async {
  await tester.tap(find.text(video ? 'Start video call' : 'Start voice call'));
  await tester.pump();
  await tester.pump();
}

Future<void> closeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets(
    'Start explicitly opens live microphone; duration waits for actual connection',
    (tester) async {
      final media = FakeMedia()..connectResult = Completer(),
          controller = FakeController();
      await openCall(tester, controller, media);
      expect(media.realtimeStarts + media.cameraStarts, 0);
      expect(find.text('00:00'), findsNothing);
      await accept(tester);
      expect(controller.starts, 1);
      expect(media.realtimeStarts, 1);
      expect(find.text('00:00'), findsNothing);
      media.connectResult!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Speak'), findsNothing);
      expect(media.cameraStarts, 0);
      await closeTree(tester);
    },
  );

  testWidgets('End prevents a late session token from opening microphone', (
    tester,
  ) async {
    final media = FakeMedia(),
        controller = FakeController()..startResult = Completer();
    await openCall(tester, controller, media);
    await accept(tester);
    await tester.tap(find.text('End call'));
    await tester.pump();
    controller.startResult!.complete({'conversationToken': 'late'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(media.realtimeStarts, 0);
    expect(media.stops, greaterThan(0));
    expect(controller.ends, greaterThan(0));
    await closeTree(tester);
  });

  testWidgets('End discards delayed WebRTC connection', (tester) async {
    final media = FakeMedia()..connectResult = Completer(),
        controller = FakeController();
    await openCall(tester, controller, media);
    await accept(tester);
    await tester.tap(find.text('End call'));
    await tester.pump();
    media.connectResult!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(media.stops, greaterThan(0));
    expect(find.text('Mute'), findsNothing);
    await closeTree(tester);
  });

  testWidgets(
    'Mute and unmute control live microphone and real captions display',
    (tester) async {
      final media = FakeMedia(), controller = FakeController();
      await openCall(tester, controller, media);
      await accept(tester);
      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(media.state.micMuted, true);
      await tester.tap(find.text('Unmute'));
      await tester.pump();
      expect(media.state.micMuted, false);
      media.update(
        const AiraMediaState(
          realtimeStatus: 'connected',
          callMode: 'speaking',
          userCaption: 'Hello.',
          agentCaption: 'Hello, friend.',
        ),
      );
      await tester.pump();
      expect(find.text('You: Hello.'), findsOneWidget);
      expect(find.text('AIRA: Hello, friend.'), findsOneWidget);
      await closeTree(tester);
    },
  );

  testWidgets('background ends stream and requires explicit restart', (
    tester,
  ) async {
    final media = FakeMedia(), controller = FakeController();
    await openCall(tester, controller, media);
    await accept(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Start again'), findsOneWidget);
    expect(media.stops, greaterThan(0));
    expect(controller.starts, 1);
    expect(controller.ends, greaterThan(0));
    await closeTree(tester);
  });

  testWidgets('facial analysis waits for saved consent', (tester) async {
    final media = FakeMedia(),
        controller = FakeController()..consentResult = Completer();
    await openCall(tester, controller, media, video: true);
    await accept(tester, video: true);
    await tester.tap(find.text('Camera on'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Show facial emotion'),
    );
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
    'self report reaches context separately from facial estimate; no-face clears estimate',
    (tester) async {
      final media = FakeMedia(), controller = FakeController();
      controller.preferences['face_cues'] = true;
      await openCall(tester, controller, media, video: true);
      await accept(tester, video: true);
      media.update(
        AiraMediaState(
          camera: 'on',
          realtimeStatus: 'connected',
          detection: 'ready',
          detectionEnabled: true,
          emotion: 'happy',
          faceCount: 1,
          observedAt: DateTime.now(),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('That’s not how I feel'));
      await tester.tap(find.text('That’s not how I feel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Sad'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.sentFeeling, 'Sad');
      expect(controller.sentCue?['label'], 'happy');
      expect(find.text('AI-estimated emotion: Happy'), findsOneWidget);
      expect(find.textContaining('You said: Sad'), findsOneWidget);
      media.update(
        const AiraMediaState(
          camera: 'on',
          realtimeStatus: 'connected',
          detection: 'unknown',
          detectionEnabled: true,
          faceCount: 0,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(controller.sentCue, isNull);
      expect(controller.sentFeeling, 'Sad');
      await closeTree(tester);
    },
  );
}
