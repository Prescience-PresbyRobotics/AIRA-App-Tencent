import 'package:aira/controller.dart';
import 'package:aira/screens/dashboard.dart';
import 'package:aira/screens/dashboard/sample_data.dart';
import 'package:aira/services/aira_api.dart';
import 'package:aira/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoNetworkController extends AiraController {
  _NoNetworkController() : super(null);
  int requests = 0;
  @override
  bool get signedIn => true;
  @override
  AiraApi get api {
    requests++;
    throw StateError('Sample dashboards must never access an account API');
  }
}

Future<void> _show(
  WidgetTester tester,
  AiraController controller,
  DashboardSampleStore store, {
  bool admin = false,
  Size size = const Size(1400, 1200),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: airaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: DashboardScreen(
          controller: controller,
          admin: admin,
          sampleStore: store,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-in dashboard defaults to isolated, labelled samples', (
    tester,
  ) async {
    final controller = _NoNetworkController();
    final store = DashboardSampleStore();
    await _show(tester, controller, store);
    expect(find.textContaining('Fictional people and data'), findsOneWidget);
    expect(find.text('Care, made personal.'), findsOneWidget);
    expect(find.text('Live records'), findsOneWidget);
    expect(controller.requests, 0);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    controller.dispose();
  });

  testWidgets(
    'reset discards sample edits without touching signed-in account',
    (tester) async {
      final controller = _NoNetworkController();
      final store = DashboardSampleStore();
      final original = store.seniors.first['name'];
      store.seniors.first['name'] = 'Changed sample';
      store.record(store.seniors.first['id'] as String, 'Changed sample name');
      await _show(tester, controller, store);
      await tester.tap(find.byKey(const Key('reset-dashboard-samples')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset samples'));
      await tester.pumpAndSettle();
      expect(store.seniors.first['name'], original);
      expect(controller.requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      controller.dispose();
    },
  );

  for (final admin in [false, true]) {
    testWidgets(
      '${admin ? 'admin' : 'caregiver'} overview fits phone and large text',
      (tester) async {
        final controller = AiraController(null)..startPreview();
        final store = DashboardSampleStore();
        await _show(
          tester,
          controller,
          store,
          admin: admin,
          size: const Size(390, 844),
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -550));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        controller.dispose();
      },
    );
  }
}
