import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/companion.dart';
import 'chat.dart';
import 'personal.dart';
import 'settings.dart';
import 'dashboard.dart';

class AiraShell extends StatefulWidget {
  final AiraController controller;
  final String? initialRoute;
  const AiraShell({super.key, required this.controller, this.initialRoute});
  @override
  State<AiraShell> createState() => _ShellState();
}

class _ShellState extends State<AiraShell> with WidgetsBindingObserver {
  Timer? _timer;
  bool _polling = false, _active = true, _responding = false;
  Future<void> _poll() async {
    if (!_active || _polling || !mounted || widget.controller.preview) return;
    _polling = true;
    try {
      await widget.controller.pollEvents();
    } catch (_) {
      /* Retry only while visible. No delivery claim on network failure. */
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _respond(Map<String, dynamic> event, String action) async {
    setState(() => _responding = true);
    try {
      await widget.controller.respondEvent(event, action);
      if (mounted && action == 'taken') {
        showMessage(context, 'Recorded as taken, based on your report.');
      }
    } catch (e) {
      if (mounted) showMessage(context, AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  Widget _event(Map<String, dynamic> event) {
    final med = event['kind'] == 'medication';
    return AiraPadding(
      padding: const EdgeInsets.all(12),
      child: AiraCard(
        color: med ? AiraColors.peach : AiraColors.lavender,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              med ? 'Medicine reminder' : 'AIRA would like to check in',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            Text(
              event['label']?.toString() ?? '',
              style: const TextStyle(fontSize: 17),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final action
                    in med
                        ? [
                            ('taken', 'Taken'),
                            ('snooze', 'In 10 minutes'),
                            ('skip', 'Skip'),
                          ]
                        : [('accept', 'Let’s chat'), ('decline', 'Not now')])
                  TextButton(
                    onPressed: _responding
                        ? null
                        : () => _respond(event, action.$1),
                    child: Text(action.$2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? care;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    if (widget.initialRoute?.startsWith('/admin') == true) care = 'admin';
    if (widget.initialRoute?.startsWith('/caregiver') == true) {
      care = 'caregiver';
    }
  }

  @override
  Widget build(BuildContext c) {
    final ctl = widget.controller;
    final wide = MediaQuery.sizeOf(c).width >= 1000;
    Widget content = care != null
        ? DashboardScreen(controller: ctl, admin: care == 'admin')
        : switch (ctl.tab) {
            0 => ChatScreen(controller: ctl),
            1 => PersonalScreen(controller: ctl),
            _ => SettingsScreen(
              controller: ctl,
              onCare: (v) => setState(() => care = v),
            ),
          };
    final destinations = [
      (Icons.chat_bubble_outline_rounded, 'Chat'),
      (Icons.person_outline_rounded, 'About me'),
      (Icons.tune_rounded, 'Settings'),
    ];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: ctl.largerText ? 224 : 208,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F3EB),
                  border: Border(right: BorderSide(color: AiraColors.line)),
                ),
                child: AiraPadding(
                  padding: const EdgeInsets.fromLTRB(22, 32, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AiraPadding(
                        padding: EdgeInsets.only(left: 14),
                        child: Text(
                          'AIRA',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: AiraColors.forest,
                          ),
                        ),
                      ),
                      const AiraPadding(
                        padding: EdgeInsets.only(left: 14, top: 6),
                        child: Text(
                          'A little company, every day.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AiraColors.muted,
                          ),
                        ),
                      ),
                      const AiraGap(height: 46),
                      for (int i = 0; i < 3; i++)
                        AiraPadding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _nav(
                            destinations[i].$1,
                            destinations[i].$2,
                            care == null && ctl.tab == i,
                            () => setState(() {
                              care = null;
                              ctl.setTab(i);
                            }),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        padding: AiraLayout.of(c)
                            .insets(const EdgeInsets.all(18)),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Companion(size: 76, animated: false),
                            Text(
                              'Here for the little things.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            AiraGap(height: 8),
                            Text(
                              'A story, a memory, or just a moment together.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AiraColors.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const AiraGap(height: 20),
                      TextButton.icon(
                        onPressed: () => setState(() => care = 'caregiver'),
                        icon: const Icon(Icons.favorite_border, size: 18),
                        label: const Text(
                          'Caregiver view',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => care = 'admin'),
                        icon: const Icon(Icons.dashboard_outlined, size: 18),
                        label: const Text(
                          'Admin dashboard',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (ctl.preview)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFFFFF3D9),
                      padding: AiraLayout.of(c).insets(
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.science_outlined, size: 18),
                          const AiraGap(width: 8),
                          Expanded(
                            child: Text(
                              wide
                                  ? 'Interface preview · session-only data · live AI not connected'
                                  : 'Preview · AI not connected',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AiraColors.ink,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: ctl.signOut,
                            child: const Text(
                              'Exit',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (care != null)
                    AiraPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => care = null),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Back to AIRA'),
                        ),
                      ),
                    ),
                  if (ctl.pendingEvents.isNotEmpty && care == null)
                    _event(ctl.pendingEvents.first),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              backgroundColor: Colors.white,
              selectedIndex: ctl.tab,
              onDestinationSelected: (v) => setState(() {
                care = null;
                ctl.setTab(v);
              }),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.$1), label: d.$2),
              ],
            ),
    );
  }

  Widget _nav(
    IconData icon,
    String label,
    bool selected,
    VoidCallback action,
  ) => Material(
    color: selected ? AiraColors.forest : Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(18),
      child: AiraPadding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : AiraColors.muted),
            const AiraGap(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : AiraColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
