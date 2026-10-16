import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class PersonalScreen extends StatelessWidget {
  final AiraController controller;
  const PersonalScreen({super.key, required this.controller});
  Future<void> memory(BuildContext c) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: c,
      builder: (c) => AlertDialog(
        title: const Text('Remember something about me'),
        content: TextField(
          controller: field,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'For example, I enjoy gardening',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (field.text.trim().isNotEmpty) {
                Navigator.pop(c, field.text.trim());
              }
            },
            child: const Text('Remember'),
          ),
        ],
      ),
    );
    if (value != null) {
      try {
        await controller.saveMemory(value);
        if (c.mounted) {
          showMessage(c, 'Saved. You can forget this at any time.');
        }
      } catch (e) {
        if (c.mounted) showMessage(c, AiraController.cleanError(e));
      }
    }
  }

  Future<void> plan(BuildContext c) async {
    final text = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(hours: 2));
    final accepted = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Check back about a plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'What would you like to talk about?',
                    hintText: 'For example, my shopping trip',
                  ),
                ),
                const AiraGap(height: 16),
                const Text(
                  'Choose when AIRA should ask how it went. Your plan stays unconfirmed until you tell AIRA the outcome.',
                  style: TextStyle(fontSize: 15),
                ),
                const AiraGap(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: c,
                      initialDate: date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(hours: 24)),
                    );
                    if (d == null || !c.mounted) return;
                    final t = await showTimePicker(
                      context: c,
                      initialTime: TimeOfDay.fromDateTime(date),
                    );
                    if (t != null) {
                      set(
                        () => date = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t.hour,
                          t.minute,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(DateFormat('d MMM, h:mm a').format(date)),
                ),
                const AiraGap(height: 10),
                const Text(
                  'Device local time. Choose within the next 24 hours.',
                  style: TextStyle(fontSize: 13, color: AiraColors.muted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  text.text.trim().isEmpty ? null : Navigator.pop(c, true),
              child: const Text('Confirm follow-up'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await controller.savePlan(text.text.trim(), date);
        if (c.mounted) showMessage(c, 'Follow-up saved.');
      } catch (e) {
        if (c.mounted) showMessage(c, AiraController.cleanError(e));
      }
    }
  }

  Future<void> medicine(BuildContext c) async {
    final name = TextEditingController(),
        instructions = TextEditingController();
    TimeOfDay time = TimeOfDay.now();
    final saved = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add a medicine reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Notice(
                  'Use an existing schedule. AIRA does not choose or change a dose. Prototype: one reminder, not a repeating prescription.',
                ),
                const AiraGap(height: 18),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Medicine label',
                  ),
                ),
                const AiraGap(height: 14),
                TextField(
                  controller: instructions,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Existing instructions',
                  ),
                ),
                const AiraGap(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showTimePicker(
                      context: c,
                      initialTime: time,
                    );
                    if (selected != null) set(() => time = selected);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(time.format(c)),
                ),
                const AiraGap(height: 10),
                const Text(
                  'Singapore time (UTC+8). Confirm that this matches your existing instructions.',
                  style: TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  name.text.trim().isEmpty ? null : Navigator.pop(c, true),
              child: const Text('Confirm reminder'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await controller.saveMedicine(
          name.text.trim(),
          instructions.text.trim(),
          time,
        );
      } catch (e) {
        if (c.mounted) showMessage(c, AiraController.cleanError(e));
      }
    }
  }

  Future<void> checkin(BuildContext c) async {
    if (!controller.consent('impact_measurement')) {
      showMessage(
        c,
        'Please enable optional weekly check-ins in Settings first.',
      );
      return;
    }
    try {
      await controller.loadMeasurementPrompt();
      if (!c.mounted) return;
      if (controller.measurementPrompt == null) {
        showMessage(c, 'Your next weekly check-in is not available yet.');
        return;
      }
      await showDialog(
        context: c,
        builder: (c) => LonelinessDialog(controller: controller),
      );
    } catch (e) {
      if (c.mounted) showMessage(c, AiraController.cleanError(e));
    }
  }

  @override
  Widget build(BuildContext c) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: ListView(
        padding: AiraLayout.of(c).insets(const EdgeInsets.all(28)),
        children: [
          const SectionHeading(
            'A little more about you',
            subtitle: 'Your memories, plans and everyday moments.',
          ),
          AiraCardGrid(
            children: [
              AiraSummaryCard(
                title: 'Memories',
                icon: Icons.bookmark_border_rounded,
                color: AiraColors.sage,
                value: '${controller.memories.length}',
                subtitle: 'Things you asked AIRA to remember',
                onTap: () => _open(c, 'Memories'),
              ),
              AiraSummaryCard(
                title: 'Plans & follow-ups',
                icon: Icons.event_outlined,
                color: AiraColors.peach,
                value: '${controller.plans.length}',
                subtitle: 'Something to look forward to',
                onTap: () => _open(c, 'Plans & follow-ups'),
              ),
              AiraSummaryCard(
                title: 'Medicine reminders',
                icon: Icons.medication_outlined,
                color: AiraColors.lavender,
                value: '${controller.medications.length}',
                subtitle: 'Your confirmed schedule',
                onTap: () => _open(c, 'Medicine reminders'),
              ),
              AiraSummaryCard(
                title: 'My feelings',
                icon: Icons.mood_rounded,
                color: AiraColors.sage,
                value: controller.mood.isEmpty
                    ? null
                    : '${controller.mood[0].toUpperCase()}${controller.mood.substring(1)}',
                subtitle: controller.mood.isEmpty
                    ? 'How are you feeling today?'
                    : 'Your own reported feeling',
                onTap: () => _open(c, 'My feelings'),
              ),
              AiraSummaryCard(
                title: 'Weekly check-in',
                icon: Icons.favorite_border_rounded,
                color: AiraColors.peach,
                value: controller.lonelyDays == null
                    ? null
                    : '${controller.lonelyDays} / 7',
                subtitle: controller.lonelyDays == null
                    ? 'A moment to reflect'
                    : 'Lonely days you reported',
                onTap: () => _open(c, 'Weekly check-in'),
              ),
            ],
          ),
          const AiraGap(height: 24),
        ],
      ),
    ),
  );

  void _open(BuildContext c, String section) => Navigator.of(c).push(
    MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AiraDetailPage(
          title: section,
          children: _details(context, section),
        ),
      ),
    ),
  );

  List<Widget> _details(BuildContext c, String section) {
    final ctl = controller;
    return switch (section) {
      'Memories' => [
        _section(
          c,
          'Memories',
          Icons.bookmark_border_rounded,
          'Little things that make you, you.',
          () => memory(c),
        ),
        if (ctl.memories.isEmpty)
          _empty(
            'What would you like AIRA to remember?',
            'Your interests, favourite things, and stories. Only with your say-so.',
          )
        else
          for (final m in ctl.memories)
            _item(
              c,
              m['user_approved_text']?.toString() ??
                  m['text']?.toString() ??
                  '',
              'Saved with your permission',
              Icons.bookmark_border_rounded,
              () async {
                if (await confirmAction(
                  c,
                  'Forget this memory?',
                  'AIRA will no longer use it. Linked follow-ups will be cancelled.',
                  confirm: 'Forget',
                )) {
                  try {
                    await ctl.forgetMemory(m);
                  } catch (e) {
                    if (c.mounted) {
                      showMessage(c, AiraController.cleanError(e));
                    }
                  }
                }
              },
            ),
      ],
      'Plans & follow-ups' => [
        _section(
          c,
          'Plans & follow-ups',
          Icons.event_outlined,
          'Something to look forward to.',
          () => plan(c),
        ),
        if (ctl.plans.isEmpty)
          _empty(
            'Any plans coming up?',
            'Choose something you’d like AIRA to ask you about.',
          )
        else
          for (final e in ctl.plans)
            _item(
              c,
              e['topic']?.toString() ?? e['label']?.toString() ?? 'Your plan',
              'Planned · ${_date(e['followup_at'] ?? e['due_at'])}',
              Icons.event_outlined,
              () async {
                try {
                  await ctl.removePlan(e['id'].toString());
                } catch (err) {
                  if (c.mounted) {
                    showMessage(c, AiraController.cleanError(err));
                  }
                }
              },
            ),
        const AiraGap(height: 16),
        const Notice(
          'Keep AIRA open for reminders. Background delivery is not active.',
        ),
      ],
      'Medicine reminders' => [
        _section(
          c,
          'Medicine reminders',
          Icons.medication_outlined,
          'Gentle reminders for your confirmed schedule.',
          () => medicine(c),
        ),
        if (ctl.medications.isEmpty)
          _empty(
            'No reminders yet',
            'Add an existing schedule. You stay in control.',
          )
        else
          for (final m in ctl.medications)
            _item(
              c,
              m['label']?.toString() ?? 'Medicine reminder',
              '${m['instructions'] ?? ''} · ${m['local_time'] ?? _date(m['due_at'])}',
              Icons.medication_outlined,
              () async {
                try {
                  await ctl.removeMedicine(m['id'].toString());
                } catch (e) {
                  if (c.mounted) {
                    showMessage(c, AiraController.cleanError(e));
                  }
                }
              },
            ),

        const AiraGap(height: 16),
        const Notice(
          'Keep AIRA open for reminders. Background delivery is not active.',
        ),
      ],
      'My feelings' => [
        MoodCheckIn(
          controller: ctl,
          onSettings: () {
            Navigator.pop(c);
            ctl.setTab(2);
          },
        ),
      ],
      _ => [
        AiraCard(
          color: AiraColors.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                size: 36,
                color: AiraColors.forest,
              ),
              const AiraGap(height: 16),
              Text(
                'How has this week felt?',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const AiraGap(height: 12),
              Text(
                ctl.lonelyDays == null
                    ? 'An optional check-in, in your own words.'
                    : 'You reported ${ctl.lonelyDays} lonely days. One answer is a starting point, not a trend.',
              ),
              const AiraGap(height: 20),
              FilledButton.icon(
                onPressed: () => checkin(c),
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  ctl.lonelyDays == null ? 'Start check-in' : 'Review check-in',
                ),
              ),
            ],
          ),
        ),
      ],
    };
  }

  String _date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    return d == null
        ? 'Time not set'
        : DateFormat('d MMM, h:mm a').format(d.toLocal());
  }

  Widget _section(
    BuildContext c,
    String title,
    IconData icon,
    String sub,
    VoidCallback action,
  ) => AiraPadding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Icon(icon, color: AiraColors.forest),
        const AiraGap(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              Text(sub, style: Theme.of(c).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Add $title',
          onPressed: action,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 30),
        ),
      ],
    ),
  );
  Widget _empty(String title, String sub) => AiraCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const AiraGap(height: 7),
        Text(
          sub,
          style: const TextStyle(fontSize: 16, color: AiraColors.muted),
        ),
      ],
    ),
  );
  Widget _item(
    BuildContext c,
    String title,
    String sub,
    IconData icon,
    VoidCallback remove,
  ) => AiraPadding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AiraCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: AiraColors.forest),
          const AiraGap(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const AiraGap(height: 4),
                Text(sub, style: Theme.of(c).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove $title',
            onPressed: remove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    ),
  );
}

