import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aira/controller.dart';
import 'package:aira/main.dart';
import 'package:aira/screens/auth.dart';
import 'package:aira/theme.dart';
import 'package:aira/widgets/ui.dart';

void main() {
  testWidgets(
    'preview onboarding is optional and does not pretend AI is live',
    (tester) async {
      final controller = AiraController(null);
      await tester.pumpWidget(AiraApp(controller: controller));
      await tester.scrollUntilVisible(
        find.text('Explore the interface'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Explore the interface'));
      await tester.pump();
      expect(find.text('Hello, I’m AIRA.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Mei');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(controller.preferences.values.any((v) => v == true), false);
      await tester.scrollUntilVisible(
        find.text('Let’s chat'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Let’s chat'));
      await tester.pump();
      expect(controller.onboarded, true);
      expect(find.textContaining('Hello, Mei.'), findsOneWidget);
      expect(find.textContaining('AI not connected'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello AIRA');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(controller.messages, isEmpty);
      expect(find.text('Hello AIRA'), findsOneWidget);
      expect(find.textContaining('Your draft is kept'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('320px and 200 percent text keeps screens usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = AiraController(null)..setScale(true);
    await tester.pumpWidget(AiraApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'welcome layout');
    controller.startPreview();
    controller.setScale(true);
    await controller.finishOnboarding('Mei', {});
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'chat layout');
    controller.setTab(1);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'personal layout');
    controller.setTab(2);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'settings layout');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('compact is default and Larger text restores roomy layout', (
    tester,
  ) async {
    final controller = AiraController(null)..startPreview();
    await controller.finishOnboarding('Mei', {});
    controller.setTab(2);
    await tester.pumpWidget(AiraApp(controller: controller));
    final heading = find.text('Make yourself comfortable');
    final compactHeight = tester.getSize(find.byType(AiraCard).first).height;
    final compactScale = MediaQuery.textScalerOf(tester.element(heading));
    expect(compactScale.scale(20), 18);
    expect(controller.largerText, false);

    await tester.tap(find.text('Larger text'));
    await tester.pumpAndSettle();
    expect(controller.largerText, true);
    expect(MediaQuery.textScalerOf(tester.element(heading)).scale(20), 20);
    expect(
      tester.getSize(find.byType(AiraCard).first).height,
      greaterThan(compactHeight),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Larger text'));
    await tester.pumpAndSettle();
    expect(controller.largerText, false);
    expect(tester.getSize(find.byType(AiraCard).first).height, compactHeight);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('compact controls retain 48 pixel touch targets', (tester) async {
    final controller = AiraController(null);
    await tester.pumpWidget(AiraApp(controller: controller));
    final button = find.widgetWithText(OutlinedButton, 'Continue with Google');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('reading preference preserves nonlinear accessibility scaling', () {
    const system = _NonlinearTextScaler();
    const compact = AiraTextScaler(system, factor: .9);
    const large = AiraTextScaler(system, factor: 1);
    for (final size in [14.0, 20.0, 40.0]) {
      expect(compact.scale(size), system.scale(size * .9));
      expect(large.scale(size), system.scale(size));
    }
  });

  testWidgets(
    'login permits existing passwords; new passwords need 10 characters',
    (tester) async {
      final controller = AiraController(null);
      await tester.pumpWidget(AiraApp(controller: controller));
      await tester.enterText(
        find.byType(TextFormField).first,
        'mei@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'older');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
      await tester.enterText(find.byType(TextFormField).last, '');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter your password.'), findsOneWidget);

      await tester.ensureVisible(find.text('New here? Create an account'));
      await tester.tap(find.text('New here? Create an account'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, '123456789');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
      await tester.pump();
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, '1234567890');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);

      await tester.pumpWidget(
        MaterialApp(home: AuthScreen(controller: controller, recovery: true)),
      );
      await tester.enterText(find.byType(TextFormField), '123456789');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
      await tester.enterText(find.byType(TextFormField), '1234567890');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofillHints,
        contains(AutofillHints.newPassword),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test('preview memory requires permission and is cleared on exit', () async {
    final controller = AiraController(null)..startPreview();
    await expectLater(
      controller.saveMemory('I enjoy gardening'),
      throwsException,
    );
    await controller.updatePreference('memory_enabled', true);
    await controller.saveMemory('I enjoy gardening');
    expect(controller.memories.length, 1);
    await controller.signOut();
    expect(controller.memories, isEmpty);
    expect(controller.preferences, isEmpty);
    controller.dispose();
  });
}

// Models a device that scales small and large text by different amounts.
class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 20 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}
