import 'package:flutter/foundation.dart';

/// Fictional, deliberately transient records for the dashboard design workspace.
/// This store has no API, authentication, browser-storage or device integration.
class DashboardSampleStore extends ChangeNotifier {
  DashboardSampleStore() {
    _seed();
  }

  late List<Map<String, dynamic>> seniors;
  late List<Map<String, dynamic>> audit;
  int _revision = 0;

  Map<String, dynamic> senior(String id) =>
      seniors.firstWhere((row) => row['id'] == id);

  void record(String seniorId, String action) {
    final matches = seniors.where((row) => row['id'] == seniorId);
    for (final row in matches) {
      _refreshActivity(row);
    }
    final editedAt = DateTime(2026, 10, 16, 16)
        .add(Duration(minutes: _revision + 1))
        .toIso8601String();
    audit.insert(0, {
      'id': 'sample-edit-${++_revision}',
      'seniorId': seniorId,
      'senior': matches.isEmpty ? 'Sample workspace' : matches.first['name'],
      'action': action,
      'date': '$editedAt+08:00',
      'actor': 'Sample operator',
    });
    notifyListeners();
  }

  void _refreshActivity(Map<String, dynamic> profile) {
    final conversations =
        (profile['conversations'] as List).cast<Map<String, dynamic>>();
    final days = List<int>.filled(7, 0);
    for (final conversation in conversations) {
      final parsed = DateTime.tryParse(conversation['date'] as String? ?? '');
      if (parsed == null) continue;
      final local = parsed.toUtc().add(const Duration(hours: 8));
      if (local.year == 2026 &&
          local.month == 10 &&
          local.day >= 10 &&
          local.day <= 16) {
        days[local.day - 10]++;
      }
    }
    profile['conversationDays'] = days;
    profile['airaInitiated'] =
        conversations.where((row) => row['initiator'] == 'AIRA').length;
    profile['seniorInitiated'] =
        conversations.where((row) => row['initiator'] == 'Senior').length;
    profile['conversationMinutes'] = conversations.fold<int>(
        0, (sum, row) => sum + (row['duration'] as num).toInt());
    // Plan usage is historical account usage; deleting a transcript does not
    // refund it, and administrative quota edits remain independently editable.
  }

  void reset() {
    _seed();
    notifyListeners();
  }

