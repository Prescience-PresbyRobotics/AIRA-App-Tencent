import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class LiveDashboardScreen extends StatefulWidget {
  final AiraController controller;
  final bool admin;
  const LiveDashboardScreen({
    super.key,
    required this.controller,
    required this.admin,
  });
  @override
  State<LiveDashboardScreen> createState() => _LiveDashboardState();
}

class _LiveDashboardState extends State<LiveDashboardScreen> {
  bool loading = false;
  String? insightError, reportError, overviewError, subject;
  Map<String, dynamic> data = {}, overview = {};
  List<Map<String, dynamic>> seniors = [], reports = [];
  final Set<String> busyReports = {};
  int generation = 0;
  late int observedSession;
  late bool observedPreview;

  @override
  void initState() {
    super.initState();
    observedSession = widget.controller.sessionEpoch;
    observedPreview = widget.controller.preview;
    widget.controller.addListener(_sessionChanged);
    load();
  }

  @override
  void didUpdateWidget(covariant LiveDashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sessionChanged);
      widget.controller.addListener(_sessionChanged);
    }
    if (old.admin != widget.admin || old.controller != widget.controller) {
      _clear();
      observedSession = widget.controller.sessionEpoch;
      observedPreview = widget.controller.preview;
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    widget.controller.removeListener(_sessionChanged);
    super.dispose();
  }

  void _clear() {
    generation++;
    subject = null;
    data = {};
    overview = {};
    seniors = [];
    reports = [];
    busyReports.clear();
    insightError = reportError = overviewError = null;
    loading = false;
  }

  void _sessionChanged() {
    if (!mounted ||
        (observedSession == widget.controller.sessionEpoch &&
            observedPreview == widget.controller.preview)) {
      return;
    }
    setState(() {
      _clear();
      observedSession = widget.controller.sessionEpoch;
      observedPreview = widget.controller.preview;
    });
    load();
  }

  bool _current(
    int request,
    int epoch,
    AiraController controller,
    bool admin,
  ) =>
      mounted &&
      generation == request &&
      widget.controller == controller &&
      controller.sessionEpoch == epoch &&
      widget.admin == admin &&
      !controller.preview &&
      controller.signedIn;

  Future<void> load() async {
    if (widget.controller.preview || !widget.controller.signedIn) return;
    final controller = widget.controller;
    final epoch = controller.sessionEpoch;
    final admin = widget.admin;
    final request = ++generation;
    final selected = subject;
    setState(() {
      loading = true;
      insightError = reportError = overviewError = null;
      data = {};
      overview = {};
      reports = [];
      busyReports.clear();
    });
    final api = controller.api;
    Map<String, dynamic> fetched = {}, summary = {};
    List<Map<String, dynamic>> directory = [], cases = [];
    String? chosen = selected, metricsFailure, reportsFailure, summaryFailure;
    // Review access is independent of permission to see insight metrics.
    await Future.wait([
      () async {
        try {
          final result = await api.request(
            'GET',
            admin ? '/admin/subjects' : '/caregiver/seniors',
          );
          directory = _rows(result['seniors']);
          if (!directory.any((p) => p['id'] == chosen)) {
            chosen = directory.isEmpty
                ? null
                : directory.first['id']?.toString();
          }
          if (!_current(request, epoch, controller, admin)) return;
          if (chosen != null) {
            fetched = await api.request(
              'GET',
              admin
                  ? '/admin/insights?subjectId=${Uri.encodeQueryComponent(chosen!)}'
                  : '/caregiver/seniors/${Uri.encodeComponent(chosen!)}/insights',
            );
          }
        } catch (e) {
          metricsFailure = AiraController.cleanError(e);
        }
      }(),
      () async {
        try {
          final result = await api.request(
            'GET',
            admin ? '/admin/incidents' : '/caregiver/reports',
          );
          cases = _rows(result[admin ? 'incidents' : 'reports']);
        } catch (e) {
          reportsFailure = AiraController.cleanError(e);
        }
      }(),
      if (admin)
        () async {
          try {
            summary = await api.request('GET', '/admin/overview');
          } catch (e) {
            summaryFailure = AiraController.cleanError(e);
          }
        }(),
    ]);
    if (!_current(request, epoch, controller, admin)) return;
    setState(() {
      seniors = directory;
      subject = chosen;
      data = fetched;
      overview = summary;
      reports = cases;
      insightError = metricsFailure;
      reportError = reportsFailure;
      overviewError = summaryFailure;
      loading = false;
    });
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};
  static List<Map<String, dynamic>> _rows(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
  static String _number(dynamic v) => v is num
      ? (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1))
      : '—';
  static String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'Date unavailable';
    final d = parsed.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  static String _label(dynamic value) =>
      (value?.toString() ?? 'Unknown').replaceAll('_', ' ');
  bool _shared(Map<String, dynamic> source, String category) =>
      source['categories'] is List &&
      (source['categories'] as List).contains(category);

  Map<String, dynamic> get _example => {
    'synthetic': true,
    'categories': ['loneliness', 'conversations', 'mood'],
    'supportedSeniors': widget.admin ? 24 : 1,
    'conversations': {
      'count': widget.admin ? 186 : 12,
      'durationMinutes': widget.admin ? 620 : 48,
      'seniorInitiated': widget.admin ? 108 : 7,
      'airaInitiated': widget.admin ? 78 : 5,
    },
    'loneliness': {
      'periods': [
        for (final item in [
          ('Baseline', 6),
          ('Week 2', 5),
          ('Week 3', 4),
          ('Latest', 3),
        ])
          {
            'label': item.$1,
            'response': {'lonely_days': item.$2, 'skipped': false},
          },
      ],
      'changeFromBaseline': -3,
      'changeFromPrevious': -1,
    },
    'mood': {
      'selfReported': [
        {'label': 'happy', 'created_at': '2026-10-14T10:00:00+08:00'},
      ],
      'inferred': [],
      'inferredStatus': 'No example inference history',
    },
  };

  @override
  Widget build(BuildContext c) {
    final preview = widget.controller.preview;
    final wide = MediaQuery.sizeOf(c).width > 900;
    final source = preview ? _example : data;
    final visibleReports = widget.admin || subject == null
        ? reports
        : reports.where((r) => r['user_id'] == subject).toList();
    return ListView(
      padding: AiraLayout.of(c).insets(EdgeInsets.all(wide ? 32 : 20)),
      children: [
        SectionHeading(
          widget.admin
              ? 'Companionship overview'
              : preview
              ? 'Mei’s wellbeing'
              : 'Shared wellbeing',
          subtitle: preview
              ? '${widget.admin ? 'Example cohort' : 'Example senior'} · Synthetic history'
              : 'Shared with permission · Current authorized records',
          action: IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (preview)
          const Notice(
            'Simulated example data · These charts are not real outcomes or real alerts.',
            color: Color(0xFFFFF1D8),
          ),
        if (!preview && !widget.controller.signedIn)
          const Notice('Please sign in to view information shared with you.')
        else if (loading)
          const Center(
            child: AiraPadding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(),
            ),
          )
        else ...[
          if (!preview && insightError != null)
            _accessNotice('Wellbeing information unavailable', insightError!),
          if (!preview && seniors.isEmpty && insightError == null)
            const AiraCard(
              child: Text(
                'No permitted senior profiles. Being signed in does not grant caregiver or admin access. A verified link or staff assignment and the senior’s sharing choices are required.',
              ),
            ),
          if (!preview && seniors.isNotEmpty) ...[
            const AiraGap(height: 20),
            DropdownButtonFormField<String>(
              key: ValueKey('$subject-${widget.admin}-$observedSession'),
              initialValue: subject,
              items: [
                for (final p in seniors)
                  DropdownMenuItem(
                    value: p['id']?.toString(),
                    child: Text(
                      (p['display_name']?.toString() ?? '').isEmpty
                          ? 'Linked senior'
                          : p['display_name'].toString(),
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  subject = value;
                  data = {};
                  reports = [];
                });
                load();
              },
              decoration: const InputDecoration(labelText: 'Senior'),
            ),
          ],
          if (preview || (insightError == null && data.isNotEmpty)) ...[
            const AiraGap(height: 20),
            if (!preview && widget.admin)
              const AiraPadding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Metrics below describe the selected senior, not a cohort.',
                  style: TextStyle(fontSize: 14, color: AiraColors.muted),
                ),
              ),
            _metrics(c, source, preview),
            const AiraGap(height: 22),
            Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide)
                  Expanded(child: _loneliness(c, source, preview))
                else
                  _loneliness(c, source, preview),
                AiraGap(width: wide ? 18 : 0, height: wide ? 0 : 18),
                if (wide)
                  Expanded(child: _activity(c, source))
                else
                  _activity(c, source),
              ],
            ),
            const AiraGap(height: 18),
            _mood(c, source, wide),
            const AiraGap(height: 20),
            Text(
              preview
                  ? 'Synthetic history illustrates the display only.'
                  : 'Source: authorized server records · ${source['retentionHours'] ?? 24}-hour prototype retention. ${_map(source['loneliness'])['note'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: AiraColors.muted),
            ),
          ],
          const AiraGap(height: 28),
          if (preview)
            _exampleReport(c)
          else ...[
            Text(
              widget.admin ? 'Assigned review queue' : 'Shared test reports',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const AiraGap(height: 8),
            Text(
              widget.admin
                  ? 'All assigned seniors · Flags are uncertain review signals. Urgent test routing does not wait for review.'
                  : 'These are internal test reports. Acknowledging receipt does not resolve a concern.',
              style: const TextStyle(fontSize: 14, color: AiraColors.muted),
            ),
            if (widget.admin && overviewError != null) ...[
              const AiraGap(height: 12),
              _accessNotice('Operator overview unavailable', overviewError!),
            ] else if (widget.admin && overview.isNotEmpty) ...[
              const AiraGap(height: 12),
              Notice(
                '${_number(overview['queueCount'])} cases in the operator overview · Review coverage: ${overview['staffedCoverage'] ?? 'Not configured'}',
              ),
            ],
            if (reportError != null) ...[
              const AiraGap(height: 12),
              _accessNotice(
                widget.admin
                    ? 'Review access unavailable'
                    : 'Report access unavailable',
                reportError!,
              ),
            ] else if (visibleReports.isEmpty) ...[
              const AiraGap(height: 12),
              AiraCard(
                child: Text(
                  widget.admin
                      ? 'No assigned, consented cases are available.'
                      : 'No test reports are currently shared${subject == null ? '' : ' for this senior'}.',
                ),
              ),
            ] else
              for (final report in visibleReports)
                AiraPadding(
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.admin
                      ? _incident(c, report)
                      : _report(c, report),
                ),
            const AiraGap(height: 12),
            const Text(
              'Test inbox only · No external caregiver delivery.',
              style: TextStyle(fontSize: 13, color: AiraColors.muted),
            ),
          ],
          const AiraGap(height: 24),
          const Text(
            'Changes are observations, not proof that AIRA caused an improvement. Missing answers remain missing.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AiraColors.muted,
            ),
          ),
        ],
        const AiraGap(height: 30),
      ],
    );
  }

  Widget _accessNotice(String title, String message) => Notice(
    '$title. $message Access depends on your assigned role, verified link and current consent.',
  );

  Widget _metrics(BuildContext c, Map<String, dynamic> source, bool preview) {
    final activity = _map(source['conversations']);
    final permitted = _shared(source, 'conversations');
    final periods = _rows(_map(source['loneliness'])['periods']);
    final answers = periods
        .where(
          (p) =>
              _map(p['response'])['skipped'] != true &&
              _map(p['response'])['lonely_days'] is num,
        )
        .toList();
    final latest = answers.isEmpty
        ? null
        : _map(answers.last['response'])['lonely_days'];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        if (widget.admin)
          _stat(
            c,
            'Seniors supported',
            permitted ? _number(source['supportedSeniors']) : '—',
            permitted
                ? (preview
                      ? 'Synthetic example cohort'
                      : 'Selected senior · completed conversation')
                : 'Not shared',
            Icons.people_outline,
            AiraColors.sage,
          ),
        _stat(
          c,
          'Conversations',
          permitted ? _number(activity['count']) : '—',
          permitted ? 'Completed conversations' : 'Not shared',
          Icons.chat_bubble_outline,
          AiraColors.sage,
        ),
        _stat(
          c,
          'Conversation minutes',
          permitted ? _number(activity['durationMinutes']) : '—',
          !permitted
              ? 'Not shared'
              : activity['durationMinutes'] is num
              ? 'Recorded conversation time'
              : activity['durationStatus']?.toString() ?? 'Timing unavailable',
          Icons.schedule,
          AiraColors.lavender,
        ),
        _stat(
          c,
          'Reported lonely days',
          _shared(source, 'loneliness') ? _number(latest) : '—',
          !_shared(source, 'loneliness')
              ? 'Not shared'
              : latest == null
              ? 'No answered weekly check-in'
              : 'Latest answered period · out of 7',
          Icons.notes_rounded,
          AiraColors.peach,
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext c,
    String label,
    String value,
    String detail,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: MediaQuery.sizeOf(c).width > 900 ? 245 : double.infinity,
    child: AiraCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AiraColors.forest),
          const AiraGap(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const AiraGap(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const AiraGap(height: 6),
          Text(
            detail,
            style: const TextStyle(fontSize: 13, color: AiraColors.muted),
          ),
        ],
      ),
    ),
  );

  Widget _loneliness(
    BuildContext c,
    Map<String, dynamic> source,
    bool preview,
  ) {
    final permitted = _shared(source, 'loneliness');
    final metrics = _map(source['loneliness']);
    final periods = _rows(metrics['periods']);
    return AiraCard(
      color: AiraColors.lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reported lonely days',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const AiraGap(height: 8),
          Text(
            !permitted
                ? 'Not shared'
                : preview
                ? 'Synthetic weekly self-report'
                : '${periods.length} recorded periods',
            style: const TextStyle(fontSize: 15, color: AiraColors.muted),
          ),
          const AiraGap(height: 22),
          if (!permitted)
            const Text(
              'The senior has not shared this measurement with this view.',
            )
          else if (periods.isEmpty)
            const Text('No weekly check-in records are available.')
          else ...[
            for (final period in periods) _period(period),
            const AiraGap(height: 10),
            Text(
              metrics['changeFromBaseline'] is num
                  ? '${_signed(metrics['changeFromBaseline'])} days from baseline'
                  : 'No comparable baseline change is available.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (metrics['changeFromPrevious'] is num)
              Text(
                '${_signed(metrics['changeFromPrevious'])} days from the previous comparable period',
                style: const TextStyle(fontSize: 14),
              ),
          ],
          const AiraGap(height: 12),
          const Text(
            '0–7 days · Missing and skipped answers are not zero. Changes come from the shared metrics service.',
            style: TextStyle(fontSize: 13, color: AiraColors.muted),
          ),
        ],
      ),
    );
  }

  String _signed(dynamic value) =>
      value is num && value > 0 ? '+${_number(value)}' : _number(value);
  Widget _period(Map<String, dynamic> period) {
    final response = _map(period['response']);
    final days = response['lonely_days'];
    final valid = response['skipped'] != true && days is num;
    final label =
        period['label']?.toString() ??
        '${period['period_start'] ?? 'Unknown period'} – ${period['period_end'] ?? ''}';
    return AiraPadding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const AiraGap(height: 7),
          if (valid)
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: LinearProgressIndicator(
                      value: (days / 7).clamp(0.0, 1.0).toDouble(),
                      minHeight: 18,
                      color: const Color(0xFF9F88CB),
                      backgroundColor: Colors.white.withValues(alpha: .5),
                    ),
                  ),
                ),
                const AiraGap(width: 12),
                Text(
                  '${_number(days)} / 7',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            )
          else
            Text(
              response['skipped'] == true ? 'Skipped' : 'No answer recorded',
              style: const TextStyle(fontSize: 15, color: AiraColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _activity(BuildContext c, Map<String, dynamic> source) {
    final permitted = _shared(source, 'conversations');
    final activity = _map(source['conversations']);
    return AiraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conversation activity',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const AiraGap(height: 24),
          if (!permitted)
            const Text('Conversation activity is not shared with this view.')
          else ...[
            _row(
              Icons.chat_bubble_outline,
              _number(activity['count']),
              'completed conversations',
            ),
            const Divider(height: 30),
            _row(
              Icons.schedule,
              _number(activity['durationMinutes']),
              'recorded conversation minutes',
            ),
            if (activity['durationMinutes'] is! num)
              AiraPadding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  activity['durationStatus']?.toString() ??
                      'Timing unavailable',
                  style: const TextStyle(fontSize: 14, color: AiraColors.muted),
                ),
              ),
            const AiraGap(height: 26),
            const Text(
              'Who started the conversation?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const AiraGap(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(
                  label: Text('Senior ${_number(activity['seniorInitiated'])}'),
                  backgroundColor: AiraColors.sage,
                  side: BorderSide.none,
                ),
                Chip(
                  label: Text('AIRA ${_number(activity['airaInitiated'])}'),
                  backgroundColor: AiraColors.lavender,
                  side: BorderSide.none,
                ),
                if (activity['unknownInitiated'] is num)
                  Chip(
                    label: Text(
                      'Unknown ${_number(activity['unknownInitiated'])}',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _mood(BuildContext c, Map<String, dynamic> source, bool wide) {
    final permitted = _shared(source, 'mood');
    final mood = _map(source['mood']);
    final self = _rows(mood['selfReported']);
    final inferred = _rows(mood['inferred']);
    Widget card(bool estimate) => AiraCard(
      color: estimate ? AiraColors.lavender : AiraColors.sage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            estimate
                ? Icons.auto_awesome_outlined
                : Icons.sentiment_satisfied_alt_outlined,
          ),
          const AiraGap(height: 12),
          Text(
            estimate ? 'AI-inferred cues' : 'Self-reported mood',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const AiraGap(height: 10),
          if (!permitted)
            const Text('Not shared')
          else if ((estimate ? inferred : self).isEmpty)
            Text(
              estimate
                  ? mood['inferredStatus']?.toString() ??
                        'No stored facial estimates'
                  : 'No self-reported feelings recorded',
            )
          else
            for (final entry in (estimate ? inferred : self).reversed.take(5))
              AiraPadding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_label(entry['label'])} · ${_date(entry['created_at'] ?? entry['observedAt'])}',
                ),
              ),
          const AiraGap(height: 6),
          Text(
            estimate
                ? 'Separate from self-report. Not a diagnosis.'
                : 'What the senior chose to tell us',
            style: const TextStyle(fontSize: 14, color: AiraColors.muted),
          ),
        ],
      ),
    );
    return Flex(
      direction: wide ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide)
          Expanded(child: card(false))
        else
          SizedBox(width: double.infinity, child: card(false)),
        AiraGap(width: wide ? 18 : 0, height: wide ? 0 : 18),
        if (wide)
          Expanded(child: card(true))
        else
          SizedBox(width: double.infinity, child: card(true)),
      ],
    );
  }

  String _subjectLabel(dynamic value) {
    final id = value?.toString() ?? '';
    for (final senior in seniors) {
      if (senior['id'] == id &&
          (senior['display_name']?.toString() ?? '').isNotEmpty) {
        return senior['display_name'].toString();
      }
    }
    return id.isEmpty ? 'Assigned senior' : 'Senior reference: $id';
  }

  Widget _incident(BuildContext c, Map<String, dynamic> incident) => AiraCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _subjectLabel(incident['user_id']),
          style: const TextStyle(fontSize: 14, color: AiraColors.muted),
        ),
        const AiraGap(height: 8),
        Text(
          '${_label(incident['priority'])} concern · ${_label(incident['state'])}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const AiraGap(height: 8),
        Text(
          '${_label(incident['source'])} interaction · ${_label(incident['reason'])} · ${_date(incident['created_at'])}',
          style: const TextStyle(fontSize: 14, color: AiraColors.muted),
        ),
        if (incident['synthetic'] == true)
          const AiraPadding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Synthetic test case'),
          ),
        if (incident['excerpt'] is String)
          AiraPadding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(incident['excerpt'] as String),
          ),
        if (incident['review_reason'] is String)
          AiraPadding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Review note: ${incident['review_reason']}'),
          ),
        const AiraGap(height: 12),
        OutlinedButton(
          onPressed: busyReports.contains(incident['id'])
              ? null
              : () => _review(incident),
          child: const Text('Review concern'),
        ),
      ],
    ),
  );

  Widget _report(BuildContext c, Map<String, dynamic> report) {
    final incident = _map(report['incident']);
    final acknowledged = report['state'] == 'acknowledged';
    return AiraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            acknowledged ? 'Receipt acknowledged' : 'Test report delivered',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const AiraGap(height: 8),
          Text(
            report['dispatch_basis'] == 'urgent_policy'
                ? 'Urgent policy · automatically routed'
                : 'Shared after reviewer approval',
          ),
          if (incident.isNotEmpty) ...[
            const AiraGap(height: 10),
            Text(
              '${_label(incident['reason'])} · Review: ${_label(incident['state'])}',
            ),
            if (incident['excerpt'] is String)
              AiraPadding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(incident['excerpt'] as String),
              ),
          ],
          const AiraGap(height: 10),
          Text(
            'Delivered: ${_date(report['delivered_at'])}${acknowledged ? ' · Acknowledged: ${_date(report['acknowledged_at'])}' : ''}',
            style: const TextStyle(fontSize: 14, color: AiraColors.muted),
          ),
          const AiraGap(height: 12),
          OutlinedButton(
            onPressed:
                report['state'] != 'test_delivered' ||
                    busyReports.contains(report['id'])
                ? null
                : () => _acknowledge(report),
            child: Text(acknowledged ? 'Acknowledged' : 'Acknowledge receipt'),
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledge(Map<String, dynamic> report) async {
    final request = generation, epoch = widget.controller.sessionEpoch;
    final controller = widget.controller;
    final admin = widget.admin;
    final id = report['id']?.toString();
    if (id == null || !_current(request, epoch, controller, admin)) return;
    setState(() => busyReports.add(id));
    try {
      await controller.api.request(
        'POST',
        '/caregiver/reports/${Uri.encodeComponent(id)}/ack',
        {},
      );
      if (!mounted || !_current(request, epoch, controller, admin)) return;
      showMessage(
        context,
        'Receipt acknowledged. The concern remains separate from this acknowledgement.',
      );
      await load();
    } catch (e) {
      if (mounted && _current(request, epoch, controller, admin)) {
        showMessage(context, AiraController.cleanError(e));
      }
    } finally {
      if (_current(request, epoch, controller, admin)) {
        setState(() => busyReports.remove(id));
      }
    }
  }

  Future<void> _review(Map<String, dynamic> incident) async {
    final request = generation, epoch = widget.controller.sessionEpoch;
    final controller = widget.controller;
    final admin = widget.admin;
    bool valid() => _current(request, epoch, controller, admin);
    if (!valid()) return;
    final note = TextEditingController();
    String state = 'reviewed';
    bool approveReport = false;
    String? validation;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => StatefulBuilder(
          builder: (context, set) => AlertDialog(
            title: const Text('Review concern'),
            content: !valid()
                ? const Text(
                    'This view has changed. Close this dialog and refresh your access.',
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'A flag is a review signal, not a diagnosis. Record your assessment.',
                        ),
                        const AiraGap(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: state,
                          items: const [
                            DropdownMenuItem(
                              value: 'reviewed',
                              child: Text('Reviewed'),
                            ),
                            DropdownMenuItem(
                              value: 'followup',
                              child: Text('Follow-up needed'),
                            ),
                            DropdownMenuItem(
                              value: 'dismissed',
                              child: Text('Dismissed'),
                            ),
                            DropdownMenuItem(
                              value: 'closed',
                              child: Text('Closed'),
                            ),
                          ],
                          onChanged: (value) => set(() {
                            state = value!;
                            if (!['reviewed', 'followup'].contains(state)) {
                              approveReport = false;
                            }
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Review result',
                          ),
                        ),
                        const AiraGap(height: 16),
                        TextField(
                          controller: note,
                          maxLength: 500,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Reason for this decision',
                            errorText: validation,
                          ),
                        ),
                        if (['reviewed', 'followup'].contains(state))
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: approveReport,
                            onChanged: (value) =>
                                set(() => approveReport = value ?? false),
                            title: const Text(
                              'Approve a test caregiver report',
                            ),
                            subtitle: const Text(
                              'Requires the senior’s sharing consent and a verified test recipient. No external message is sent.',
                            ),
                          ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !valid()
                    ? null
                    : () {
                        if (note.text.trim().isEmpty) {
                          set(
                            () => validation = 'Enter a reason before saving.',
                          );
                          return;
                        }
                        Navigator.pop(dialog, {
                          'state': state,
                          'reason': note.text.trim(),
                          'expectedVersion': incident['version'],
                          'approveReport': approveReport,
                        });
                      },
                child: const Text('Save review'),
              ),
            ],
          ),
        ),
      ),
    );
    // The route may finish its exit animation after this Future completes.
    Future<void>.delayed(const Duration(seconds: 1), note.dispose);
    if (result == null || !valid()) return;
    final id = incident['id']?.toString();
    if (id == null) return;
    setState(() => busyReports.add(id));
    try {
      await controller.api.request(
        'POST',
        '/admin/incidents/${Uri.encodeComponent(id)}/review',
        result,
      );
      if (!mounted || !valid()) return;
      showMessage(
        context,
        'Review saved. Any eligible report goes to the internal test inbox.',
      );
      await load();
    } catch (e) {
      if (mounted && valid()) {
        showMessage(context, AiraController.cleanError(e));
      }
    } finally {
      if (valid()) setState(() => busyReports.remove(id));
    }
  }

  Widget _exampleReport(BuildContext c) => AiraCard(
    color: const Color(0xFFFFF1D8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Example urgent concern',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        const AiraGap(height: 8),
        const Text('Synthetic test report · automatically routed · unreviewed'),
        const AiraGap(height: 8),
        const Text(
          'No real caregiver contacted. Acknowledgement and review are separate.',
          style: TextStyle(fontSize: 15, color: AiraColors.muted),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: c,
            builder: (context) => AlertDialog(
              title: const Text('Synthetic test case'),
              content: const Text(
                'An urgent test report can be routed before admin review. Real reporting needs verified caregiver linkage, explicit consent and an evaluated urgency policy. No recipient has been contacted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: const Text('View example details'),
        ),
      ],
    ),
  );

  Widget _row(IconData icon, String number, String label) => Row(
    children: [
      Icon(icon, color: AiraColors.forest),
      const AiraGap(width: 16),
      Text(
        number,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
      ),
      const AiraGap(width: 12),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, color: AiraColors.muted),
        ),
      ),
    ],
  );
}