class LonelinessDialog extends StatefulWidget {
  final AiraController controller;
  const LonelinessDialog({super.key, required this.controller});
  @override
  State<LonelinessDialog> createState() => _LonelinessState();
}

class _LonelinessState extends State<LonelinessDialog> {
  int? selected;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    selected = widget.controller.measurementResponse?['lonely_days'] as int?;
  }

  Future<void> save(int? value) async {
    setState(() => busy = true);
    try {
      await widget.controller.saveLoneliness(value);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final prompt = widget.controller.measurementPrompt!;
    final start = DateTime.parse(prompt['period_start'].toString());
    final end = DateTime.parse(prompt['period_end'].toString());
    return AlertDialog(
      title: const Text('How has your week felt?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}',
              style: const TextStyle(fontSize: 16, color: AiraColors.muted),
            ),
            const AiraGap(height: 18),
            const Text(
              'On how many of these seven days did you feel lonely?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const AiraGap(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i <= 7; i++)
                  ChoiceChip(
                    label: Text('$i ${i == 1 ? 'day' : 'days'}'),
                    selected: selected == i,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => selected = i),
                    padding: const EdgeInsets.all(9),
                  ),
              ],
            ),
            const AiraGap(height: 18),
            const Text(
              'You can skip this. It will not affect your chats. This is your own report, not an AI estimate.',
              style: TextStyle(fontSize: 15, color: AiraColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => save(null),
          child: const Text('Skip this question'),
        ),
        FilledButton(
          onPressed: busy || selected == null ? null : () => save(selected),
          child: Text(busy ? 'Saving…' : 'Save check-in'),
        ),
      ],
    );
  }
}

