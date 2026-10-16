/// A local, temporary invitation to ask about an expression during silence.
/// It never asserts the person's actual feeling or inserts a user chat turn.
class FacialCheckInPolicy {
  String? _stableLabel, _cueId;
  DateTime? _stableSince, _lastOffer, _expires;
  int _sequence = 0;

  void reset() {
    _stableLabel = null;
    _stableSince = null;
    _lastOffer = null;
    _cueId = null;
    _expires = null;
  }

  Map<String, String>? evaluate({
    required DateTime now,
    required DateTime connectedAt,
    required String? freshLabel,
    required bool agentSpeaking,
    required bool awaitingReply,
    DateTime? lastUserActivity,
    String? selfReportedFeeling,
  }) {
    if (freshLabel != _stableLabel) {
      _stableLabel = freshLabel;
      _stableSince = now;
      _cueId = null;
      _expires = null;
    }
    final eligibleExpression = const {
      'happy',
      'sad',
      'angry',
      'fearful',
      'surprised',
    }.contains(freshLabel);
    final quiet =
        now.difference(lastUserActivity ?? connectedAt) >=
        const Duration(seconds: 6);
    if (!eligibleExpression ||
        agentSpeaking ||
        awaitingReply ||
        !quiet ||
        selfReportedFeeling != null) {
      _cueId = null;
      _expires = null;
      return null;
    }
    if (_cueId != null && _expires != null && now.isBefore(_expires!)) {
      return {
        'id': _cueId!,
        'label': freshLabel!,
        'expiresAt': _expires!.toUtc().toIso8601String(),
      };
    }
    _cueId = null;
    if (_stableSince == null ||
        now.difference(_stableSince!) < const Duration(seconds: 5) ||
        (_lastOffer != null &&
            now.difference(_lastOffer!) < const Duration(seconds: 60))) {
      return null;
    }
    _lastOffer = now;
    _expires = now.add(const Duration(seconds: 20));
    _cueId = 'expression-${++_sequence}-${now.millisecondsSinceEpoch}';
    return {
      'id': _cueId!,
      'label': freshLabel!,
      'expiresAt': _expires!.toUtc().toIso8601String(),
    };
  }
}
