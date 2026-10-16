import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/companion.dart';
import '../widgets/ui.dart';
import '../media/aira_media.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.controller,
    required this.video,
    this.mediaController,
  });
  final AiraController controller;
  final bool video;

  /// Adapter injection permits browser-free lifecycle tests.
  final AiraMediaController? mediaController;
  @override
  State<CallScreen> createState() => _CallState();
}

class _CallState extends State<CallScreen> with WidgetsBindingObserver {
  late final AiraMediaController media;
  Timer? ticker;
  Future<void>? closingSession;
  bool active = false, starting = false, previewOpen = false;
  bool ended = false, paused = false, savingConsent = false, publishing = false;
  bool captions = true, sessionClosed = true;
  int epoch = 0, consentEpoch = 0;
  DateTime? connectedAt, lastPublishedAt;
  String? lastPublishedLabel, correction, contextError;
  bool correctionShared = false;
  String caption = 'A little chat, at your pace.';
  String get mode => widget.video ? 'video' : 'voice';
  bool get cameraAllowed => active || previewOpen;
  bool current(int value) => mounted && !ended && epoch == value;

  @override
  void initState() {
    super.initState();
    media = widget.mediaController ?? AiraMediaController();
    media.addListener(mediaChanged);
    WidgetsBinding.instance.addObserver(this);
    // Preload local SDK code only. Microphone capture begins after Start.
    unawaited(media.prepareRealtime().catchError((_) {}));
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || ended) return;
      if (active) {
        setState(() {});
        unawaited(publishContext());
      }
    });
  }

  @override
  void dispose() {
    ended = true;
    ++epoch;
    ++consentEpoch;
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    media.removeListener(mediaChanged);
    media.dispose();
    unawaited(closeSession());
    super.dispose();
  }

  Future<void> closeSession() async {
    if (widget.controller.preview || sessionClosed) return;
    sessionClosed = true;
    try {
      await widget.controller.endCall();
    } catch (_) {
      // Local devices stop immediately even if server cleanup cannot finish.
    }
  }

  void mediaChanged() {
    if (!mounted || ended) return;
    final state = media.state;
    if (state.suspended && (active || starting || previewOpen)) {
      pauseCall('The call stopped while AIRA was in the background.');
    } else if ((active || starting) &&
        (state.realtimeStatus == 'failed' ||
            state.realtimeStatus == 'disconnected')) {
      pauseCall(
        state.realtimeError ??
            'The call ended. Start again when you are ready.',
      );
    } else if (active) {
      unawaited(publishContext());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      pauseCall('The call stopped while AIRA was in the background.');
    }
  }

  void pauseCall(String message) {
    if (!mounted || ended || (!active && !starting && !previewOpen)) return;
    ++epoch;
    ++consentEpoch;
    active = false;
    starting = false;
    previewOpen = false;
    connectedAt = null;
    media.stopAll();
    closingSession = closeSession();
    setState(() {
      paused = true;
      savingConsent = false;
      caption = message;
    });
  }

  Future<void> start() async {
    if (active || starting || ended) return;
    if (widget.controller.preview) {
      setState(() {
        previewOpen = true;
        caption = 'Camera preview only. Live calls need a connected account.';
      });
      return;
    }
    final request = ++epoch;
    setState(() {
      starting = true;
      caption = 'Connecting your live call…';
      contextError = null;
    });
    try {
      await closingSession;
      if (!current(request)) return;
      sessionClosed = false;
      final config = await widget.controller.beginRealtimeCall(mode);
      // Controller and browser adapter each cancel their own obsolete startup.
      // Do not let an old continuation close a newer call on this controller.
      if (!current(request)) return;
      await media.startRealtime(config);
      if (!current(request)) return;
      if (!media.state.connected) {
        throw StateError('The live connection was not established.');
      }
      setState(() {
        active = true;
        starting = false;
        paused = false;
        connectedAt = media.state.realtimeConnectedAt ?? DateTime.now();
        lastPublishedAt = null;
        lastPublishedLabel = null;
        correctionShared = false;
        caption = 'Talk naturally. You can interrupt AIRA by speaking.';
      });
      unawaited(publishContext(force: true));
    } catch (error) {
      if (!current(request)) return;
      starting = false;
      active = false;
      media.stopAll();
      closingSession = closeSession();
      setState(() {
        caption =
            'The call could not start. Please try again or return to chat.';
      });
      if (mounted) showMessage(context, AiraController.cleanError(error));
    }
  }

  Future<void> camera() async {
    if (!cameraAllowed) return;
    final request = epoch;
    try {
      if (media.state.cameraOn || media.state.cameraBusy) {
        ++consentEpoch;
        setState(() => savingConsent = false);
        media.stopCamera();
        unawaited(publishContext(force: true));
      } else {
        await media.startCamera();
        // The browser camera epoch disposes permission results after End.
      }
    } catch (_) {
      if (mounted && current(request)) {
        showMessage(
          context,
          'Camera access was not available. You can keep using voice or text.',
        );
      }
    }
  }

  Future<void> detection(bool enabled) async {
    final request = ++consentEpoch;
    if (!enabled) {
      media.setDetection(false);
      unawaited(publishContext(force: true));
    }
    setState(() => savingConsent = true);
    try {
      if (!widget.controller.preview) {
        await widget.controller.updatePreference('face_cues', enabled);
      }
      if (!mounted || ended || request != consentEpoch) return;
      if (enabled && cameraAllowed && media.state.cameraOn) {
        media.setDetection(true);
      }
    } catch (_) {
      if (mounted && !ended && request == consentEpoch) {
        media.setDetection(false);
        showMessage(
          context,
          enabled
              ? 'Facial detection remains off because your choice could not be saved.'
              : 'Detection is off here. Please retry saving your privacy choice in Settings.',
        );
      }
    } finally {
      if (mounted && !ended && request == consentEpoch) {
        setState(() => savingConsent = false);
      }
    }
  }

  Map<String, dynamic>? freshCue() {
    final state = media.state;
    if (!widget.controller.consent('face_cues') ||
        !state.detectionEnabled ||
        state.detection != 'ready' ||
        state.faceCount != 1 ||
        state.emotion == null ||
        state.observedAt == null ||
        DateTime.now().difference(state.observedAt!).abs() >
            const Duration(seconds: 5)) {
      return null;
    }
    return {
      'label': state.emotion,
      'observedAt': state.observedAt!.toUtc().toIso8601String(),
    };
  }

  Future<void> publishContext({bool force = false}) async {
    if (!active || ended || publishing || widget.controller.preview) return;
    final cue = freshCue();
    final now = DateTime.now();
    final cleared = cue == null && lastPublishedLabel != null;
    if (!force &&
        !cleared &&
        lastPublishedAt != null &&
        now.difference(lastPublishedAt!) < const Duration(seconds: 3)) {
      return;
    }
    if (!force &&
        cue == null &&
        lastPublishedLabel == null &&
        correctionShared) {
      return;
    }
    final request = epoch;
    final feeling = correction;
    publishing = true;
    try {
      await widget.controller.publishCallContext(
        cueSummary: cue,
        selfReportedFeeling: feeling,
      );
      if (!current(request) || !active) return;
      lastPublishedAt = now;
      lastPublishedLabel = cue?['label'] as String?;
      setState(() {
        correctionShared = feeling == correction;
        contextError = null;
      });
    } catch (_) {
      if (current(request) && active) {
        lastPublishedAt = now;
        setState(
          () => contextError = 'Your feeling or facial estimate could not reach AIRA yet. You can also say how you feel.',
        );
      }
    } finally {
      publishing = false;
    }
  }

  void end() {
    if (ended) return;
    ended = true;
    active = false;
    starting = false;
    previewOpen = false;
    ++epoch;
    ++consentEpoch;
    media.stopAll();
    closingSession = closeSession();
    Navigator.pop(context);
  }

  Future<void> correct() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('How do you feel?'),
        children: [
          for (final feeling in ['Happy', 'Sad', 'Worried', 'Calm', 'Mixed'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, feeling),
              child: AiraPadding(
                padding: const EdgeInsets.all(10),
                child: Text(feeling),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (result == null || !mounted || ended) return;
    setState(() {
      correction = result;
      correctionShared = false;
    });
    unawaited(publishContext(force: true));
  }

  String get duration {
    final seconds = connectedAt == null
        ? 0
        : DateTime.now().difference(connectedAt!).inSeconds.clamp(0, 86400);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: media,
    builder: (context, _) => PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ended = true;
          ++epoch;
          media.stopAll();
          unawaited(closeSession());
        }
      },
      child: Scaffold(
        backgroundColor: AiraColors.lavender,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  AiraPadding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'End and return to chat',
                          onPressed: end,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const AiraGap(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AIRA',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'AI companion · Live conversation',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AiraColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (active)
                          Text(
                            duration,
                            semanticsLabel: 'Active call elapsed $duration',
                            style: const TextStyle(fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: AiraLayout.of(context)
                          .insets(const EdgeInsets.symmetric(horizontal: 24)),
                      child: Column(
                        children: [
                          if (widget.video)
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: 300,
                                height: 225,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      const ColoredBox(
                                        color: Color(0xFF4F4C60),
                                      ),
                                      AiraCameraPreview(controller: media),
                                      if (!media.state.cameraOn)
                                        const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.videocam_off_outlined,
                                                color: Colors.white,
                                                size: 32,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'Camera off',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
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
                          Companion(
                            size: widget.video
                                ? 175
                                : MediaQuery.sizeOf(context).width < 500
                                ? 235
                                : 290,
                            speaking: media.state.playing,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .75),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              starting
                                  ? 'Connecting…'
                                  : active
                                  ? media.state.micMuted
                                        ? 'Microphone muted'
                                        : media.state.callMode == 'speaking'
                                        ? 'AIRA is speaking · you can interrupt'
                                        : 'Listening — speak naturally'
                                  : 'Ready when you are',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const AiraGap(height: 16),
                          AiraCard(
                            child: Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(height: 1.4),
                            ),
                          ),
                          if (active) ...[
                            SwitchListTile(
                              title: const Text('Show captions'),
                              value: captions,
                              onChanged: (value) =>
                                  setState(() => captions = value),
                            ),
                            if (captions && media.state.userCaption != null)
                              AiraCard(
                                child: Text('You: ${media.state.userCaption}'),
                              ),
                            if (captions && media.state.agentCaption != null)
                              AiraCard(
                                child: Text(
                                  'AIRA: ${media.state.agentCaption}',
                                ),
                              ),
                            const AiraGap(height: 12),
                          ],
                          if (widget.video) ...[
                            const AiraGap(height: 16),
                            AiraCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Column(
                                children: [
                                  Material(
                                    type: MaterialType.transparency,
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Show facial emotion',
                                        style: TextStyle(fontSize: 18),
                                      ),
                                      subtitle: Text(
                                        savingConsent
                                            ? 'Saving your choice…'
                                            : widget.controller.preview
                                            ? 'Optional · processed on this device'
                                            : 'Optional · frames stay here; a fresh estimate can help AIRA reply',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      value: media.state.detectionEnabled,
                                      onChanged:
                                          cameraAllowed &&
                                              media.state.cameraOn &&
                                              !savingConsent
                                          ? detection
                                          : null,
                                    ),
                                  ),
                                  if (media.state.detectionEnabled) ...[
                                    const Divider(),
                                    Text(
                                      media.state.emotionText,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Text(
                                      'A facial expression is an uncertain estimate, not how you necessarily feel.',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    TextButton(
                                      onPressed: correct,
                                      child: const Text(
                                        'That’s not how I feel',
                                      ),
                                    ),
                                  ],
                                  if (correction != null)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'You said: $correction · ${widget.controller.preview
                                                ? 'local preview'
                                                : correctionShared
                                                ? 'shared with AIRA'
                                                : 'sharing…'}',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              color: AiraColors.forest,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Clear my stated feeling',
                                          onPressed: () {
                                            setState(() {
                                              correction = null;
                                              correctionShared = false;
                                            });
                                            unawaited(
                                              publishContext(force: true),
                                            );
                                          },
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                          const AiraGap(height: 16),
                          if (media.state.error != null)
                            Notice(media.state.error!),
                          if (media.state.realtimeError != null)
                            Notice(media.state.realtimeError!),
                          if (contextError != null) Notice(contextError!),
                          if (widget.controller.preview)
                            const Notice(
                              'Preview mode: camera and facial detection work locally. Sign in to a connected account for live voice calls.',
                            ),
                          if (!active && !widget.controller.preview)
                            const Notice(
                              'Start opens your microphone. ElevenLabs processes voice; OpenAI creates replies. ElevenLabs recordings are off, and its call history is scheduled for deletion after the call. Camera images stay on your device; camera starts only when you choose.',
                            ),
                          if (active)
                            const Text(
                              'AIRA may take a moment to check a reply before speaking.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AiraColors.muted,
                              ),
                            ),
                          const AiraGap(height: 16),
                        ],
                      ),
                    ),
                  ),
                  AiraPadding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            if (!active && !previewOpen)
                              FilledButton.icon(
                                onPressed:
                                    starting ||
                                        (widget.controller.preview &&
                                            !widget.video)
                                    ? null
                                    : start,
                                icon: const Icon(Icons.call_outlined),
                                label: Text(
                                  starting
                                      ? 'Connecting…'
                                      : widget.controller.preview
                                      ? widget.video
                                            ? 'Open camera preview'
                                            : 'Sign in for live calls'
                                      : paused
                                      ? 'Start again'
                                      : widget.video
                                      ? 'Start video call'
                                      : 'Start voice call',
                                ),
                              ),
                            if (active)
                              FilledButton.icon(
                                onPressed: () =>
                                    media.setMicMuted(!media.state.micMuted),
                                icon: Icon(
                                  media.state.micMuted
                                      ? Icons.mic_off_outlined
                                      : Icons.mic_none_rounded,
                                ),
                                label: Text(
                                  media.state.micMuted ? 'Unmute' : 'Mute',
                                ),
                              ),
                            if (cameraAllowed && widget.video)
                              OutlinedButton.icon(
                                onPressed: camera,
                                icon: Icon(
                                  media.state.cameraOn
                                      ? Icons.videocam_off_outlined
                                      : Icons.videocam_outlined,
                                ),
                                label: Text(
                                  media.state.cameraOn || media.state.cameraBusy
                                      ? 'Camera off'
                                      : 'Camera on',
                                ),
                              ),
                          ],
                        ),
                        const AiraGap(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB94952),
                            ),
                            onPressed: end,
                            icon: const Icon(Icons.call_end_rounded),
                            label: const Text('End call'),
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