  void _seed() {
    _revision = 0;
    seniors = [
      _profile(
        index: 0,
        name: 'Mei Tan',
        initials: 'MT',
        age: 72,
        caregiver: 'Lily · daughter',
        plan: 'Family',
        activity: [2, 1, 2, 1, 2, 2, 2],
        mood: [3, 3, 4, 3, 4, 4, 4],
        lonely: [5, 4, 3, 3],
        topics: [
          'Orchids on the balcony',
          'Saturday lunch with Lily',
          'A quieter afternoon',
        ],
        memories: [
          _memory(
            'mei-orchids',
            'Loves growing orchids on her balcony.',
            'preference',
            'User statement · text chat',
            15,
          ),
          _memory(
            'mei-lily',
            'Daughter Lily visits for lunch on Saturdays.',
            'relationship',
            'User statement · voice call',
            14,
          ),
          _memory(
            'mei-music',
            'Enjoys old Mandarin songs and gentle morning walks.',
            'preference',
            'User statement · text chat',
            12,
          ),
        ],
        medicines: [
          _medicine(
            'mei-am',
            'Morning medicine',
            'Follow the existing prescription label.',
            '08:00',
            6,
            7,
          ),
          _medicine(
            'mei-pm',
            'Evening medicine',
            'Reminder only · no dose changes.',
            '20:00',
            7,
            7,
          ),
        ],
        plans: [
          _plan('mei-lunch', 'Lunch with Lily', 17, 12),
          _plan('mei-garden', 'Water the balcony orchids', 17, 9),
          _plan('mei-walk', 'Neighbourhood morning walk', 18, 8),
        ],
        alerts: [
          _alert(
            'mei-routine',
            'Missed medicine',
            'medium',
            'Morning reminder needs a check-in',
            'One scheduled reminder has no acknowledgement. This does not establish whether medicine was taken.',
            'No acknowledgement recorded for the 08:00 reminder.',
            'App activity · missing acknowledgement',
            16,
            9,
            'open',
          ),
          _alert(
            'mei-quiet',
            'Isolation',
            'low',
            'A quieter week at home',
            'Mei described staying home more often. Ask how she feels and whether she would enjoy company.',
            'I stayed home most afternoons this week. It felt a little quiet.',
            'User statement · fictional text conversation',
            15,
            15,
            'reviewing',
            note:
                'Sample caregiver note: ask about a short walk at Saturday lunch.',
          ),
        ],
      ),
      _profile(
        index: 1,
        name: 'Daniel Lim',
        initials: 'DL',
        age: 79,
        caregiver: 'Marcus · son',
        plan: 'Family',
        activity: [1, 2, 1, 2, 1, 1, 2],
        mood: [3, 2, 3, 2, 2, 2, 3],
        lonely: [4, 5, 4, 5],
        topics: [
          'Missing my friends',
          'What Aira can and cannot know',
          'The old chess club',
        ],
        memories: [
          _memory(
            'daniel-chess',
            'Used to play chess every Thursday at the community club.',
            'preference',
            'User statement · voice call',
            14,
          ),
          _memory(
            'daniel-marcus',
            'Son Marcus calls on Sunday afternoons.',
            'relationship',
            'User statement · text chat',
            12,
          ),
          _memory(
            'daniel-name',
            'Prefers to be called Uncle Daniel.',
            'preference',
            'User statement · text chat',
            10,
          ),
        ],
        medicines: [
          _medicine(
            'daniel-am',
            'Daily medicine',
            'Use the regimen already agreed with the clinician.',
            '09:00',
            7,
            7,
          ),
        ],
        plans: [
          _plan('daniel-call', 'Sunday call with Marcus', 18, 15),
          _plan('daniel-chess', 'Ask about the community chess club', 19, 10),
        ],
        alerts: [
          _alert(
            'daniel-support',
            'Self-harm concern',
            'high',
            'Needs a personal check-in',
            'A concerning user statement was flagged for human review. Intent and immediate safety have not been established. This is a fictional example, not a diagnosis or an emergency service.',
            'Some evenings I wonder if anyone would notice if I was no longer here.',
            'Automated review signal · user statement in sample text chat',
            16,
            10,
            'open',
            note:
                'Sample routing: caregiver inbox. No external contact occurred.',
          ),
          _alert(
            'daniel-belief',
            'AI-related belief',
            'medium',
            'Clarify Aira’s limits',
            'Daniel attributed private knowledge to Aira. Review the surrounding conversation and respond with a grounded explanation. This does not establish psychosis.',
            'Can you hear me when the app is closed? Sometimes it feels like you know.',
            'Automated review signal · fictional voice transcript',
            15,
            14,
            'reviewing',
            note:
                'Sample note: remind Daniel that Aira is an AI and cannot listen when the app is closed.',
          ),
        ],
      ),
      _profile(
        index: 2,
        name: 'Asha Menon',
        initials: 'AM',
        age: 68,
        caregiver: 'Priya · daughter',
        plan: 'Companion',
        activity: [2, 2, 2, 3, 1, 2, 2],
        mood: [4, 4, 3, 4, 4, 5, 4],
        lonely: [3, 3, 2, 2],
        topics: [
          'Cooking for the family',
          'A question about my medicine',
          'Tuesday book club',
        ],
        memories: [
          _memory(
            'asha-cooking',
            'Enjoys cooking vegetarian meals for the family.',
            'preference',
            'User statement · text chat',
            15,
          ),
          _memory(
            'asha-priya',
            'Daughter Priya lives nearby.',
            'relationship',
            'User statement · video call',
            13,
          ),
          _memory(
            'asha-books',
            'Goes to a book club on Tuesdays.',
            'plan',
            'User statement · voice call',
            11,
          ),
        ],
        medicines: [
          _medicine(
            'asha-daily',
            'Daily medicine',
            'Take only as directed on your existing prescription.',
            '08:30',
            7,
            7,
          ),
        ],
        plans: [
          _plan('asha-family', 'Family lunch', 18, 12),
          _plan('asha-books', 'Book club at the library', 20, 14),
          _plan('asha-recipe', 'Share a recipe with Priya', 17, 16),
        ],
        alerts: [
          _alert(
            'asha-reply',
            'Unsafe AI reply',
            'high',
            'Review an inappropriate medicine reply',
            'A deliberately unsafe sample assistant reply suggested changing an existing regimen. It is included only to demonstrate the review workflow. Aira should instead direct medicine changes to a clinician or pharmacist.',
            'AIRA: You can probably skip it if you feel fine.',
            'Automated review signal · fictional assistant output',
            15,
            11,
            'open',
            note:
                'Sample review action: flag response quality and add a correction.',
          ),
        ],
      ),
      _profile(
        index: 3,
        name: 'Yusuf Rahman',
        initials: 'YR',
        age: 75,
        caregiver: 'Amir · nephew',
        plan: 'Trial',
        activity: [1, 1, 1, 1, 2, 1, 1],
        mood: [3, 4, 3, 4, 3, 4, 4],
        lonely: [4, 3, 3, 2],
        topics: [
          'A very dramatic TV show',
          'Morning at the park',
          'Tea with Amir',
        ],
        memories: [
          _memory(
            'yusuf-park',
            'Likes taking photos of birds during park walks.',
            'preference',
            'User statement · video call',
            15,
          ),
          _memory(
            'yusuf-amir',
            'Nephew Amir visits for tea.',
            'relationship',
            'User statement · text chat',
            13,
          ),
          _memory(
            'yusuf-tv',
            'Enjoys detective television dramas.',
            'preference',
            'User statement · voice call',
            12,
          ),
        ],
        medicines: [
          _medicine(
            'yusuf-evening',
            'Evening medicine',
            'Follow the existing prescription label.',
            '19:00',
            7,
            7,
          ),
        ],
        plans: [
          _plan('yusuf-tea', 'Tea with Amir', 17, 16),
          _plan('yusuf-park', 'Morning birdwatching at the park', 18, 7),
        ],
        alerts: [
          _alert(
            'yusuf-quote',
            'Wellbeing concern',
            'low',
            'Context checked · television quotation',
            'The flagged phrase referred to a character in a television drama. Human review marked this sample as a false positive after reading the surrounding conversation.',
            'That detective said he had nothing left to live for. Such a dramatic show!',
            'Human review · fictional conversation context',
            14,
            18,
            'resolved',
            note:
                'False positive: fictional television quotation, not the senior expressing personal intent.',
          ),
        ],
      ),
    ];
    audit = [
      {
        'id': 'sample-audit-1',
        'seniorId': 'sample-yusuf',
        'senior': 'Yusuf Rahman',
        'action': 'Marked television quotation as a false positive',
        'date': '2026-10-15T10:10:00+08:00',
        'actor': 'Sample reviewer',
      },
      {
        'id': 'sample-audit-2',
        'seniorId': 'sample-mei',
        'senior': 'Mei Tan',
        'action': 'Added a Saturday lunch follow-up',
        'date': '2026-10-15T09:30:00+08:00',
        'actor': 'Sample caregiver',
      },
      {
        'id': 'sample-audit-3',
        'seniorId': 'sample-daniel',
        'senior': 'Daniel Lim',
        'action': 'Started review of an AI-related belief signal',
        'date': '2026-10-15T14:30:00+08:00',
        'actor': 'Sample reviewer',
      },
    ];
    audit.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }
}

