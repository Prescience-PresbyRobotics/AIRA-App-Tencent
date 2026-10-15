import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/aira_api.dart';

String requestUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ChatTurn {
  final String id, text;
  final bool fromAira;
  final String? speechToken;
  final DateTime time;
  ChatTurn({
    required this.text,
    required this.fromAira,
    String? id,
    this.speechToken,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       time = DateTime.now();
}

class AiraController extends ChangeNotifier {
  final SupabaseClient? client;
  AiraController(this.client) {
    _auth = client?.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        _identity = null;
        _clear();
        return;
      }
      _signingOut = false;
      if (_identity != event.session!.user.id) {
        _clear();
        _identity = event.session!.user.id;
      }
      if (event.event == AuthChangeEvent.passwordRecovery) {
        recovering = true;
        notifyListeners();
        return;
      }
      if (event.event != AuthChangeEvent.tokenRefreshed) {
        preview = false;
        bootstrap();
      }
    });
    if (client?.auth.currentSession != null) bootstrap();
  }
  StreamSubscription<AuthState>? _auth;
  String? _identity;
  int _sessionEpoch = 0;
  int get sessionEpoch => _sessionEpoch;
  bool _disposed = false;
  bool _current(int epoch) => !_disposed && epoch == _sessionEpoch;
  void cancelSend() {
    revision++;
    sending = false;
    notifyListeners();
  }

  bool preview = false,
      onboarded = false,
      loading = false,
      sending = false,
      recovering = false;
  String name = '', error = '', conversationId = '', activeCallId = '';
  bool _signingOut = false;
  bool largerText = false;
  int tab = 0;
  int? lonelyDays;
  String mood = '';
  int privacyVersion = 1, revision = 0;
  String? pendingText, pendingRequest;
  Map<String, dynamic>? measurementPrompt, measurementResponse;
  List<Map<String, dynamic>> pendingEvents = [];
  Map<String, dynamic> preferences = {};
  Map<String, dynamic> insights = {};
  Map<String, dynamic> capabilities = {};
  List<Map<String, dynamic>> memories = [], plans = [], medications = [];
  List<ChatTurn> messages = [];
  bool get configured => client != null;
  bool get signedIn =>
      preview || (!_signingOut && client?.auth.currentSession != null);
  String get displayName => name.trim().isEmpty ? 'friend' : name.trim();
  AiraApi get api => AiraApi(client!);
  bool consent(String key) => preferences[key] == true;
  void _clear() {
    _sessionEpoch++;
    revision++;
    sending = false;
    loading = false;
    recovering = false;
    largerText = false;
    pendingText = null;
    pendingRequest = null;
    measurementPrompt = null;
    measurementResponse = null;
    pendingEvents = [];
    preview = false;
    onboarded = false;
    name = '';
    conversationId = '';
    activeCallId = '';
    messages = [];
    memories = [];
    plans = [];
    medications = [];
    preferences = {};
    insights = {};
    capabilities = {};
    lonelyDays = null;
    mood = '';
    error = '';
    tab = 0;
    notifyListeners();
  }

  void startPreview() {
    _clear();
    preview = true;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    final epoch = sessionEpoch;
    loading = true;
    error = '';
    notifyListeners();
    try {
      final data = await api.request('GET', '/me');
      if (!_current(epoch)) return;
      final profile = Map<String, dynamic>.from(data['profile'] ?? {});
      privacyVersion = profile['consent_version'] as int? ?? 1;
      name = profile['display_name']?.toString() ?? '';
      preferences = Map<String, dynamic>.from(data['preferences'] ?? {});
      largerText = (preferences['text_scale'] as num? ?? 1) > 1;
      capabilities = Map<String, dynamic>.from(data['capabilities'] ?? {});
      onboarded =
          profile['onboarded'] == true || preferences['onboarded'] == true;
      await refreshPersonal();
    } catch (e) {
      if (!_current(epoch)) return;
      error = 'Could not load your account. ${cleanError(e)}';
    }
    if (!_current(epoch)) return;
    loading = false;
    notifyListeners();
  }

  static String cleanError(Object e) {
    if (e is AuthException) return e.message;
    if (e is AiraException) return e.message;
    return 'Please check your connection and try again.';
  }

  void setTab(int value) {
    tab = value;
    notifyListeners();
  }

  Future<void> setScale(bool large) {
    // Onboarding submits this choice with the rest of the profile. Preview
    // preferences remain local to the session.
    if (preview || !onboarded) {
      largerText = large;
      notifyListeners();
      return Future<void>.value();
    }
    return _queuePreference(() async {
      final epoch = sessionEpoch;
      // Keep the existing backend preference values; the theme defines the
      // compact/roomy typography and spacing represented by these two choices.
      final storedScale = large ? 1.25 : 1.0;
      cancelSend();
      final result = await api.request('PATCH', '/preferences', {
        'text_scale': storedScale,
      });
      if (!_current(epoch)) return;
      privacyVersion =
          result['profile']?['consent_version'] as int? ?? privacyVersion;
      largerText = large;
      preferences['text_scale'] = storedScale;
      pendingRequest = null;
      pendingText = null;
      notifyListeners();
    });
  }

  Future<void> finishOnboarding(
    String value,
    Map<String, dynamic> choices,
  ) async {
    final epoch = sessionEpoch;
    final proposedName = value.trim();
    if (!preview) {
      final result = await api.request('PATCH', '/preferences', {
        'display_name': proposedName,
        'locale': 'en',
        'timezone': 'Asia/Singapore',
        'onboarded': true,
        'text_scale': largerText ? 1.25 : 1,
        ...choices,
      });
      if (!_current(epoch)) return;
      privacyVersion =
          result['profile']?['consent_version'] as int? ?? privacyVersion;
    }
    name = proposedName;
    preferences.addAll(choices);
    onboarded = true;
    notifyListeners();
  }

  Future<void> _preferenceQueue = Future<void>.value();
  Future<void> updatePreference(String key, bool value) =>
      _queuePreference(() => _updatePreference(key, value));

  Future<void> _queuePreference(Future<void> Function() update) {
    final epoch = sessionEpoch;
    final task = _preferenceQueue.then((_) async {
      if (_current(epoch)) await update();
    });
    _preferenceQueue = task.catchError((Object _) {});
    return task;
  }

  Future<void> _updatePreference(String key, bool value) async {
    final epoch = sessionEpoch;
    cancelSend();
    if (!preview) {
      final result = await api.request('PATCH', '/preferences', {key: value});
      if (!_current(epoch)) return;
      privacyVersion =
          result['profile']?['consent_version'] as int? ?? privacyVersion;
    }
    preferences[key] = value;
    if (!value) {
      pendingEvents = [];
      if (key == 'memory_enabled') memories = [];
      if (key == 'mood_history') mood = '';
      if (key == 'social_reminders') plans = [];
      if (key == 'medication_reminders') medications = [];
      if (key == 'impact_measurement') {
        measurementPrompt = null;
        measurementResponse = null;
        lonelyDays = null;
      }
    }
    messages.clear();
    conversationId = activeCallId;
    pendingRequest = null;
    pendingText = null;
    notifyListeners();
  }

  Future<void> refreshPersonal() async {
    if (preview || client == null) return;
    final epoch = sessionEpoch;
    final version = privacyVersion;
    final result = await Future.wait([
      api.request('GET', '/memories'),
      api.request('GET', '/events/proposals'),
      api.request('GET', '/medications'),
    ]);
    if (!_current(epoch) || version != privacyVersion) return;
    memories = _items(result[0], 'memories');
    plans = _items(result[1], 'schedules');
    medications = _items(result[2], 'schedules');
    notifyListeners();
  }

  static List<Map<String, dynamic>> _items(
    Map<String, dynamic> data,
    String key,
  ) => (data[key] ?? data['items'] ?? [] as dynamic)
      .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
      .toList();
  Future<ChatTurn> send(
    String text, {
    String mode = 'text',
    Map<String, dynamic>? cueSummary,
    String? feeling,
  }) async {
    if (preview) {
      throw const AiraException(
        'Live AI is not connected in this preview. Your draft is kept.',
      );
    }
    if (sending) throw const AiraException('Please wait for AIRA to finish.');
    if (text.trim().isEmpty) {
      throw const AiraException('Please write a message first.');
    }
    sending = true;
    notifyListeners();
    final epoch = revision;
    final session = sessionEpoch;
    final id = pendingText == text && pendingRequest != null
        ? pendingRequest!
        : requestUuid();
    pendingText = text;
    pendingRequest = id;
    final context = messages
        .skip(max(0, messages.length - 10))
        .map((e) => {'role': e.fromAira ? 'assistant' : 'user', 'text': e.text})
        .toList();
    try {
      final result = await api.request('POST', '/messages', {
        'clientMessageId': id,
        'text': text.trim(),
        'mode': mode,
        if (conversationId.isNotEmpty) 'conversationId': conversationId,
        'context': context,
        'contextVersion': privacyVersion,
        if (cueSummary != null) 'cueSummary': cueSummary,
        if (feeling != null) 'selfReportedFeeling': feeling,
      });
      if (!_current(session) || epoch != revision) {
        throw const AiraException('This conversation has ended.');
      }
      if (result['text'] == null) {
        throw const AiraException(
          'That message is still processing or its reply has expired. Please retry shortly.',
        );
      }
      privacyVersion = result['privacyVersion'] as int? ?? privacyVersion;
      conversationId = result['conversationId']?.toString() ?? conversationId;
      final reply = ChatTurn(
        text:
            result['text']?.toString() ??
            'No reply was returned. Please try again.',
        fromAira: true,
        id: result['messageId']?.toString(),
        speechToken: result['speechToken']?.toString(),
      );
      messages.add(ChatTurn(text: text.trim(), fromAira: false, id: id));
      messages.add(reply);
      pendingText = null;
      pendingRequest = null;
      return reply;
    } finally {
      if (_current(session) && epoch == revision) {
        sending = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveMemory(String text) async {
    final epoch = sessionEpoch;
    if (!consent('memory_enabled')) {
      throw const AiraException(
        'Please enable saved memories in Settings first.',
      );
    }
    if (preview) {
      memories.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'user_approved_text': text,
      });
    } else {
      await api.request('POST', '/memories', {'text': text, 'confirmed': true});
      if (!_current(epoch)) return;
      await refreshPersonal();
    }
    if (_current(epoch)) notifyListeners();
  }

  Future<void> forgetMemory(Map<String, dynamic> memory) async {
    final epoch = sessionEpoch;
    cancelSend();
    if (!preview) {
      final result = await api.request('DELETE', '/memories/${memory['id']}');
      if (!_current(epoch)) return;
      privacyVersion = result['privacyVersion'] as int? ?? privacyVersion;
    }
    memories.removeWhere((e) => e['id'] == memory['id']);
    messages.clear();
    conversationId = '';
    notifyListeners();
  }

  Future<void> savePlan(String title, DateTime at) async {
    final epoch = sessionEpoch;
    if (!at.isAfter(DateTime.now()) ||
        at.isAfter(DateTime.now().add(const Duration(hours: 24)))) {
      throw const AiraException(
        'Choose a future time within the next 24 hours for this prototype.',
      );
    }
    if (!consent('social_reminders')) {
      throw const AiraException(
        'Please allow conversation invitations in Settings first.',
      );
    }
    final data = {
      'topic': title,
      'followupAt': at.toUtc().toIso8601String(),
      'timezone': 'Asia/Singapore',
      'confirmed': true,
      'channel': 'chat',
    };
    if (preview) {
      plans.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'topic': title,
        'followup_at': at.toIso8601String(),
        'status': 'confirmed',
      });
    } else {
      await api.request('POST', '/events/proposals', data);
      if (!_current(epoch)) return;
      await refreshPersonal();
    }
    if (_current(epoch)) notifyListeners();
  }

  Future<void> removePlan(String id) async {
    final epoch = sessionEpoch;
    if (!preview) await api.request('DELETE', '/events/$id');
    if (!_current(epoch)) return;
    plans.removeWhere((e) => e['id'] == id);
    notifyListeners();
  }

  Future<void> saveMedicine(
    String label,
    String instructions,
    TimeOfDay time,
  ) async {
    final epoch = sessionEpoch;
    if (!consent('medication_reminders')) {
      throw const AiraException(
        'Please enable medication reminders in Settings first.',
      );
    }
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (preview) {
      medications.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'label': label,
        'instructions': instructions,
        'local_time': clock,
      });
    } else {
      await api.request('POST', '/medications', {
        'label': label,
        'instructions': instructions,
        'localTime': clock,
        'timezone': 'Asia/Singapore',
        'confirmed': true,
        'sourceType': 'user_entered',
      });
      if (!_current(epoch)) return;
      await refreshPersonal();
    }
    if (_current(epoch)) notifyListeners();
  }

  Future<void> removeMedicine(String id) async {
    final epoch = sessionEpoch;
    if (!preview) await api.request('DELETE', '/medications/$id');
    if (!_current(epoch)) return;
    medications.removeWhere((e) => e['id'] == id);
    notifyListeners();
  }

  Future<void> loadMeasurementPrompt() async {
    if (preview) {
      final utc = DateTime.now().toUtc().add(const Duration(hours: 8));
      final end = DateTime.utc(
        utc.year,
        utc.month,
        utc.day,
      ).subtract(const Duration(days: 1));
      final start = end.subtract(const Duration(days: 6));
      measurementPrompt = {
        'id': 'preview',
        'period_start': start.toIso8601String().substring(0, 10),
        'period_end': end.toIso8601String().substring(0, 10),
        'timezone': 'Asia/Singapore',
      };
      return;
    }
    final epoch = sessionEpoch;
    final version = privacyVersion;
    final result = await api.request('GET', '/measurements/prompt');
    if (!_current(epoch) || version != privacyVersion) return;
    measurementPrompt = result['prompt'] == null
        ? null
        : Map<String, dynamic>.from(result['prompt']);
    measurementResponse = result['response'] == null
        ? null
        : Map<String, dynamic>.from(result['response']);
  }

  Future<void> saveLoneliness(int? days) async {
    final epoch = sessionEpoch;
    final version = privacyVersion;
    if (measurementPrompt == null) {
      throw const AiraException('Your next check-in is not available yet.');
    }
    if (!preview) {
      await api.request('POST', '/measurements/loneliness', {
        'promptId': measurementPrompt!['id'],
        'lonelyDays': days,
        'skipped': days == null,
        'expectedVersion': measurementResponse?['version'] ?? 0,
        'requestId': requestUuid(),
      });
      if (!_current(epoch) || version != privacyVersion) return;
      await loadMeasurementPrompt();
    }
    if (!_current(epoch) || version != privacyVersion) return;
    lonelyDays = days;
    notifyListeners();
  }

  Future<void> beginCall(String mode) async {
    cancelSend();
    messages.clear();
    pendingRequest = null;
    pendingText = null;
    conversationId = '';
    final epoch = revision;
    final session = sessionEpoch;
    if (!preview) {
      final service = api;
      final result = await service.request('POST', '/calls', {'mode': mode});
      final id = result['conversation']?['id']?.toString() ?? '';
      if (!_current(session) || epoch != revision) {
        if (_current(session) && id.isNotEmpty) {
          try {
            await service.request('POST', '/calls/$id/end', {});
          } catch (_) {}
        }
        return;
      }
      conversationId = id;
      activeCallId = id;
    }
    notifyListeners();
  }

  Future<void> endCall() async {
    cancelSend();
    final id = activeCallId;
    activeCallId = '';
    conversationId = '';
    pendingText = null;
    pendingRequest = null;
    if (!preview && id.isNotEmpty) {
      try {
        await api.request('POST', '/calls/$id/end', {});
      } catch (_) {
        /* Local capture must still end if the backend is unavailable. */
      }
    }
  }

  Future<void> pollEvents() async {
    if (preview || !signedIn) return;
    final epoch = revision;
    final result = await api.request('GET', '/events');
    if (_disposed || epoch != revision) return;
    pendingEvents = _items(result, 'events');
    notifyListeners();
  }

  Future<void> respondEvent(Map<String, dynamic> event, String action) async {
    final epoch = sessionEpoch;
    final medication = event['kind'] == 'medication';
    final result = await api.request(
      'POST',
      '/${medication ? 'medication-occurrences' : 'invitations'}/${event['id']}/respond',
      {
        'action': action,
        'requestId': requestUuid(),
        'expectedVersion': event['action_version'] ?? event['version'] ?? 1,
        if (action == 'snooze')
          'nextNotifyAt': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
      },
    );
    if (!_current(epoch)) return;
    if (action == 'accept') {
      cancelSend();
      messages.clear();
      conversationId = result['event']?['conversation_id']?.toString() ?? '';
      tab = 0;
    }
    await pollEvents();
  }

  Future<void> saveMood(String value) async {
    if (!consent('mood_history')) {
      throw const AiraException('Please enable saved mood in Settings first.');
    }
    final epoch = sessionEpoch;
    final version = privacyVersion;
    if (!preview) {
      await api.request('POST', '/measurements/mood', {'label': value});
    }
    if (!_current(epoch)) return;
    if (version != privacyVersion) return;
    mood = value;
    notifyListeners();
  }

  Future<void> deleteData() async {
    cancelSend();
    final epoch = sessionEpoch;
    if (!preview) await api.request('DELETE', '/me/data');
    if (!_current(epoch)) return;
    messages = [];
    memories = [];
    plans = [];
    medications = [];
    conversationId = '';
    lonelyDays = null;
    mood = '';
    await signOut();
  }

  Future<void> signOut() async {
    _signingOut = true;
    _identity = null;
    _clear();
    if (client != null) await client!.auth.signOut();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionEpoch++;
    revision++;
    _auth?.cancel();
    super.dispose();
  }
}
