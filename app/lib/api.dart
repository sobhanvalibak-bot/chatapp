import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static String baseUrl = 'http://127.0.0.1:3000';
  static String? token;
  static String? username;
  static int? userId;
  static void Function()? onUnauthorized;

  static final _msgCtrl = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get messages => _msgCtrl.stream;
  static WebSocketChannel? _ws;
  static Timer? _retry;
  static bool _wsWanted = false;

  static bool get loggedIn => token != null;

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? baseUrl;
    token = p.getString('token');
    username = p.getString('username');
    userId = p.getInt('userId');
  }

  static Future<void> setBaseUrl(String url) async {
    url = url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'http://$url';
    baseUrl = url;
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', url);
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> _req(String method, String path, {Map? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      late http.Response r;
      if (method == 'GET') {
        r = await http.get(uri, headers: _headers);
      } else {
        r = await http.post(uri, headers: _headers, body: json.encode(body ?? {}));
      }
      final text = utf8.decode(r.bodyBytes);
      final data = text.isEmpty ? null : json.decode(text);
      if (r.statusCode == 401 && token != null) {
        await logout();
        onUnauthorized?.call();
        throw ApiException('نشست شما منقضی شده، دوباره وارد شوید');
      }
      if (r.statusCode >= 400) {
        throw ApiException((data is Map ? data['error'] : null) ?? 'خطای سرور (${r.statusCode})');
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('اتصال به سرور برقرار نشد. آدرس سرور را بررسی کنید.');
    }
  }

  static Future<void> auth(String path, String u, String p) async {
    final d = await _req('POST', path, body: {'username': u, 'password': p});
    token = d['token'];
    username = d['user']['username'];
    userId = d['user']['id'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    await prefs.setString('username', username!);
    await prefs.setInt('userId', userId!);
    connectWs();
  }

  static Future<void> logout() async {
    _wsWanted = false;
    _retry?.cancel();
    _ws?.sink.close();
    _ws = null;
    token = null;
    username = null;
    userId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('username');
    await p.remove('userId');
  }

  static List<Map<String, dynamic>> _list(dynamic d) =>
      (d as List).map((e) => Map<String, dynamic>.from(e)).toList();

  static Future<List<Map<String, dynamic>>> chats() async => _list(await _req('GET', '/chats'));

  static Future<List<Map<String, dynamic>>> users(String q) async =>
      _list(await _req('GET', '/users?q=${Uri.encodeQueryComponent(q)}'));

  static Future<List<Map<String, dynamic>>> history(int peer) async =>
      _list(await _req('GET', '/messages/$peer'));

  static Future<Map<String, dynamic>> send(int peer, String text) async =>
      Map<String, dynamic>.from(await _req('POST', '/messages/$peer', body: {'text': text}));

  static Future<void> markRead(int peer) async {
    try {
      await _req('POST', '/read/$peer');
    } catch (_) {}
  }

  // ---- WebSocket (دریافت لحظه‌ای پیام) ----
  static void connectWs() {
    if (token == null) return;
    _wsWanted = true;
    _retry?.cancel();
    _ws?.sink.close();
    final wsUrl = '${baseUrl.replaceFirst('http', 'ws')}/ws?token=$token';
    try {
      final ch = WebSocketChannel.connect(Uri.parse(wsUrl));
      _ws = ch;
      ch.stream.listen(
        (e) {
          try {
            final m = json.decode(e as String);
            if (m['type'] == 'message') {
              _msgCtrl.add(Map<String, dynamic>.from(m['message']));
            }
          } catch (_) {}
        },
        onDone: () => _scheduleRetry(ch),
        onError: (_) => _scheduleRetry(ch),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry(null);
    }
  }

  static void _scheduleRetry(WebSocketChannel? ch) {
    if (!_wsWanted) return;
    if (ch != null && !identical(ch, _ws)) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), connectWs);
  }
}
