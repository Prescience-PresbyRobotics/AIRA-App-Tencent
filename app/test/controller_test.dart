import 'dart:async';

import 'package:aira/controller.dart';
import 'package:aira/services/aira_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecordedRequest {
  RecordedRequest(this.method, this.path, Map<String, dynamic>? body)
    : data = body == null ? null : Map<String, dynamic>.from(body);
  final String method, path;
  final Map<String, dynamic>? data;
}

class ControllerApi extends AiraApi {
  ControllerApi()
    : super(
        SupabaseClient(
          'http://localhost:54321',
          'test-only-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final calls = <RecordedRequest>[];
  Future<Map<String, dynamic>> Function(RecordedRequest)? respond;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) {
    final call = RecordedRequest(method, path, data);
    calls.add(call);
    if (respond == null) throw StateError('Unexpected request: $method $path');
    return respond!(call);
  }
}

class TestedController extends AiraController {
  TestedController(this.testApi) : super(null);
  final ControllerApi testApi;
  @override
  AiraApi get api => testApi;
}

Map<String, dynamic> approvedReply(
  String text, {
  String conversation = 'conversation-a',
  int privacyVersion = 1,
}) => {
  'text': text,
  'messageId': 'approved-reply',
  'conversationId': conversation,
  'privacyVersion': privacyVersion,
  'speechToken': 'approved-short-lived-token',
};

void main() {
  late ControllerApi api;
  late TestedController controller;
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  setUp(() {
    api = ControllerApi();
    controller = TestedController(api);
  });
  tearDown(() async {
    controller.dispose();
    await api.client.dispose();
  });

  test(
    'onboarding saves display choice and account bootstrap restores it',
    () async {
      var savedScale = 1.0;
      api.respond = (call) async {
        if (call.method == 'PATCH') {
          savedScale = (call.data!['text_scale'] as num).toDouble();
          return {
            'profile': {'consent_version': 2},
          };
        }
        return {
          'profile': {'onboarded': true},
          'preferences': {'text_scale': savedScale},
        };
      };
      await controller.setScale(true);
      expect(api.calls, isEmpty);
      await controller.finishOnboarding('Mei', {});
      expect(savedScale, 1.25);
      controller.largerText = false;
      await controller.bootstrap();
      expect(controller.largerText, isTrue);
      expect(controller.onboarded, isTrue);
    },
  );

  test(
    'display saves share the preference queue and preserve chat history',
    () async {
      controller.onboarded = true;
      controller.messages = [ChatTurn(text: 'Hello', fromAira: false)];
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (call) async {
        if (call.data?['text_scale'] == 1.25) return completion.future;
        return {
          'profile': {'consent_version': 3},
        };
      };
      final larger = controller.setScale(true);
      final compact = controller.setScale(false);
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, hasLength(1));
      completion.complete({
        'profile': {'consent_version': 2},
      });
      await larger;
      await compact;
      expect(api.calls.map((call) => call.data!['text_scale']), [1.25, 1.0]);
      expect(controller.largerText, isFalse);
      expect(controller.privacyVersion, 3);
      expect(controller.messages.single.text, 'Hello');
    },
  );

  test(
    'failed or obsolete display save cannot change the account preference',
    () async {
      controller.onboarded = true;
      api.respond = (_) async => throw const AiraException('Offline');
      await expectLater(
        controller.setScale(true),
        throwsA(isA<AiraException>()),
      );
      expect(controller.largerText, isFalse);
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (_) => completion.future;
      final pending = controller.setScale(true);
      await Future<void>.delayed(Duration.zero);
      await controller.signOut();
      completion.complete({
        'profile': {'consent_version': 9},
      });
      await pending;
      expect(controller.largerText, isFalse);
      expect(controller.preferences, isEmpty);
      expect(controller.privacyVersion, isNot(9));
    },
  );

  test(
    'cancelSend discards a delayed reply and does not resume sending',
    () async {
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (_) => completion.future;
      final result = controller.send('Hello');
      final rejected = expectLater(result, throwsA(isA<AiraException>()));
      expect(controller.sending, isTrue);
      controller.cancelSend();
      completion.complete(approvedReply('Too late', privacyVersion: 7));
      await rejected;
      expect(controller.messages, isEmpty);
      expect(controller.conversationId, isEmpty);
      expect(controller.privacyVersion, 1);
      expect(controller.sending, isFalse);
    },
  );

  test(
    'cancelled old reply cannot overwrite a newer pending request',
    () async {
      final oldReply = Completer<Map<String, dynamic>>();
      final newReply = Completer<Map<String, dynamic>>();
      api.respond = (_) =>
          api.calls.length == 1 ? oldReply.future : newReply.future;
      final old = controller.send('First question');
      final rejected = expectLater(old, throwsA(isA<AiraException>()));
      controller.cancelSend();
      final current = controller.send('New question');
      final currentRequest = controller.pendingRequest;
      oldReply.complete(approvedReply('Obsolete'));
      await rejected;
      expect(controller.sending, isTrue);
      expect(controller.pendingText, 'New question');
      expect(controller.pendingRequest, currentRequest);
      expect(controller.messages, isEmpty);
      newReply.complete(approvedReply('Current answer'));
      await current;
      expect(controller.messages.map((m) => m.text), [
        'New question',
        'Current answer',
      ]);
      expect(controller.sending, isFalse);
    },
  );

