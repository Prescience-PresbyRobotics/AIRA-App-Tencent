import 'package:aira/controller.dart';
import 'package:aira/screens/call_history.dart';
import 'package:aira/screens/call_schedule.dart';
import 'package:aira/screens/settings.dart';
import 'package:aira/screens/shell.dart';
import 'package:aira/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ArchiveController extends AiraController {
  ArchiveController() : super(null) {
    preferences['store_conversations'] = true;
  }
  bool removed = false;
  @override
  Future<void> refreshCallHistory({bool older = false}) async {
    callHistory = [
      if (!removed)
        {
          'id': 'call-a',
          'mode': 'video',
          'startedAt': '2026-10-16T10:00:00Z',
          'endedAt': '2026-10-16T10:02:30Z',
          'initiator': 'aira',
          'turnCount': 2,
        },
    ];
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> loadCallTranscript(String id) async => {
    'call': callHistory.single,
    'messages': [
      {
        'id': 'a',
        'role': 'assistant',
        'text': 'Hey, lovely to hear your voice!',
      },
      {'id': 'b', 'role': 'user', 'text': 'I went for a walk today.'},
    ],
  };

  @override
  Future<void> deleteCallTranscript(String id) async {
    removed = true;
    callHistory.clear();
    notifyListeners();
  }
}

class IncomingController extends AiraController {
  IncomingController() : super(null) {
    preferences.addAll(defaultFeaturePreferences);
    onboarded = true;
    tab = 2;
  }
  Map<String, dynamic>? offered;
  final actions = <String>[];
  @override
  bool get signedIn => true;
  @override
  Future<void> pollEvents() async {}
  @override
  Future<void> refreshCallSchedule() async {
    incomingCall = offered;
    notifyListeners();
  }

  @override
  Future<bool> respondScheduledCall(
    Map<String, dynamic> invitation,
    String action,
  ) async {
    actions.add(action);
    offered = incomingCall = null;
    notifyListeners();
    return false;
  }
}

Widget app(Widget child) => MaterialApp(theme: airaTheme(), home: child);

void main() {
  testWidgets('saved calls open a separate transcript and can be deleted', (
    tester,
  ) async {
    final controller = ArchiveController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(CallHistoryScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Video call with AIRA'), findsOneWidget);
    expect(controller.messages, isEmpty);
    await tester.tap(find.text('Video call with AIRA'));
    await tester.pumpAndSettle();
    expect(find.text('Video call transcript'), findsOneWidget);
    expect(find.text('I went for a walk today.'), findsOneWidget);
    await tester.ensureVisible(find.text('Delete transcript'));
    await tester.tap(find.text('Delete transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete transcript'));
    await tester.pumpAndSettle();
    expect(controller.removed, isTrue);
    expect(find.text('No saved calls yet'), findsOneWidget);
  });

  testWidgets('call schedule keeps timezone and browser limitation visible', (
    tester,
  ) async {
    final controller = AiraController(null)..startPreview();
    addTearDown(controller.dispose);
    await controller.saveCallSchedule(const TimeOfDay(hour: 17, minute: 30));
    await tester.pumpWidget(app(CallScheduleScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Singapore time · Asia/Singapore'), findsOneWidget);
    expect(find.textContaining('tab is closed'), findsOneWidget);
    expect(controller.callSchedule!['enabled'], isTrue);
    await tester.ensureVisible(find.text('Daily call from AIRA'));
    await tester.tap(find.text('Daily call from AIRA'));
    await tester.pumpAndSettle();
    expect(controller.callSchedule!['enabled'], isFalse);
    expect(controller.callSchedule!['localTime'], '17:30');
    await tester.ensureVisible(find.text('Remove call schedule'));
    await tester.tap(find.text('Remove call schedule'));
    await tester.pumpAndSettle();
    expect(controller.callSchedule, isNull);
    expect(find.text('Choose a call time'), findsOneWidget);
  });

  testWidgets(
    'Care connections exposes both dashboards without assigning a role',
    (tester) async {
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      String? selected;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SettingsScreen(
              controller: controller,
              onCare: (role) => selected = role,
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Care connections'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Care connections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Care connections'));
      await tester.pumpAndSettle();
      expect(find.textContaining('assigned admin role'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Preview admin dashboard'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Preview admin dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview admin dashboard'));
      await tester.pumpAndSettle();
      expect(selected, 'admin');
      expect(controller.preferences.containsKey('role'), isFalse);
    },
  );
  testWidgets('call settings remain usable at 320px and large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final archive = ArchiveController();
    final preview = AiraController(null)..startPreview();
    addTearDown(archive.dispose);
    addTearDown(preview.dispose);
    Widget large(Widget child) => MaterialApp(
      theme: airaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: child,
    );
    await tester.pumpWidget(large(CallHistoryScreen(controller: archive)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(large(CallScheduleScreen(controller: preview)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'incoming invitation appears above an open Settings detail and declines cleanly',
    (tester) async {
      final controller = IncomingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: airaTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: AiraShell(controller: controller),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Larger text'), findsOneWidget);
      controller.offered = {
        'id': 'incoming-a',
        'version': 1,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String(),
      };
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Incoming voice call'), findsOneWidget);
      await tester.tap(find.text('Silence ring'));
      await tester.pump();
      expect(find.text('Enable ring'), findsOneWidget);
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(controller.actions, ['decline']);
      expect(find.text('Incoming voice call'), findsNothing);
      expect(find.text('Larger text'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
