import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class CallScheduleScreen extends StatefulWidget {
  const CallScheduleScreen({super.key, required this.controller});
  final AiraController controller;
  @override
  State<CallScheduleScreen> createState() => _CallScheduleState();
}

class _CallScheduleState extends State<CallScheduleScreen> {
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.controller.refreshCallSchedule();
    } catch (e) {
      if (mounted) setState(() => error = AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  TimeOfDay? get selectedTime {
    final parts = widget.controller.callSchedule?['localTime']
        ?.toString()
        .split(':');
    if (parts == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    return hour == null || minute == null
        ? null
        : TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'When should AIRA call you?',
    );
    if (time != null && mounted) await _save(time);
  }

  Future<void> _save(TimeOfDay time, {bool enabled = true}) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveCallSchedule(time, enabled: enabled);
    } catch (e) {
      if (mounted) setState(() => error = AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.deleteCallSchedule();
    } catch (e) {
      if (mounted) setState(() => error = AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final ctl = widget.controller;
      final time = selectedTime;
      final next = DateTime.tryParse(
        ctl.callSchedule?['nextCallAt']?.toString() ?? '',
      );
      return AiraDetailPage(
        title: 'Calls from AIRA',
        children: [
          AiraCard(
            color: AiraColors.sage,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.add_call, size: 34, color: AiraColors.forest),
                const AiraGap(height: 14),
                Text(
                  'Make time for a little company',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const AiraGap(height: 10),
                const Text(
                  'Choose a daily time. AIRA will call, and you can accept or decline. When you answer, AIRA speaks first.',
                ),
                const AiraGap(height: 18),
                FilledButton.icon(
                  onPressed: loading || saving ? null : _chooseTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(
                    time == null
                        ? 'Choose a call time'
                        : 'Every day at ${time.format(context)}',
                  ),
                ),
                const AiraGap(height: 8),
                const Text('Singapore time · Asia/Singapore'),
              ],
            ),
          ),
          const AiraGap(height: 18),
          if (loading || saving) const LinearProgressIndicator(),
          if (error != null) ...[
            Notice(error!),
            TextButton(
              onPressed: loading || saving ? null : _load,
              child: const Text('Try again'),
            ),
          ],
          if (time != null) ...[
            AiraCard(
              padding: const EdgeInsets.all(8),
              child: SwitchListTile(
                title: const Text('Daily call from AIRA'),
                subtitle: Text(
                  ctl.callSchedule?['enabled'] == true
                      ? 'AIRA will ring at your chosen time.'
                      : 'Paused. Your chosen time is kept.',
                ),
                value: ctl.callSchedule?['enabled'] == true,
                onChanged: saving
                    ? null
                    : (enabled) => _save(time, enabled: enabled),
              ),
            ),
            if (next != null && ctl.callSchedule?['enabled'] == true) ...[
              const AiraGap(height: 12),
              Text(
                'Next call: ${DateFormat('d MMM, h:mm a').format(next.toUtc().add(const Duration(hours: 8)))} Singapore time',
              ),
            ],
            const AiraGap(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: saving ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove call schedule'),
              ),
            ),
          ],
          const AiraGap(height: 16),
          const Notice(
            'Keep AIRA open and visible in your browser at the chosen time. Calls cannot ring when the tab is closed or your device is asleep.',
            icon: Icons.info_outline,
          ),
          if (ctl.preview) ...[
            const AiraGap(height: 12),
            const Notice(
              'Preview only. This schedule stays in this session and will not place a live call.',
            ),
          ],
        ],
      );
    },
  );
}
