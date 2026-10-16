import 'package:aira/screens/dashboard/caregiver_workspace.dart';
import 'package:aira/screens/dashboard/sample_data.dart';
import 'package:aira/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

Future<void> showWorkspace(
  WidgetTester tester,
  DashboardSampleStore store, {
  String? seniorId,
  Size size = const Size(1400, 1800),
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
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: CaregiverWorkspace(
            store: store,
            seniorId: seniorId ?? store.seniors.first['id'] as String,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, String name) async {
  final finder = find.widgetWithText(ChoiceChip, name).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save sample'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('self-report corrections keep caregiver provenance',
      (tester) async {
    final store = DashboardSampleStore();
    await showWorkspace(tester, store);
    await tester.tap(find.text('Edit check-in').first);
    await tester.pumpAndSettle();
    final dropdown = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('0').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Source / reason for correction'),
        'Senior clarified their weekly answer.');
    await save(tester);
    expect((store.seniors.first['lonelyDays'] as List).last, 0);
    expect(store.seniors.first['lonelinessAmendment'],
        contains('amended by sample caregiver'));
    expect(store.audit.first['action'],
        contains('Amended latest loneliness self-report'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('stale transcript dialog cannot mutate a reset sample',
      (tester) async {
    final store = DashboardSampleStore();
    final original = (store.seniors.first['conversations'] as List).first;
    original['reviewed'] = false;
    await showWorkspace(tester, store);
    await tab(tester, 'Conversations');
    await tester.tap(find.text(original['title'] as String).first);
    await tester.pumpAndSettle();
    store.reset();
    final replacement = (store.seniors.first['conversations'] as List).first;
    replacement['reviewed'] = false;
    final auditLength = store.audit.length;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark reviewed'));
    await tester.pumpAndSettle();
    expect(replacement['reviewed'], false);
    expect(original['reviewed'], false);
    expect(store.audit.length, auditLength);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('memory edits are isolated and survive switching sample seniors',
      (tester) async {
    final store = DashboardSampleStore();
    final firstId = store.seniors.first['id'] as String;
    final secondId = store.seniors[1]['id'] as String;
    final firstLength = (store.senior(firstId)['memories'] as List).length;
    final otherLength = (store.senior(secondId)['memories'] as List).length;
    await showWorkspace(tester, store);
    await tab(tester, 'Memories');
    await tester.tap(find.text('Add memory'));
    await tester.pumpAndSettle();
    await tester.enterText(
        field('What should AIRA remember?'), 'Enjoys painting blue birds.');
    await save(tester);
    expect((store.senior(firstId)['memories'] as List).length, firstLength + 1);
    expect((store.senior(secondId)['memories'] as List).length, otherLength);
    expect(store.audit.first['seniorId'], firstId);
    await showWorkspace(tester, store, seniorId: secondId);
    await tab(tester, 'Memories');
    expect(find.text('Enjoys painting blue birds.'), findsNothing);
    await showWorkspace(tester, store, seniorId: firstId);
    await tab(tester, 'Memories');
    expect(find.text('Enjoys painting blue birds.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('plan edits keep Singapore time and medicine validates time',
      (tester) async {
    final store = DashboardSampleStore();
    await showWorkspace(tester, store);
    await tab(tester, 'Care plan');
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('Time (24-hour)')).controller!.text,
        '12:00');
    await tester.enterText(field('Time (24-hour)'), '17:45');
    await save(tester);
    expect((store.seniors.first['plans'] as List).first['date'],
        '2026-10-17T17:45:00+08:00');
    await tester.tap(find.text('Edit reminder').first);
    await tester.pumpAndSettle();
    await tester.enterText(field('Reminder time (24-hour)'), '30:00');
    await save(tester);
    expect(find.text('Use a time from 00:00 to 23:59.'), findsOneWidget);
    await tester.enterText(field('Reminder time (24-hour)'), '09:30');
    await tester.enterText(field('Start date'), '2026-12-20');
    await save(tester);
    final medicine = (store.seniors.first['medicines'] as List).first;
    expect(medicine['time'], '09:30');
    expect(medicine['date'], '2026-12-20');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('review needs a note and sample settings remain senior scoped',
      (tester) async {
    final store = DashboardSampleStore();
    await showWorkspace(tester, store);
    await tab(tester, 'Alerts & review');
    await tester.tap(find.text('Morning reminder needs a check-in'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Review note / next step'), '');
    await save(tester);
    expect(find.text('Please enter review note / next step.'), findsOneWidget);
    await tester.enterText(
        field('Review note / next step'), 'Ask about this at the next visit.');
    await save(tester);
    expect((store.seniors.first['alerts'] as List).first['note'],
        'Ask about this at the next visit.');
    await tab(tester, 'Settings');
    final otherMemorySetting =
        (store.seniors[1]['settings'] as Map)['memory_enabled'];
    final toggle = find.widgetWithText(SwitchListTile, 'Personal memory');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect((store.seniors.first['settings'] as Map)['memory_enabled'], false);
    expect((store.seniors[1]['settings'] as Map)['memory_enabled'],
        otherMemorySetting);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('care plan and memory editor fit phone at double text size',
      (tester) async {
    final store = DashboardSampleStore();
    await showWorkspace(tester, store, size: const Size(390, 844), scale: 2);
    await tab(tester, 'Care plan');
    expect(tester.takeException(), isNull);
    await tab(tester, 'Memories');
    await tester.ensureVisible(find.text('Add memory'));
    await tester.tap(find.text('Add memory'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
