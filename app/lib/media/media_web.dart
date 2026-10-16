import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'media_types.dart';

@JS('airaMedia.prepareRealtime')
external JSPromise<JSAny?> _prepareRealtime();
@JS('airaMedia.startRealtime')
external JSPromise<JSString> _startRealtime(JSString config);
@JS('airaMedia.setMicMuted')
external void _setMicMuted(JSBoolean muted);
@JS('airaMedia.setSpeakerMuted')
external void _setSpeakerMuted(JSBoolean muted);
@JS('airaMedia.refreshMicrophones')
external JSPromise<JSAny?> _refreshMicrophones();
@JS('airaMedia.changeMicrophone')
external JSPromise<JSAny?> _changeMicrophone(JSString id);
@JS('airaMedia.snapshot')
external JSString _snapshot();
@JS('airaMedia.attachPreview')
external void _attachPreview(JSObject element);
@JS('airaMedia.startCamera')
external JSPromise<JSAny?> _startCamera();
@JS('airaMedia.stopCamera')
external void _stopCamera();
@JS('airaMedia.setDetection')
external void _setDetection(JSBoolean enabled);
@JS('airaMedia.startRecording')
external JSPromise<JSAny?> _startRecording();
@JS('airaMedia.finishRecording')
external JSPromise<JSString> _finishRecording();
@JS('airaMedia.cancelRecording')
external void _cancelRecording();
@JS('airaMedia.playAudio')
external JSPromise<JSAny?> _playAudio(JSString base64, JSString mimeType);
@JS('airaMedia.stopPlayback')
external void _stopPlayback();
@JS('airaMedia.stopAll')
external void _stopAll();

class AiraMediaController extends ChangeNotifier {
  AiraMediaController() {
    _refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }
  AiraMediaState state = const AiraMediaState();
  Timer? _timer;
  bool _disposed = false;
  String? _previous;

  void _refresh() {
    if (_disposed) return;
    try {
      final encoded = _snapshot().toDart;
      if (_previous == encoded) return;
      _previous = encoded;
      state = AiraMediaState.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      notifyListeners();
    } catch (_) {
      state = const AiraMediaState(
        error: 'Browser media could not load. Please refresh or use text.',
        detection: 'unavailable',
      );
    }
  }

  Future<void> prepareRealtime() async {
    if (_disposed) return;
    await _prepareRealtime().toDart;
  }

  Future<void> startRealtime(Map<String, dynamic> config) async {
    if (_disposed) return;
    final result = jsonDecode(
      (await _startRealtime(jsonEncode(config).toJS).toDart).toDart,
    ) as Map<String, dynamic>;
    _refresh();
    if (result['error'] != null) throw StateError(result['error'] as String);
  }

  void setMicMuted(bool muted) {
    if (_disposed) return;
    _setMicMuted(muted.toJS);
    _refresh();
  }

  void setSpeakerMuted(bool muted) {
    if (_disposed) return;
    _setSpeakerMuted(muted.toJS);
    _refresh();
  }

  Future<void> refreshMicrophones() async {
    if (_disposed) return;
    await _refreshMicrophones().toDart;
    _refresh();
  }

  Future<void> changeMicrophone(String deviceId) async {
    if (_disposed) return;
    await _changeMicrophone(deviceId.toJS).toDart;
    _refresh();
  }

  Future<void> startCamera() async {
    if (_disposed) return;
    await _startCamera().toDart;
    _refresh();
  }

  void stopCamera() {
    _stopCamera();
    _refresh();
  }

  void setDetection(bool enabled) {
    _setDetection(enabled.toJS);
    _refresh();
  }

  Future<void> startRecording() async {
    if (_disposed) return;
    await _startRecording().toDart;
    _refresh();
  }

  Future<RecordedAudio> finishRecording() async {
    if (_disposed) throw StateError('The call has ended.');
    final result = jsonDecode(
      (await _finishRecording().toDart).toDart,
    ) as Map<String, dynamic>;
    _refresh();
    if (result['error'] != null) throw StateError(result['error'] as String);
    return RecordedAudio(
      bytes: base64Decode(result['base64'] as String),
      mimeType: result['mimeType'] as String,
    );
  }

  void cancelRecording() {
    _cancelRecording();
    _refresh();
  }

  Future<void> playAudio(
    Uint8List bytes, [
    String mimeType = 'audio/mpeg',
  ]) async {
    if (_disposed) return;
    final playback = _playAudio(base64Encode(bytes).toJS, mimeType.toJS).toDart;
    _refresh();
    await playback;
    _refresh();
  }

  void stopPlayback() {
    _stopPlayback();
    _refresh();
  }

  void stopAll() {
    _stopAll();
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _stopAll();
    super.dispose();
  }
}

/// Camera access must be enabled with an explicit UI action on [controller].
/// Creating this widget never requests device permission or begins recording.
class AiraCameraPreview extends StatelessWidget {
  const AiraCameraPreview({super.key, required this.controller});
  final AiraMediaController controller;

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) =>
        _attachPreview(element as web.HTMLDivElement),
  );
}
