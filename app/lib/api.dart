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

class Account {
  final int id;
  final String username;
  final String token;
  Account({required this.id, required this.username, required this.token});

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'token': token};
  factory Account.fromJson(Map<String, dynamic> j) =>
      Account(id: j['id'] as int, username: j['username'] as String, token: j['token'] as String);
}

class Api {
  static String baseUrl = 'http://127.0.0.1:3001';
  static void Function()? onUnauthorized;
  static String? notice;
  static String storageStatus = 'ok';

  // ---- accounts (multi-account, saved on the phone) ----
  static List<Account> accounts = [];
  static Account? _active;
  static String? get token => _active?.token;
  static String? get username => _active?.username;
  static int? get userId => _active?.id;
  static bool get loggedIn => _active != null;

  static final _msgCtrl = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get messages => _msgCtrl.stream;
  static WebSocketChannel? _ws;
  static Timer? _retry;
  static bool _wsWanted = false;

  static Account? _find(int? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      baseUrl = p.getString('baseUrl') ?? baseUrl;
      final raw = p.getString('accounts');
      if (raw != null) {
        accounts = (json.decode(raw) as List)
            .map((e) => Account.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      _active = _find(p.getInt('activeId'));
      storageStatus = 'ok';
    } catch (e) {
      storageStatus = 'read error: $e';
    }
    if (_active == null && accounts.isNotEmpty) _active = accounts.first;
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ok1 = await p.setString('accounts', json.encode(accounts.map((a) => a.toJson()).toList()));
      final ok2 = _active != null ? await p.setInt('activeId', _active!.id) : await p.remove('activeId');
      if (!ok1 || !ok2) throw 'write returned false';
      storageStatus = 'ok';
    } catch (e) {
      storageStatus = 'write error: $e';
    }
  }

  static Future<void> setBaseUrl(String url) async {
    url = url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'http://$url';
    baseUrl = url;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('baseUrl', url);
    } catch (_) {}
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  // Server error messages are translated to English here.
  static String? _tr(dynamic e) {
    if (e is! String) return null;
    const map = {
      'نام کاربری باید': 'Username must be 3-32 characters: English letters, numbers or _',
      'رمز عبور حداقل': 'Password must be at least 6 characters',
      'قبلاً گرفته': 'This username is already taken',
      'نام کاربری و رمز عبور را وارد': 'Enter username and password',
      'اشتباه است': 'Wrong username or password',
      'تعداد تلاش': 'Too many attempts, try again in a few minutes',
      'کاربر پیدا نشد': 'User not found',
      'متن پیام': 'Invalid message text',
    };
    for (final k in map.keys) {
      if (e.contains(k)) return map[k];
    }
    return e;
  }

  static Future<dynamic> _req(String method, String path, {Map? body}) async {
    late http.Response r;
    try {
      final uri = Uri.parse('$baseUrl$path');
      if (method == 'GET') {
        r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      } else {
        r = await http
            .post(uri, headers: _headers, body: json.encode(body ?? {}))
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      throw ApiException(
          'Could not connect to the server ($baseUrl). Make sure the server is running and the address is correct.');
    }
    dynamic data;
    try {
      final text = utf8.decode(r.bodyBytes);
      data = text.isEmpty ? null : json.decode(text);
    } catch (_) {
      throw ApiException(
          'Unexpected response from $baseUrl (status ${r.statusCode}). Check the server address and port.');
    }
    if (r.statusCode == 401 && token != null) {
      notice = 'Session expired, please sign in again';
      await logout();
      onUnauthorized?.call();
      throw ApiException('Session expired, please sign in again');
    }
    if (r.statusCode >= 400) {
      throw ApiException(_tr(data is Map ? data['error'] : null) ?? 'Server error (${r.statusCode})');
    }
    return data;
  }

  /// Sign in / sign up. The account is added to the saved list and becomes active.
  static Future<void> auth(String path, String u, String p) async {
    final d = await _req('POST', path, body: {'username': u, 'password': p});
    late Account acc;
    try {
      acc = Account(
        id: d['user']['id'] as int,
        username: d['user']['username'] as String,
        token: d['token'] as String,
      );
    } catch (_) {
      throw ApiException('Unexpected response from $baseUrl. Is this the chat server?');
    }
    accounts.removeWhere((a) => a.id == acc.id);
    accounts.add(acc);
    _active = acc;
    await _save();
    try {
      connectWs();
    } catch (_) {}
  }

  /// Switch to another saved account (no password needed).
  static Future<void> switchTo(Account a) async {
    _active = a;
    await _save();
    try {
      connectWs();
    } catch (_) {}
  }

  /// Log out of the active account only. Other saved accounts stay.
  static Future<void> logout() async {
    final id = userId;
    accounts.removeWhere((a) => a.id == id);
    _closeWs();
    _active = accounts.isNotEmpty ? accounts.first : null;
    await _save();
    if (_active != null) {
      try {
        connectWs();
      } catch (_) {}
    }
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

  // ---- WebSocket (realtime messages) ----
  static void _closeWs() {
    _wsWanted = false;
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    try {
      ws?.sink.close();
    } catch (_) {}
  }

  static void connectWs() {
    if (token == null) return;
    _closeWs();
    _wsWanted = true;
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
