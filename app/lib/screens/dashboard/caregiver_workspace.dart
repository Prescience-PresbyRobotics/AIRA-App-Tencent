import 'package:flutter/material.dart';

import '../../theme.dart';
import 'sample_data.dart';
import 'widgets.dart';

/// Fictional care workspace. All mutations stay in [DashboardSampleStore].
/// This widget intentionally has no API or real-account controller dependency.
class CaregiverWorkspace extends StatefulWidget {
  const CaregiverWorkspace({
    super.key,
    required this.store,
    required this.seniorId,
  });

  final DashboardSampleStore store;
  final String seniorId;

  @override
  State<CaregiverWorkspace> createState() => _CaregiverWorkspaceState();
}

class _CaregiverWorkspaceState extends State<CaregiverWorkspace> {
  int _tab = 0;
  String _conversationKind = 'All';
  String _alertCategory = 'All';
  String _alertState = 'All';

  static const _tabs = [
    ('Overview', Icons.dashboard_outlined),
    ('Conversations', Icons.forum_outlined),
    ('Alerts & review', Icons.shield_outlined),
    ('Care plan', Icons.calendar_month_outlined),
    ('Memories', Icons.auto_awesome_outlined),
    ('Settings', Icons.tune_rounded),
  ];
  static const _green = Color(0xFF287460);
  static const _purple = Color(0xFF7965AB);
  static const _amber = Color(0xFFA16522);
  static const _red = Color(0xFFAA4842);
  static const _alertStates = [
    'open',
    'reviewing',
    'follow-up',
    'resolved',
    'dismissed'
  ];
  static bool _closed(Map<String, dynamic> alert) =>
      ['resolved', 'dismissed', 'closed'].contains(alert['status']);

  Map<String, dynamic> get senior => widget.store.senior(widget.seniorId);
  List<Map<String, dynamic>> _list(String key) =>
      (senior[key] as List).cast<Map<String, dynamic>>();
  String get _name => (senior['preferredName'] ?? senior['name']).toString();

