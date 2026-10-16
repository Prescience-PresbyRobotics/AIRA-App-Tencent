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
      constraints: const BoxConstraints(maxWidth: 960),
      child: ListView(
        padding: AiraLayout.of(c).insets(const EdgeInsets.all(28)),
        children: [
          const SectionHeading(
            'Make yourself comfortable',
            subtitle: 'A few simple choices. All in your control.',
          ),
          _profile(c),
          const AiraGap(height: 20),
          AiraCardGrid(
            children: [
              AiraSummaryCard(
                title: 'Appearance',
                subtitle: controller.largerText
                    ? 'Larger text · Roomier layout'
                    : 'Standard text · Compact layout',
                icon: Icons.text_fields_rounded,
                color: AiraColors.sage,
                onTap: () => _open(c, 'Appearance'),
              ),
              AiraSummaryCard(
                title: 'Privacy & memory',
                subtitle: 'Choose what AIRA remembers',
                icon: Icons.shield_outlined,
                color: AiraColors.lavender,
                onTap: () => _open(c, 'Privacy & memory'),
              ),
              AiraSummaryCard(
                title: 'Reminders',
                subtitle: 'Invitations and medicine schedules',
                icon: Icons.notifications_none_rounded,
                color: AiraColors.peach,
                onTap: () => _open(c, 'Reminders'),
              ),
              AiraSummaryCard(
                title: 'Care connections',
                subtitle: 'Your sharing choices and care views',
                icon: Icons.favorite_border_rounded,
                color: AiraColors.sage,
                onTap: () => _open(c, 'Care connections'),
              ),
              AiraSummaryCard(
                title: 'Account & data',
                subtitle: 'Manage your data or sign out',
                icon: Icons.manage_accounts_outlined,
                color: AiraColors.lavender,
                onTap: () => _open(c, 'Account & data'),
              ),
            ],
          ),
          const AiraGap(height: 22),
          Text('AIRA · Prototype 0.1', style: Theme.of(c).textTheme.bodySmall),
          const AiraGap(height: 16),
        ],
      ),
    ),
  );

  Widget _profile(BuildContext c) => AiraCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _open(c, 'Profile'),
      child: AiraPadding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AiraColors.sage,
              radius: 26,
              child: Text(
                controller.displayName[0].toUpperCase(),
                style: const TextStyle(color: AiraColors.forest, fontSize: 24),
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
                    'Profile · English',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
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

  List<Widget> _details(BuildContext c, String section) => switch (section) {
    'Profile' => [
      AiraCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.name.isEmpty ? 'Your AIRA space' : controller.name,
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const AiraGap(height: 8),
            Text(
              controller.preview
                  ? 'Interface preview'
                  : controller.client?.auth.currentUser?.email ?? 'Signed in',
            ),
            const AiraGap(height: 16),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.language_rounded),
              title: Text('English'),
              subtitle: Text('First release language'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule_rounded),
              title: Text('Singapore time'),
              subtitle: Text('Chat invitations pause from 9 PM to 9 AM'),
            ),
          ],
        ),
      ),
    ],
    'Appearance' => [
      AiraCard(
        padding: const EdgeInsets.all(8),
        child: SwitchListTile(
          title: const Text('Larger text'),
          subtitle: const Text('Bigger text and more spacious layout'),
          value: controller.largerText,
          onChanged: (value) async {
            try {
              await controller.setScale(value);
            } catch (e) {
              if (c.mounted) showMessage(c, AiraController.cleanError(e));
            }
          },
        ),
      ),
      const AiraGap(height: 20),
      AiraCard(
        color: AiraColors.sage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              color: AiraColors.forest,
              size: 28,
            ),
            const AiraGap(height: 14),
            Text(
              'A little company, every day.',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const AiraGap(height: 8),
            Text(
              'This is how your text will look.',
              style: Theme.of(c).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
      const AiraGap(height: 16),
      const Notice(
        'AIRA also follows your device’s larger-text and reduced-motion settings.',
      ),
    ],
    'Privacy & memory' => [
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
      const AiraGap(height: 20),
      const Notice(
        'Camera and facial analysis have separate controls during calls. Face frames stay on your device.',
        icon: Icons.videocam_outlined,
      ),
      const AiraGap(height: 12),
      const Notice(
        'OpenAI receives permitted conversation context. ElevenLabs processes voice audio. Provider retention must be checked before a real pilot.',
        icon: Icons.cloud_outlined,
      ),
    ],
    'Reminders' => [
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
              'Your confirmed schedule stays in your control. Separate from social invitations.',
            ),
          ],
        ),
      ),
      const AiraGap(height: 20),
      const Notice(
        'Keep AIRA open for reminders. Background delivery is not active.',
        icon: Icons.notifications_none_rounded,
      ),
    ],
    'Care connections' => [
      const Notice(
        'Caregiver linking is configured by an administrator. Sharing requires a verified link and your permission.',
        icon: Icons.link_rounded,
      ),
      const AiraGap(height: 16),
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
              'Only assigned, authorized staff can view these categories.',
            ),
            _toggle(
              c,
              'urgent_sharing',
              'Route urgent concerns to my caregiver',
              'Automatic test inbox routing with a verified link. No real notifications yet.',
            ),
            _toggle(
              c,
              'reviewed_sharing',
              'Share reviewed reports',
              'Requires a verified link and an authorized reviewer’s approval.',
            ),
          ],
        ),
      ),
      const AiraGap(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(c);
              onCare('caregiver');
            },
            icon: const Icon(Icons.favorite_border),
            label: Text(
              controller.preview ? 'Preview caregiver view' : 'Caregiver view',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(c);
              onCare('admin');
            },
            icon: const Icon(Icons.dashboard_outlined),
            label: Text(
              controller.preview
                  ? 'Preview admin dashboard'
                  : 'Admin dashboard',
            ),
          ),
        ],
      ),
    ],
    _ => [
      AiraCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.manage_accounts_outlined,
              size: 32,
              color: AiraColors.forest,
            ),
            const AiraGap(height: 16),
            Text(
              'Your data stays in your control',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const AiraGap(height: 12),
            const Text(
              'Deleting AIRA data clears your profile content and signs you out. Your sign-in identity remains until an administrator removes it.',
            ),
            const AiraGap(height: 20),
            OutlinedButton.icon(
              onPressed: () => _deleteData(c),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete my data'),
            ),
            const AiraGap(height: 12),
            OutlinedButton.icon(
              onPressed: controller.signOut,
              icon: const Icon(Icons.logout_rounded),
              label: Text(controller.preview ? 'Exit preview' : 'Sign out'),
            ),
          ],
        ),
      ),
      const AiraGap(height: 20),
      const Notice('AIRA is not a medical or emergency service.'),
    ],
  };

  Future<void> _deleteData(BuildContext c) async {
    if (await confirmAction(
      c,
      'Delete your AIRA data?',
      'This removes your conversations, memories, check-ins and reminders, cancels pending follow-ups, disables your AIRA profile and signs you out. Your sign-in identity remains; an administrator must remove it separately.',
      confirm: 'Delete my data',
    )) {
      try {
        await controller.deleteData();
        if (c.mounted) showMessage(c, 'Your AIRA data has been cleared.');
      } catch (e) {
        if (c.mounted) showMessage(c, AiraController.cleanError(e));
      }
    }
  }

  Widget _toggle(BuildContext c, String key, String title, String sub) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(sub, style: Theme.of(c).textTheme.bodySmall),
        value: controller.consent(key),
        onChanged: (v) => toggle(c, key, v),
      );
}
