import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/companion.dart';
import '../widgets/ui.dart';
import 'call.dart';
import 'call_history.dart';
import 'personal.dart';

class ChatScreen extends StatefulWidget {
  final AiraController controller;
  const ChatScreen({super.key, required this.controller});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final draft = TextEditingController(), scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scrollToLatest();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshCallHistory();
    });
  }

  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  void scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> olderHistory() async {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final extent = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;
    await Future.wait([
      if (widget.controller.hasOlderHistory)
        widget.controller.refreshHistory(older: true),
      if (widget.controller.callHistoryCursor != null)
        widget.controller.refreshCallHistory(older: true),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(
          (offset + scroll.position.maxScrollExtent - extent).clamp(
            0.0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  Future<void> enableHistory() async {
    try {
      await widget.controller.updatePreference('store_conversations', true);
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    }
  }

  Future<void> send() async {
    final value = draft.text;
    if (value.trim().isEmpty || widget.controller.sending) return;
    final ctl = widget.controller;
    final epoch = ctl.sessionEpoch;
    try {
      final request = ctl.send(value);
      // A real outgoing bubble owns this draft now. Preview rejection keeps it.
      if (!ctl.preview && ctl.sending) draft.clear();
      scrollToLatest();
      await request;
      if (!mounted || epoch != ctl.sessionEpoch) return;
      scrollToLatest();
    } catch (e) {
      if (mounted && epoch == ctl.sessionEpoch) {
        showMessage(context, AiraController.cleanError(e));
      }
    }
  }

  Future<void> retry(ChatTurn message) async {
    try {
      await widget.controller.retryMessage(message);
      if (mounted) scrollToLatest();
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    }
  }

  Future<void> useName() async {
    final ctl = widget.controller;
    final proposed = ctl.suggestedName;
    if (proposed == null) return;
    try {
      await ctl.confirmPreferredName(proposed);
      if (mounted) {
        showMessage(
          context,
          ctl.consent('memory_enabled')
              ? 'Your preferred name is saved.'
              : 'I’ll use that name in this chat.',
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    }
  }

  Future<void> call(bool video) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(controller: widget.controller, video: video),
      ),
    );
    if (mounted) scrollToLatest();
  }

  @override
  Widget build(BuildContext c) {
    final ctl = widget.controller;
    final roomy = MediaQuery.sizeOf(c).width > 740;
    final visible = ctl.visibleMessages;
    final opening = ctl.showIntroduction;
    final entries =
        <({DateTime time, ChatTurn? message, Map<String, dynamic>? call})>[
          if (opening)
            (
              time: ctl.introduction.time,
              message: ctl.introduction,
              call: null,
            ),
          for (final message in visible)
            (time: message.time, message: message, call: null),
          for (final call in ctl.callHistory)
            if (DateTime.tryParse(call['startedAt']?.toString() ?? '')
                case final DateTime time)
              (time: time.toLocal(), message: null, call: call),
        ]..sort((a, b) => a.time.compareTo(b.time));
    return LayoutBuilder(
      builder: (context, bounds) {
        final scrollAll =
            bounds.maxHeight < 400 || MediaQuery.textScalerOf(c).scale(1) > 1.5;
        final header = AiraPadding(
          padding: EdgeInsets.fromLTRB(
            roomy ? 40 : 20,
            24,
            roomy ? 40 : 20,
            20,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AiraColors.peach,
                      shape: BoxShape.circle,
                    ),
                    child: const Companion(size: 50, animated: false),
                  ),
                  const AiraGap(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AIRA',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Your AI companion',
                          style: const TextStyle(
                            fontSize: 15,
                            color: AiraColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (roomy) ...[
                    OutlinedButton.icon(
                      onPressed: () => call(false),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Voice call'),
                    ),
                    const AiraGap(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => call(true),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video call'),
                    ),
                  ],
                ],
              ),
              if (!roomy) ...[
                const AiraGap(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => call(false),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Voice call'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => call(true),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video call'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
        final history = ListView(
          controller: scrollAll ? null : scroll,
          shrinkWrap: scrollAll,
          physics: scrollAll ? const NeverScrollableScrollPhysics() : null,
          padding: AiraLayout.of(c).insets(
            EdgeInsets.symmetric(horizontal: roomy ? 56 : 20, vertical: 24),
          ),
          children: [
            if (ctl.historyLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (ctl.hasOlderHistory || ctl.callHistoryCursor != null)
              Center(
                child: TextButton.icon(
                  onPressed: olderHistory,
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Load earlier messages and calls'),
                ),
              ),
            if (ctl.historyError.isNotEmpty) ...[
              Notice('Could not restore saved chats. ${ctl.historyError}'),
              TextButton(
                onPressed: () => ctl.refreshHistory(),
                child: const Text('Retry history'),
              ),
            ],
            if (!ctl.preview && !ctl.consent('store_conversations'))
              AiraPadding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AiraCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const Text(
                        'Chat saving is off. New conversations will disappear when you leave.',
                      ),
                      TextButton.icon(
                        onPressed: enableHistory,
                        icon: const Icon(Icons.cloud_done_outlined),
                        label: const Text('Keep future conversations'),
                      ),
                    ],
                  ),
                ),
              ),
            if (ctl.callHistoryError.isNotEmpty) ...[
              Notice('Could not restore calls. ${ctl.callHistoryError}'),
              TextButton(
                onPressed: ctl.refreshCallHistory,
                child: const Text('Retry call history'),
              ),
            ],
            for (final (index, entry) in entries.indexed) ...[
              if (index == 0 ||
                  !DateUtils.isSameDay(entry.time, entries[index - 1].time))
                _dateDivider(entry.time),
              if (entry.message != null)
                _bubble(
                  entry.message!,
                  opening: opening && entry.message == ctl.introduction,
                )
              else
                _callCard(entry.call!),
            ],
            if (ctl.sending || ctl.historyAwaitingReply)
              const _TypingIndicator(),
            if (ctl.suggestedName != null && !ctl.sending)
              AiraPadding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: ctl.savingName ? null : useName,
                      icon: const Icon(Icons.person_outline, size: 19),
                      label: Text(
                        ctl.savingName
                            ? 'Saving…'
                            : ctl.consent('memory_enabled')
                            ? 'Remember “${ctl.suggestedName}” as my name'
                            : 'Use “${ctl.suggestedName}” for this chat',
                      ),
                    ),
                    TextButton(
                      onPressed: ctl.savingName
                          ? null
                          : ctl.dismissSuggestedName,
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ),
            if (ctl.preview) ...[
              const AiraGap(height: 12),
              const Notice(
                'Interface preview · Aira’s introduction is shown here. Live replies are not connected.',
              ),
            ],
          ],
        );
        final composer = Container(
          padding: AiraLayout.of(c).insets(
            EdgeInsets.fromLTRB(roomy ? 36 : 16, 16, roomy ? 36 : 16, 12),
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AiraColors.line)),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: draft,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Message AIRA',
                        counterText: '',
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const AiraGap(width: 12),
                  FilledButton(
                    onPressed: ctl.sending || ctl.savingName ? null : send,
                    child: const AiraPadding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        semanticLabel: 'Send message',
                      ),
                    ),
                  ),
                ],
              ),
              const AiraGap(height: 10),
              const Text(
                'AI can make mistakes. Your choices are always yours.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AiraColors.muted),
              ),
            ],
          ),
        );
        final content = Column(
          mainAxisSize: scrollAll ? MainAxisSize.min : MainAxisSize.max,
          children: [
            header,
            const Divider(height: 1),
            if (scrollAll) history else Expanded(child: history),
            composer,
          ],
        );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: scrollAll
                ? SingleChildScrollView(controller: scroll, child: content)
                : content,
          ),
        );
      },
    );
  }

  Widget _dateDivider(DateTime date) {
    final local = date.toLocal();
    final today = DateTime.now();
    final label = DateUtils.isSameDay(local, today)
        ? 'TODAY'
        : DateFormat(
            local.year == today.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy',
          ).format(local).toUpperCase();
    return AiraPadding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          AiraPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                color: AiraColors.muted,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _callCard(Map<String, dynamic> call) {
    final video = call['mode'] == 'video';
    final incoming = call['initiator'] == 'aira';
    final date = DateTime.tryParse(call['startedAt']?.toString() ?? '');
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Material(
            color: incoming ? Colors.white : AiraColors.sage,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('call-card-${call['id']}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallTranscriptScreen(
                    controller: widget.controller,
                    call: call,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AiraColors.forest.withValues(alpha: .08),
                      child: Icon(
                        video ? Icons.videocam_outlined : Icons.call_outlined,
                        color: AiraColors.forest,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video ? 'Video call' : 'Voice call',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                incoming
                                    ? Icons.call_received
                                    : Icons.call_made,
                                size: 14,
                                color: AiraColors.muted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${callDuration(call)}${date == null ? '' : ' · ${DateFormat('h:mm a').format(date.toLocal())}'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AiraColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap for transcript',
                            style: TextStyle(
                              fontSize: 12,
                              color: AiraColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatTurn m, {bool opening = false}) {
    final ctl = widget.controller;
    final time = DateFormat('h:mm a').format(m.time.toLocal());
    final status = switch (m.delivery) {
      MessageDelivery.sending => 'Sending',
      MessageDelivery.delivered => 'Delivered',
      MessageDelivery.read => 'Read',
      MessageDelivery.unconfirmed => 'Not confirmed',
      MessageDelivery.cancelled => 'Stopped',
    };
    final icon = switch (m.delivery) {
      MessageDelivery.sending => Icons.schedule_rounded,
      MessageDelivery.delivered ||
      MessageDelivery.read => Icons.done_all_rounded,
      MessageDelivery.unconfirmed => Icons.error_outline_rounded,
      MessageDelivery.cancelled => Icons.pause_circle_outline,
    };
    return Align(
      alignment: m.fromAira ? Alignment.centerLeft : Alignment.centerRight,
      child: AiraPadding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 630),
          child: Column(
            crossAxisAlignment: m.fromAira
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Container(
                key: ValueKey('bubble-${m.id}'),
                padding: AiraLayout.of(context)
                    .insets(const EdgeInsets.fromLTRB(18, 15, 15, 10)),
                decoration: BoxDecoration(
                  color: m.fromAira ? Colors.white : AiraColors.sage,
                  border: Border.all(
                    color: AiraColors.line.withValues(alpha: .5),
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(m.fromAira ? 5 : 20),
                    bottomRight: Radius.circular(m.fromAira ? 20 : 5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectionArea(
                      child: Text(
                        m.text,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const AiraGap(height: 8),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.end,
                      children: [
                        if (m.mode != 'text')
                          Icon(
                            m.mode == 'video'
                                ? Icons.videocam_outlined
                                : Icons.call_outlined,
                            size: 13,
                            color: AiraColors.muted,
                            semanticLabel: '${m.mode} call transcript',
                          ),
                        Text(
                          time,
                          key: ValueKey('time-${m.id}'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AiraColors.muted,
                          ),
                        ),
                        if (!m.fromAira)
                          Tooltip(
                            message: m.delivery == MessageDelivery.read
                                ? 'Read means Aira returned a reply. Aira is AI.'
                                : m.delivery == MessageDelivery.delivered
                                ? 'Aira’s server received your message.'
                                : status,
                            child: Semantics(
                              label: status,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 16,
                                    color: m.delivery == MessageDelivery.read
                                        ? AiraColors.forest
                                        : AiraColors.muted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: m.delivery == MessageDelivery.read
                                          ? AiraColors.forest
                                          : AiraColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!m.fromAira && m.issue != null) ...[
                const AiraGap(height: 5),
                Text(
                  m.delivery == MessageDelivery.delivered
                      ? 'Delivered · reply unavailable'
                      : m.issue!,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13, color: AiraColors.muted),
                ),
                TextButton.icon(
                  onPressed: ctl.sending ? null : () => retry(m),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
              if (m.fromAira &&
                  m.actionNotice?.isNotEmpty == true &&
                  !m.text.contains(m.actionNotice!))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    m.actionNotice!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AiraColors.muted,
                    ),
                  ),
                ),
              if (m.fromAira)
                for (final action in m.actions.where(
                  (action) => [
                    'saved',
                    'updated',
                    'already_saved',
                  ].contains(action['status']),
                ))
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('About me')),
                          body: ListenableBuilder(
                            listenable: ctl,
                            builder: (context, _) =>
                                PersonalScreen(controller: ctl),
                          ),
                        ),
                      ),
                    ),
                    icon: Icon(switch (action['kind']) {
                      'medication' => Icons.medication_outlined,
                      'event' => Icons.event_available_outlined,
                      _ => Icons.bookmark_added_outlined,
                    }, size: 17),
                    label: Text(
                      '${switch (action['kind']) {
                        'medication' => 'Medicine reminder',
                        'event' => 'Plan',
                        _ => 'Memory',
                      }} ${action['status'] == 'updated'
                          ? 'updated'
                          : action['status'] == 'already_saved'
                          ? 'already saved'
                          : 'saved'} · ${action['label'] ?? 'View in About me'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else {
      animation.repeat();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Aira is preparing a reply',
    child: ExcludeSemantics(
      child: AiraPadding(
        key: const ValueKey('aira-typing-indicator'),
        padding: const EdgeInsets.only(bottom: 16, top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var dot = 0; dot < 3; dot++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Opacity(
                        opacity: MediaQuery.disableAnimationsOf(context)
                            ? .6
                            : .35 +
                                  .65 *
                                      ((math.sin(
                                                (animation.value - dot * .18) *
                                                    math.pi *
                                                    2,
                                              ) +
                                              1) /
                                          2),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AiraColors.forest,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Aira is typing…',
                style: TextStyle(color: AiraColors.muted, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
