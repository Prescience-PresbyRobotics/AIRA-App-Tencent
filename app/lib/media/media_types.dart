import 'dart:typed_data';

class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

/// Facial estimates and user-reported feelings deliberately have separate data.
/// This state contains only local model output, never a self-reported correction.
class AiraMediaState {
  const AiraMediaState({
    this.camera = 'off',
    this.microphone = 'off',
    this.detection = 'off',
    this.detectionEnabled = false,
    this.emotion,
    this.reason = 'Detection off',
    this.faceCount = 0,
    this.observedAt,
    this.inferenceMs,
    this.playing = false,
    this.suspended = false,
    this.error,
    this.recordingSeconds = 0,
    this.realtimeStatus = 'idle',
    this.callMode = 'listening',
    this.micMuted = false,
    this.userCaption,
    this.agentCaption,
    this.realtimeError,
    this.realtimeConnectedAt,
  });
  final String camera, microphone, detection;
  final String realtimeStatus, callMode;
  final bool micMuted;
  final String? userCaption, agentCaption, realtimeError;
  final DateTime? realtimeConnectedAt;
  bool get connected => realtimeStatus == 'connected';
  final bool detectionEnabled, playing, suspended;
  final String? emotion, reason, error;
  final int faceCount;
  final int recordingSeconds;
  final DateTime? observedAt;
  final int? inferenceMs;

  bool get cameraOn => camera == 'on';
  bool get isRecording => microphone == 'recording';
  bool get hasRecording => isRecording || microphone == 'recorded';
  bool get cameraBusy => camera == 'starting';
  bool get microphoneBusy => microphone == 'requesting';
  String get emotionText => emotion == null
      ? (reason ?? 'Unable to detect')
      : 'AI-estimated emotion: ${emotion![0].toUpperCase()}${emotion!.substring(1)}';

  factory AiraMediaState.fromJson(Map<String, dynamic> json) => AiraMediaState(
    realtimeStatus: json['realtimeStatus'] as String? ?? 'idle',
    callMode: json['callMode'] as String? ?? 'listening',
    micMuted: json['micMuted'] == true,
    userCaption: json['userCaption'] as String?,
    agentCaption: json['agentCaption'] as String?,
    realtimeError: json['realtimeError'] as String?,
    realtimeConnectedAt: json['realtimeConnectedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['realtimeConnectedAt'] as num).toInt(),
          )
        : null,
    camera: json['camera'] as String? ?? 'off',
    microphone: json['microphone'] as String? ?? 'off',
    detection: json['detection'] as String? ?? 'off',
    detectionEnabled: json['detectionEnabled'] == true,
    emotion: json['emotion'] as String?,
    reason: json['reason'] as String?,
    error: json['error'] as String?,
    faceCount: json['faceCount'] as int? ?? 0,
    observedAt: json['observedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['observedAt'] as num).toInt(),
          )
        : null,
    inferenceMs: (json['inferenceMs'] as num?)?.toInt(),
    playing: json['playing'] == true,
    recordingSeconds: json['recordingSeconds'] as int? ?? 0,
    suspended: json['suspended'] == true,
  );
}
