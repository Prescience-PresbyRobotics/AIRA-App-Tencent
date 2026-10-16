import 'dart:async';

import 'package:aira/controller.dart';
import 'package:aira/screens/chat.dart';
import 'package:aira/services/aira_api.dart';
import 'package:aira/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatApi extends AiraApi {
  ChatApi()
    : super(
        SupabaseClient(
          'http://localhost:54321',
          'test-only-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final calls = <({String method, String path, Map<String, dynamic>? body})>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  String acknowledgedStatus = 'not_found';
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add((method: method, path: path, body: data));
    if (method == 'GET' && path.endsWith('/status')) {
      return {'status': acknowledgedStatus};
    }
    if (method == 'POST' && path == '/messages') {
      final result = Completer<Map<String, dynamic>>();
      replies.add(result);
      return result.future;
    }
    if (method == 'GET' && path == '/calls/history') return {'calls': []};
    if (method == 'GET' && path == '/calls/call-one/transcript') {
      return {
        'messages': [
          {'role': 'user', 'text': 'Spoken garden detail'},
        ],
      };
    }
    if (method == 'PATCH' && path == '/preferences') {
      return {
        'profile': {'consent_version': 2},
      };
    }
    throw StateError('Unexpected request: $method $path');
  }
}

class ChatController extends AiraController {
  ChatController(this.service) : super(null);
  final ChatApi service;
  @override
  AiraApi get api => service;
}

Future<void> showChat(WidgetTester tester, ChatController controller) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: airaTheme(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, child) => ChatScreen(controller: controller),
        ),
      ),
    ),
  );
}

Map<String, dynamic> reply(String text) => {
  'text': text,
  'status': 'approved',
  'messageId': 'reply-id',
  'conversationId': 'conversation-id',
  'privacyVersion': 1,
};

