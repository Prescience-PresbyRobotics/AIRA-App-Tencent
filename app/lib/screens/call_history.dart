import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key, required this.controller});
  final AiraController controller;
  @override
  State<CallHistoryScreen> createState() => _CallHistoryState();
}

class _CallHistoryState extends State<CallHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshCallHistory();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final ctl = widget.controller;
      return AiraDetailPage(
        title: 'Call history',
        children: [
          const Notice(
            'Read your voice and video transcripts here, or tap a call in your chat. AIRA can use saved chats and calls for context. Audio recordings are not saved by AIRA.',
            icon: Icons.history_rounded,
          ),
          const AiraGap(height: 18),
          if (!ctl.consent('store_conversations'))
            const Notice(
              'Turn on Save conversations in Privacy & memory to keep transcripts across visits.',
            )
          else if (ctl.preview)
            const Notice(
              'Your calls will appear here after you sign in and make a live call.',
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: ctl.callHistoryLoading
                    ? null
                    : ctl.refreshCallHistory,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ),
            if (ctl.callHistoryError.isNotEmpty) Notice(ctl.callHistoryError),
            if (ctl.callHistoryLoading) const LinearProgressIndicator(),
            if (ctl.callHistory.isEmpty && !ctl.callHistoryLoading)
              const AiraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.call_outlined,
                      size: 32,
                      color: AiraColors.forest,
                    ),
                    AiraGap(height: 12),
                    Text('No saved calls yet'),
                    AiraGap(height: 6),
                    Text('After a call, open its transcript here.'),
                  ],
                ),
              ),
            for (final call in ctl.callHistory) ...[
              AiraCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: call['mode'] == 'video'
                        ? AiraColors.lavender
                        : AiraColors.sage,
                    child: Icon(
                      call['mode'] == 'video'
                          ? Icons.videocam_outlined
                          : Icons.call_outlined,
                      color: AiraColors.forest,
                    ),
                  ),
                  title: Text(
                    call['mode'] == 'video'
                        ? 'Video call with AIRA'
                        : 'Voice call with AIRA',
                  ),
                  subtitle: Text(
                    '${callDate(call['startedAt'])}\n${call['initiator'] == 'aira' ? 'AIRA called you' : 'You called AIRA'} · ${callDuration(call)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CallTranscriptScreen(controller: ctl, call: call),
                    ),
                  ),
                ),
              ),
              const AiraGap(height: 10),
            ],
            if (ctl.callHistoryCursor != null)
              OutlinedButton(
                onPressed: ctl.callHistoryLoading
                    ? null
                    : () => ctl.refreshCallHistory(older: true),
                child: const Text('Earlier calls'),
              ),
          ],
        ],
      );
    },
  );
}

String callDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Time unavailable'
      : DateFormat('d MMM yyyy, h:mm a').format(date.toLocal());
}

String callDuration(Map<String, dynamic> call) {
  final start = DateTime.tryParse(call['startedAt']?.toString() ?? '');
  final end = DateTime.tryParse(call['endedAt']?.toString() ?? '');
  if (start == null || end == null) {
    return call['status'] == 'active' ? 'In progress' : 'Ended';
  }
  final seconds = end.difference(start).inSeconds.clamp(0, 86400);
  return seconds < 60 ? '$seconds sec' : '${seconds ~/ 60} min';
}

class CallTranscriptScreen extends StatefulWidget {
  const CallTranscriptScreen({
    super.key,
    required this.controller,
    required this.call,
  });
  final AiraController controller;
  final Map<String, dynamic> call;
  @override
  State<CallTranscriptScreen> createState() => _CallTranscriptState();
}

class _CallTranscriptState extends State<CallTranscriptScreen> {
  List<Map<String, dynamic>> messages = [];
  Map<String, dynamic> call = {};
  bool loading = true;
  String? error;
  late final int session;

  @override
  void initState() {
    super.initState();
    session = widget.controller.sessionEpoch;
    call = widget.call;
    widget.controller.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (widget.controller.sessionEpoch != session ||
        !widget.controller.consent('store_conversations')) {
      if (mounted) {
        setState(() {
          messages = [];
          error = 'Your account or privacy choices changed.';
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.controller.loadCallTranscript(
        widget.call['id'].toString(),
      );
      if (!mounted || widget.controller.sessionEpoch != session) return;
      setState(() {
        call = Map<String, dynamic>.from(result['call'] ?? widget.call);
        messages = (result['messages'] as List? ?? [])
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmAction(
      context,
      'Delete this call transcript?',
      'This removes this call’s saved transcript. Your text chats and other calls stay saved.',
      confirm: 'Delete transcript',
    )) {
      return;
    }
    try {
      await widget.controller.deleteCallTranscript(
        widget.call['id'].toString(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AiraDetailPage(
    title: call['mode'] == 'video'
        ? 'Video call transcript'
        : 'Voice call transcript',
    children: [
      AiraCard(
        color: AiraColors.sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              callDate(call['startedAt']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const AiraGap(height: 8),
            Text(
              '${call['initiator'] == 'aira' ? 'AIRA called you' : 'You called AIRA'} · ${callDuration(call)}',
            ),
            const AiraGap(height: 12),
            const Text(
              'Speech recognition can make mistakes. This is a text transcript, not an audio recording.',
            ),
          ],
        ),
      ),
      const AiraGap(height: 16),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Notice(error!),
      if (!loading && messages.isEmpty && error == null)
        const Notice(
          'No transcript is available yet. If the call just ended, refresh in a moment.',
        ),
      for (final message in messages) ...[
        AiraCard(
          color: message['role'] == 'assistant'
              ? AiraColors.lavender
              : Colors.white,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message['role'] == 'assistant' ? 'AIRA' : 'You',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AiraColors.forest,
                ),
              ),
              const AiraGap(height: 6),
              SelectionArea(child: Text(message['text']?.toString() ?? '')),
            ],
          ),
        ),
        const AiraGap(height: 10),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh transcript'),
          ),
          TextButton.icon(
            onPressed: loading ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete transcript'),
          ),
        ],
      ),
    ],
  );
}
