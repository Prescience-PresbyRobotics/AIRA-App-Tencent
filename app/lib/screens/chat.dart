import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/companion.dart';
import '../widgets/ui.dart';
import '../media/aira_media.dart';
import 'call.dart';

class ChatScreen extends StatefulWidget {
  final AiraController controller;
  const ChatScreen({super.key, required this.controller});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  final draft = TextEditingController(), scroll = ScrollController();
  final media = AiraMediaController();
  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
    media.dispose();
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

  Future<void> read(ChatTurn turn) async {
    final epoch = widget.controller.revision;
    try {
      if (turn.speechToken == null) {
        showMessage(context, 'Speech is unavailable for this message.');
        return;
      }
      final bytes = await widget.controller.api.speech(turn.speechToken!);
      if (!mounted || epoch != widget.controller.revision) return;
      await media.playAudio(bytes, 'audio/mpeg');
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    }
  }

  void call(bool video) {
    media.stopPlayback();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(controller: widget.controller, video: video),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final ctl = widget.controller;
    final roomy = MediaQuery.sizeOf(c).width > 740;
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
            _dateDivider(ctl.introduction.time),
            _bubble(ctl.introduction, opening: true),
            for (final (index, message) in ctl.visibleMessages.indexed) ...[
              if (!DateUtils.isSameDay(
                message.time,
                index == 0
                    ? ctl.introduction.time
                    : ctl.visibleMessages[index - 1].time,
              ))
                _dateDivider(message.time),
              _bubble(message),
            ],
            if (ctl.sending) const _TypingIndicator(),
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
        : DateFormat('EEE, d MMM').format(local).toUpperCase();
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
              if (m.fromAira && !opening && m.speechToken != null)
                TextButton.icon(
                  onPressed: () => read(m),
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  label: const Text(
                    'Read aloud',
                    style: TextStyle(fontSize: 13),
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
