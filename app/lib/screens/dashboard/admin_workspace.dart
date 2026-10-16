import 'package:flutter/material.dart';

import '../../theme.dart';
import 'sample_data.dart';
import 'widgets.dart';

/// A cohort workspace backed exclusively by the resettable sample store.
class AdminWorkspace extends StatefulWidget {
  const AdminWorkspace({
    super.key,
    required this.store,
    required this.onOpenSenior,
  });
  final DashboardSampleStore store;
  final ValueChanged<String> onOpenSenior;

  @override
  State<AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<AdminWorkspace> {
  int _tab = 0;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _query = '',
      _category = 'All concerns',
      _priority = 'All priorities',
      _status = 'All statuses';
  static const _tabs = [
    'Overview',
    'Seniors & accounts',
    'Review queue',
    'Plans & access',
    'Activity log',
  ];
  static const _green = Color(0xFF327363),
      _amber = Color(0xFF9B6A29),
      _red = Color(0xFFB25952),
      _purple = Color(0xFF7A6B9F);
  List<Map<String, dynamic>> get _seniors => widget.store.seniors;
  List<Map<String, dynamic>> _rows(dynamic value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
  List<double> _numbers(dynamic value) => value is List
      ? value.whereType<num>().map((n) => n.toDouble()).toList()
      : [];
  double _sum(Iterable<num> values) =>
      values.fold(0, (total, value) => total + value);
  String _n(num value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(1);
  String _text(dynamic value) => value?.toString() ?? '';
  String _date(dynamic value) {
    final parsed = value is DateTime ? value : DateTime.tryParse(_text(value));
    // Date-only forms are calendar values, not device-timezone instants.
    final date =
        parsed?.isUtc == true ? parsed!.add(const Duration(hours: 8)) : parsed;
    return date == null
        ? _text(value)
        : '${date.day} ${const [
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
            'Dec'
          ][date.month - 1]} ${date.year}';
  }

  String _dateInput(dynamic value) {
    final parsed = value is DateTime ? value : DateTime.tryParse(_text(value));
    // Date-only forms are calendar values, not device-timezone instants.
    final date =
        parsed?.isUtc == true ? parsed!.add(const Duration(hours: 8)) : parsed;
    return date == null
        ? _text(value)
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<({Map<String, dynamic> senior, Map<String, dynamic> alert})>
      get _alerts => [
            for (final senior in _seniors)
              for (final alert in _rows(senior['alerts']))
                (senior: senior, alert: alert),
          ];
  bool _closed(Map<String, dynamic> alert) => [
        'resolved',
        'closed',
        'dismissed',
      ].contains(_text(alert['status']).toLowerCase());
  bool _reviewed(Map<String, dynamic> alert) =>
      _closed(alert) ||
      [
        'reviewed',
        'reviewing',
        'in review',
        'follow-up',
        'follow-up needed',
      ].contains(_text(alert['status']).toLowerCase());
  String _concern(Map<String, dynamic> alert) {
    final raw = _text(alert['category']);
    if (raw.toLowerCase().contains('psychosis') ||
        raw.toLowerCase().contains('belief')) {
      return 'AI-related belief concerns';
    }
    return raw.isEmpty ? 'Other concern' : raw;
  }

  Color _priorityColor(dynamic value) =>
      _text(value).toLowerCase() == 'urgent' ||
              _text(value).toLowerCase() == 'high'
          ? _red
          : _amber;
  List<double> _cohort(String field, int count, {bool average = false}) =>
      List.generate(count, (i) {
        final values = _seniors
            .map((s) => _numbers(s[field]))
            .where((v) => v.length > i)
            .map((v) => v[i])
            .toList();
        return values.isEmpty
            ? 0
            : _sum(values) / (average ? values.length : 1);
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  ChoiceChip(
                    label: Text(_tabs[i]),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            switch (_tab) {
              0 => _overview(),
              1 => _directory(),
              2 => _reviewQueue(),
              3 => _plans(),
              _ => _activity(),
            },
          ],
        ),
      );

  Widget _metricGrid(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final count = constraints.maxWidth > 1080 && scale < 1.5
              ? 4
              : constraints.maxWidth > 560 && scale < 1.6
                  ? 2
                  : 1;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final child in children)
                SizedBox(
                  width: (constraints.maxWidth - (count - 1) * 16) / count,
                  child: child,
                ),
            ],
          );
        },
      );

  Widget _overview() {
    final supported =
        _seniors.where((s) => _sum(_numbers(s['conversationDays'])) > 0).length;
    final count = _sum(_cohort('conversationDays', 7));
    final minutes = _sum(
      _seniors.map((s) => (s['conversationMinutes'] as num?) ?? 0),
    );
    final open = _alerts.where((row) => !_closed(row.alert)).length;
    final reviewed = _alerts.where((row) => _reviewed(row.alert)).length;
    final lonely = _cohort('lonelyDays', 4, average: true);
    final responding =
        _seniors.where((s) => _numbers(s['lonelyDays']).length == 4).length;
    final moodReplies = _seniors.fold<int>(
      0,
      (n, s) => n + _numbers(s['moodDays']).length,
    );
    final initiator = [
      _sum(_seniors.map((s) => (s['seniorInitiated'] as num?) ?? 0)),
      _sum(_seniors.map((s) => (s['airaInitiated'] as num?) ?? 0)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricGrid([
          DashboardMetric(
            label: 'Seniors reached',
            value: '$supported / ${_seniors.length}',
            detail: 'At least one conversation this week',
            icon: Icons.people_alt_outlined,
            color: _green,
          ),
          DashboardMetric(
            label: 'Conversations',
            value: _n(count),
            detail: 'Last 7 days · across the sample cohort',
            icon: Icons.forum_outlined,
            color: _purple,
          ),
          DashboardMetric(
            label: 'Together this week',
            value: '${_n(minutes)} min',
            detail: count > 0
                ? '${_n(minutes / count)} min per conversation on average'
                : 'No completed conversations',
            icon: Icons.schedule,
            color: _amber,
          ),
          DashboardMetric(
            label: 'Open concerns',
            value: '$open',
            detail: '$reviewed of ${_alerts.length} have a recorded review',
            icon: Icons.shield_outlined,
            color: _red,
          ),
        ]),
        const SizedBox(height: 20),
        DashboardColumns(
          children: [
            DashCard(
              title: 'A little connection, every day',
              subtitle: 'Conversations across all sample seniors · last 7 days',
              child: DashboardBars(
                values: _cohort('conversationDays', 7),
                labels: const [
                  '10 Oct',
                  '11 Oct',
                  '12 Oct',
                  '13 Oct',
                  '14 Oct',
                  '15 Oct',
                  '16 Oct',
                ],
                color: _green,
                unit: ' chats',
              ),
            ),
            DashCard(
              title: 'Reported lonely days',
              subtitle: 'Cohort average · days out of 7 · weekly self-report',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardTrend(
                    values: lonely,
                    labels: const ['25 Sep', '2 Oct', '9 Oct', '16 Oct'],
                    maxY: 7,
                    color: _purple,
                    unit: ' days',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$responding of ${_seniors.length} seniors answered all four weeks. Sample change: ${_n(lonely.last - lonely.first)} days. This does not establish an effect of AIRA.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        DashboardColumns(
          children: [
            DashCard(
              title: 'Who starts the conversation?',
              subtitle: 'Last 7 days · completed conversations',
              child: Column(
                children: [
                  DashboardBars(
                    values: initiator,
                    labels: const ['Senior', 'AIRA'],
                    color: _amber,
                    unit: ' chats',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_n(initiator.first)} senior-led · ${_n(initiator.last)} AIRA-led',
                  ),
                ],
              ),
            ),
            DashCard(
              title: 'How people say they feel',
              subtitle: 'Average self-reported mood · 1 low, 5 good',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardTrend(
                    values: _cohort('moodDays', 7, average: true),
                    labels: const [
                      '10 Oct',
                      '11 Oct',
                      '12 Oct',
                      '13 Oct',
                      '14 Oct',
                      '15 Oct',
                      '16 Oct',
                    ],
                    maxY: 5,
                    color: _green,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$moodReplies / ${_seniors.length * 7} daily responses. Separate from facial or language estimates.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        DashboardColumns(
          children: [
            DashCard(
              title: 'Review coverage',
              subtitle: 'Recorded review progress, not clinical outcomes',
              action: TextButton(
                onPressed: () => setState(() => _tab = 2),
                child: const Text('Open queue'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _progress(
                    'Reviewed concerns',
                    reviewed,
                    _alerts.length,
                    _green,
                  ),
                  const SizedBox(height: 18),
                  _progress(
                    'Weekly check-in coverage',
                    responding,
                    _seniors.length,
                    _purple,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Urgent examples show routing separately from review. No real recipient is contacted.',
                    style: TextStyle(fontSize: 13, color: AiraColors.muted),
                  ),
                ],
              ),
            ),
            DashCard(
              title: 'People to check in with',
              subtitle: 'Based on open sample concerns',
              child: Column(
                children: [
                  for (final s in _seniors
                      .where(
                        (s) => _rows(s['alerts']).any((a) => !_closed(a)),
                      )
                      .take(3))
                    _personLink(
                      s,
                      '${_rows(s['alerts']).where((a) => !_closed(a)).length} open concerns · ${s['caregiver']}',
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _progress(String label, int used, int total, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · $used / $total',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (used / total).clamp(0, 1),
              minHeight: 10,
              color: color,
              backgroundColor: color.withValues(alpha: .12),
            ),
          ),
        ],
      );

  Widget _personLink(Map<String, dynamic> s, String subtitle) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AiraColors.sage,
              child: Text(
                _text(s['initials']),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(s['name']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  TextButton(
                    onPressed: () => widget.onOpenSenior(_text(s['id'])),
                    child: const Text('Open senior workspace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _directory() {
    final rows = _seniors
        .where(
          (s) => ['name', 'email', 'caregiver', 'status'].any(
            (key) => _text(s[key]).toLowerCase().contains(_query.toLowerCase()),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('admin-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search seniors',
            hintText: 'Name, email, caregiver or status',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        Text(
          '${rows.length} senior${rows.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const DashCard(
            title: 'No matching seniors',
            child: Text('Try another name, caregiver or email.'),
          ),
        for (final s in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DashCard(
              title: _text(s['name']),
              subtitle:
                  '${s['age']} years · ${s['language']} · Caregiver: ${s['caregiver']}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DashboardTag(label: _text(s['status']), color: _green),
                      DashboardTag(label: _text(s['plan']), color: _purple),
                      DashboardTag(
                        label: _text(s['accessRole'] ?? 'Senior'),
                        color: _amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_text(s['email'])),
                  Text(
                    '${s['phone']} · Last active: ${_date(s['lastActive'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (s['passwordResetStatus'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _text(s['passwordResetStatus']),
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => widget.onOpenSenior(_text(s['id'])),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Open senior'),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey('edit-account-${s['id']}'),
                        onPressed: () => _editAccount(s),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Edit account'),
                      ),
                      TextButton.icon(
                        onPressed: () => _resetPassword(s),
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Password reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _reviewQueue() {
    final categories =
        _alerts.map((row) => _concern(row.alert)).toSet().toList()..sort();
    final priorities = _alerts
        .map((row) => _text(row.alert['priority']))
        .toSet()
        .toList()
      ..sort();
    final statuses = _alerts
        .map((row) => _text(row.alert['status']))
        .toSet()
        .toList()
      ..sort();
    final rows = _alerts
        .where(
          (row) =>
              (_category == 'All concerns' ||
                  _concern(row.alert) == _category) &&
              (_priority == 'All priorities' ||
                  _text(row.alert['priority']) == _priority) &&
              (_status == 'All statuses' ||
                  _text(row.alert['status']) == _status),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Review signals, with the context to understand them',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'AI-related belief concerns (sometimes called “AI psychosis”), unsafe interactions and self-harm references need human context. These sample flags are not diagnoses.',
          style: TextStyle(color: AiraColors.muted),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in [
                (
                  label: 'Concern',
                  value: _category,
                  values: ['All concerns', ...categories],
                  set: (String v) => setState(() => _category = v),
                ),
                (
                  label: 'Priority',
                  value: _priority,
                  values: ['All priorities', ...priorities],
                  set: (String v) => setState(() => _priority = v),
                ),
                (
                  label: 'Review status',
                  value: _status,
                  values: ['All statuses', ...statuses],
                  set: (String v) => setState(() => _status = v),
                ),
              ])
                SizedBox(
                  width: c.maxWidth > 900 &&
                          MediaQuery.textScalerOf(context).scale(14) < 22
                      ? (c.maxWidth - 24) / 3
                      : c.maxWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('filter-${entry.label}-${entry.value}'),
                    initialValue: entry.values.contains(entry.value)
                        ? entry.value
                        : entry.values.first,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: entry.label),
                    items: entry.values
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) entry.set(v);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${rows.length} matching concerns',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const DashCard(
            title: 'Nothing in this view',
            child: Text('Try another filter to see the other sample concerns.'),
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DashCard(
              title: _text(row.alert['title']),
              subtitle:
                  '${row.senior['name']} · ${_text(row.alert['time'] ?? row.alert['date'])}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DashboardTag(label: _concern(row.alert), color: _purple),
                      DashboardTag(
                        label: _text(row.alert['priority']),
                        color: _priorityColor(row.alert['priority']),
                      ),
                      DashboardTag(
                        label: _text(row.alert['status']),
                        color: _green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_text(row.alert['detail'] ?? row.alert['summary'])),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AiraColors.cream,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Conversation evidence · fictional',
                            style: TextStyle(
                              fontSize: 12,
                              color: AiraColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _text(
                              row.alert['evidence'] ?? row.alert['excerpt'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_text(row.alert['note'] ?? row.alert['reviewNote'])
                      .isNotEmpty)
                    Text(
                      'Review note: ${row.alert['note'] ?? row.alert['reviewNote']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (row.alert['routing'] != null)
                    Text(
                      'Routing: ${row.alert['routing']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _review(row.senior, row.alert),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review concern'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.onOpenSenior(_text(row.senior['id'])),
                        child: const Text('Open senior context'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _plans() {
    final plans = _seniors.map((s) => _text(s['plan'])).toSet().toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardColumns(
          children: [
            DashCard(
              title: 'Plans across the cohort',
              subtitle: 'Sample access plans · no billing or payments',
              child: DashboardBars(
                values: [
                  for (final plan in plans)
                    _seniors.where((s) => s['plan'] == plan).length.toDouble(),
                ],
                labels: plans,
                color: _purple,
                unit: ' seniors',
              ),
            ),
            DashCard(
              title: 'Call allowance',
              subtitle: 'Sample monthly usage and assigned minutes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in _seniors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _progress(
                        _text(s['name']),
                        (s['minutesUsed'] as num?)?.toInt() ?? 0,
                        (s['minutesLimit'] as num?)?.toInt() ?? 0,
                        _green,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final s in _seniors)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DashCard(
              title: _text(s['name']),
              subtitle: '${s['plan']} · ${s['minutesLimit']} minutes / month',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DashboardTag(label: _text(s['status']), color: _green),
                      DashboardTag(
                        label: _text(s['accessRole'] ?? 'Senior'),
                        color: _purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Plan ends ${_date(s['planEnds'])} · Caregiver: ${s['caregiver']}',
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _editAccount(s, plansFirst: true),
                      icon: const Icon(Icons.tune),
                      label: const Text('Manage plan & access'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _activity() => DashCard(
        title: 'Workspace activity',
        subtitle: 'Changes to these sample records · resets with sample data',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.store.audit.isEmpty)
              const Text(
                'No sample edits yet. Account, care and review changes will appear here.',
              ),
            for (final item in widget.store.audit)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.history, color: _green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text(item['action']),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${item['senior'] ?? item['seniorName'] ?? item['name'] ?? item['seniorId'] ?? 'Workspace'} · ${_text(item['date'] ?? item['time'] ?? item['at'])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Future<void> _editAccount(
    Map<String, dynamic> senior, {
    bool plansFirst = false,
  }) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: _text(senior['name']));
    final email = TextEditingController(text: _text(senior['email']));
    final phone = TextEditingController(text: _text(senior['phone']));
    final caregiver = TextEditingController(text: _text(senior['caregiver']));
    final ends = TextEditingController(text: _dateInput(senior['planEnds']));
    final minutes = TextEditingController(text: _text(senior['minutesLimit']));
    String status = _text(senior['status']),
        role = _text(senior['accessRole'] ?? 'Senior'),
        plan = _text(senior['plan']);
    final saved = await _dialog<bool>(
      builder: (dialog) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(
            plansFirst ? 'Manage plan & access' : 'Edit sample account',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Changes apply only to this sample workspace. No real account, permissions or subscription will change.',
                      style: TextStyle(fontSize: 14, color: AiraColors.muted),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v ?? '')
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: caregiver,
                      decoration: const InputDecoration(
                        labelText: 'Assigned caregiver',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _select(
                      'Account status',
                      status,
                      {status, 'Active', 'Paused', 'Invited'}.toList(),
                      (v) => set(() => status = v),
                    ),
                    const SizedBox(height: 14),
                    _select(
                        'Access role',
                        role,
                        const [
                          'Senior',
                          'Caregiver',
                          'Administrator',
                        ],
                        (v) => set(() => role = v)),
                    const SizedBox(height: 14),
                    _select(
                      'Plan',
                      plan,
                      {plan, 'Companion', 'Family', 'Trial'}.toList(),
                      (v) => set(() => plan = v),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: ends,
                      decoration: const InputDecoration(
                        labelText: 'Plan expiry (YYYY-MM-DD)',
                      ),
                      validator: (v) {
                        final parsed = DateTime.tryParse(v ?? '');
                        return parsed != null && _dateInput(parsed) == v
                            ? null
                            : 'Use a valid YYYY-MM-DD date.';
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly call allowance (minutes)',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n != null && n >= 0 && n <= 100000
                            ? null
                            : 'Choose 0 to 100,000 minutes.';
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('Save sample account'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && _currentSenior(senior)) {
      senior.addAll({
        'name': name.text.trim(),
        'initials': name.text
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'caregiver': caregiver.text.trim(),
        'status': status,
        'accessRole': role,
        'plan': plan,
        'planEnds': '${ends.text.trim()}T23:59:00+08:00',
        'minutesLimit': int.parse(minutes.text),
      });
      widget.store.record(
        _text(senior['id']),
        'Updated sample account, plan and access',
      );
      _message('Sample account updated');
    }
    for (final c in [name, email, phone, caregiver, ends, minutes]) {
      c.dispose();
    }
  }

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> change,
  ) =>
      DropdownButtonFormField<String>(
        key: ValueKey('admin-select-$label'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) change(v);
        },
      );

  Future<void> _resetPassword(Map<String, dynamic> senior) async {
    final reset = await _dialog<bool>(
      builder: (dialog) => AlertDialog(
        title: const Text('Simulate password reset'),
        content: Text(
          'Mark a reset as requested for ${senior['name']} in this sample workspace. No email is sent and no password is changed or displayed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Simulate reset'),
          ),
        ],
      ),
    );
    if (reset == true && _currentSenior(senior)) {
      senior['passwordResetStatus'] = 'Sample password reset requested';
      widget.store.record(
        _text(senior['id']),
        'Simulated password reset request',
      );
      _message('Sample reset recorded. No email sent.');
    }
  }

  Future<void> _review(
    Map<String, dynamic> senior,
    Map<String, dynamic> alert,
  ) async {
    var status = _text(alert['status']);
    final note = TextEditingController(
      text: _text(alert['note'] ?? alert['reviewNote']),
    );
    final form = GlobalKey<FormState>();
    final saved = await _dialog<bool>(
      builder: (dialog) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Review sample concern'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${senior['name']} · ${alert['title']}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Record a human assessment. Updating this sample does not contact anyone or establish a diagnosis.',
                      style: TextStyle(color: AiraColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _select(
                      'Review decision',
                      status,
                      {
                        status,
                        'open',
                        'reviewing',
                        'follow-up',
                        'resolved',
                        'dismissed',
                      }.toList(),
                      (v) => set(() => status = v),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: 'Assessment and next step',
                      ),
                      minLines: 3,
                      maxLines: 6,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Add a note explaining the decision.'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('Save sample review'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && _currentSenior(senior)) {
      alert['status'] = status;
      alert['note'] = note.text.trim();
      if (_status != 'All statuses' &&
          !_alerts.any((row) => row.alert['status'] == _status)) {
        _status = 'All statuses';
      }
      widget.store.record(
        _text(senior['id']),
        'Reviewed ${alert['title']}: $status',
      );
      _message('Sample review saved');
    }
    note.dispose();
  }

  Future<T?> _dialog<T>({required WidgetBuilder builder}) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  }

  bool _currentSenior(Map<String, dynamic> source) =>
      mounted &&
      widget.store.seniors.any((current) => identical(current, source));

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
