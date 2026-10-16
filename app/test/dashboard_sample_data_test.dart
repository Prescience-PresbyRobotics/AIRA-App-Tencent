import 'package:flutter_test/flutter_test.dart';
import 'package:aira/screens/dashboard/sample_data.dart';

void main() {
  late DashboardSampleStore store;

  setUp(() => store = DashboardSampleStore());
  tearDown(() => store.dispose());

  test('reset creates independent fictional nested records', () {
    final old = store.seniors.first;
    final originalMemory = (old['memories'] as List).first['text'];
    old['name'] = 'Changed sample';
    (old['settings'] as Map)['memory_enabled'] = false;
    (old['memories'] as List).first['text'] = 'Changed note';
    (old['conversations'] as List).clear();
    store.record(old['id'] as String, 'Edited the fictional record');
    expect(store.audit.first['action'], 'Edited the fictional record');
    store.reset();
    final fresh = store.seniors.first;
    expect(fresh['name'], 'Mei Tan');
    expect((fresh['settings'] as Map)['memory_enabled'], true);
    expect((fresh['memories'] as List).first['text'], originalMemory);
    expect(fresh['conversations'], isNotEmpty);
    expect(identical(old, fresh), false);
    expect(
        store.audit
            .any((row) => row['action'] == 'Edited the fictional record'),
        false);
  });

  test('activity metrics match the fictional conversation evidence', () {
    var count = 0;
    for (final senior in store.seniors) {
      final conversations = (senior['conversations'] as List).cast<Map>();
      count += conversations.length;
      expect(
          (senior['conversationDays'] as List<int>)
              .fold<int>(0, (a, b) => a + b),
          conversations.length);
      expect(
          (senior['airaInitiated'] as int) + (senior['seniorInitiated'] as int),
          conversations.length);
      expect(senior['conversationMinutes'],
          conversations.fold<int>(0, (a, b) => a + (b['duration'] as int)));
      expect(
        senior['minutesUsed'],
        conversations
            .where((row) => row['kind'] == 'voice' || row['kind'] == 'video')
            .fold<int>(0, (sum, row) => sum + (row['duration'] as int)),
      );
      expect(
          (senior['moodDays'] as List<int>)
              .every((point) => point >= 1 && point <= 5),
          true);
      expect(
          (senior['lonelyDays'] as List<int>)
              .every((point) => point >= 0 && point <= 7),
          true);
      for (final conversation in conversations) {
        final date = DateTime.parse(conversation['date'] as String)
            .toUtc()
            .add(const Duration(hours: 8));
        expect(date.year, 2026);
        expect(date.month, 10);
        expect(date.day, inInclusiveRange(10, 16));
      }
    }
    expect(count, 44);
  });

  test(
      'deleting a sample conversation refreshes aggregates and preserves quota edits',
      () {
    final senior = store.seniors.first;
    final beforeCount = (senior['conversations'] as List).length;
    final beforeMinutes = senior['conversationMinutes'] as int;
    final removed = (senior['conversations'] as List).removeAt(0) as Map;
    senior['minutesUsed'] = 222;
    var notified = 0;
    store.addListener(() => notified++);
    store.record(senior['id'] as String, 'Deleted a sample conversation');
    expect(
        (senior['conversationDays'] as List<int>).fold<int>(0, (a, b) => a + b),
        beforeCount - 1);
    expect(
        (senior['airaInitiated'] as int) + (senior['seniorInitiated'] as int),
        beforeCount - 1);
    expect(senior['conversationMinutes'],
        beforeMinutes - (removed['duration'] as int));
    expect(senior['minutesUsed'], 222);
    expect(notified, 1);
    expect(store.audit.first['seniorId'], senior['id']);
  });

  test('every review alert links to its actual fictional conversation excerpt',
      () {
    for (final senior in store.seniors) {
      final conversations = (senior['conversations'] as List).cast<Map>();
      for (final alert in (senior['alerts'] as List).cast<Map>()) {
        final evidence = conversations
            .singleWhere((row) => row['id'] == alert['conversationId']);
        final quote = (alert['excerpt'] as String).replaceFirst('AIRA: ', '');
        expect(
            (evidence['messages'] as List)
                .any((message) => message['text'] == quote),
            true);
        expect(alert['source'], isNotEmpty);
        expect(alert['date'], evidence['date']);
        expect(['open', 'reviewing', 'resolved'], contains(alert['status']));
      }
    }
    final daniel = store.senior('sample-daniel');
    expect(
        (daniel['alerts'] as List)
            .any((row) => row['category'] == 'AI-related belief'),
        true);
    final resolved = (store.senior('sample-yusuf')['alerts'] as List).first;
    expect(resolved['status'], 'resolved');
    expect(resolved['note'], contains('False positive'));
  });

  test('all fixture IDs are unique and all contacts clearly fictional', () {
    final ids = <String>[];
    for (final senior in store.seniors) {
      ids.add(senior['id'] as String);
      expect(senior['email'], endsWith('@sample.example.invalid'));
      expect(senior['phone'], startsWith('Sample contact'));
      for (final key in [
        'memories',
        'medicines',
        'plans',
        'conversations',
        'alerts'
      ]) {
        for (final row in senior[key] as List) {
          ids.add(row['id'] as String);
        }
      }
      expect(
          (senior['settings'] as Map).keys,
          containsAll([
            'face_cues',
            'largerText',
            'reducedMotion',
            'store_conversations',
            'admin_insights'
          ]));
    }
    expect(ids.toSet().length, ids.length);
  });
}