/// Self-report is optional and remains separate from facial estimates.
class MoodCheckIn extends StatefulWidget {
  const MoodCheckIn({super.key, required this.controller, this.onSettings});
  final AiraController controller;
  final VoidCallback? onSettings;
  @override
  State<MoodCheckIn> createState() => _MoodCheckInState();
}

class _MoodCheckInState extends State<MoodCheckIn> {
  bool saving = false;

  Future<void> save(String feeling) async {
    final controller = widget.controller;
    if (saving || !controller.consent('mood_history')) return;
    final epoch = controller.sessionEpoch;
    setState(() => saving = true);
    try {
      await controller.saveMood(feeling);
      if (!mounted || controller.sessionEpoch != epoch) return;
      showMessage(
        context,
        controller.preview
            ? 'Your feeling is saved for this preview session.'
            : 'Saved as your own reported feeling.',
      );
    } catch (error) {
      if (mounted && controller.sessionEpoch == epoch) {
        showMessage(context, AiraController.cleanError(error));
      }
    } finally {
      if (mounted && controller.sessionEpoch == epoch) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final allowed = widget.controller.consent('mood_history');
      return AiraCard(
        color: AiraColors.sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How do you feel today?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const AiraGap(height: 8),
            const Text(
              'Optional · Your own feeling, separate from an AI estimate.',
              style: TextStyle(fontSize: 15, color: AiraColors.muted),
            ),
            const AiraGap(height: 16),
            if (!allowed) ...[
              const Text(
                'To save a feeling, turn on “Save my reported mood” in Settings.',
                style: TextStyle(fontSize: 16),
              ),
              const AiraGap(height: 8),
              TextButton(
                onPressed:
                    widget.onSettings ?? () => widget.controller.setTab(2),
                child: const Text('Open Settings'),
              ),
            ] else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final feeling in [
                    'happy',
                    'okay',
                    'sad',
                    'worried',
                    'tired',
                  ])
                    ChoiceChip(
                      label: Text(
                        '${feeling[0].toUpperCase()}${feeling.substring(1)}',
                      ),
                      selected: widget.controller.mood == feeling,
                      onSelected: saving ? null : (_) => save(feeling),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                ],
              ),
              if (saving)
                const AiraPadding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Saving your feeling…',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