  test(
    'preview switch clears account state and rejects a late private reply',
    () async {
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (_) => completion.future;
      controller.name = 'Previous account';
      controller.memories = [
        {'id': 'private', 'text': 'Private fact'},
      ];
      final epoch = controller.sessionEpoch;
      final result = controller.send('Private question');
      final rejected = expectLater(result, throwsA(isA<AiraException>()));
      controller.startPreview();
      completion.complete(approvedReply('Private answer'));
      await rejected;
      expect(controller.sessionEpoch, greaterThan(epoch));
      expect(controller.preview, isTrue);
      expect(controller.name, isEmpty);
      expect(controller.memories, isEmpty);
      expect(controller.messages, isEmpty);
      expect(controller.pendingText, isNull);
      expect(controller.pendingRequest, isNull);
      expect(controller.sending, isFalse);
      await expectLater(
        controller.send('Preview message'),
        throwsA(isA<AiraException>()),
      );
      expect(api.calls, hasLength(1));
    },
  );

  test(
    'sign-out account boundary rejects a delayed prior-account response',
    () async {
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (_) => completion.future;
      controller.preferences = {'store_conversations': true};
      final epoch = controller.sessionEpoch;
      final result = controller.send('Account A data');
      final rejected = expectLater(result, throwsA(isA<AiraException>()));
      await controller.signOut();
      // New account UI may arrive before the old account network response.
      controller.name = 'Account B';
      controller.messages = [
        ChatTurn(text: 'Account B context', fromAira: false),
      ];
      completion.complete(
        approvedReply(
          'Account A answer',
          conversation: 'account-a-conversation',
          privacyVersion: 99,
        ),
      );
      await rejected;
      expect(controller.sessionEpoch, greaterThan(epoch));
      expect(controller.name, 'Account B');
      expect(controller.messages.single.text, 'Account B context');
      expect(controller.conversationId, isEmpty);
      expect(controller.preferences, isEmpty);
      expect(controller.privacyVersion, isNot(99));
    },
  );

  test(
    'only ten recent turns and current privacy version reach the API',
    () async {
      controller.privacyVersion = 8;
      controller.conversationId = 'existing-conversation';
      controller.messages = List.generate(
        14,
        (i) => ChatTurn(text: 'turn $i', fromAira: i.isOdd),
      );
      api.respond = (_) async => approvedReply('New reply', privacyVersion: 8);
      await controller.send(
        '  New message  ',
        mode: 'video',
        cueSummary: {'label': 'happy', 'observedAt': '2026-10-14T10:00:00Z'},
        feeling: 'Sad',
      );
      final body = api.calls.single.data!;
      final context = body['context'] as List;
      expect(context, hasLength(10));
      expect(context.first, {'role': 'user', 'text': 'turn 4'});
      expect(context.last, {'role': 'assistant', 'text': 'turn 13'});
      expect(body['contextVersion'], 8);
      expect(body['conversationId'], 'existing-conversation');
      expect(body['text'], 'New message');
      expect(body['selfReportedFeeling'], 'Sad');
      expect((body['cueSummary'] as Map)['label'], 'happy');
      expect(body['clientMessageId'], matches(uuidV4));
    },
  );

  test(
    'uncertain send retries preserve one UUID and new messages get new IDs',
    () async {
      var attempt = 0;
      api.respond = (_) async {
        attempt++;
        if (attempt == 1) throw const AiraException('Connection lost');
        return approvedReply('Reply $attempt');
      };
      await expectLater(
        controller.send('Retry this message'),
        throwsA(isA<AiraException>()),
      );
      final originalId = api.calls.first.data!['clientMessageId'];
      expect(originalId, matches(uuidV4));
      expect(controller.pendingRequest, originalId);
      expect(controller.messages, isEmpty);
      expect(controller.sending, isFalse);
      await controller.send('Retry this message');
      expect(api.calls[1].data!['clientMessageId'], originalId);
      expect(controller.messages, hasLength(2));
      expect(controller.pendingRequest, isNull);
      expect(controller.pendingText, isNull);
      await controller.send('Another message');
      final nextId = api.calls.last.data!['clientMessageId'];
      expect(nextId, matches(uuidV4));
      expect(nextId, isNot(originalId));
    },
  );

  test(
    'still-processing reply retains retry identity and adds no empty turn',
    () async {
      api.respond = (_) async => {'status': 'processing', 'text': null};
      await expectLater(
        controller.send('Is that ready?'),
        throwsA(isA<AiraException>()),
      );
      final originalId = controller.pendingRequest;
      expect(controller.messages, isEmpty);
      api.respond = (_) async => approvedReply('Ready now');
      await controller.send('Is that ready?');
      expect(api.calls.last.data!['clientMessageId'], originalId);
      expect(controller.messages.map((m) => m.text), [
        'Is that ready?',
        'Ready now',
      ]);
    },
  );

