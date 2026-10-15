import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  final AiraController controller;
  final ValueChanged<String> onCare;
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onCare,
  });
  Future<void> toggle(BuildContext c, String key, bool value) async {
    try {
      await controller.updatePreference(key, value);
    } catch (e) {
      if (c.mounted) showMessage(c, AiraController.cleanError(e));
    }
  }

  @override
  Widget build(BuildContext c) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: AiraLayout.of(c).insets(const EdgeInsets.all(28)),
        children: [
          const SectionHeading(
            'Make yourself comfortable',
            subtitle: 'Your preferences. Your privacy. Your pace.',
          ),
          AiraCard(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AiraColors.sage,
                  radius: 28,
                  child: Text(
                    controller.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      color: AiraColors.forest,
                      fontSize: 24,
                    ),
                  ),
                ),
                const AiraGap(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.name.isEmpty
                            ? 'Your AIRA space'
                            : controller.name,
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                      Text(
                        controller.preview
                            ? 'Interface preview'
                            : controller.client?.auth.currentUser?.email ??
                                  'Signed in',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AiraColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const AiraGap(height: 24),
          Text('Comfort & language', style: Theme.of(c).textTheme.titleLarge),
          const AiraGap(height: 14),
          AiraCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Larger text'),
                  subtitle: const Text(
                    'Bigger text and more spacious layout',
                    style: TextStyle(fontSize: 15),
                  ),
                  value: controller.largerText,
                  onChanged: (value) async {
                    try {
                      await controller.setScale(value);
                    } catch (e) {
                      if (c.mounted) {
                        showMessage(c, AiraController.cleanError(e));
                      }
                    }
                  },
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.language_rounded),
                  title: Text('English'),
                  subtitle: Text(
                    'First release language',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.schedule_rounded),
                  title: Text('Singapore time'),
                  subtitle: Text(
                    'Check-ins pause from 9 PM to 9 AM',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const AiraGap(height: 28),
          Text('What AIRA remembers', style: Theme.of(c).textTheme.titleLarge),
          const AiraGap(height: 14),
          AiraCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _toggle(
                  c,
                  'store_conversations',
                  'Save conversations',
                  'Keep your chat for this prototype’s 24-hour lifetime.',
                ),
                _toggle(
                  c,
                  'memory_enabled',
                  'Saved memories',
                  'AIRA asks before saving a personal detail.',
                ),
                _toggle(
                  c,
                  'impact_measurement',
                  'Weekly check-ins',
                  'Optional lonely-days responses and conversation activity.',
                ),
                _toggle(
                  c,
                  'mood_history',
                  'Save my reported mood',
                  'Keep feelings you explicitly choose to record.',
                ),
              ],
            ),
          ),
          const AiraGap(height: 28),
          Text(
            'Invitations & reminders',
            style: Theme.of(c).textTheme.titleLarge,
          ),
          const AiraGap(height: 14),
          AiraCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _toggle(
                  c,
                  'social_reminders',
                  'Invite me to chat',
                  'At most one gentle social invitation per day.',
                ),
                _toggle(
                  c,
                  'medication_reminders',
                  'Medication reminders',
                  'Separate from social invitations. Your confirmed schedule stays in your control.',
                ),
              ],
            ),
          ),
          const AiraGap(height: 28),
          Text('Privacy & sharing', style: Theme.of(c).textTheme.titleLarge),
          const AiraGap(height: 14),
          AiraCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _toggle(
                  c,
                  'monitoring_enabled',
                  'Allow review evidence',
                  'Limited flagged excerpts for authorized reviewers. Test-only in this prototype.',
                ),
                _toggle(
                  c,
                  'admin_insights',
                  'Share insights with assigned staff',
                  'Only specifically assigned, authorized staff can view these categories.',
                ),
                _toggle(
                  c,
                  'urgent_sharing',
                  'Route urgent concerns to my caregiver',
                  'Requires a verified link. Automatic test inbox routing; no real notifications yet.',
                ),
                _toggle(
                  c,
                  'reviewed_sharing',
                  'Share reviewed reports',
                  'Requires a verified link and an authorized reviewer’s approval.',
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.link_outlined),
                  title: Text('Caregiver connection'),
                  subtitle: Text(
                    'Linking is configured by an administrator in this prototype. Sharing requires a verified caregiver and your permission.',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const AiraGap(height: 14),
          const Notice(
            'Camera and facial analysis have separate controls during calls. Face frames stay on your device. OpenAI receives permitted conversation context; ElevenLabs processes voice audio. Provider retention must be checked before a real pilot.',
          ),
          const AiraGap(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCare('caregiver'),
                icon: const Icon(Icons.favorite_border),
                label: Text(
                  controller.preview
                      ? 'Preview caregiver view'
                      : 'Caregiver view',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onCare('admin'),
                icon: const Icon(Icons.dashboard_outlined),
                label: Text(
                  controller.preview
                      ? 'Preview admin dashboard'
                      : 'Admin dashboard',
                ),
              ),
            ],
          ),
          const AiraGap(height: 28),
          Text('Your data & account', style: Theme.of(c).textTheme.titleLarge),
          const AiraGap(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmAction(
                    c,
                    'Delete your AIRA data?',
                    'This removes your conversations, memories, check-ins and reminders, and cancels pending follow-ups. This also disables access to your AIRA profile and signs you out. Your sign-in identity remains; an administrator must remove it separately.',
                    confirm: 'Delete my data',
                  )) {
                    try {
                      await controller.deleteData();
                      if (c.mounted) {
                        showMessage(c, 'Your AIRA data has been cleared.');
                      }
                    } catch (e) {
                      if (c.mounted) {
                        showMessage(c, AiraController.cleanError(e));
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete my data'),
              ),
              OutlinedButton.icon(
                onPressed: controller.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text(controller.preview ? 'Exit preview' : 'Sign out'),
              ),
            ],
          ),
          const AiraGap(height: 30),
          const Text(
            'AIRA · Prototype 0.1\nNot a medical or emergency service.',
            style: TextStyle(
              fontSize: 14,
              color: AiraColors.muted,
              height: 1.6,
            ),
          ),
          const AiraGap(height: 20),
        ],
      ),
    ),
  );
  Widget _toggle(BuildContext c, String key, String title, String sub) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(sub, style: const TextStyle(fontSize: 15, height: 1.4)),
        value: controller.consent(key),
        onChanged: (v) => toggle(c, key, v),
      );
}
