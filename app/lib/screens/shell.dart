import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../media/aira_media.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/companion.dart';
import 'chat.dart';
import 'personal.dart';
import 'settings.dart';
import 'dashboard.dart';
import 'dashboard/sample_data.dart';
import 'call.dart';

class AiraShell extends StatefulWidget {
  final AiraController controller;
  final String? initialRoute;
  const AiraShell({super.key, required this.controller, this.initialRoute});
  @override
  State<AiraShell> createState() => _ShellState();
}

class _ShellState extends State<AiraShell> with WidgetsBindingObserver {
  final DashboardSampleStore _dashboardSamples = DashboardSampleStore();
  Timer? _timer;
  bool _polling = false, _active = true, _responding = false;
  bool _showingIncoming = false;
  String? _shownInvitation;
  Future<void> _poll() async {
    if (!_active || _polling || !mounted || widget.controller.preview) return;
    _polling = true;
    try {
      await Future.wait([
        widget.controller.pollEvents(),
        widget.controller.refreshCallSchedule(),
      ]);
    } catch (_) {
      /* Retry only while visible. No delivery claim on network failure. */
    } finally {
      _polling = false;
      if (mounted && _active) unawaited(_showIncomingCall());
    }
  }

  Future<void> _showIncomingCall() async {
    final ctl = widget.controller;
    final invitation = ctl.incomingCall;
    if (_showingIncoming ||
        invitation == null ||
        ctl.callBusy ||
        invitation['id'] == _shownInvitation ||
        !mounted) {
      return;
    }
    final expires = DateTime.tryParse(
      invitation['expiresAt']?.toString() ?? '',
    );
    if (expires == null || !expires.isAfter(DateTime.now())) return;
    _shownInvitation = invitation['id']?.toString();
    _showingIncoming = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _IncomingCallDialog(controller: ctl, invitation: invitation),
    );
    _showingIncoming = false;
    if (!mounted || accepted != true || !ctl.signedIn) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(controller: ctl, video: false),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dashboardSamples.dispose();
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
        ? DashboardScreen(
            controller: ctl,
            admin: care == 'admin',
            sampleStore: _dashboardSamples,
          )
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

class _IncomingCallDialog extends StatefulWidget {
  const _IncomingCallDialog({
    required this.controller,
    required this.invitation,
  });
  final AiraController controller;
  final Map<String, dynamic> invitation;
  @override
  State<_IncomingCallDialog> createState() => _IncomingCallState();
}

class _IncomingCallState extends State<_IncomingCallDialog>
    with WidgetsBindingObserver {
  Timer? timer;
  bool busy = false, ringEnabled = true, active = true, closing = false;
  String? error;
  late final int session;
  @override
  void initState() {
    super.initState();
    session = widget.controller.sessionEpoch;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_accountOrInvitationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ring());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || closing) return;
      final expiration = DateTime.tryParse(
        widget.invitation['expiresAt']?.toString() ?? '',
      );
      if (expiration == null || !expiration.isAfter(DateTime.now())) {
        stopIncomingRingtone();
        if (!busy) _close(false);
      }
    });
  }

  Future<void> _ring() async {
    if (!mounted || closing || !active || !ringEnabled || busy) return;
    final expiration = DateTime.tryParse(
      widget.invitation['expiresAt']?.toString() ?? '',
    );
    if (expiration == null || !expiration.isAfter(DateTime.now())) {
      _close(false);
      return;
    }
    try {
      // Autoplay restrictions can keep an incoming call silent. The visible
      // invitation is always available, and this never opens a microphone.
      await startIncomingRingtone();
    } catch (_) {
      // A silent ring does not stop the user accepting or declining the call.
    }
    if (!mounted || closing || !active || !ringEnabled || busy) {
      stopIncomingRingtone();
    }
  }

  void _accountOrInvitationChanged() {
    if (!mounted || closing) return;
    final changed = widget.controller.sessionEpoch != session;
    final stillIncoming =
        widget.controller.incomingCall?['id'] == widget.invitation['id'];
    if (changed || !stillIncoming) {
      stopIncomingRingtone();
      if (changed || !busy) _close(false);
    }
  }

  void _close(bool accepted) {
    if (!mounted || closing) return;
    closing = true;
    stopIncomingRingtone();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(accepted);
    });
    // A polling callback can arrive outside a frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      unawaited(_ring());
    } else {
      stopIncomingRingtone();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    stopIncomingRingtone();
    widget.controller.removeListener(_accountOrInvitationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> respond(String action) async {
    stopIncomingRingtone();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final accepted = await widget.controller.respondScheduledCall(
        widget.invitation,
        action,
      );
      if (mounted) _close(accepted);
    } catch (e) {
      if (mounted) setState(() => error = AiraController.cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: const Color(0xFF173B31),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Incoming voice call',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const AiraGap(height: 16),
              const Text(
                'AIRA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const AiraGap(height: 12),
              const Companion(size: 160, activity: CompanionActivity.greeting),
              const AiraGap(height: 12),
              const Text(
                'A little time together?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const AiraGap(height: 8),
              const Text(
                'Your microphone starts only after you accept.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: busy
                    ? null
                    : () {
                        setState(() => ringEnabled = !ringEnabled);
                        if (ringEnabled) {
                          unawaited(_ring());
                        } else {
                          stopIncomingRingtone();
                        }
                      },
                icon: Icon(
                  ringEnabled
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
                label: Text(ringEnabled ? 'Silence ring' : 'Enable ring'),
              ),
              if (error != null) ...[
                const AiraGap(height: 12),
                Text(error!, style: const TextStyle(color: Color(0xFFFFD4A4))),
              ],
              const AiraGap(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD7535F),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: busy ? null : () => respond('decline'),
                    icon: const Icon(Icons.call_end_rounded),
                    label: const Text('Decline'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC9E9CD),
                      foregroundColor: const Color(0xFF153A2D),
                    ),
                    onPressed: busy ? null : () => respond('accept'),
                    icon: const Icon(Icons.call_rounded),
                    label: Text(busy ? 'Connecting…' : 'Accept'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
