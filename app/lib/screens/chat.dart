import 'package:flutter/material.dart';

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

  Future<void> send() async {
    final value = draft.text;
    if (value.trim().isEmpty) return;
    try {
      await widget.controller.send(value);
      if (!mounted) return;
      draft.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
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
                          ctl.sending ? 'Thinking…' : 'Your AI companion',
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
            const Row(
              children: [
                Expanded(child: Divider()),
                AiraPadding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.6,
                      color: AiraColors.muted,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const AiraGap(height: 20),
            if (ctl.messages.isEmpty) ...[
              Center(
                child: Column(
                  children: [
                    Companion(
                      size: (roomy ? 225 : 175) * (ctl.largerText ? 1 : .9),
                    ),
                    Text(
                      'Hello${ctl.name.isNotEmpty ? ', ${ctl.name}' : ''}.\nHow’s your day going?',
                      textAlign: TextAlign.center,
                      style: Theme.of(c).textTheme.headlineMedium,
                    ),
                    const AiraGap(height: 12),
                    const Text(
                      'There’s no rush. I’m here to listen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: AiraColors.muted),
                    ),
                    const AiraGap(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final (icon, text) in [
                          (Icons.wb_sunny_outlined, 'Talk about my day'),
                          (Icons.auto_stories_outlined, 'Share a memory'),
                          (Icons.coffee_outlined, 'Just have a chat'),
                        ])
                          OutlinedButton.icon(
                            onPressed: () {
                              draft.text = text;
                            },
                            icon: Icon(icon, size: 20),
                            label: Text(
                              text,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (ctl.preview) ...[
                const AiraGap(height: 26),
                const Notice(
                  'This is the interface preview. Connect your Supabase project and AI services to start a live conversation.',
                ),
              ],
            ] else
              for (final message in ctl.messages) _bubble(message),
            if (ctl.sending)
              const AiraPadding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    AiraGap(width: 12),
                    Flexible(
                      child: Text(
                        'AIRA is thinking…',
                        style: TextStyle(color: AiraColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
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
                    onPressed: ctl.sending ? null : send,
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

  Widget _bubble(ChatTurn m) => Align(
    alignment: m.fromAira ? Alignment.centerLeft : Alignment.centerRight,
    child: AiraPadding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 630),
        child: Column(
          crossAxisAlignment: m.fromAira
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Container(
              padding: AiraLayout.of(context).insets(const EdgeInsets.all(20)),
              decoration: BoxDecoration(
                color: m.fromAira ? Colors.white : AiraColors.sage,
                border: Border.all(
                  color: AiraColors.line.withValues(alpha: .5),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(m.fromAira ? 5 : 22),
                  bottomRight: Radius.circular(m.fromAira ? 22 : 5),
                ),
              ),
              child: SelectableText(
                m.text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (m.fromAira)
              TextButton.icon(
                onPressed: () => read(m),
                icon: const Icon(Icons.volume_up_outlined, size: 20),
                label: const Text('Read aloud', style: TextStyle(fontSize: 15)),
              ),
          ],
        ),
      ),
    ),
  );
}
