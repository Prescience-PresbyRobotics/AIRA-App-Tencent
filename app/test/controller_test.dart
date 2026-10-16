import 'dart:async';

import 'package:aira/controller.dart';
import 'package:aira/services/aira_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
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

  test('logout closes the active call and clears local state without waiting on the network', () async {
    final closed = Completer<Map<String, dynamic>>();
    api.respond = (_) => closed.future;
    controller.activeCallId = 'call-to-close';
    controller.callHistory = [
      {'id': 'private-call'},
    ];
    controller.callSchedule = {'localTime': '09:00'};
    final result = controller.signOut();
    expect(controller.activeCallId, isEmpty);
    expect(controller.callHistory, isEmpty);
    expect(controller.callSchedule, isNull);
    expect(api.calls.single.path, '/calls/call-to-close/end');
    closed.completeError(const AiraException('Offline'));
    await result;
    expect(controller.signedIn, isFalse);
  });

  test('disabled Google provider has a useful email fallback message', () {
    expect(
      AiraController.cleanError(
        const AuthException('Unsupported provider: provider is not enabled'),
      ),
      'Google sign-in is not available yet. Please use email to sign in for now.',
    );
  });

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

  test(
    'call context clears cues and End preserves the chat timeline',
    () async {
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
      expect(controller.messages.single.text, 'Private spoken turn');
      expect(controller.outbox.single.delivery, MessageDelivery.cancelled);
      expect(controller.activeCallId, isEmpty);
      expect(api.calls.last.path, '/calls/current-call/end');
    },
  );
  test(
    'bootstrap restores saved history and pagination merges without duplicates',
    () async {
      Map<String, dynamic> turn(String id, String text, String at) => {
        'id': id,
        'text': text,
        'role': 'assistant',
        'createdAt': at,
        'contextVersion': 4,
        'mode': 'text',
      };
      api.respond = (call) async {
        if (call.path == '/me') {
          return {
            'profile': {'onboarded': true, 'consent_version': 4},
            'preferences': {'store_conversations': true},
          };
        }
        if (call.path == '/history') {
          return {
            'messages': [
              turn('latest', 'Welcome back', '2026-10-16T10:00:00Z'),
            ],
            'nextCursor': '10',
            'conversationId': 'saved-text-thread',
            'privacyVersion': 4,
          };
        }
        if (call.path == '/history?before=10') {
          return {
            'messages': [turn('older', 'Last week', '2026-10-09T10:00:00Z')],
            'nextCursor': null,
            'privacyVersion': 4,
          };
        }
        throw StateError('Unexpected request ${call.path}');
      };
      await controller.bootstrap();
      expect(controller.messages.single.text, 'Welcome back');
      expect(controller.conversationId, 'saved-text-thread');
      expect(controller.showIntroduction, isFalse);
      expect(controller.hasOlderHistory, isTrue);
      await controller.refreshHistory(older: true);
      expect(controller.messages.map((m) => m.text), [
        'Last week',
        'Welcome back',
      ]);
      expect(controller.hasOlderHistory, isFalse);
      await controller.refreshHistory();
      expect(controller.messages, hasLength(2));
      expect(controller.messages.every((m) => m.speechToken == null), isTrue);
    },
  );

  test(
    'history response cannot cross account or storage opt-out boundaries',
    () async {
      controller.preferences['store_conversations'] = true;
      final completion = Completer<Map<String, dynamic>>();
      api.respond = (call) async {
        if (call.path == '/history') return completion.future;
        return {
          'profile': {'consent_version': 2},
        };
      };
      final loading = controller.refreshHistory();
      await controller.updatePreference('store_conversations', false);
      completion.complete({
        'messages': [
          {
            'id': 'private',
            'text': 'Private history',
            'role': 'user',
            'createdAt': '2026-10-16T10:00:00Z',
          },
        ],
      });
      await loading;
      expect(controller.messages, isEmpty);
      expect(controller.historyLoading, isFalse);
      expect(controller.historyLoaded, isFalse);
    },
  );

  test('calls preserve the text thread and existing saved messages', () async {
    controller.messages = [ChatTurn(text: 'Before our call', fromAira: false)];
    controller.conversationId = 'text-thread';
    api.respond = (call) async => call.path == '/calls/session'
        ? {
            'conversationId': 'live-call',
            'conversationToken': 'temporary-token',
          }
        : {};
    await controller.beginRealtimeCall('voice');
    expect(controller.conversationId, 'text-thread');
    expect(controller.activeCallId, 'live-call');
    expect(controller.messages.single.text, 'Before our call');
    await controller.endCall();
    expect(controller.conversationId, 'text-thread');
    expect(controller.messages.single.text, 'Before our call');
  });
  test(
    'forgetting retains the archive but never reuses its old model context',
    () async {
      controller.preferences['memory_enabled'] = true;
      controller.preferences['store_conversations'] = true;
      controller.messages = [
        ChatTurn(
          text: 'My old personal detail',
          fromAira: false,
          contextVersion: 1,
        ),
        ChatTurn(text: 'I will remember', fromAira: true, contextVersion: 1),
      ];
      controller.memories = [
        {'id': 'old-memory', 'text': 'Old personal detail'},
      ];
      api.respond = (call) async => call.method == 'DELETE'
          ? {'privacyVersion': 2}
          : approvedReply('Fresh conversation', privacyVersion: 2);
      await controller.forgetMemory(controller.memories.single);
      expect(controller.messages, hasLength(2));
      expect(controller.memories, isEmpty);
      await controller.send('Something new');
      expect(api.calls.last.data!['context'], isEmpty);
      expect(controller.messages, hasLength(4));
    },
  );
  test('reload restores Delivered and then changes to Read when saved reply appears', () async {
    controller.preferences['store_conversations'] = true;
    var completed = false;
    final at = DateTime.now().toUtc().toIso8601String();
    api.respond = (_) async => {
      'messages': [
        {
          'id': 'user-turn',
          'text': 'Still there?',
          'role': 'user',
          'createdAt': at,
          'requestStatus': completed ? 'completed' : 'processing',
          'delivery': completed ? 'read' : 'delivered',
          'order': '1',
        },
        if (completed)
          {
            'id': 'reply-turn',
            'text': 'Right here',
            'role': 'assistant',
            'createdAt': at,
            'delivery': 'read',
            'requestStatus': 'completed',
            'order': '2',
          },
      ],
      'privacyVersion': 1,
      'nextCursor': null,
    };
    await controller.refreshHistory();
    expect(controller.messages.single.delivery, MessageDelivery.delivered);
    expect(controller.historyAwaitingReply, isTrue);
    completed = true;
    await controller.refreshHistory();
    expect(controller.messages.map((m) => m.text), [
      'Still there?',
      'Right here',
    ]);
    expect(controller.messages.first.delivery, MessageDelivery.read);
    expect(controller.historyAwaitingReply, isFalse);
  });
  test(
    'history refresh during a send cannot duplicate its outgoing bubble',
    () async {
      controller.preferences['store_conversations'] = true;
      final reply = Completer<Map<String, dynamic>>();
      api.respond = (call) async {
        if (call.method == 'POST') return reply.future;
        return {
          'messages': [
            {
              'id': controller.pendingRequest,
              'text': 'In flight',
              'role': 'user',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'requestStatus': 'processing',
              'delivery': 'delivered',
            },
          ],
          'privacyVersion': 1,
        };
      };
      final sending = controller.send('In flight');
      await controller.refreshHistory();
      expect(controller.messages, hasLength(1));
      reply.complete(approvedReply('Got it'));
      await sending;
      expect(controller.messages.map((m) => m.text), ['In flight', 'Got it']);
      expect(controller.outbox, isEmpty);
    },
  );
  test('main chat and client payload omit transcript bubbles; shared context is server-owned', () async {
    controller.messages = [
      ChatTurn(text: 'Text message', fromAira: false),
      ChatTurn(text: 'Private spoken message', fromAira: false, mode: 'voice'),
      ChatTurn(text: 'Video reply', fromAira: true, mode: 'video'),
    ];
    expect(controller.visibleMessages.map((turn) => turn.text), [
      'Text message',
    ]);
    api.respond = (_) async => approvedReply('Text reply');
    await controller.send('New text');
    expect(api.calls.last.data!['context'], [
      {'role': 'user', 'text': 'Text message'},
    ]);
    expect(controller.visibleMessages.map((turn) => turn.text), [
      'Text message',
      'New text',
      'Text reply',
    ]);
  });

  test(
    'call archive pagination stays separate and clears with storage opt-out',
    () async {
      controller.preferences['store_conversations'] = true;
      api.respond = (request) async {
        if (request.method == 'PATCH') {
          return {
            'profile': {'consent_version': 2},
          };
        }
        return {
          'calls': [
            {
              'id': request.path.contains('?') ? 'older' : 'latest',
              'mode': 'voice',
            },
          ],
          'nextCursor': request.path.contains('?') ? null : 'previous',
          'privacyVersion': 1,
        };
      };
      await controller.refreshCallHistory();
      await controller.refreshCallHistory(older: true);
      expect(controller.callHistory.map((call) => call['id']), [
        'latest',
        'older',
      ]);
      expect(controller.messages, isEmpty);
      await controller.updatePreference('store_conversations', false);
      expect(controller.callHistory, isEmpty);
      expect(controller.callHistoryCursor, isNull);
    },
  );

  test('delayed call archive cannot restore another account data', () async {
    controller.preferences['store_conversations'] = true;
    final result = Completer<Map<String, dynamic>>();
    api.respond = (_) => result.future;
    final pending = controller.refreshCallHistory();
    controller.startPreview();
    result.complete({
      'calls': [
        {'id': 'private', 'mode': 'video'},
      ],
      'privacyVersion': 1,
    });
    await pending;
    expect(controller.callHistory, isEmpty);
    expect(controller.callHistoryLoading, isFalse);
  });

  test(
    'call transcript upload is pinned to its captured account session',
    () async {
      final oldSession = controller.sessionEpoch;
      controller.startPreview();
      await controller.saveCallTranscript(
        'provider-id',
        [
          {'role': 'user', 'text': 'Old account'},
        ],
        conversationId: 'old-call',
        expectedSession: oldSession,
      );
      expect(api.calls, isEmpty);
    },
  );

  test(
    'medicine create and edit accept future dates and carry version protection',
    () async {
      controller.preferences['medication_reminders'] = true;
      final future = DateTime.now().toUtc().add(const Duration(days: 7));
      api.respond = (_) async => {};
      await controller.saveMedicine(
        'Existing tablet',
        'Usual instructions',
        const TimeOfDay(hour: 9, minute: 0),
        dueAt: future,
        recurrence: 'daily',
      );
      expect(api.calls.single.path, '/medications');
      expect(api.calls.single.data!['dueAt'], future.toIso8601String());
      expect(api.calls.single.data!['recurrence'], 'daily');
      await controller.saveMedicine(
        'Existing tablet',
        'Updated reminder note',
        const TimeOfDay(hour: 10, minute: 0),
        dueAt: future,
        existing: {'id': 'medicine-one', 'version': 4},
      );
      expect(api.calls.last.method, 'PATCH');
      expect(api.calls.last.path, '/medications/medicine-one');
      expect(api.calls.last.data!['expectedVersion'], 4);
      expect(api.calls.last.data!['recurrence'], 'once');
      await expectLater(
        controller.saveMedicine(
          'Tablet',
          '',
          const TimeOfDay(hour: 9, minute: 0),
          dueAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        throwsA(isA<AiraException>()),
      );
      expect(api.calls, hasLength(2));
    },
  );

  test(
    'deleting a call revokes shared context but retains other visible history',
    () async {
      controller.privacyVersion = 2;
      controller.messages = [
        ChatTurn(text: 'Earlier text', fromAira: false, contextVersion: 2),
      ];
      controller.callHistory = [
        {'id': 'removed'},
        {'id': 'kept'},
      ];
      controller.pendingRequest = 'old-request';
      controller.pendingText = 'old text';
      api.respond = (_) async => {'deleted': true, 'privacyVersion': 3};
      await controller.deleteCallTranscript('removed');
      expect(controller.privacyVersion, 3);
      expect(controller.messages.single.text, 'Earlier text');
      expect(controller.callHistory.single['id'], 'kept');
      expect(controller.pendingRequest, isNull);
      expect(controller.pendingText, isNull);
    },
  );

  test(
    'automatic action receipts attach to reply only after server success',
    () async {
      api.respond = (_) async => {
        ...approvedReply('I saved that for you.'),
        'actions': [
          {
            'kind': 'memory',
            'id': 'memory-one',
            'label': 'Gardening',
            'status': 'saved',
          },
        ],
        'actionNotice': 'You can review this in About me.',
      };
      final result = await controller.send('I enjoy gardening');
      expect(result.actions.single['id'], 'memory-one');
      expect(result.actionNotice, 'You can review this in About me.');
      expect(controller.messages.last.actions.single['status'], 'saved');
    },
  );

  test('refreshing recent calls preserves earlier loaded call cards', () async {
    controller.preferences['store_conversations'] = true;
    var refreshed = false;
    api.respond = (request) async => {
      'calls': [
        {
          'id': request.path.contains('?')
              ? 'older'
              : refreshed
              ? 'new'
              : 'latest',
          'mode': 'voice',
        },
      ],
      'nextCursor': request.path.contains('?') ? null : 'previous',
      'privacyVersion': 1,
    };
    await controller.refreshCallHistory();
    await controller.refreshCallHistory(older: true);
    refreshed = true;
    await controller.refreshCallHistory();
    expect(controller.callHistory.map((call) => call['id']), [
      'latest',
      'older',
      'new',
    ]);
    expect(controller.callHistoryCursor, isNull);
  });

  test('scheduled call accept is claimed before native call start', () async {
    api.respond = (request) async {
      if (request.path == '/scheduled-calls/incoming/respond') {
        return {'startCall': true};
      }
      if (request.path == '/calls/session') {
        return {'conversationId': 'new-call', 'conversationToken': 'token'};
      }
      throw StateError('Unexpected path');
    };
    final accepted = await controller.respondScheduledCall({
      'id': 'incoming',
      'version': 3,
    }, 'accept');
    expect(accepted, isTrue);
    expect(controller.activeCallId, isEmpty);
    await controller.beginRealtimeCall('voice');
    expect(api.calls.last.data, {'mode': 'voice', 'invitationId': 'incoming'});
    expect(controller.pendingScheduledCallId, isNull);
    expect(controller.activeCallId, 'new-call');
  });

  test(
    'decline and already claimed scheduled calls never start a call',
    () async {
      api.respond = (_) async => {'startCall': false};
      for (final action in ['decline', 'accept']) {
        expect(
          await controller.respondScheduledCall({
            'id': 'incoming',
            'version': 1,
          }, action),
          isFalse,
        );
        expect(controller.pendingScheduledCallId, isNull);
        expect(controller.activeCallId, isEmpty);
      }
    },
  );

  test('call schedule persists explicit time and expected revision', () async {
    api.respond = (request) async => {
      'schedule': {...?request.data, 'version': 2},
    };
    controller.callSchedule = {
      'localTime': '18:00',
      'version': 1,
      'enabled': true,
    };
    await controller.saveCallSchedule(const TimeOfDay(hour: 9, minute: 30));
    expect(api.calls.last.data, {
      'localTime': '09:30',
      'timeZone': 'Asia/Singapore',
      'enabled': true,
      'expectedVersion': 1,
    });
    expect(controller.callSchedule!['version'], 2);
    await controller.deleteCallSchedule();
    expect(api.calls.last.method, 'DELETE');
    expect(api.calls.last.data, {'expectedVersion': 2});
    expect(controller.callSchedule, isNull);
  });
}
