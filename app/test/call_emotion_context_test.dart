import 'package:aira/media/call_emotion_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final started = DateTime.utc(2026, 10, 16, 10);
  Map<String, String>? check(
    FacialCheckInPolicy policy,
    int seconds, {
    String? label = 'happy',
    bool speaking = false,
    bool waiting = false,
    int? lastUserSecond,
    String? feeling,
  }) => policy.evaluate(
    now: started.add(Duration(seconds: seconds)),
    connectedAt: started,
    freshLabel: label,
    agentSpeaking: speaking,
    awaitingReply: waiting,
    lastUserActivity: lastUserSecond == null
        ? null
        : started.add(Duration(seconds: lastUserSecond)),
    selfReportedFeeling: feeling,
  );

  test(
    'stable expression and six silent seconds create one short-lived cue',
    () {
      final policy = FacialCheckInPolicy();
      expect(check(policy, 0), isNull);
      expect(check(policy, 5), isNull);
      final cue = check(policy, 6)!;
      expect(cue['label'], 'happy');
      expect(
        DateTime.parse(cue['expiresAt']!),
        started.add(const Duration(seconds: 26)),
      );
      expect(check(policy, 12), cue);
      expect(
        check(policy, 26),
        isNull,
        reason: 'expiry cannot renew the same prompt',
      );
      expect(check(policy, 65), isNull);
      expect(
        check(policy, 66)!['id'],
        isNot(cue['id']),
        reason: 'at most once a minute',
      );
    },
  );

  test(
    'speech, waiting for a reply and explicit feeling clear eligible cues',
    () {
      for (final variant in ['speech', 'agent', 'waiting', 'feeling']) {
        final policy = FacialCheckInPolicy();
        check(policy, 0);
        expect(check(policy, 6), isNotNull);
        expect(
          check(
            policy,
            7,
            lastUserSecond: variant == 'speech' ? 7 : null,
            speaking: variant == 'agent',
            waiting: variant == 'waiting',
            feeling: variant == 'feeling' ? 'calm' : null,
          ),
          isNull,
        );
        expect(
          check(policy, 20),
          isNull,
          reason: 'a cleared cue cannot revive before cooldown',
        );
      }
    },
  );

  test(
    'changed, stale or absent face clears immediately; neutral never prompts',
    () {
      for (final label in ['sad', null, 'neutral']) {
        final policy = FacialCheckInPolicy();
        check(policy, 0);
        expect(check(policy, 6), isNotNull);
        expect(check(policy, 7, label: label), isNull);
      }
      final policy = FacialCheckInPolicy();
      check(policy, 0, label: 'neutral');
      expect(check(policy, 90, label: 'neutral'), isNull);
      expect(check(policy, 91, label: 'sad'), isNull);
      expect(check(policy, 95, label: 'sad'), isNull);
      expect(check(policy, 96, label: 'sad'), isNotNull);
      policy.reset();
      expect(
        check(policy, 100, label: 'sad'),
        isNull,
        reason: 'new calls require a new stable expression',
      );
    },
  );
}
