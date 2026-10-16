import 'package:aira/controller.dart';
import 'package:aira/main.dart';
import 'package:aira/screens/personal.dart';
import 'package:aira/screens/auth.dart';
import 'package:aira/screens/settings.dart';
import 'package:aira/theme.dart';
import 'package:aira/widgets/companion.dart';
import 'package:aira/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget screen(AiraController controller, Widget child, {double scale = 1}) =>
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        theme: airaTheme(largerText: controller.largerText),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('public auth hides the forgot-password entry', (tester) async {
    final controller = AiraController(null);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: airaTheme(),
        home: AuthScreen(controller: controller),
      ),
    );
    expect(find.text('Forgot password?'), findsNothing);
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    expect(find.text('Create account'), findsOneWidget);
    expect(
      find.textContaining(RegExp('verify|resend', caseSensitive: false)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'About me summary opens memories and keeps save and forget actions',
    (tester) async {
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      await controller.updatePreference('memory_enabled', true);
      await tester.pumpWidget(
        screen(controller, PersonalScreen(controller: controller)),
      );
      expect(find.byType(AiraSummaryCard), findsNWidgets(5));
      expect(find.text('What would you like AIRA to remember?'), findsNothing);
      await tester.tap(find.text('Memories'));
      await tester.pumpAndSettle();
      expect(
        find.text('What would you like AIRA to remember?'),
        findsOneWidget,
      );
      expect(find.text('No reminders yet'), findsNothing);
      await tester.tap(find.byTooltip('Add Memories'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'I enjoy gardening');
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(find.text('I enjoy gardening'), findsOneWidget);
      expect(controller.memories, hasLength(1));
      await tester.tap(find.byTooltip('Remove I enjoy gardening'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      expect(controller.memories, isEmpty);
    },
  );

  testWidgets('Plans and medicine cards open only their focused controls', (
    tester,
  ) async {
    final controller = AiraController(null)..startPreview();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      screen(controller, PersonalScreen(controller: controller)),
    );
    for (final section in ['Plans & follow-ups', 'Medicine reminders']) {
      await tester.ensureVisible(find.text(section));
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add $section'), findsOneWidget);
      expect(find.text('What would you like AIRA to remember?'), findsNothing);
      expect(
        find.textContaining('Background delivery is not active'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Add $section'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(
      controller.preferences.values.every((value) => value == true),
      isTrue,
    );
  });

  testWidgets(
    'medicine reminders can be edited and keep a future date beyond tomorrow',
    (tester) async {
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      final due = DateTime.now().toUtc().add(const Duration(days: 10));
      controller.medications = [
        {
          'id': 'existing',
          'label': 'Morning tablet',
          'instructions': 'Existing directions',
          'due_at': due.toIso8601String(),
          'recurrence': 'once',
          'version': 3,
        },
      ];
      await tester.pumpWidget(
        screen(controller, PersonalScreen(controller: controller)),
      );
      await tester.ensureVisible(find.text('Medicine reminders'));
      await tester.tap(find.text('Medicine reminders'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Morning tablet'));
      await tester.pumpAndSettle();
      expect(find.text('Edit medicine reminder'), findsOneWidget);
      expect(find.text('Morning tablet'), findsWidgets);
      expect(find.textContaining('next 24 hours'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Existing directions'),
        'Updated note',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Repeat daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeat daily'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(controller.medications, hasLength(1));
      expect(controller.medications.single['instructions'], 'Updated note');
      expect(controller.medications.single['version'], 4);
      expect(controller.medications.single['recurrence'], 'daily');
      final saved = DateTime.parse(
        controller.medications.single['due_at'].toString(),
      );
      expect(saved.difference(due).inMinutes.abs(), lessThan(1));
    },
  );

  testWidgets(
    'Settings overview is short and privacy choices remain explicit',
    (tester) async {
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        screen(
          controller,
          SettingsScreen(controller: controller, onCare: (_) {}),
        ),
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(AiraSummaryCard), findsNWidgets(7));
      expect(find.text('Save conversations'), findsNothing);
      await tester.tap(find.text('Privacy & memory'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(4));
      expect(controller.consent('memory_enabled'), isTrue);
      await tester.tap(find.text('Saved memories'));
      await tester.pumpAndSettle();
      expect(controller.consent('memory_enabled'), isFalse);
      expect(controller.consent('store_conversations'), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reminders'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(2));
      expect(controller.consent('medication_reminders'), isTrue);
    },
  );

  testWidgets(
    'summary cards and details reflow at 320px with large system text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        screen(
          controller,
          SettingsScreen(controller: controller, onCare: (_) {}),
          scale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Appearance'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final card = find.byType(AiraSummaryCard).first;
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Larger text'));
      await tester.pumpAndSettle();
      expect(controller.largerText, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings exposes logout and Exit preview clears all local account data',
    (tester) async {
      final controller = AiraController(null)..startPreview();
      addTearDown(controller.dispose);
      controller.onboarded = true;
      controller.name = 'Private preview name';
      controller.messages = [
        ChatTurn(text: 'Private message', fromAira: false),
      ];
      controller.memories = [
        {'id': 'memory', 'text': 'Private memory'},
      ];
      controller.callHistory = [
        {'id': 'call', 'mode': 'voice'},
      ];
      controller.callSchedule = {'localTime': '09:00'};
      controller.incomingCall = {'id': 'ring'};
      controller.activeCallId = 'active-call';
      controller.tab = 2;
      await tester.pumpWidget(AiraApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('settings-logout')), findsOneWidget);
      expect(find.text('Exit preview'), findsOneWidget);
      final epoch = controller.sessionEpoch;
      await tester.tap(find.byKey(const ValueKey('settings-logout')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(controller.sessionEpoch, greaterThan(epoch));
      expect(controller.signedIn, isFalse);
      expect(controller.messages, isEmpty);
      expect(controller.memories, isEmpty);
      expect(controller.callHistory, isEmpty);
      expect(controller.activeCallId, isEmpty);
      expect(controller.callSchedule, isNull);
      expect(controller.incomingCall, isNull);
      expect(controller.name, isEmpty);
      expect(controller.preferences, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('companion visibly repaints and stops for reduced motion', (
    tester,
  ) async {
    Widget host({bool reduced = false, bool animated = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Center(child: Companion(size: 160, animated: animated)),
      ),
    );
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(Companion),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.pumpWidget(host());
    final initial = painter();
    await tester.pump(const Duration(milliseconds: 450));
    expect(painter().shouldRepaint(initial), isTrue);
    await tester.pumpWidget(host(reduced: true));
    final still = painter();
    await tester.pump(const Duration(seconds: 1));
    expect(painter().shouldRepaint(still), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(animated: false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
