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
  final transcript = TextEditingController();
  final elapsed = Stopwatch();
  Timer? ticker;
  Future<void>? closingSession;
  bool busy = false, review = false, active = false, starting = false;
  bool ended = false, paused = false, savingConsent = false;
  int epoch = 0, consentEpoch = 0;
  String caption = 'A little chat, at your pace.';
  String? correction;
  bool correctionPending = false;
  String get mode => widget.video ? 'video' : 'voice';
  bool current(int value) => mounted && !ended && active && epoch == value;

  @override
  void initState() {
    super.initState();
    media = widget.mediaController ?? AiraMediaController();
    media.addListener(mediaChanged);
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && active) setState(() {});
    });
  }

  @override
  void dispose() {
    ended = true;
    ++epoch;
    ++consentEpoch;
    ticker?.cancel();
    elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    media.removeListener(mediaChanged);
    media.dispose();
    transcript.dispose();
    unawaited(closeSession());
    super.dispose();
  }

  Future<void> closeSession() async {
    if (widget.controller.preview) return;
    try {
      await widget.controller.endCall();
    } catch (_) {
      // Media is already stopped; a failed cleanup must never restart capture.
    }
  }

  void mediaChanged() {
    if (media.state.suspended && (active || starting)) pauseCall();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      pauseCall();
    }
  }

  void pauseCall() {
    if (!mounted || ended || (!active && !starting)) return;
    ++epoch;
    ++consentEpoch;
    widget.controller.cancelSend();
    active = false;
    starting = false;
    media.stopAll();
    elapsed.stop();
    closingSession = closeSession();
    setState(() {
      busy = false;
      paused = true;
      savingConsent = false;
      caption = 'The call is paused. Start again when you are ready.';
    });
  }

  Future<void> start() async {
    if (active || starting || ended) return;
    final request = ++epoch;
    setState(() {
      starting = true;
      caption = 'Getting ready…';
    });
    try {
      await closingSession;
      if (!mounted || ended || epoch != request) return;
      if (!widget.controller.preview) await widget.controller.beginCall(mode);
      if (!mounted || ended || epoch != request) {
        await closeSession();
        return;
      }
      setState(() {
        active = true;
        starting = false;
        paused = false;
        elapsed.reset();
        elapsed.start();
        caption = widget.controller.preview
            ? 'Try your camera and the optional facial expression display.'
            : 'Tap Speak when you are ready. You can check your words before sending.';
      });
    } catch (error) {
      if (!mounted || ended || epoch != request) return;
      setState(() {
        starting = false;
        caption =
            'The call could not start. Please try again or return to chat.';
      });
      showMessage(context, AiraController.cleanError(error));
    }
  }

  Future<void> camera() async {
    if (!active) return;
    final request = epoch;
    try {
      if (media.state.cameraOn || media.state.cameraBusy) {
        ++consentEpoch;
        setState(() => savingConsent = false);
        media.stopCamera();
      } else {
        await media.startCamera();
        if (!current(request)) media.stopCamera();
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
    if (!enabled) media.setDetection(false);
    setState(() => savingConsent = true);
    try {
      if (!widget.controller.preview) {
        await widget.controller.updatePreference('face_cues', enabled);
      }
      if (!mounted || ended || request != consentEpoch) return;
      if (enabled && active && media.state.cameraOn) media.setDetection(true);
    } catch (_) {
      if (mounted && !ended && request == consentEpoch) {
        media.setDetection(false);
        showMessage(
          context,
          enabled
              ? 'Facial detection remains off because your choice could not be saved.'
              : 'Detection is off on this device. Please retry saving your privacy choice in Settings.',
        );
      }
    } finally {
      if (mounted && !ended && request == consentEpoch) {
        setState(() => savingConsent = false);
      }
    }
  }

  Future<void> record() async {
    if (!active || busy) return;
    if (widget.controller.preview) {
      showMessage(
        context,
        'Voice AI needs service setup. Camera and local emotion detection can be tried now.',
      );
      return;
    }
    final request = ++epoch;
    if (!media.state.hasRecording) {
      try {
        await media.startRecording();
        if (!current(request)) media.cancelRecording();
      } catch (_) {
        if (mounted && current(request)) {
          showMessage(
            context,
            'Microphone access was not available. Please use chat.',
          );
        }
      }
      return;
    }
    setState(() {
      busy = true;
      caption = 'Writing down what you said…';
    });
    try {
      final audio = await media.finishRecording();
      if (!current(request)) {
        audio.bytes.fillRange(0, audio.bytes.length, 0);
        return;
      }
      Map<String, dynamic> data;
      try {
        data = await widget.controller.api.transcribe(
          audio.bytes,
          audio.mimeType,
        );
      } finally {
        audio.bytes.fillRange(0, audio.bytes.length, 0);
      }
      if (!current(request)) return;
      setState(() {
        transcript.text = data['text']?.toString() ?? '';
        review = true;
        caption = 'Check the words below, then send.';
      });
    } catch (error) {
      if (mounted && current(request)) {
        showMessage(context, AiraController.cleanError(error));
      }
    } finally {
      if (current(request)) setState(() => busy = false);
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

  Future<void> send() async {
    if (!active || busy || transcript.text.trim().isEmpty) return;
    final request = ++epoch;
    final feeling = correctionPending ? correction : null;
    setState(() {
      busy = true;
      caption = 'AIRA is thinking…';
    });
    try {
      final reply = await widget.controller.send(
        transcript.text,
        mode: mode,
        cueSummary: freshCue(),
        feeling: feeling,
      );
      if (!current(request)) return;
      setState(() {
        caption = reply.text;
        review = false;
        correctionPending = false;
      });
      if (reply.speechToken != null) {
        final bytes = await widget.controller.api.speech(reply.speechToken!);
        if (!current(request)) {
          bytes.fillRange(0, bytes.length, 0);
          return;
        }
        try {
          await media.playAudio(bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
    } catch (error) {
      if (mounted && current(request)) {
        showMessage(context, AiraController.cleanError(error));
      }
    } finally {
      if (current(request)) setState(() => busy = false);
    }
  }

  void stopReply() {
    ++epoch;
    widget.controller.cancelSend();
    media.cancelRecording();
    media.stopPlayback();
    setState(() {
      busy = false;
      caption =
          'Stopped. Your words are kept here if you would like to try again.';
    });
  }

  void end() {
    if (ended) return;
    ended = true;
    active = false;
    ++epoch;
    ++consentEpoch;
    widget.controller.cancelSend();
    media.stopAll();
    elapsed.stop();
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
    if (result != null && mounted && !ended) {
      setState(() {
        correction = result;
        correctionPending = true;
      });
      showMessage(
        context,
        'Your feeling will take priority in your next reply. The facial estimate stays separate.',
      );
    }
  }

  String get duration {
    final seconds = elapsed.elapsed.inSeconds;
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
          elapsed.stop();
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
                                'AI companion · Tap to speak',
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
                            '${widget.controller.preview ? 'Preview · ' : ''}$duration',
                            semanticsLabel:
                                '${widget.controller.preview ? 'Preview' : 'Active call'} elapsed $duration',
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
                                width: 170,
                                height: 124,
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
                            size: MediaQuery.sizeOf(context).width < 500
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
                              media.state.isRecording
                                  ? 'Listening… ${media.state.recordingSeconds} / 45 sec'
                                  : media.state.hasRecording
                                  ? 'Recording ready to review'
                                  : media.state.playing
                                  ? 'AIRA is speaking'
                                  : busy
                                  ? 'AIRA is thinking…'
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
                          const AiraGap(height: 16),
                          if (widget.video) ...[
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
                                          active &&
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
                                    TextButton(
                                      onPressed: busy ? null : correct,
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
                                            'You said: $correction · ${correctionPending ? 'used for your next reply' : 'shared with AIRA'}',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              color: AiraColors.forest,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Clear my stated feeling',
                                          onPressed: busy
                                              ? null
                                              : () => setState(
                                                  () => correction = null,
                                                ),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            const AiraGap(height: 16),
                          ],
                          if (media.state.error != null)
                            Notice(media.state.error!),
                          if (review) ...[
                            TextField(
                              controller: transcript,
                              minLines: 2,
                              maxLines: 5,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: 'What I heard — you can edit this',
                              ),
                            ),
                            const AiraGap(height: 12),
                            FilledButton(
                              onPressed: active && !busy ? send : null,
                              child: const Text('Send to AIRA'),
                            ),
                            const AiraGap(height: 16),
                          ],
                          if (widget.controller.preview)
                            const Notice(
                              'Voice needs OpenAI and ElevenLabs setup. You can try the real camera and on-device facial model in this preview.',
                            ),
                          if (!active)
                            const Notice(
                              'Starting a call does not switch on your camera or microphone. You choose when to use them.',
                            ),
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
                            if (!active)
                              FilledButton.icon(
                                onPressed: starting ? null : start,
                                icon: const Icon(Icons.call_outlined),
                                label: Text(
                                  starting
                                      ? 'Connecting…'
                                      : paused
                                      ? 'Start again'
                                      : widget.video
                                      ? 'Start video call'
                                      : 'Start voice call',
                                ),
                              ),
                            if (active)
                              FilledButton.icon(
                                onPressed: busy || media.state.microphoneBusy
                                    ? null
                                    : record,
                                icon: Icon(
                                  media.state.hasRecording
                                      ? Icons.stop_rounded
                                      : Icons.mic_none_rounded,
                                ),
                                label: Text(
                                  media.state.hasRecording
                                      ? 'Finish speaking'
                                      : 'Speak',
                                ),
                              ),
                            if (active && widget.video)
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
                            if (busy ||
                                media.state.playing ||
                                media.state.hasRecording)
                              OutlinedButton.icon(
                                onPressed: stopReply,
                                icon: const Icon(Icons.stop),
                                label: const Text('Stop reply'),
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
