import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import 'dashboard/admin_workspace.dart';
import 'dashboard/caregiver_workspace.dart';
import 'dashboard/sample_data.dart';
import 'live_dashboard.dart';

/// The sample workspace is deliberately disconnected from account APIs.
/// Real linked records keep their original permission-checked screen.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.admin,
    this.sampleStore,
  });

  final AiraController controller;
  final bool admin;
  final DashboardSampleStore? sampleStore;

  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  late final DashboardSampleStore store =
      widget.sampleStore ?? DashboardSampleStore();
  late String selectedId = store.seniors.first['id'] as String;
  bool live = false;
  bool seniorDetail = false;

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admin != widget.admin) seniorDetail = false;
  }

  @override
  void dispose() {
    if (widget.sampleStore == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Column(
      children: [
        _workspaceBar(context),
        Expanded(
          child: live
              ? LiveDashboardScreen(
                  controller: widget.controller,
                  admin: widget.admin,
                )
              : ListView(
                  key: PageStorageKey('sample-${widget.admin}-$seniorDetail'),
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
                  ),
                  children: [
                    _heading(context),
                    const SizedBox(height: 24),
                    if (!widget.admin || seniorDetail) ...[
                      _seniorPicker(context),
                      const SizedBox(height: 20),
                      CaregiverWorkspace(
                        key: ValueKey(selectedId),
                        store: store,
                        seniorId: selectedId,
                      ),
                    ] else
                      AdminWorkspace(
                        store: store,
                        onOpenSenior: (id) => setState(() {
                          selectedId = id;
                          seniorDetail = true;
                        }),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _workspaceBar(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      color: live ? AiraColors.sage : const Color(0xFFFFF0D7),
      border: const Border(bottom: BorderSide(color: AiraColors.line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Row(
          children: [
            Icon(live ? Icons.lock_outline : Icons.science_outlined, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                live
                    ? 'Live records · Your existing access and sharing permissions apply'
                    : 'Sample workspace · Fictional people and data · Edits last for this session',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          children: [
            if (!live)
              TextButton.icon(
                key: const Key('reset-dashboard-samples'),
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset samples'),
              ),
            if (!widget.controller.preview && widget.controller.signedIn)
              OutlinedButton(
                key: const Key('dashboard-data-mode'),
                onPressed: () => setState(() => live = !live),
                child: Text(live ? 'Sample workspace' : 'Live records'),
              ),
          ],
        );
        return constraints.maxWidth < 700
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, actions],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  actions,
                ],
              );
      },
    ),
  );

  Widget _heading(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.admin && seniorDetail)
        TextButton.icon(
          onPressed: () => setState(() => seniorDetail = false),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to all seniors'),
        ),
      Text(
        widget.admin && !seniorDetail
            ? 'A little care. A wider view.'
            : 'Care, made personal.',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.admin && !seniorDetail
            ? 'Admin dashboard · People, wellbeing and operations in one place.'
            : 'Caregiver workspace · Get to know the day behind the numbers.',
        style: const TextStyle(fontSize: 16, color: AiraColors.muted),
      ),
    ],
  );

  Widget _seniorPicker(BuildContext context) {
    final senior = store.senior(selectedId);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AiraColors.forest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AiraColors.sage,
                child: Text(
                  senior['initials'] as String,
                  style: const TextStyle(
                    color: AiraColors.forest,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senior['name'] as String,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${senior['age']} years · ${senior['language']} · Sample profile',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFDCE9DA),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final picker = DropdownButtonFormField<String>(
            key: ValueKey('sample-senior-$selectedId'),
            initialValue: selectedId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Select senior'),
            items: [
              for (final person in store.seniors)
                DropdownMenuItem(
                  value: person['id'] as String,
                  child: Text(person['name'] as String),
                ),
            ],
            onChanged: (id) {
              if (id != null) setState(() => selectedId = id);
            },
          );
          return constraints.maxWidth < 700
              ? Column(children: [identity, const SizedBox(height: 18), picker])
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 24),
                    SizedBox(width: 270, child: picker),
                  ],
                );
        },
      ),
    );
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset the sample workspace?'),
        content: const Text(
          'This clears your sample edits in both dashboards and restores the fictional examples. Real accounts are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset samples'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    store.reset();
    setState(() => selectedId = store.seniors.first['id'] as String);
  }
}
