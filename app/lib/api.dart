import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
  String username;
  final String token;
  Account({required this.id, required this.username, required this.token});

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'token': token};
  factory Account.fromJson(Map<String, dynamic> j) =>
      Account(id: j['id'] as int, username: j['username'] as String, token: j['token'] as String);
}

class OfflineState {
  final bool noInternet; // true = اینترنت نیست، false = سرور جواب نمیده
  final DateTime since;
  OfflineState(this.noInternet, this.since);
}

/// برای لغو آپلود در حال انجام
class UploadCancel {
  bool cancelled = false;
  HttpClient? _client;
  void cancel() {
    cancelled = true;
    try {
      _client?.close(force: true);
    } catch (_) {}
  }
}

class Api {
  /// حداکثر حجم فایل: ۳۰ مگابایت (سرور هم همین‌قدر قبول میکنه)
  static const int maxFileBytes = 30 * 1024 * 1024;

  static String baseUrl = 'http://127.0.0.1:3001';
  static void Function()? onUnauthorized;
  static String? notice;
  static String storageStatus = 'ok';

  /// null = سرور در دسترسه؛ غیر از اون = آفلاین (صفحه‌ی Offline نشون داده میشه)
  static final ValueNotifier<OfflineState?> offline = ValueNotifier(null);
  static Timer? _mon;
  static bool _checking = false;
  static int _tick = 0;

  static bool get isLocalServer {
    try {
      final h = Uri.parse(baseUrl).host;
      return h == '127.0.0.1' || h == 'localhost' || h == '::1' || h == '[::1]';
    } catch (_) {
      return false;
    }
  }

  static int get serverPort {
    try {
      final u = Uri.parse(baseUrl);
      return u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
    } catch (_) {
      return 3001;
    }
  }

  /// هر ۴ ثانیه وقتی آفلاینیم (و هر ~۱۶ ثانیه وقتی آنلاینیم) سرور رو چک میکنه
  static void startMonitor() {
    _mon?.cancel();
    checkServer();
    _mon = Timer.periodic(const Duration(seconds: 4), (_) {
      if (offline.value != null || ++_tick % 4 == 0) checkServer();
    });
  }

  static void stopMonitor() {
    _mon?.cancel();
    _mon = null;
  }

  /// true = سرور جواب داد
  static Future<bool> checkServer() async {
    if (_checking) return offline.value == null;
    _checking = true;
    var up = false;
    var noNet = false;
    try {
      try {
        final r = await http.get(Uri.parse('$baseUrl/')).timeout(const Duration(seconds: 4));
        up = r.statusCode < 500;
      } catch (_) {}
      if (!up && !isLocalServer) {
        try {
          await InternetAddress.lookup('example.com').timeout(const Duration(seconds: 3));
        } catch (_) {
          noNet = true;
        }
      }
    } finally {
      _checking = false;
    }
    final cur = offline.value;
    if (up) {
      if (cur != null) {
        offline.value = null;
        if (loggedIn) {
          try {
            connectWs();
          } catch (_) {}
        }
      }
    } else if (cur == null) {
      offline.value = OfflineState(noNet, DateTime.now());
    } else if (cur.noInternet != noNet) {
      offline.value = OfflineState(noNet, cur.since);
    }
    return up;
  }

  /// حالت تم (روشن / تاریک / سیستم)
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  // ---- accounts (multi-account, saved on the phone) ----
  static List<Account> accounts = [];
  static Account? _active;
  static String? get token => _active?.token;
  static String? get username => _active?.username;
  static int? get userId => _active?.id;
  static bool get loggedIn => _active != null;

  /// پروفایل خودم (username, bio, avatar, ...)
  static Map<String, dynamic>? me;

  /// همه‌ی رویدادهای لحظه‌ای سرور: message, edit, delete, pin, read, user, hello
  static final _evCtrl = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get events => _evCtrl.stream;
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
      final t = p.getString('theme');
      if (t == 'dark') themeMode.value = ThemeMode.dark;
      if (t == 'light') themeMode.value = ThemeMode.light;
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

  static Future<void> setTheme(ThemeMode m) async {
    themeMode.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', m == ThemeMode.dark ? 'dark' : (m == ThemeMode.light ? 'light' : 'system'));
    } catch (_) {}
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

