import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AiraApi {
  final SupabaseClient client;
  AiraApi(this.client);
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? data]) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) throw const AiraException('Please sign in to continue.');
    final req = http.Request(
        method,
        Uri.parse(
            '${const String.fromEnvironment('SUPABASE_URL')}/functions/v1/aira-api/v1$path'));
    req.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'apikey': const String.fromEnvironment('SUPABASE_ANON_KEY')
    });
    if (data != null) req.body = jsonEncode(data);
    final response = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 60)));
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : {'items': decoded};
    } catch (_) {
      throw const AiraException(
          'The service is unavailable. Please try again.');
    }
    if (response.statusCode >= 400) {
      throw AiraException(body['message']?.toString() ??
          body['error']?.toString() ??
          'Could not complete that request. Please try again.');
    }
    return body;
  }

  Future<Map<String, dynamic>> transcribe(Uint8List bytes, String mime) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) {
      throw const AiraException('Please sign in to use voice.');
    }
    return request('POST', '/audio/transcriptions', {
      'audioBase64': base64Encode(bytes),
      'mimeType': mime.split(';').first.trim(),
      'locale': 'en'
    });
  }

  Future<Uint8List> speech(String token) async {
    final body = await request('POST', '/speech', {'speechToken': token});
    return base64Decode(body['audioBase64'] as String);
  }
}

class AiraException implements Exception {
  final String message;
  const AiraException(this.message);
  @override
  String toString() => message;
}
