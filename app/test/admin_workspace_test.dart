import 'package:aira/screens/dashboard/admin_workspace.dart';
import 'package:aira/screens/dashboard/sample_data.dart';
import 'package:aira/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showAdmin(
  WidgetTester tester,
  DashboardSampleStore store, {
  ValueChanged<String>? onOpen,
  double width = 1200,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: airaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AdminWorkspace(store: store, onOpenSenior: onOpen ?? (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('directory search and open target the selected sample senior', (
    tester,
  ) async {
    final store = DashboardSampleStore();
    String? opened;
    await showAdmin(tester, store, onOpen: (id) => opened = id);
    await tapVisible(tester, find.text('Seniors & accounts'));
    final senior = store.seniors[1];
    await tester.enterText(
      find.byKey(const Key('admin-search')),
      senior['name'] as String,
    );
    await tester.pumpAndSettle();
    expect(find.text(store.seniors.first['name'] as String), findsNothing);
    expect(find.text(senior['name'] as String), findsNWidgets(2));
    await tapVisible(tester, find.text('Open senior'));
    expect(opened, senior['id']);
  });

  testWidgets(
    'account edits update source records and audit, reset is simulated',
    (tester) async {
      final store = DashboardSampleStore();
      final senior = store.seniors.first;
      final priorAudit = store.audit.length;
      await showAdmin(tester, store);
      await tapVisible(tester, find.text('Seniors & accounts'));
      await tapVisible(
        tester,
        find.byKey(ValueKey('edit-account-${senior['id']}')),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Mei Sample Updated',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'mei.updated@example.test',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('admin-select-Access role')),
      );
      await tapVisible(tester, find.text('Caregiver').last);
      await tester.enterText(find.byType(TextFormField).at(4), '2027-02-28');
      await tester.enterText(find.byType(TextFormField).at(5), '450');
      await tapVisible(tester, find.text('Save sample account'));
      expect(senior['name'], 'Mei Sample Updated');
      expect(senior['email'], 'mei.updated@example.test');
      expect(senior['accessRole'], 'Caregiver');
      expect(senior['planEnds'], '2027-02-28T23:59:00+08:00');
      expect(senior['minutesLimit'], 450);
      expect(store.audit.length, priorAudit + 1);
      await tapVisible(tester, find.text('Password reset').first);
      expect(find.textContaining('No email is sent'), findsOneWidget);
      await tapVisible(tester, find.text('Simulate reset'));
      expect(senior['passwordResetStatus'], 'Sample password reset requested');
      expect(store.audit.length, priorAudit + 2);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
      'reset invalidates an account dialog without recording a false edit',
      (tester) async {
    final store = DashboardSampleStore();
    final original = store.seniors.first;
    await showAdmin(tester, store);
    await tapVisible(tester, find.text('Seniors & accounts'));
    await tapVisible(
        tester, find.byKey(ValueKey('edit-account-${original['id']}')));
    await tester.enterText(find.byType(TextFormField).first, 'Stale edit');
    store.reset();
    final resetAuditCount = store.audit.length;
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save sample account'));
    expect(store.seniors.first['name'], original['name']);
    expect(store.audit.length, resetAuditCount);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('queue filters concern types and records a reasoned review', (
    tester,
  ) async {
    final store = DashboardSampleStore();
    await showAdmin(tester, store);
    await tapVisible(tester, find.text('Review queue'));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('filter-Concern-All concerns')),
    );
    await tapVisible(tester, find.text('AI-related belief concerns').last);
    final matches = [
      for (final s in store.seniors)
        for (final a in (s['alerts'] as List).cast<Map<String, dynamic>>())
          if ((a['category'] as String).contains('belief')) a,
    ];
    expect(find.text('${matches.length} matching concerns'), findsOneWidget);
    await tapVisible(tester, find.text('Review concern').first);
    await tester.enterText(find.byType(TextFormField), '');
    await tapVisible(tester, find.text('Save sample review'));
    expect(find.text('Add a note explaining the decision.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'Sample review: arrange a gentle check-in and clarify AIRA is an AI character.',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('admin-select-Review decision')),
    );
    await tapVisible(tester, find.text('resolved').last);
    await tapVisible(tester, find.text('Save sample review'));
    expect(matches.first['status'], 'resolved');
    expect(matches.first['note'], contains('gentle check-in'));
    expect(store.audit.first['action'], contains('Reviewed'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('admin tabs adapt to a narrow screen and 200 percent text', (
    tester,
  ) async {
    await showAdmin(tester, DashboardSampleStore(), width: 390, textScale: 2);
    expect(tester.takeException(), isNull);
    for (final tab in [
      'Seniors & accounts',
      'Review queue',
      'Plans & access',
      'Activity log',
    ]) {
      await tapVisible(tester, find.text(tab));
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