  static Future<dynamic> _req(String method, String path, {Map? body, int timeout = 10}) async {
    late http.Response r;
    try {
      final uri = Uri.parse('$baseUrl$path');
      final t = Duration(seconds: timeout);
      switch (method) {
        case 'GET':
          r = await http.get(uri, headers: _headers).timeout(t);
          break;
        case 'PUT':
          r = await http.put(uri, headers: _headers, body: json.encode(body ?? {})).timeout(t);
          break;
        case 'PATCH':
          r = await http.patch(uri, headers: _headers, body: json.encode(body ?? {})).timeout(t);
          break;
        case 'DELETE':
          r = await http.delete(uri, headers: _headers).timeout(t);
          break;
        default:
          r = await http.post(uri, headers: _headers, body: json.encode(body ?? {})).timeout(t);
      }
    } catch (_) {
      unawaited(checkServer());
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
    me = null;
    await _save();
    try {
      connectWs();
    } catch (_) {}
  }

  /// Switch to another saved account (no password needed).
  static Future<void> switchTo(Account a) async {
    _active = a;
    me = null;
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
    me = null;
    await _save();
    if (_active != null) {
      try {
        connectWs();
      } catch (_) {}
    }
  }

  static List<Map<String, dynamic>> _list(dynamic d) =>
      (d as List).map((e) => Map<String, dynamic>.from(e)).toList();

  static Map<String, dynamic> _map(dynamic d) => Map<String, dynamic>.from(d as Map);

  // ---- profile ----
  static Future<void> _applyMe(Map<String, dynamic> d) async {
    me = d;
    final a = _active;
    if (a != null && d['username'] is String && d['username'] != a.username) {
      a.username = d['username'] as String;
      await _save();
    }
  }

  /// برای اینکه تب پروفایل/تنظیمات بعد از ادمین شدن دوباره ساخته بشه
  static final ValueNotifier<int> meTick = ValueNotifier(0);
  static bool get isAdmin => me?['isAdmin'] == true;

  // ---- admin ----
  /// کد یک‌بارمصرف رو مصرف میکنه. خروجی: true = تازه ادمین شد، false = از قبل ادمین بود
  static Future<bool> redeemAdminCode(String code) async {
    final d = _map(await _req('POST', '/admin/redeem', body: {'code': code}));
    final u = d['user'];
    if (u is Map) {
      await _applyMe(Map<String, dynamic>.from(u));
      meTick.value++;
    }
    return d['alreadyAdmin'] != true;
  }

  static Future<List<Map<String, dynamic>>> adminUsers(String q) async =>
      _list(await _req('GET', '/admin/users?q=${Uri.encodeQueryComponent(q)}'));

  static Future<Map<String, dynamic>> adminCreateCode() async =>
      _map(await _req('POST', '/admin/codes'));

  static Future<List<Map<String, dynamic>>> adminCodes() async =>
      _list(await _req('GET', '/admin/codes'));

  static Future<void> adminDeleteCode(String id) async {
    await _req('DELETE', '/admin/codes/$id');
  }

  static Future<Map<String, dynamic>> adminSetAdmin(int userId, bool value) async =>
      _map(await _req('POST', '/admin/users/$userId/admin', body: {'isAdmin': value}));

  static Future<Map<String, dynamic>> refreshMe() async {
    final d = _map(await _req('GET', '/me'));
    await _applyMe(d);
    meTick.value++;
    return d;
  }

  static Future<Map<String, dynamic>> updateProfile({String? username, String? bio}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    final d = _map(await _req('PATCH', '/me', body: body));
    await _applyMe(d);
    return d;
  }

  /// اضافه کردن یک عکس به پروفایل (عکس جدید میشه عکس اصلی)
  static Future<Map<String, dynamic>> addPhoto(List<int> bytes) async {
    final d = _map(await _req('POST', '/me/photos', body: {'data': base64Encode(bytes)}, timeout: 40));
    await _applyMe(d);
    return d;
  }

  static Future<Map<String, dynamic>> deletePhoto(String id) async {
    final d = _map(await _req('DELETE', '/me/photos/$id'));
    await _applyMe(d);
    return d;
  }

  static Future<Map<String, dynamic>> setMainPhoto(String id) async {
    final d = _map(await _req('POST', '/me/photos/$id/main'));
    await _applyMe(d);
    return d;
  }

  /// گذاشتن آهنگِ یک پیام روی پروفایل خودم
  static Future<Map<String, dynamic>> setMusicFromMessage(int messageId) async {
    final d = _map(await _req('POST', '/me/music', body: {'messageId': messageId}, timeout: 40));
    await _applyMe(d);
    return d;
  }

  /// گذاشتن آهنگِ پروفایل یه کاربر دیگه روی پروفایل خودم
  static Future<Map<String, dynamic>> setMusicFromUser(int userId) async {
    final d = _map(await _req('POST', '/me/music', body: {'userId': userId}, timeout: 40));
    await _applyMe(d);
    return d;
  }

  /// آپلود مستقیم آهنگ از گوشی برای پروفایل
  static Future<Map<String, dynamic>> uploadMusic(
    String path,
    String name, {
    void Function(double)? onProgress,
  }) async {
    final d = await _postFile('/me/music/upload', path, name, onProgress: onProgress);
    await _applyMe(d);
    return d;
  }

  static Future<Map<String, dynamic>> removeMusic() async {
    final d = _map(await _req('DELETE', '/me/music'));
    await _applyMe(d);
    return d;
  }

  /// فایل‌هایی که من و این کاربر برای هم فرستادیم (جدیدترین اول)
  static Future<List<Map<String, dynamic>>> shared(int peer) async =>
      _list(await _req('GET', '/shared/$peer'));

  static Future<Map<String, dynamic>> user(int id) async => _map(await _req('GET', '/users/$id'));

  // ---- chats / messages ----
  static Future<List<Map<String, dynamic>>> chats() async => _list(await _req('GET', '/chats'));

  static Future<List<Map<String, dynamic>>> users(String q) async =>
      _list(await _req('GET', '/users?q=${Uri.encodeQueryComponent(q)}'));

  static Future<List<Map<String, dynamic>>> history(int peer) async =>
      _list(await _req('GET', '/messages/$peer'));

  static Future<Map<String, dynamic>> send(int peer, String text, {int? replyTo}) async =>
      _map(await _req('POST', '/messages/$peer', body: {'text': text, if (replyTo != null) 'replyTo': replyTo}));

  /// emoji = null → برداشتن ری‌اکشن خودم؛ دوباره زدن همون ایموجی هم برمیداره
  static Future<Map<String, dynamic>> reactMessage(int id, String? emoji) async =>
      _map(await _req('POST', '/message/$id/react', body: {'emoji': emoji}));

  static Future<Map<String, dynamic>> editMessage(int id, String text) async =>
      _map(await _req('PUT', '/message/$id', body: {'text': text}));

  /// everyone = true → برای هر دو طرف (فقط پیام‌های خودم)
  static Future<void> deleteMessage(int id, {required bool everyone}) async {
    await _req('DELETE', '/message/$id${everyone ? '?all=1' : ''}');
  }

  static Future<Map<String, dynamic>> pinMessage(int id, bool pinned) async =>
      _map(await _req('POST', '/message/$id/pin', body: {'pinned': pinned}));

  static Future<void> markRead(int peer) async {
    try {
      await _req('POST', '/read/$peer');
    } catch (_) {}
  }

  // ---- files ----
  /// آدرس مسیرهای عمومی (آواتار، کاور آهنگ)
  static String assetUrl(String rel) => '$baseUrl$rel';

  /// آدرس دانلود/استریم فایل پیام (با توکن؛ پلیر و عکس بدون هدر هم کار کنن)
  static String fileUrl(Map f) => '$baseUrl${f['url']}?token=${Uri.encodeQueryComponent(token ?? '')}';

  static Future<Directory> _filesDir() async {
    Directory base;
    try {
      base = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final d = Directory('${base.path}/chat_files');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _localName(Map msg) {
    final n = ((msg['file'] as Map)['name'] as String).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${msg['id']}_$n';
  }

  /// مسیر فایل دانلودشده (اگه قبلاً دانلود شده باشه)
  static Future<String?> localPath(Map msg) async {
    try {
      final d = await _filesDir();
      final file = File('${d.path}/${_localName(msg)}');
      final size = ((msg['file'] as Map)['size'] as num).toInt();
      if (await file.exists() && await file.length() == size) return file.path;
    } catch (_) {}
    return null;
  }

  static Future<String> downloadFile(Map msg, {void Function(double)? onProgress}) async {
    final f = msg['file'] as Map;
    final total = (f['size'] as num).toInt();
    final d = await _filesDir();
    final target = File('${d.path}/${_localName(msg)}');
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final rq = await client.getUrl(Uri.parse(fileUrl(f)));
      final resp = await rq.close();
      if (resp.statusCode == 404) throw ApiException('The file is no longer available');
      if (resp.statusCode != 200) throw ApiException('Download failed (${resp.statusCode})');
      sink = part.openWrite();
      var got = 0;
      await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return target.path;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Download failed. Check your connection to $baseUrl.');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// آپلود فایل (تا ۳۰ مگابایت) با درصد پیشرفت. بدنه‌ی درخواست خود فایله.
  static Future<Map<String, dynamic>> sendFile(
    int peer,
    String path,
    String name, {
    String caption = '',
    int? replyTo,
    void Function(double)? onProgress,
    UploadCancel? cancel,
    String? mediaKind, // 'voice' | 'round' | 'gif'
    int? durationMs,
    String? waveform, // base64
    String? thumb, // base64 JPEG ریز برای پیش‌نمایش
  }) =>
      _postFile('/messages/$peer/file', path, name,
          caption: caption,
          replyTo: replyTo,
          onProgress: onProgress,
          cancel: cancel,
          mediaKind: mediaKind,
          durationMs: durationMs,
          waveform: waveform,
          thumb: thumb);

  // ---- گیف‌های من ----
  static Future<List<Map<String, dynamic>>> gifs() async => _list(await _req('GET', '/me/gifs'));

  /// گیف یه پیام رو به گیف‌های من اضافه میکنه؛ true = تازه اضافه شد، false = از قبل بود
  static Future<bool> addGif(int messageId) async {
    final r = _map(await _req('POST', '/me/gifs', body: {'messageId': messageId}));
    return r['added'] == true;
  }

  static Future<void> deleteGif(String id) async => _req('DELETE', '/me/gifs/$id');

  static Future<Map<String, dynamic>> sendGif(int peer, String gifId, {int? replyTo}) async =>
      _map(await _req('POST', '/messages/$peer/gif', body: {'gifId': gifId, if (replyTo != null) 'replyTo': replyTo}));

  static Future<Map<String, dynamic>> _postFile(
    String urlPath,
    String path,
    String name, {
    String caption = '',
    int? replyTo,
    void Function(double)? onProgress,
    UploadCancel? cancel,
    String? mediaKind,
    int? durationMs,
    String? waveform,
    String? thumb,
  }) async {
    if (cancel?.cancelled == true) throw ApiException('Upload cancelled');
    final file = File(path);
    final len = await file.length();
    if (len == 0) throw ApiException('The file is empty');
    if (len > maxFileBytes) throw ApiException('File is too large (max 30 MB)');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    cancel?._client = client;
    try {
      final rq = await client.postUrl(Uri.parse('$baseUrl$urlPath'));
      rq.headers.set('Authorization', 'Bearer $token');
      rq.headers.set('Content-Type', 'application/octet-stream');
      rq.headers.set('x-file-name', Uri.encodeComponent(name.length > 150 ? name.substring(name.length - 150) : name));
      if (caption.isNotEmpty) rq.headers.set('x-caption', Uri.encodeComponent(caption));
      if (replyTo != null) rq.headers.set('x-reply-to', replyTo.toString());
      if (mediaKind != null) rq.headers.set('x-media-kind', mediaKind);
      if (durationMs != null) rq.headers.set('x-duration', durationMs.toString());
      if (waveform != null && waveform.isNotEmpty) rq.headers.set('x-waveform', waveform);
      if (thumb != null && thumb.isNotEmpty) rq.headers.set('x-thumb', thumb);
      rq.contentLength = len;
      var sent = 0;
      await for (final chunk in file.openRead()) {
        rq.add(chunk);
        await rq.flush();
        sent += chunk.length;
        onProgress?.call(sent / len);
      }
      final resp = await rq.close().timeout(const Duration(minutes: 3));
      final text = await resp.transform(utf8.decoder).join();
      dynamic data;
      try {
        data = text.isEmpty ? null : json.decode(text);
      } catch (_) {
        throw ApiException('Unexpected response from $baseUrl (status ${resp.statusCode}).');
      }
      if (resp.statusCode == 401) {
        notice = 'Session expired, please sign in again';
        await logout();
        onUnauthorized?.call();
        throw ApiException('Session expired, please sign in again');
      }
      if (resp.statusCode >= 400) {
        throw ApiException(_tr(data is Map ? data['error'] : null) ?? 'Server error (${resp.statusCode})');
      }
      return _map(data);
    } on ApiException {
      rethrow;
    } catch (_) {
      if (cancel?.cancelled == true) throw ApiException('Upload cancelled');
      throw ApiException('Upload failed. Check your connection to $baseUrl.');
    } finally {
      client.close(force: true);
    }
  }

  // ---- WebSocket (realtime) ----
  static void _closeWs() {
    _wsWanted = false;
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    try {
      ws?.sink.close();
    } catch (_) {}
  }

  /// وقتی اپ میره بک‌گراند صدا زده میشه (برای درست شدن «آخرین بازدید»)
  static void disconnectWs() => _closeWs();

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
            if (m is Map && m['type'] is String) {
              _evCtrl.add(Map<String, dynamic>.from(m));
            }
          } catch (_) {}
        },
        onDone: () {
          unawaited(checkServer());
          _scheduleRetry(ch);
        },
        onError: (_) {
          unawaited(checkServer());
          _scheduleRetry(ch);
        },
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