  test(
    'weekly Skip remains null, zero stays valid, edits use server version',
    () async {
      final prompt = <String, dynamic>{
        'id': 'server-prompt',
        'period_start': '2026-10-07',
        'period_end': '2026-10-13',
        'timezone': 'Asia/Singapore',
      };
      Map<String, dynamic>? saved;
      api.respond = (call) async {
        if (call.method == 'GET' && call.path == '/measurements/prompt') {
          return {'prompt': prompt, 'response': saved};
        }
        if (call.method == 'POST' && call.path == '/measurements/loneliness') {
          saved = {
            'version': (saved?['version'] as int? ?? 0) + 1,
            'lonely_days': call.data!['lonelyDays'],
            'skipped': call.data!['skipped'],
          };
          return {'response': saved};
        }
        throw StateError('Unexpected endpoint ${call.path}');
      };
      await controller.loadMeasurementPrompt();
      await controller.saveLoneliness(null);
      var submitted = api.calls.where((c) => c.method == 'POST').single.data!;
      expect(submitted['promptId'], 'server-prompt');
      expect(submitted['lonelyDays'], isNull);
      expect(submitted['skipped'], isTrue);
      expect(submitted['expectedVersion'], 0);
      expect(submitted['requestId'], matches(uuidV4));
      expect(submitted.containsKey('period_start'), isFalse);
      expect(controller.lonelyDays, isNull);
      expect(controller.measurementResponse!['skipped'], isTrue);
      await controller.saveLoneliness(0);
      submitted = api.calls.where((c) => c.method == 'POST').last.data!;
      expect(submitted['lonelyDays'], 0);
      expect(submitted['skipped'], isFalse);
      expect(submitted['expectedVersion'], 1);
      expect(controller.lonelyDays, 0);
      expect(controller.measurementPrompt!['period_end'], '2026-10-13');
      expect(controller.measurementResponse!['version'], 2);
    },
  );

  test(
    'late weekly prompt cannot repopulate data after account boundary',
    () async {
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (_) => completion.future;
      final pending = controller.loadMeasurementPrompt();
      controller.startPreview();
      completion.complete({
        'prompt': {'id': 'previous-account-prompt'},
        'response': {'lonely_days': 6},
      });
      await pending;
      expect(controller.measurementPrompt, isNull);
      expect(controller.measurementResponse, isNull);
      expect(controller.lonelyDays, isNull);
    },
  );
  test(
    'realtime session arriving after End is closed without reopening the call',
    () async {
      final session = Completer<Map<String, dynamic>>();
      api.respond = (call) async {
        if (call.path == '/calls/session') return session.future;
        if (call.path == '/calls/late-call/end') return {'ended': true};
        throw StateError('Unexpected request ${call.path}');
      };
      final opening = controller.beginRealtimeCall('voice');
      final rejected = expectLater(opening, throwsA(isA<AiraException>()));
      await controller.endCall();
      session.complete({
        'conversationId': 'late-call',
        'conversationToken': 'temporary-token',
      });
      await rejected;
      expect(controller.activeCallId, isEmpty);
      expect(controller.conversationId, isEmpty);
      expect(api.calls.last.path, '/calls/late-call/end');
    },
  );

  test(
    'realtime session from a previous identity never opens in preview',
    () async {
      final session = Completer<Map<String, dynamic>>();
      api.respond = (_) => session.future;
      final opening = controller.beginRealtimeCall('video');
      final rejected = expectLater(opening, throwsA(isA<AiraException>()));
      controller.startPreview();
      session.complete({
        'conversationId': 'prior-account-call',
        'conversationToken': 'private-token',
      });
      await rejected;
      expect(controller.preview, isTrue);
      expect(controller.activeCallId, isEmpty);
      expect(controller.conversationId, isEmpty);
      expect(
        api.calls,
        hasLength(1),
        reason: 'Never clean up using a different account token',
      );
    },
  );

  test('call context explicitly clears both cues and End removes temporary buffers', () async {
    api.respond = (_) async => {};
    controller.activeCallId = 'current-call';
    controller.conversationId = 'current-call';
    await controller.publishCallContext(
      cueSummary: {'label': 'happy'},
      selfReportedFeeling: 'sad',
    );
    expect(api.calls.last.path, '/calls/current-call/context');
    expect(api.calls.last.data!['selfReportedFeeling'], 'sad');
    await controller.publishCallContext();
    expect(api.calls.last.data, {
      'cueSummary': null,
      'selfReportedFeeling': null,
    });
    controller.messages.add(
      ChatTurn(text: 'Private spoken turn', fromAira: false),
    );
    controller.outbox.add(
      ChatTurn(
        text: 'Waiting spoken turn',
        fromAira: false,
        delivery: MessageDelivery.sending,
      ),
    );
    await controller.endCall();
    expect(controller.messages, isEmpty);
    expect(controller.outbox, isEmpty);
    expect(controller.activeCallId, isEmpty);
    expect(api.calls.last.path, '/calls/current-call/end');
  });
}