Map<String, dynamic> _profile({
  required int index,
  required String name,
  required String initials,
  required int age,
  required String caregiver,
  required String plan,
  required List<int> activity,
  required List<int> mood,
  required List<int> lonely,
  required List<String> topics,
  required List<Map<String, dynamic>> memories,
  required List<Map<String, dynamic>> medicines,
  required List<Map<String, dynamic>> plans,
  required List<Map<String, dynamic>> alerts,
}) {
  final slug = name.split(' ').first.toLowerCase();
  final conversations = <Map<String, dynamic>>[];
  for (var day = 0; day < activity.length; day++) {
    for (var session = 0; session < activity[day]; session++) {
      final number = conversations.length;
      final kind = ['text', 'voice', 'video'][(number + index) % 3];
      final topic = topics[number % topics.length];
      conversations.add({
        'id': '$slug-conversation-$number',
        'kind': kind,
        'title': topic,
        'date':
            '2026-10-${(10 + day).toString().padLeft(2, '0')}T${(9 + session * 4).toString().padLeft(2, '0')}:00:00+08:00',
        'duration': kind == 'text' ? 3 + number % 3 : 7 + number % 8,
        'initiator': number.isEven ? 'Senior' : 'AIRA',
        'summary': 'A fictional conversation about ${topic.toLowerCase()}.',
        'messages': <Map<String, dynamic>>[
          {
            'role': 'assistant',
            'text':
                'Hey ${name.split(' ').first}! What has your day been like?',
          },
          {
            'role': 'user',
            'text': 'I was thinking about ${topic.toLowerCase()}.',
          },
          {'role': 'assistant', 'text': 'Ooh, tell me a little more!'},
        ],
        'reviewed': number % 4 != 0,
      });
    }
  }
  conversations.sort(
    (a, b) => (b['date'] as String).compareTo(a['date'] as String),
  );
  // Include the actual quoted context for each fictional review case.
  for (var i = 0; i < alerts.length; i++) {
    final alert = alerts[i];
    final conversation = conversations[i];
    alert['conversationId'] = conversation['id'];
    conversation['title'] = alert['title'];
    conversation['summary'] = alert['detail'];
    conversation['date'] = alert['date'];
    conversation['messages'] = <Map<String, dynamic>>[
      {'role': 'assistant', 'text': 'How has today been for you?'},
      {
        'role': alert['category'] == 'Unsafe AI reply' ? 'assistant' : 'user',
        'text': (alert['excerpt'] as String).replaceFirst('AIRA: ', ''),
      },
      if (alert['category'] != 'Unsafe AI reply')
        {
          'role': 'assistant',
          'text': alert['category'] == 'Self-harm concern'
              ? 'I’m glad you told me. Are you safe right now? We can think about someone you trust to be with you.'
              : alert['category'] == 'AI-related belief'
                  ? 'I’m an AI character. I can only respond to what you share here while we’re connected.'
                  : 'Thanks for telling me. How are you feeling about that?',
        },
    ];
    conversation['reviewed'] = alert['status'] == 'resolved';
  }
  conversations.sort(
    (a, b) => (b['date'] as String).compareTo(a['date'] as String),
  );
  // Trends and durations derive from the actual fictional conversation list.
  final dailyCounts = List<int>.filled(7, 0);
  for (final row in conversations) {
    final day = DateTime.parse(row['date'] as String)
        .toUtc()
        .add(const Duration(hours: 8))
        .day;
    if (day >= 10 && day <= 16) dailyCounts[day - 10]++;
  }
  final minutes = conversations.fold<int>(
    0,
    (sum, row) => sum + row['duration'] as int,
  );
  return {
    'id': 'sample-$slug',
    'name': name,
    'preferredName': index == 1 ? 'Uncle Daniel' : name.split(' ').first,
    'initials': initials,
    'age': age,
    'email': '$slug@sample.example.invalid',
    'phone': 'Sample contact ${index + 1}',
    'language': 'English',
    'status': 'Active',
    'accessRole': 'Senior',
    'plan': plan,
    'planEnds':
        index == 3 ? '2026-10-23T23:59:00+08:00' : '2026-11-16T23:59:00+08:00',
    'minutesLimit': plan == 'Family'
        ? 600
        : plan == 'Companion'
            ? 300
            : 120,
    'minutesUsed': conversations
        .where((row) => row['kind'] == 'voice' || row['kind'] == 'video')
        .fold<int>(0, (sum, row) => sum + (row['duration'] as int)),
    'caregiver': caregiver,
    'joined':
        '2026-09-${(10 + index).toString().padLeft(2, '0')}T09:00:00+08:00',
    'lastActive': conversations.first['date'],
    'lonelyDays': lonely,
    'conversationDays': dailyCounts,
    'moodDays': mood,
    'airaInitiated':
        conversations.where((row) => row['initiator'] == 'AIRA').length,
    'seniorInitiated':
        conversations.where((row) => row['initiator'] == 'Senior').length,
    'conversationMinutes': minutes,
    'memories': memories,
    'medicines': medicines,
    'plans': plans,
    'conversations': conversations,
    'alerts': alerts,
    'callTime': '10:00',
    'timezone': 'Asia/Singapore',
    'settings': <String, bool>{
      'store_conversations': true,
      'memory_enabled': true,
      'impact_measurement': true,
      'mood_history': true,
      'face_cues': true,
      'social_reminders': true,
      'medication_reminders': true,
      'monitoring_enabled': true,
      'admin_insights': true,
      'urgent_sharing': true,
      'reviewed_sharing': true,
      'largerText': index == 1,
      'reducedMotion': false,
      'callInvitations': true,
      'callSound': true,
    },
  };
}

