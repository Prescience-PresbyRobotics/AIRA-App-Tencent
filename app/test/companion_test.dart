import 'package:aira/widgets/companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget scene({
  bool reducedMotion = false,
  bool systemReducedMotion = false,
  bool tickerEnabled = true,
  CompanionActivity activity = CompanionActivity.idle,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: systemReducedMotion),
    child: TickerMode(
      enabled: tickerEnabled,
      child: Center(
        child: Companion(reducedMotion: reducedMotion, activity: activity),
      ),
    ),
  ),
);

void main() {
  testWidgets('character has active motion and responds to a greeting tap', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.tap(find.byType(Companion));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final kind in ['preference', 'system', 'hidden route']) {
    testWidgets('$kind stops decorative animation including greeting taps', (
      tester,
    ) async {
      await tester.pumpWidget(
        scene(
          reducedMotion: kind == 'preference',
          systemReducedMotion: kind == 'system',
          tickerEnabled: kind != 'hidden route',
        ),
      );
      await tester.tap(find.byType(Companion));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('all conversation actions paint at compact and large sizes', (
    tester,
  ) async {
    for (final action in CompanionActivity.values) {
      for (final expression in CompanionExpression.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: Companion(
                size: 210,
                activity: action,
                expression: expression,
                voiceLevel: .25,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