void main() {
  late ChatApi api;
  late ChatController controller;
  setUp(() {
    api = ChatApi();
    controller = ChatController(api);
  });
  tearDown(() async {
    controller.dispose();
    await api.client.dispose();
  });

  testWidgets('first chat introduces Aira once, with the actual display time', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final before = DateTime.now();
    await showChat(tester, controller);
    final intro = controller.introduction;
    expect(intro.text, airaIntroduction);
    expect(find.text(airaIntroduction), findsOneWidget);
    expect(
      tester.getSemantics(find.text(airaIntroduction)).label,
      startsWith(airaIntroduction),
      reason: 'The full greeting must be exposed as static message text',
    );
    expect(
      tester
          .getSemantics(find.text(airaIntroduction))
          .getSemanticsData()
          .flagsCollection
          .isTextField,
      isFalse,
      reason:
          'A conversation message must not announce as a disabled text field',
    );
    semantics.dispose();
    expect(find.text('Your AI companion'), findsOneWidget);
    expect(find.byKey(const ValueKey('aira-typing-indicator')), findsNothing);
    expect(intro.time.isBefore(before), isFalse);
    expect(find.text(DateFormat('h:mm a').format(intro.time)), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(identical(controller.introduction, intro), isTrue);
    expect(
      api.calls,
      isEmpty,
      reason: 'The fixed introduction does not fake a model call',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'checks move from Sending to server-confirmed Delivered then Read on reply',
    (tester) async {
      await showChat(tester, controller);
      await tester.enterText(find.byType(TextField), 'Mei');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(find.text('Mei'), findsOneWidget);
      expect(find.text('Sending'), findsOneWidget);
      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Read'), findsNothing);
      expect(
        find.byKey(const ValueKey('aira-typing-indicator')),
        findsOneWidget,
      );
      final outgoing = controller.outbox.single;
      final originalTime = outgoing.time;

      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Sending'),
        findsOneWidget,
        reason: 'Elapsed time is not delivery evidence',
      );
      api.acknowledgedStatus = 'processing';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Read'), findsNothing);

      api.replies.single.complete(
        reply('Nice to meet you, Mei. What do you enjoy doing?'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Read'), findsOneWidget);
      expect(find.byKey(const ValueKey('aira-typing-indicator')), findsNothing);
      expect(controller.messages.first.time, originalTime);
      expect(controller.outbox, isEmpty);
      expect(find.text('Use “Mei” for this chat'), findsOneWidget);
      expect(
        controller.name,
        isEmpty,
        reason: 'A suggested name is not automatically saved',
      );
      final post = api.calls.firstWhere((c) => c.path == '/messages');
      expect((post.body!['context'] as List).first['text'], airaIntroduction);
      expect(post.body!['introductionShown'], isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'delivery failure stays visible and retry retains original identity and timestamp',
    (tester) async {
      await showChat(tester, controller);
      await tester.enterText(find.byType(TextField), 'A little chat');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      final original = controller.outbox.single;
      api.replies.single.completeError(
        const AiraException('Connection unavailable'),
      );
      await tester.pump();
      expect(find.text('Not confirmed'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const ValueKey('aira-typing-indicator')), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(controller.outbox.single.id, original.id);
      expect(controller.outbox.single.time, original.time);
      final requests = api.calls.where((c) => c.path == '/messages').toList();
      expect(
        requests[0].body!['clientMessageId'],
        requests[1].body!['clientMessageId'],
      );
      api.replies.last.complete(reply('I’d like that. What’s on your mind?'));
      await tester.pump();
      expect(controller.messages.first.time, original.time);
      expect(find.text('Read'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'call cards appear in the chat without exposing transcript bubbles',
    (tester) async {
      controller.preferences['store_conversations'] = true;
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      controller.messages = [
        ChatTurn(
          text: 'A text before the call',
          fromAira: false,
          time: start.subtract(const Duration(minutes: 1)),
        ),
      ];
      controller.callHistory = [
        {
          'id': 'call-one',
          'mode': 'video',
          'initiator': 'user',
          'startedAt': start.toIso8601String(),
          'endedAt': start.add(const Duration(minutes: 2)).toIso8601String(),
          'status': 'ended',
        },
      ];
      await showChat(tester, controller);
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('call-card-call-one'));
      expect(card, findsOneWidget);
      expect(find.textContaining('2 min'), findsOneWidget);
      expect(find.text('Spoken garden detail'), findsNothing);
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getTopLeft(find.text('A text before the call')).dy),
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Video call transcript'), findsOneWidget);
      expect(find.text('Spoken garden detail'), findsOneWidget);
    },
  );

  testWidgets(
    'main chat omits read aloud and only shows confirmed action receipts',
    (tester) async {
      controller.messages = [
        ChatTurn(
          text: 'Your reminder is saved.',
          fromAira: true,
          speechToken: 'unused-playback-token',
          actions: [
            {
              'kind': 'medication',
              'id': 'medicine',
              'label': 'Morning tablet',
              'status': 'saved',
            },
            {'kind': 'memory', 'label': 'Not confirmed', 'status': 'failed'},
          ],
        ),
      ];
      await showChat(tester, controller);
      await tester.pumpAndSettle();
      expect(find.text('Read aloud'), findsNothing);
      expect(
        find.text('Medicine reminder saved · Morning tablet'),
        findsOneWidget,
      );
      expect(find.textContaining('Not confirmed'), findsNothing);
    },
  );

  test(
    'confirming name respects memory permission and never silently saves',
    () async {
      controller.suggestedName = 'Mei';
      await controller.confirmPreferredName('Mei');
      expect(controller.name, 'Mei');
      expect(controller.suggestedName, isNull);
      expect(api.calls, isEmpty);
      controller.preferences['memory_enabled'] = true;
      await controller.confirmPreferredName('Mei Lin');
      expect(api.calls.single.method, 'PATCH');
      expect(api.calls.single.body, {'display_name': 'Mei Lin'});
      expect(controller.name, 'Mei Lin');
      expect(controller.privacyVersion, 2);
    },
  );

  test(
    'first conversational reply is not misclassified as a preferred name',
    () async {
      expect(controller.introduction.text, airaIntroduction);
      final result = controller.send('I feel sad');
      api.replies.single.complete(reply('I’m here to listen. What happened?'));
      await result;
      expect(controller.suggestedName, isNull);
      expect(controller.name, isEmpty);
      expect(api.calls.where((c) => c.path == '/preferences'), isEmpty);
    },
  );
}
