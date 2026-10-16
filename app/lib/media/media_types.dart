import 'dart:typed_data';

class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

class AudioInputDevice {
  const AudioInputDevice({required this.id, required this.label});
  final String id, label;

  factory AudioInputDevice.fromJson(Map<String, dynamic> json) =>
      AudioInputDevice(
        id: json['id'] as String,
        label: json['label'] as String,
      );
}

class AudioOutputDevice {
  const AudioOutputDevice({required this.id, required this.label});
  final String id, label;

  factory AudioOutputDevice.fromJson(Map<String, dynamic> json) =>
      AudioOutputDevice(
        id: json['id'] as String,
        label: json['label'] as String,
      );
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
    this.speakerMuted = false,
    this.inputLevel = 0,
    this.outputLevel = 0,
    this.awaitingReply = false,
    this.microphoneIssue,
    this.microphoneName,
    this.selectedMicrophoneId,
    this.availableMicrophones = const [],
    this.changingMicrophone = false,
    this.availableSpeakers = const [],
    this.selectedSpeakerId = 'default',
    this.speakerName = 'System default',
    this.speakerSelectionSupported = false,
    this.changingSpeaker = false,
    this.speakerIssue,
    this.lastUserActivityAt,
    this.userCaption,
    this.agentCaption,
    this.realtimeError,
    this.realtimeConnectedAt,
    this.voiceConversationId,
    this.callTranscript = const [],
  });
  final String camera, microphone, detection;
  final String realtimeStatus, callMode;
  final bool micMuted, speakerMuted, awaitingReply, changingMicrophone;
  final double inputLevel, outputLevel;
  final String? microphoneIssue, microphoneName, selectedMicrophoneId;
  final List<AudioInputDevice> availableMicrophones;
  final List<AudioOutputDevice> availableSpeakers;
  final String selectedSpeakerId, speakerName;
  final bool speakerSelectionSupported, changingSpeaker;
  final String? speakerIssue;
  final DateTime? lastUserActivityAt;
  final String? userCaption, agentCaption, realtimeError;
  final DateTime? realtimeConnectedAt;
  final String? voiceConversationId;
  final List<Map<String, dynamic>> callTranscript;
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
      : '${emotion![0].toUpperCase()}${emotion!.substring(1)}';

  factory AiraMediaState.fromJson(Map<String, dynamic> json) => AiraMediaState(
    realtimeStatus: json['realtimeStatus'] as String? ?? 'idle',
    callMode: json['callMode'] as String? ?? 'listening',
    micMuted: json['micMuted'] == true,
    speakerMuted: json['speakerMuted'] == true,
    inputLevel: (json['inputLevel'] as num?)?.toDouble() ?? 0,
    outputLevel: (json['outputLevel'] as num?)?.toDouble() ?? 0,
    awaitingReply: json['awaitingReply'] == true,
    microphoneIssue: json['microphoneIssue'] as String?,
    microphoneName: json['microphoneName'] as String?,
    selectedMicrophoneId: json['selectedMicrophoneId'] as String?,
    changingMicrophone: json['changingMicrophone'] == true,
    selectedSpeakerId: json['selectedSpeakerId'] as String? ?? 'default',
    speakerName: json['speakerName'] as String? ?? 'System default',
    speakerSelectionSupported: json['speakerSelectionSupported'] == true,
    changingSpeaker: json['changingSpeaker'] == true,
    speakerIssue: json['speakerIssue'] as String?,
    lastUserActivityAt: json['lastUserActivityAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['lastUserActivityAt'] as num).toInt(),
          )
        : null,
    availableSpeakers: (json['availableSpeakers'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AudioOutputDevice.fromJson)
        .toList(),
    availableMicrophones: (json['availableMicrophones'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AudioInputDevice.fromJson)
        .toList(),
    voiceConversationId: json['voiceConversationId'] as String?,
    callTranscript: (json['callTranscript'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(),
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
