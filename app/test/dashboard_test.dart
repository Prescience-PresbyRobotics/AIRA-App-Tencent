import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aira/controller.dart';
import 'package:aira/services/aira_api.dart';
import 'package:aira/screens/live_dashboard.dart';

class FakeApi extends AiraApi {
  FakeApi(this.handler)
      : super(SupabaseClient('https://example.supabase.co', 'public',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final Future<Map<String, dynamic>> Function(
      String, String, Map<String, dynamic>?) handler;
  @override
  Future<Map<String, dynamic>> request(String method, String path,
          [Map<String, dynamic>? data]) =>
      handler(method, path, data);
}

class FakeController extends AiraController {
  FakeController(this.fake) : super(null);
  final FakeApi fake;
  int epoch = 1;
  @override
  int get sessionEpoch => epoch;
  @override
  bool get signedIn => true;
  @override
  AiraApi get api => fake;
  void switchAccount() {
    epoch++;
    notifyListeners();
  }
}

Map<String, dynamic> insights(int count,
        {List<String> categories = const [
          'conversations',
          'loneliness',
          'mood'
        ]}) =>
    {
      'categories': categories,
      'supportedSeniors': 1,
      'conversations': {
        'count': count,
        'seniorInitiated': count,
        'airaInitiated': 0,
        'durationMinutes': 12
      },
      'loneliness': {
        'periods': [
          {
            'period_start': '2026-10-07',
            'period_end': '2026-10-13',
            'response': {'lonely_days': 0, 'skipped': false}
          }
        ]
      },
      'mood': {
        'selfReported': [],
        'inferred': [],
        'inferredStatus': 'Not stored'
      }
    };
Future<void> show(WidgetTester tester, FakeController controller,
    {bool admin = false}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: LiveDashboardScreen(controller: controller, admin: admin))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('withheld metrics are not shown as measured zero',
      (tester) async {
    final ctl = FakeController(FakeApi((m, p, d) async {
      if (p == '/caregiver/seniors') {
        return {
          'seniors': [
            {'id': 'one', 'display_name': 'Test senior'}
          ]
        };
      }
      if (p.contains('/insights')) {
        return insights(0, categories: ['loneliness']);
      }
      return {'reports': []};
    }));
    await show(tester, ctl);
    expect(find.text('Not shared'), findsWidgets);
    expect(find.text('0 / 7'), findsOneWidget);
    expect(find.text('No comparable baseline change is available.'),
        findsOneWidget);
    expect(find.text('completed conversations'), findsNothing);
  });
  testWidgets('late prior-account insights never replace current account',
      (tester) async {
    final old = Completer<Map<String, dynamic>>();
    int calls = 0;
    final ctl = FakeController(FakeApi((m, p, d) async {
      if (p == '/caregiver/seniors') {
        return {
          'seniors': [
            {'id': 'one', 'display_name': 'Test senior'}
          ]
        };
      }
      if (p.contains('/insights')) {
        return ++calls == 1 ? old.future : insights(9);
      }
      return {'reports': []};
    }));
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LiveDashboardScreen(controller: ctl, admin: false))));
    await tester.pump();
    ctl.switchAccount();
    await tester.pumpAndSettle();
    expect(find.text('9'), findsWidgets);
    old.complete(insights(1));
    await tester.pumpAndSettle();
    expect(find.text('9'), findsWidgets);
    expect(find.text('Senior 1'), findsNothing);
  });
  testWidgets(
      'reviewer queue remains available without insight or operator role',
      (tester) async {
    final ctl = FakeController(FakeApi((m, p, d) async {
      if (p == '/admin/subjects') return {'seniors': []};
      if (p == '/admin/overview') {
        throw const AiraException('You do not have access to this view.');
      }
      if (p == '/admin/incidents') {
        return {
          'incidents': [
            {
              'id': 'case',
              'user_id': 'senior',
              'version': 2,
              'state': 'new',
              'priority': 'review',
              'reason': 'uncertain',
              'excerpt': 'Review evidence',
              'source': 'user'
            }
          ]
        };
      }
      return {};
    }));
    await show(tester, ctl, admin: true);
    expect(find.text('Review evidence'), findsOneWidget);
    expect(find.text('Review concern'), findsOneWidget);
    expect(
        find.textContaining('Operator overview unavailable'), findsOneWidget);
  });
}
