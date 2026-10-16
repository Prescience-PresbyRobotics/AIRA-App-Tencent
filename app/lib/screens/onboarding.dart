import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/companion.dart';
import '../widgets/ui.dart';

class OnboardingScreen extends StatefulWidget {
  final AiraController controller;
  const OnboardingScreen({super.key, required this.controller});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  int step = 0;
  bool busy = false;
  final choices = <String, dynamic>{
    'store_conversations': false,
    'memory_enabled': false,
    'social_reminders': false,
    'medication_reminders': false,
    'impact_measurement': false,
    'monitoring_enabled': false,
  };
  Future<void> finish() async {
    setState(() => busy = true);
    try {
      await widget.controller.finishOnboarding('', choices);
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: SingleChildScrollView(
            padding: AiraLayout.of(c).insets(const EdgeInsets.all(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => step == 0
                          ? widget.controller.signOut()
                          : setState(() => step--),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back'),
                    ),
                    const Spacer(),
                    Text(
                      '${step + 1} of 2',
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (widget.controller.preview)
                  const Notice(
                    'Interface preview · changes stay in this session.',
                  ),
                if (widget.controller.error.isNotEmpty) ...[
                  const AiraGap(height: 14),
                  Notice(widget.controller.error),
                  TextButton(
                    onPressed: widget.controller.bootstrap,
                    child: const Text('Retry account setup'),
                  ),
                ],
                const AiraGap(height: 18),
                if (step == 0) ...[
                  Center(
                    child: Companion(
                      size: widget.controller.largerText ? 200 : 180,
                    ),
                  ),
                  Text(
                    'Hello, I’m AIRA.',
                    textAlign: TextAlign.center,
                    style: Theme.of(c).textTheme.headlineLarge,
                  ),
                  const AiraGap(height: 12),
                  const Text(
                    'Your AI companion. We can chat, share a story, or talk about your day.',
                    textAlign: TextAlign.center,
                  ),
                  const AiraGap(height: 28),
                  const Text(
                    'Let’s get comfortable first. Aira will introduce itself when we start chatting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AiraColors.muted),
                  ),
                  const AiraGap(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Larger text'),
                    value: widget.controller.largerText,
                    onChanged: widget.controller.setScale,
                  ),
                  const AiraGap(height: 18),
                  FilledButton(
                    onPressed: () => setState(() => step = 1),
                    child: const Text('Continue'),
                  ),
                ] else ...[
                  Text(
                    'Your company.\nYour choices.',
                    style: Theme.of(c).textTheme.headlineLarge,
                  ),
                  const AiraGap(height: 12),
                  const Text(
                    'Everything below is optional. You can change your choices at any time.',
                    style: TextStyle(
                      color: AiraColors.muted,
                      fontSize: 18,
                      height: 1.5,
                    ),
                  ),
                  const AiraGap(height: 24),
                  _choice(
                    'store_conversations',
                    'Save our conversations',
                    'Return to your conversation later.',
                  ),
                  _choice(
                    'memory_enabled',
                    'Remember what matters',
                    'Only save details you explicitly confirm.',
                  ),
                  _choice(
                    'social_reminders',
                    'Invite me to chat',
                    'Allow gentle check-ins. Quiet hours: 9 PM–9 AM Singapore time.',
                  ),
                  _choice(
                    'medication_reminders',
                    'Medication reminders',
                    'Remind you about a schedule you confirm.',
                  ),
                  _choice(
                    'impact_measurement',
                    'Optional weekly check-ins',
                    'Keep your reported lonely days and conversation activity.',
                  ),
                  _choice(
                    'monitoring_enabled',
                    'Allow safety-review evidence',
                    'Save limited flagged excerpts for authorized review. Test-only in this prototype.',
                  ),
                  const AiraGap(height: 20),
                  const Notice(
                    'AIRA is AI and can make mistakes. It is not an emergency service. Camera and microphone are requested only when you choose to use them.',
                  ),
                  const AiraGap(height: 24),
                  FilledButton(
                    onPressed: busy ? null : finish,
                    child: Text(busy ? 'Getting ready…' : 'Let’s chat'),
                  ),
                ],
                const AiraGap(height: 20),
                const Text(
                  'English · Singapore time',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AiraColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _choice(String key, String title, String subtitle) => AiraPadding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AiraCard(
      padding: const EdgeInsets.all(8),
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        value: choices[key] == true,
        onChanged: (v) => setState(() => choices[key] = v),
      ),
    ),
  );
}