Map<String, dynamic> _memory(
  String id,
  String text,
  String category,
  String source,
  int day,
) =>
    {
      'id': 'memory-$id',
      'text': text,
      'category': category,
      'source': source,
      'date': '2026-10-${day.toString().padLeft(2, '0')}T11:00:00+08:00',
    };

Map<String, dynamic> _medicine(
  String id,
  String name,
  String instructions,
  String time,
  int taken,
  int expected,
) =>
    {
      'id': 'medicine-$id',
      'name': name,
      'instructions': instructions,
      'time': time,
      'date': '2026-10-01T$time:00+08:00',
      'frequency': 'Daily',
      'enabled': true,
      'taken': taken,
      'expected': expected,
    };

Map<String, dynamic> _plan(String id, String title, int day, int hour) => {
      'id': 'plan-$id',
      'title': title,
      'date':
          '2026-10-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00+08:00',
      'status': 'Upcoming',
    };

Map<String, dynamic> _alert(
  String id,
  String category,
  String priority,
  String title,
  String detail,
  String excerpt,
  String source,
  int day,
  int hour,
  String status, {
  String note = '',
}) =>
    {
      'id': 'alert-$id',
      'category': category,
      'priority': priority,
      'title': title,
      'detail': detail,
      'excerpt': excerpt,
      'source': source,
      'date':
          '2026-10-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00+08:00',
      'status': status,
      'note': note,
    };
