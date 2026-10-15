import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'media_types.dart';

/// Native audio/camera adapters remain a separate, explicitly unimplemented milestone.
class AiraMediaController extends ChangeNotifier {
  AiraMediaState state = const AiraMediaState(
    detection: 'unavailable',
    reason: 'Model unavailable on this platform',
    error: 'Voice and camera are currently available in the browser version.',
  );
  Future<void> startCamera() async => notifyListeners();
  void stopCamera() {}
  void setDetection(bool enabled) => notifyListeners();
  Future<void> startRecording() async => notifyListeners();
  Future<RecordedAudio> finishRecording() =>
      Future.error(UnsupportedError('Use the browser version for voice.'));
  void cancelRecording() {}
  Future<void> playAudio(Uint8List bytes,
          [String mimeType = 'audio/mpeg']) async =>
      notifyListeners();
  void stopPlayback() {}
  void stopAll() {}
}

class AiraCameraPreview extends StatelessWidget {
  const AiraCameraPreview({super.key, required this.controller});
  final AiraMediaController controller;
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('Camera preview is available in the browser version.'));
}