  @override
  void didUpdateWidget(covariant CaregiverWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seniorId != widget.seniorId ||
        oldWidget.store != widget.store) {
      _tab = 0;
      _conversationKind = _alertCategory = _alertState = 'All';
    }
  }

  void _record(String action) {
    widget.store.record(widget.seniorId, action);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sample saved · $action'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: ChoiceChip(
                        avatar: Icon(_tabs[i].$2, size: 18),
                        label: Text(_tabs[i].$1),
                        selected: _tab == i,
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        onSelected: (_) => setState(() => _tab = i),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            switch (_tab) {
              1 => _conversations(),
              2 => _alerts(),
              3 => _carePlan(),
              4 => _memories(),
              5 => _settings(),
              _ => _overview(),
            },
          ],
        ),
      );

  Widget _overview() {
    final lonely = (senior['lonelyDays'] as List).cast<num>();
    final activity = (senior['conversationDays'] as List).cast<num>();
    final mood = (senior['moodDays'] as List).cast<num>();
    final count = activity.fold<int>(0, (sum, n) => sum + n.toInt());
    final open = _list('alerts').where((alert) => !_closed(alert)).toList();
    final medicines = _list('medicines');
    final expected = medicines.fold<int>(
      0,
      (sum, m) => sum + (m['expected'] as num).toInt(),
    );
    final taken = medicines.fold<int>(
      0,
      (sum, m) => sum + (m['taken'] as num).toInt(),
    );
    final change = lonely.last.toInt() - lonely.first.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid([
          DashboardMetric(
            label: 'Conversations this week',
            value: '$count',
            detail: '${senior['conversationMinutes']} minutes together',
            icon: Icons.forum_outlined,
            color: _green,
          ),
          DashboardMetric(
            label: 'Reported lonely days',
            value: '${lonely.last} / 7',
            detail:
                '${change > 0 ? '+' : ''}$change days from first sample week',
            icon: Icons.favorite_border,
            color: _purple,
          ),
          DashboardMetric(
            label: 'Needs a look',
            value: '${open.length}',
            detail:
                '${open.where((a) => a['priority'] == 'high').length} high-priority review signals',
            icon: Icons.shield_outlined,
            color: _amber,
          ),
          DashboardMetric(
            label: 'Medicine check-ins',
            value: '$taken / $expected',
            detail: 'Marked taken · Last 7 sample days',
            icon: Icons.medication_outlined,
            color: const Color(0xFF3D6D9C),
          ),
        ]),
        const SizedBox(height: 18),
        DashboardColumns(
          children: [
            DashCard(
              title: 'A little less lonely?',
              subtitle: 'Weekly self-report · Days feeling lonely out of 7',
              action: TextButton(
                onPressed: () => _editCheckIn(loneliness: true),
                child: const Text('Edit check-in'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashboardTrend(
                    values: lonely.map((n) => n.toDouble()).toList(),
                    labels: const ['25 Sep', '2 Oct', '9 Oct', '16 Oct'],
                    maxY: 7,
                    color: _purple,
                    unit: ' days',
                  ),
                  const SizedBox(height: 12),
                  _caption(
                    senior['lonelinessAmendment']?.toString() ??
                        'Self-reported answers, not a clinical score or evidence of AIRA’s impact.',
                  ),
                ],
              ),
            ),
            DashCard(
              title: 'Room for conversation',
              subtitle: 'Completed conversations · Last 7 sample days',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashboardBars(
                    values: activity.map((n) => n.toDouble()).toList(),
                    labels: const [
                      'Sat',
                      'Sun',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                    ],
                    color: _green,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      DashboardTag(
                        label: 'Senior started ${senior['seniorInitiated']}',
                        color: _green,
                      ),
                      DashboardTag(
                        label: 'AIRA started ${senior['airaInitiated']}',
                        color: _purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        DashboardColumns(
          children: [
            DashCard(
              title: 'How $_name says they feel',
              subtitle: 'Self-reported mood · 1 very low to 5 very good',
              action: TextButton(
                onPressed: () => _editCheckIn(loneliness: false),
                child: const Text('Edit check-in'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashboardTrend(
                    values: mood.map((n) => n.toDouble()).toList(),
                    labels: const [
                      'Sat',
                      'Sun',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                    ],
                    maxY: 5,
                    color: _amber,
                  ),
                  if (senior['moodAmendment'] != null) ...[
                    const SizedBox(height: 12),
                    _caption(senior['moodAmendment'].toString()),
                  ],
                  const Divider(height: 28),
                  _iconNote(
                    Icons.face_outlined,
                    'Expression cues stay separate',
                    'No facial-expression history in this sample. A face estimate does not establish someone’s mood.',
                  ),
                ],
              ),
            ),
            DashCard(
              title: 'Care at a glance',
              subtitle: 'Useful things to follow up on',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _iconNote(
                    Icons.waving_hand_outlined,
                    'Last conversation',
                    _date(senior['lastActive']),
                  ),
                  const Divider(height: 28),
                  _iconNote(
                    Icons.medication_outlined,
                    expected > taken
                        ? '${expected - taken} medicine check-ins unconfirmed'
                        : 'All sample medicine check-ins recorded',
                    'Unconfirmed does not mean a dose was missed. Ask before changing a routine.',
                  ),
                  const Divider(height: 28),
                  _iconNote(
                    Icons.calendar_month_outlined,
                    '${_list('plans').where((p) => p['status'] != 'done' && p['status'] != 'completed').length} upcoming plans',
                    'A personal occasion can be a lovely reason to check in.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _tab = 3),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Open care plan'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        DashboardColumns(
          children: [
            DashCard(
              title: 'Priority inbox',
              subtitle: 'Review the context before making a judgement',
              action: TextButton(
                onPressed: () => setState(() => _tab = 2),
                child: const Text('View all'),
              ),
              child: open.isEmpty
                  ? _empty(Icons.check_circle_outline, 'No open sample alerts')
                  : Column(
                      children: [
                        for (final alert in open.take(3)) _alertPreview(alert),
                      ],
                    ),
            ),
            DashCard(
              title: 'A familiar daily rhythm',
              subtitle: 'Current medicine and call schedule',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final medicine in medicines.where(
                    (m) => m['enabled'] == true,
                  ))
                    _scheduleRow(
                      medicine['time'].toString(),
                      medicine['name'].toString(),
                      medicine['frequency'].toString(),
                      Icons.medication_outlined,
                    ),
                  if (_settingsMap['callInvitations'] == true)
                    _scheduleRow(
                      senior['callTime']?.toString() ?? 'Not set',
                      'A call from AIRA',
                      'Daily invitation · Accept or decline',
                      Icons.call_outlined,
                    ),
                  const SizedBox(height: 10),
                  _caption(
                    'Sample schedule only. No medicine alarm or real call is sent.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricGrid(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
          final count = constraints.maxWidth >= 1100 && scaled <= 1.4
              ? 4
              : constraints.maxWidth >= 620 && scaled <= 1.5
                  ? 2
                  : 1;
          final width = (constraints.maxWidth - (count - 1) * 14) / count;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Future<void> _editCheckIn({required bool loneliness}) async {
    final key = loneliness ? 'lonelyDays' : 'moodDays';
    final entries = senior[key] as List;
    final result = await _editor(
      loneliness
          ? 'Edit sample loneliness check-in'
          : 'Edit sample mood check-in',
      [
        _Field(
          'score',
          loneliness ? 'Reported lonely days (0–7)' : 'Reported mood (1–5)',
          entries.last.toString(),
          choices: [
            for (var n = loneliness ? 0 : 1; n <= (loneliness ? 7 : 5); n++)
              '$n'
          ],
        ),
        const _Field('source', 'Source / reason for correction', '', lines: 2),
      ],
      introduction: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _caption(
          loneliness
              ? 'Correct the senior’s latest reported answer for 16 Oct 2026. Do not infer lonely days from usage or expression cues.'
              : 'Correct the senior’s latest reported answer for 16 Oct 2026. Scale: 1 very low, 2 low, 3 okay, 4 good, 5 very good. A face estimate is not a self-report.',
        ),
      ),
    );
    if (result == null) return;
    entries[entries.length - 1] = int.parse(result['score']!);
    senior[loneliness ? 'lonelinessAmendment' : 'moodAmendment'] =
        'Latest self-report amended by sample caregiver · ${result['source']}';
    _record(
        'Amended latest ${loneliness ? 'loneliness' : 'mood'} self-report to ${result['score']} · ${result['source']}');
  }

  Widget _conversations() {
    final rows = _list('conversations').where(
      (c) =>
          _conversationKind == 'All' ||
          c['kind'] == _conversationKind.toLowerCase(),
    );
    return DashCard(
      title: 'Conversations with AIRA',
      subtitle: 'Text, voice and video · Fictional transcripts for $_name',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filters(
            const ['All', 'Text', 'Voice', 'Video'],
            _conversationKind,
            (value) => setState(() => _conversationKind = value),
          ),
          const SizedBox(height: 12),
          for (final row in rows)
            _recordTile(
              icon: _kindIcon(row['kind']),
              title: row['title'].toString(),
              subtitle: row['summary'].toString(),
              metadata:
                  '${_date(row['date'])} · ${row['duration']} min · ${row['initiator']} started',
              tags: [
                DashboardTag(label: _title(row['kind'].toString())),
                if (row['reviewed'] == true)
                  const DashboardTag(label: 'Reviewed', color: _green),
              ],
              onTap: () => _conversationDetail(row),
            ),
          if (rows.isEmpty)
            _empty(
              Icons.forum_outlined,
              'No sample conversations in this category',
            ),
          const SizedBox(height: 8),
          _caption(
            'Open a conversation to review, correct or remove its sample history. Every change is logged.',
          ),
        ],
      ),
    );
  }

  Future<void> _conversationDetail(Map<String, dynamic> row) async {
    final owner = widget.seniorId;
    final source = senior;
    final store = widget.store;
    final name = _name;
    bool current() =>
        mounted &&
        widget.seniorId == owner &&
        identical(widget.store, store) &&
        store.seniors.contains(source) &&
        (source['conversations'] as List).contains(row);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(row['title'].toString()),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _caption(
                  'Fictional ${row['kind']} transcript · ${_date(row['date'])}',
                ),
                const SizedBox(height: 14),
                for (final raw in row['messages'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: raw['role'] == 'user'
                            ? AiraColors.sage
                            : AiraColors.cream,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              raw['role'] == 'user' ? name : 'AIRA',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 5),
                            SelectableText(raw['text'].toString()),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!current()) return;
              _remove('conversations', row, 'conversation');
            },
            child: const Text('Delete history'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!current()) return;
              _editConversation(row);
            },
            child: const Text('Edit history'),
          ),
          if (row['reviewed'] != true)
            TextButton(
              onPressed: () {
                if (!current()) {
                  Navigator.pop(dialogContext);
                  return;
                }
                row['reviewed'] = true;
                _record('Reviewed conversation: ${row['title']}');
                Navigator.pop(dialogContext);
              },
              child: const Text('Mark reviewed'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editConversation(Map<String, dynamic> row) async {
    final messages = (row['messages'] as List).cast<Map<String, dynamic>>();
    final result = await _editor('Edit sample conversation', [
      _Field('title', 'Conversation title', row['title'].toString()),
      _Field('summary', 'Summary', row['summary'].toString(), lines: 3),
      for (var i = 0; i < messages.length; i++)
        _Field(
          'message$i',
          '${messages[i]['role'] == 'user' ? _name : 'AIRA'} · Message ${i + 1}',
          messages[i]['text'].toString(),
          lines: 3,
        ),
      const _Field('reason', 'Reason for this correction', '', lines: 2),
    ]);
    if (result == null) return;
    row['title'] = result['title'];
    row['summary'] = result['summary'];
    for (var i = 0; i < messages.length; i++) {
      messages[i]['text'] = result['message$i'];
    }
    row['reviewed'] = true;
    _record('Edited history: ${row['title']} · ${result['reason']}');
  }

  Widget _alerts() {
    final all = _list('alerts');
    const categories = [
      'All',
      'Self-harm concern',
      'AI-related belief',
      'Unsafe AI reply',
      'Isolation',
      'Missed medicine',
      'Wellbeing concern',
    ];
    final rows = all.where(
      (a) =>
          (_alertCategory == 'All' || a['category'] == _alertCategory) &&
          (_alertState == 'All' || a['status'] == _alertState),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid([
          DashboardMetric(
            label: 'Open signals',
            value: '${all.where((a) => a['status'] == 'open').length}',
            detail: 'Ready for a person to review',
            icon: Icons.inbox_outlined,
            color: _amber,
          ),
          DashboardMetric(
            label: 'Being reviewed',
            value: '${all.where((a) => [
                  'reviewing',
                  'follow-up'
                ].contains(a['status'])).length}',
            detail: 'Follow-up in progress',
            icon: Icons.manage_search,
            color: _purple,
          ),
          DashboardMetric(
            label: 'Closed',
            value: '${all.where(_closed).length}',
            detail: 'Review decisions, not clinical outcomes',
            icon: Icons.task_alt,
            color: _green,
          ),
        ]),
        const SizedBox(height: 18),
        DashCard(
          title: 'Safety & wellbeing review',
          subtitle:
              'Look at what was said, who said it and the surrounding context',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _iconNote(
                Icons.info_outline,
                'Signals for human review',
                'AI-related belief concerns cover the requested “AI psychosis” review area. This is not a diagnosis. Fictional examples do not establish risk or trigger contact.',
              ),
              const SizedBox(height: 18),
              _filters(
                categories,
                _alertCategory,
                (v) => setState(() => _alertCategory = v),
              ),
              const SizedBox(height: 10),
              _filters(
                const ['All', ..._alertStates],
                _alertState,
                (v) => setState(() => _alertState = v),
              ),
              const SizedBox(height: 12),
              for (final row in rows) _alertPreview(row),
              if (rows.isEmpty)
                _empty(
                  Icons.shield_outlined,
                  'No sample alerts match these filters',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alertPreview(Map<String, dynamic> alert) => _recordTile(
        icon: alert['priority'] == 'high'
            ? Icons.flag_outlined
            : Icons.shield_outlined,
        iconColor: alert['priority'] == 'high' ? _red : _amber,
        title: alert['title'].toString(),
        subtitle: alert['category'].toString(),
        metadata:
            '${_date(alert['date'])} · ${_title(alert['status'].toString())}',
        tags: [
          DashboardTag(
            label: '${_title(alert['priority'].toString())} priority',
            color: alert['priority'] == 'high' ? _red : _amber,
          ),
        ],
        onTap: () => _reviewAlert(alert),
      );

  Future<void> _reviewAlert(Map<String, dynamic> alert) async {
    final sources = _list('conversations').where(
      (conversation) => conversation['id'] == alert['conversationId'],
    );
    final result = await _editor(
      'Review sample concern',
      [
        _Field(
          'status',
          'Review status',
          alert['status'].toString(),
          choices: _alertStates,
        ),
        _Field(
          'note',
          'Review note / next step',
          alert['note']?.toString() ?? '',
          lines: 4,
        ),
      ],
      introduction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            alert['title'].toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(alert['detail'].toString()),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AiraColors.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _caption('Fictional evidence · ${alert['source']}'),
                const SizedBox(height: 7),
                SelectableText('“${alert['excerpt']}”'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _caption(
            'Uncertain review signal. Read the full context; a keyword alone does not prove intent, a condition or harm. Saving a review contacts no one.',
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _conversationDetail(sources.first),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Read source conversation'),
            ),
          ],
          const SizedBox(height: 18),
        ],
      ),
    );
    if (result == null) return;
    alert['status'] = result['status'];
    alert['note'] = result['note'];
    _record(
      'Reviewed ${alert['category']}: ${result['status']} · ${result['note']}',
    );
  }

  Widget _carePlan() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashCard(
            title: 'Medicine reminders',
            subtitle: 'Manage the sample’s existing routine',
            action: FilledButton.tonalIcon(
              onPressed: () => _editMedicine(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add medicine'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _caption(
                  'Reminder management only. These fictional instructions are not a prescription or a dose recommendation.',
                ),
                const SizedBox(height: 12),
                for (final row in _list('medicines')) _medicineCard(row),
                if (_list('medicines').isEmpty)
                  _empty(Icons.medication_outlined,
                      'No sample medicine reminders'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          DashCard(
            title: 'Plans & follow-ups',
            subtitle:
                'Appointments, personal occasions and things to look forward to',
            action: FilledButton.tonalIcon(
              onPressed: () => _editPlan(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add plan'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _list('plans'))
                  _recordTile(
                    icon: Icons.event_outlined,
                    title: row['title'].toString(),
                    subtitle: _date(row['date']),
                    tags: [
                      DashboardTag(label: _title(row['status'].toString()))
                    ],
                    onTap: () => _editPlan(row),
                    actions: [
                      TextButton.icon(
                        onPressed: () => _editPlan(row),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Edit'),
                      ),
                      IconButton(
                        tooltip: 'Delete plan ${row['title']}',
                        onPressed: () => _remove('plans', row, 'plan'),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                if (_list('plans').isEmpty)
                  _empty(Icons.event_outlined, 'No sample plans yet'),
              ],
            ),
          ),
        ],
      );

  Widget _medicineCard(Map<String, dynamic> medicine) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AiraColors.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _iconNote(
              Icons.medication_outlined,
              medicine['name'].toString(),
              medicine['instructions'].toString(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DashboardTag(
                  label: '${medicine['time']} · ${medicine['frequency']}',
                  color: _purple,
                ),
                DashboardTag(
                  label: medicine['enabled'] == true ? 'Reminder on' : 'Paused',
                  color: _green,
                ),
                DashboardTag(
                  label:
                      '${medicine['taken']}/${medicine['expected']} marked taken',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (medicine['date'] != null)
              _caption('Starts ${_date(medicine['date'], withTime: false)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _editMedicine(medicine),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit reminder'),
                ),
                TextButton(
                  onPressed: () {
                    medicine['enabled'] = medicine['enabled'] != true;
                    _record(
                      '${medicine['enabled'] == true ? 'Enabled' : 'Paused'} medicine: ${medicine['name']}',
                    );
                  },
                  child: Text(medicine['enabled'] == true ? 'Pause' : 'Enable'),
                ),
                TextButton(
                  onPressed: (medicine['taken'] as num) >=
                          (medicine['expected'] as num)
                      ? null
                      : () {
                          medicine['taken'] =
                              (medicine['taken'] as num).toInt() + 1;
                          _record(
                            'Marked one sample medicine check-in taken: ${medicine['name']}',
                          );
                        },
                  child: const Text('Mark taken'),
                ),
                IconButton(
                  tooltip: 'Delete medicine ${medicine['name']}',
                  onPressed: () =>
                      _remove('medicines', medicine, 'medicine reminder'),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _editMedicine([Map<String, dynamic>? row]) async {
    final result = await _editor(
      row == null ? 'Add sample medicine' : 'Edit sample medicine',
      [
        _Field('name', 'Medicine name', row?['name']?.toString() ?? ''),
        _Field(
          'instructions',
          'Existing instructions',
          row?['instructions']?.toString() ?? '',
          lines: 2,
        ),
        _Field('date', 'Start date', _dateInput(row?['date']), date: true),
        _Field(
          'time',
          'Reminder time (24-hour)',
          row?['time']?.toString() ?? '09:00',
          time: true,
        ),
        _Field(
          'frequency',
          'Repeat',
          row?['frequency']?.toString() ?? 'Daily',
          choices: const ['Daily', 'Once'],
        ),
      ],
      introduction: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _caption(
          'Use the senior’s existing instructions. This sample cannot send reminders or change a prescription.',
        ),
      ),
    );
    if (result == null) return;
    final medicine = row ??
        <String, dynamic>{
          'id': _id(),
          'enabled': true,
          'taken': 0,
          'expected': 1,
        };
    medicine.addAll(result);
    if (row == null) _list('medicines').add(medicine);
    _record(
      '${row == null ? 'Added' : 'Edited'} medicine: ${medicine['name']}',
    );
  }

  Future<void> _editPlan([Map<String, dynamic>? row]) async {
    final parsed = DateTime.tryParse(row?['date']?.toString() ?? '');
    final source =
        parsed?.isUtc == true ? parsed!.add(const Duration(hours: 8)) : parsed;
    final result = await _editor(
      row == null ? 'Add sample plan' : 'Edit sample plan',
      [
        _Field('title', 'Plan or follow-up', row?['title']?.toString() ?? ''),
        _Field('date', 'Date', _dateInput(row?['date']), date: true),
        _Field(
          'time',
          'Time (24-hour)',
          source == null
              ? '15:00'
              : '${_pad(source.hour)}:${_pad(source.minute)}',
          time: true,
        ),
        _Field(
          'status',
          'Status',
          _planStatus(row?['status']),
          choices: const ['upcoming', 'done', 'cancelled'],
        ),
      ],
    );
    if (result == null) return;
    final plan = row ?? <String, dynamic>{'id': _id()};
    plan.addAll(result);
    plan['date'] = '${result['date']}T${result['time']}:00+08:00';
    if (row == null) _list('plans').add(plan);
    _record('${row == null ? 'Added' : 'Edited'} plan: ${plan['title']}');
  }

  static String _planStatus(dynamic value) =>
      value == 'done' || value == 'completed'
          ? 'done'
          : value == 'cancelled'
              ? 'cancelled'
              : 'upcoming';

  Widget _memories() => DashCard(
        title: 'The little things that matter',
        subtitle: 'Review what AIRA remembers about $_name',
        action: FilledButton.tonalIcon(
          onPressed: () => _editMemory(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add memory'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _caption(
              'Correct a detail or remove it. Memories are personal notes, not inferred diagnoses.',
            ),
            const SizedBox(height: 12),
            for (final memory in _list('memories'))
              _recordTile(
                icon: Icons.auto_awesome_outlined,
                title: memory['text'].toString(),
                subtitle: 'Source: ${memory['source']}',
                metadata: _date(memory['date'], withTime: false),
                tags: [
                  DashboardTag(
                    label: _title(memory['category'].toString()),
                    color: _purple,
                  ),
                ],
                onTap: () => _editMemory(memory),
                actions: [
                  TextButton.icon(
                    onPressed: () => _editMemory(memory),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  IconButton(
                    tooltip: 'Delete memory ${memory['text']}',
                    onPressed: () => _remove('memories', memory, 'memory'),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            if (_list('memories').isEmpty)
              _empty(Icons.auto_awesome_outlined, 'No sample memories yet'),
          ],
        ),
      );

  Future<void> _editMemory([Map<String, dynamic>? row]) async {
    final categories = <String>{
      'preference',
      'relationship',
      'routine',
      'plan',
      'other',
      if (row != null) row['category'].toString(),
    }.toList();
    final result = await _editor(
      row == null ? 'Add sample memory' : 'Edit sample memory',
      [
        _Field(
          'text',
          'What should AIRA remember?',
          row?['text']?.toString() ?? '',
          lines: 3,
        ),
        _Field(
          'category',
          'Category',
          row?['category']?.toString() ?? 'preference',
          choices: categories,
        ),
        _Field(
          'source',
          'Source or correction note',
          row?['source']?.toString() ?? 'Caregiver sample note',
        ),
      ],
    );
    if (result == null) return;
    final memory = row ??
        <String, dynamic>{
          'id': _id(),
          'date': _nowSingapore().toIso8601String(),
        };
    memory.addAll(result);
    if (row == null) _list('memories').add(memory);
    _record('${row == null ? 'Added' : 'Edited'} memory: ${memory['text']}');
  }

  Map<String, dynamic> get _settingsMap =>
      senior['settings'] as Map<String, dynamic>;

  Widget _settings() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardColumns(
            children: [
              DashCard(
                title: 'Personal details',
                subtitle: 'How AIRA knows this sample senior',
                action: TextButton.icon(
                  onPressed: _editProfile,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _labelValue('Full name', senior['name'].toString()),
                    _labelValue('Call me', _name),
                    _labelValue('Language', senior['language'].toString()),
                    _labelValue('Phone', senior['phone'].toString()),
                    _labelValue('Caregiver', senior['caregiver'].toString()),
                  ],
                ),
              ),
              DashCard(
                title: 'Calls from AIRA',
                subtitle: 'Let companionship fit their day',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _switch(
                      'callInvitations',
                      'Daily call invitation',
                      'The senior chooses to accept or decline.',
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(
                        senior['callTime']?.toString() ?? 'Choose a time',
                      ),
                      subtitle: const Text('Daily · Singapore time'),
                      trailing: const Icon(Icons.edit_outlined, size: 20),
                      onTap: _editCallTime,
                    ),
                    _switch(
                      'callSound',
                      'Incoming ringtone',
                      'Play a sound for an invitation.',
                    ),
                    _caption(
                      'Sample only. The live app currently requires an open, visible tab for incoming invitations.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          DashboardColumns(
            children: [
              DashCard(
                title: 'Personalisation & accessibility',
                child: Column(
                  children: [
                    _switch(
                      'memory_enabled',
                      'Personal memory',
                      'Remember useful user-stated details.',
                    ),
                    _switch(
                      'social_reminders',
                      'Plans & social follow-ups',
                      'Keep track of upcoming personal occasions.',
                    ),
                    _switch(
                      'medication_reminders',
                      'Medicine reminders',
                      'Use the reminders in their care plan.',
                    ),
                    _switch(
                      'largerText',
                      'Larger text',
                      'A roomier reading experience.',
                    ),
                    _switch(
                      'reducedMotion',
                      'Reduced motion',
                      'Gentler mascot animations.',
                    ),
                  ],
                ),
              ),
              DashCard(
                title: 'Privacy & care connections',
                subtitle:
                    'These sample switches change no real consent or access',
                child: Column(
                  children: [
                    _switch(
                      'store_conversations',
                      'Save conversations',
                      'Keep text and call histories.',
                    ),
                    _switch(
                      'impact_measurement',
                      'Wellbeing check-ins',
                      'Record self-reported loneliness and activity.',
                    ),
                    _switch(
                      'mood_history',
                      'Mood history',
                      'Keep self-reported mood entries.',
                    ),
                    _switch(
                      'face_cues',
                      'Live expression cues',
                      'Optional estimates during video calls.',
                    ),
                    _switch(
                      'monitoring_enabled',
                      'Safety review signals',
                      'Surface possible concerns for review.',
                    ),
                    _switch(
                      'urgent_sharing',
                      'Urgent caregiver sharing',
                      'Share eligible urgent concerns.',
                    ),
                    _switch(
                      'reviewed_sharing',
                      'Reviewed caregiver sharing',
                      'Share concerns after review.',
                    ),
                    _switch(
                      'admin_insights',
                      'Admin insights',
                      'Allow scoped wellbeing insight access.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _switch(String key, String label, String detail) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(detail, style: const TextStyle(fontSize: 13)),
        value: _settingsMap[key] == true,
        onChanged: (value) {
          _settingsMap[key] = value;
          _record('$label ${value ? 'on' : 'off'}');
        },
      );

  Future<void> _editProfile() async {
    final languages = <String>{
      senior['language'].toString(),
      'English',
      'Mandarin',
      'Malay',
      'Tamil',
    }.toList();
    final result = await _editor(
      'Edit sample personal details',
      [
        _Field('name', 'Full name', senior['name'].toString()),
        _Field('preferredName', 'Preferred name', _name),
        _Field('phone', 'Phone', senior['phone'].toString()),
        _Field(
          'language',
          'Preferred language',
          senior['language'].toString(),
          choices: languages,
        ),
        _Field('caregiver', 'Caregiver name', senior['caregiver'].toString()),
      ],
      introduction: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _caption(
          'Language is a sample preference. English is the live app’s first supported language. Changing this field does not contact a caregiver.',
        ),
      ),
    );
    if (result == null) return;
    senior.addAll(result);
    senior['initials'] = result['name']!
        .split(RegExp(r'\s+'))
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    _record('Updated personal details');
  }

  Future<void> _editCallTime() async {
    final result = await _editor('Set sample call time', [
      _Field(
        'callTime',
        'Daily time (24-hour, Singapore)',
        senior['callTime']?.toString() ?? '18:00',
        time: true,
      ),
    ]);
    if (result == null) return;
    senior['callTime'] = result['callTime'];
    _record(
      'Call invitation scheduled for ${result['callTime']} Singapore time',
    );
  }

  Future<void> _remove(
    String key,
    Map<String, dynamic> row,
    String label,
  ) async {
    final result = await _editor(
      'Remove sample $label?',
      [const _Field('reason', 'Reason for removal', '', lines: 2)],
      introduction: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'This removes only the fictional $label for $_name. Reset sample data restores it.',
        ),
      ),
      saveLabel: 'Remove sample',
    );
    if (result == null) return;
    _list(key).remove(row);
    _record('Removed $label · ${result['reason']}');
  }

  Future<Map<String, String>?> _editor(
    String title,
    List<_Field> fields, {
    Widget? introduction,
    String saveLabel = 'Save sample',
  }) async {
    final owner = widget.seniorId;
    final source = senior;
    final form = GlobalKey<FormState>();
    final controllers = {
      for (final field in fields)
        field.key: TextEditingController(text: field.value),
    };
    final route = DialogRoute<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (introduction != null) introduction,
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: field.choices != null
                          ? DropdownButtonFormField<String>(
                              initialValue: field.choices!.contains(field.value)
                                  ? field.value
                                  : field.choices!.first,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              items: [
                                for (final value in field.choices!)
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(_title(value)),
                                  ),
                              ],
                              onChanged: (value) =>
                                  controllers[field.key]!.text = value!,
                            )
                          : TextFormField(
                              controller: controllers[field.key],
                              minLines: field.lines,
                              maxLines: field.lines,
                              maxLength: field.lines > 1 ? 2000 : 200,
                              decoration: InputDecoration(
                                labelText: field.label,
                                alignLabelWithHint: field.lines > 1,
                                hintText: field.date ? 'YYYY-MM-DD' : null,
                                suffixIcon: field.date
                                    ? IconButton(
                                        tooltip:
                                            'Choose ${field.label.toLowerCase()}',
                                        icon: const Icon(
                                          Icons.calendar_month_outlined,
                                        ),
                                        onPressed: () async {
                                          final today = _nowSingapore();
                                          final first = DateTime(2020);
                                          final last = DateTime(today.year + 3);
                                          final entered = DateTime.tryParse(
                                                controllers[field.key]!.text,
                                              ) ??
                                              today;
                                          final initial =
                                              entered.isBefore(first)
                                                  ? first
                                                  : entered.isAfter(last)
                                                      ? last
                                                      : entered;
                                          final picked = await showDatePicker(
                                            context: dialogContext,
                                            initialDate: initial,
                                            firstDate: first,
                                            lastDate: last,
                                          );
                                          if (picked != null) {
                                            controllers[field.key]!.text =
                                                _dateInput(
                                              picked.toIso8601String(),
                                            );
                                          }
                                        },
                                      )
                                    : field.time
                                        ? IconButton(
                                            tooltip:
                                                'Choose ${field.label.toLowerCase()}',
                                            icon: const Icon(Icons.schedule),
                                            onPressed: () async {
                                              final parts =
                                                  controllers[field.key]!
                                                      .text
                                                      .split(':');
                                              final picked =
                                                  await showTimePicker(
                                                context: dialogContext,
                                                initialTime: TimeOfDay(
                                                  hour:
                                                      int.tryParse(parts.first)
                                                              ?.clamp(0, 23) ??
                                                          9,
                                                  minute: parts.length == 2
                                                      ? int.tryParse(parts.last)
                                                              ?.clamp(0, 59) ??
                                                          0
                                                      : 0,
                                                ),
                                              );
                                              if (picked != null) {
                                                controllers[field.key]!.text =
                                                    '${_pad(picked.hour)}:${_pad(picked.minute)}';
                                              }
                                            },
                                          )
                                        : null,
                              ),
                              validator: (value) {
                                final input = value?.trim() ?? '';
                                if (input.isEmpty) {
                                  return 'Please enter ${field.label.toLowerCase()}.';
                                }
                                if (field.date &&
                                    (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                            .hasMatch(input) ||
                                        DateTime.tryParse(input) == null ||
                                        _dateInput(input) != input)) {
                                  return 'Use a valid date: YYYY-MM-DD.';
                                }
                                if (field.time &&
                                    !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$')
                                        .hasMatch(input)) {
                                  return 'Use a time from 00:00 to 23:59.';
                                }
                                return null;
                              },
                            ),
                    ),
                  _caption(
                    'Only this sample senior is updated. No live account, recipient or provider is changed.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, {
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim(),
              });
            },
            child: Text(saveLabel),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    // The overlay keeps the fields mounted through its dismissal animation.
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (!mounted || widget.seniorId != owner || !identical(source, senior)) {
      return null;
    }
    return result;
  }

  Widget _filters(
    List<String> values,
    String selected,
    ValueChanged<String> onChanged,
  ) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(_title(value)),
              selected: value == selected,
              onSelected: (_) => onChanged(value),
            ),
        ],
      );

  Widget _recordTile({
    required IconData icon,
    required String title,
    required String subtitle,
    String? metadata,
    List<Widget> tags = const [],
    List<Widget> actions = const [],
    Color? iconColor,
    required VoidCallback onTap,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AiraColors.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 22, color: iconColor ?? _green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AiraColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(fontSize: 14, color: AiraColors.muted),
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 8),
                    _caption(metadata),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: tags),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

  Widget _scheduleRow(
    String time,
    String title,
    String detail,
    IconData icon,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AiraColors.sage,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: _green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$time · $title',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _caption(detail),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _iconNote(IconData icon, String title, String detail) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _green, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AiraColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _labelValue(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _caption(label),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
      );

  Widget _empty(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            Icon(icon, size: 34, color: AiraColors.muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );

  static Widget _caption(String text) => Text(
        text,
        style:
            const TextStyle(fontSize: 12, height: 1.5, color: AiraColors.muted),
      );
  static String _title(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
  static String _pad(int value) => value.toString().padLeft(2, '0');
  static String _id() => 'sample-${DateTime.now().microsecondsSinceEpoch}';
  static DateTime _nowSingapore() {
    final date = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime(date.year, date.month, date.day, date.hour, date.minute);
  }

  static String _dateInput(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '') ?? _nowSingapore();
    final local = date.isUtc ? date.add(const Duration(hours: 8)) : date;
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)}';
  }

  static String _date(dynamic value, {bool withTime = true}) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? 'No date set';
    final date = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = '${date.day} ${months[date.month - 1]} ${date.year}';
    return withTime ? '$day, ${_pad(date.hour)}:${_pad(date.minute)} SGT' : day;
  }

  static IconData _kindIcon(dynamic kind) => kind == 'video'
      ? Icons.videocam_outlined
      : kind == 'voice'
          ? Icons.call_outlined
          : Icons.chat_bubble_outline;
}

class _Field {
  const _Field(
    this.key,
    this.label,
    this.value, {
    this.lines = 1,
    this.choices,
    this.date = false,
    this.time = false,
  });
  final String key, label, value;
  final int lines;
  final List<String>? choices;
  final bool date, time;
}
