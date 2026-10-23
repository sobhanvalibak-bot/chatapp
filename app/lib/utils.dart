import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'api.dart';
import 'attheme.dart';
import 'ce_text.dart';

const _tgBlueDefault = Color(0xFF3390EC);

/// رنگ اصلی اپ؛ اگه تم .attheme فعال باشه از اون گرفته میشه
Color get tgBlue => AtTheme.accent ?? _tgBlueDefault;

const _avatarColors = [
  Color(0xFFE17076),
  Color(0xFFFAA774),
  Color(0xFFA695E7),
  Color(0xFF7BC862),
  Color(0xFF6EC9CB),
  Color(0xFF65AADD),
  Color(0xFFEE7AAE),
];

Color avatarColor(int id) => _avatarColors[id % _avatarColors.length];

/// رنگ‌های سازگار با حالت روشن/تاریک
extension Pal on BuildContext {
  bool get dark => Theme.of(this).brightness == Brightness.dark;

  /// اولین کلید موجود از تم .attheme، وگرنه رنگ پیش‌فرض روشن/تاریک
  Color _p(List<String> keys, Color light, Color dk) {
    final d = dark; // وابستگی به Theme تا با تغییر تم بازسازی بشه
    return AtTheme.pick(keys) ?? (d ? dk : light);
  }

  Color get chatBg =>
      _p(const ['chat_wallpaper', 'windowBackgroundGray'], const Color(0xFFE7EBF0), const Color(0xFF0E1621));
  Color get bubbleMine => _p(const ['chat_outBubble'], const Color(0xFFEFFDDE), const Color(0xFF2B5278));
  Color get bubbleOther => _p(const ['chat_inBubble'], Colors.white, const Color(0xFF182533));
  Color get fieldFill => _p(const ['chat_messagePanelBackground', 'windowBackgroundGray'],
      const Color(0xFFF1F3F5), const Color(0xFF242F3D));
  Color get barBg => _p(const ['actionBarDefault', 'windowBackgroundWhite'], Colors.white, const Color(0xFF17212B));
  Color get subText => _p(
      const ['windowBackgroundWhiteGrayText', 'windowBackgroundWhiteGrayText2', 'chat_inTimeText'],
      Colors.grey,
      const Color(0xFF7F91A4));
  Color get metaMine => _p(const ['chat_outTimeText'], const Color(0xFF5DAE55), const Color(0xFF7DA8D3));
  Color get metaOther => _p(const ['chat_inTimeText'], Colors.grey, const Color(0xFF7F91A4));
  Color get tickRead =>
      _p(const ['chat_outSentCheckRead', 'chat_outSentCheck'], const Color(0xFF3390EC), const Color(0xFF6AB3F3));
  Color get mainText => _p(const ['windowBackgroundWhiteBlackText'], Colors.black, Colors.white);
  Color get cardBg => _p(const ['windowBackgroundWhite'], Colors.white, const Color(0xFF17212B));

  /// رنگ متن داخل حباب‌ها (فقط وقتی تم سفارشی فعاله، وگرنه null = پیش‌فرض)
  Color? get msgTextIn => AtTheme.pick(const ['chat_messageTextIn']);
  Color? get msgTextOut => AtTheme.pick(const ['chat_messageTextOut']);
}

/// جهت متن را از اولین حرف معنادار تشخیص می‌دهد (فارسی/عربی → راست‌به‌چپ)
TextDirection dirOf(String s) {
  // توکن ایموجی کاستوم حرف لاتین داره؛ نباید روی تشخیص جهت اثر بذاره
  if (s.contains('\u2063')) s = s.replaceAll(ceRe, '');
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

String _two(int n) => n.toString().padLeft(2, '0');

String fmtHm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return fmtHm(ms);
  }
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (diff < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
  return '${d.year}/${_two(d.month)}/${_two(d.day)}';
}

/// «online» یا «last seen ...»
String presenceText(Map<String, dynamic> u) {
  if (u['online'] == true) return 'online';
  final ms = (u['lastSeen'] as num?)?.toInt() ?? 0;
  if (ms <= 0) return 'last seen a long time ago';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inSeconds < 60) return 'last seen just now';
  if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'last seen today at ${fmtHm(ms)}';
  if (days == 1) return 'last seen yesterday at ${fmtHm(ms)}';
  return 'last seen ${d.year}/${_two(d.month)}/${_two(d.day)}';
}

class Avatar extends StatelessWidget {
  final int id;
  final String name;
  final double size;
  final String? url;
  final bool online;
  const Avatar({
    super.key,
    required this.id,
    required this.name,
    this.size = 54,
    this.url,
    this.online = false,
  });

  /// از روی map کاربر (id, username, avatar, online)
  Avatar.fromUser(Map<String, dynamic> u, {super.key, this.size = 54, bool showOnline = false})
      : id = (u['id'] as num?)?.toInt() ?? 0,
        name = displayNameOf(u),
        url = u['avatar'] as String?,
        online = showOnline && u['online'] == true;

  Widget _letter() {
    final c = avatarColor(id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(c, Colors.white, 0.25)!, c],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget base;
    final u = url;
    if (u == null || u.isEmpty) {
      base = _letter();
    } else {
      base = ClipOval(
        child: Image.network(
          '${Api.baseUrl}$u',
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _letter(),
          loadingBuilder: (_, child, p) => p == null ? child : _letter(),
        ),
      );
    }
    if (!online) return base;
    final dot = size * 0.26;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: const Color(0xFF4CD964),
                shape: BoxShape.circle,
                border: Border.all(color: context.cardBg, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// فایل و آهنگ
// ---------------------------------------------------------------------------

String fmtSize(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}

Map<String, dynamic>? fileOf(Map m) => m['file'] is Map ? Map<String, dynamic>.from(m['file'] as Map) : null;

String fileKind(Map m) => (fileOf(m)?['kind'] as String?) ?? '';

Map<String, dynamic> audioMeta(Map m) {
  final f = fileOf(m);
  final md = f?['meta'];
  return md is Map ? Map<String, dynamic>.from(md) : <String, dynamic>{};
}

String audioTitle(Map m) {
  final t = audioMeta(m)['title'];
  if (t is String && t.trim().isNotEmpty) return t.trim();
  final n = (fileOf(m)?['name'] as String?) ?? 'Audio';
  final dot = n.lastIndexOf('.');
  return dot > 0 ? n.substring(0, dot) : n;
}

String? audioArtist(Map m) {
  final a = audioMeta(m)['artist'];
  return (a is String && a.trim().isNotEmpty) ? a.trim() : null;
}

Duration? audioDuration(Map m) {
  final d = audioMeta(m)['duration'];
  return d is num && d > 0 ? Duration(milliseconds: d.toInt()) : null;
}

/// گیف؟ (ویدیوی بی‌صدا یا فایل image/gif)
bool isGifMsg(Map m) {
  final f = fileOf(m);
  if (f == null) return false;
  return f['kind'] == 'gif' || (f['kind'] == 'image' && f['mime'] == 'image/gif');
}

final Map<String, Uint8List> _thumbCache = {};

/// پیش‌نمایش ریزِ عکس/ویدیو/گیف به اندازه‌ی یه ایموجی (برای لیست گفتگوها).
/// برای ویدیو همون فریم اول رو نشون میده. اگه چیزی برای نمایش نباشه null برمیگردونه.
Widget? previewThumb(Map m, {double size = 20}) {
  final f = fileOf(m);
  if (f == null) return null;
  final kind = f['kind'];
  if (kind != 'image' && kind != 'video' && kind != 'gif') return null;
  Widget? img;
  final t = f['thumb'];
  if (t is String && t.isNotEmpty) {
    try {
      final bytes = _thumbCache.putIfAbsent(t, () => base64Decode(t));
      if (_thumbCache.length > 300) _thumbCache.remove(_thumbCache.keys.first);
      img = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    } catch (_) {}
  }
  // پیام‌های قدیمی (بدون thumb): عکس‌های کوچیک رو از سرور میگیره
  if (img == null && kind == 'image' && ((f['size'] as num?) ?? 0) <= 5 * 1024 * 1024) {
    img = Image.network(
      Api.fileUrl(f),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
  if (img == null) return null;
  final play = kind != 'image';
  return ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          img,
          if (play)
            Center(
              child: Container(
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                padding: EdgeInsets.all(size * 0.08),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.5),
              ),
            ),
        ],
      ),
    ),
  );
}

/// متن کوتاه یک پیام برای لیست گفتگوها / بنر پین
/// icon=false → برای عکس/ویدیو/گیف فقط اسم («Photo») بدون ایموجی
String msgPreview(Map m, {bool icon = true}) {
  final text = stripCe(((m['text'] as String?) ?? '').trim());
  final f = fileOf(m);
  if (f == null) return text;
  String label;
  switch (f['kind']) {
    case 'audio':
      final a = audioArtist(m);
      label = '🎵 ${a != null ? '$a - ' : ''}${audioTitle(m)}';
      break;
    case 'voice':
      final d = audioDuration(m);
      label = '🎤 Voice message${d == null ? '' : ' (${fmtDur(d)})'}';
      break;
    case 'round':
      label = '📹 Video message';
      break;
    case 'image':
      label = f['mime'] == 'image/gif' ? '${icon ? '🎞 ' : ''}GIF' : '${icon ? '🖼 ' : ''}Photo';
      break;
    case 'video':
      label = '${icon ? '🎬 ' : ''}Video';
      break;
    case 'gif':
      label = '${icon ? '🎞 ' : ''}GIF';
      break;
    default:
      label = '📎 ${f['name']}';
  }
  return text.isEmpty ? label : '$label  $text';
}

// ---------------------------------------------------------------------------
// عکس‌ها و آهنگ پروفایل
// ---------------------------------------------------------------------------

/// عکس‌های پروفایل یک کاربر: [{id, url}] (اولی = عکس اصلی)
List<Map<String, dynamic>> userPhotos(Map u) {
  final p = u['photos'];
  if (p is List && p.isNotEmpty) {
    return p.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  final a = u['avatar'];
  if (a is String && a.isNotEmpty) return [{'id': 'main', 'url': a}];
  return [];
}

/// آهنگ پروفایل رو شبیه یه «پیام آهنگ» درمیاره تا با همون پلیر پخش بشه
Map<String, dynamic>? profileMusicMsg(Map u) {
  final m = u['music'];
  if (m is! Map) return null;
  return {
    'id': 'pm_${u['id']}',
    'from': u['id'],
    'to': u['id'],
    'text': '',
    'file': Map<String, dynamic>.from(m),
  };
}


/// اسم نمایشی: اسم + فامیلی؛ اگه نبود یوزرنیم
String displayNameOf(Map u, {String? fallback}) {
  final f = ((u['firstName'] as String?) ?? '').trim();
  final l = ((u['lastName'] as String?) ?? '').trim();
  final full = '$f $l'.trim();
  if (full.isNotEmpty) return full;
  return (u['username'] as String?) ?? fallback ?? '?';
}


/// آواتار «Saved Messages»: دایره‌ی آبی با آیکن بوکمارک
class SavedAvatar extends StatelessWidget {
  final double size;
  const SavedAvatar({super.key, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF59B5F5), Color(0xFF2E8EE0)],
        ),
      ),
      child: Icon(CupertinoIcons.bookmark_fill, color: Colors.white, size: size * 0.46),
    );
  }
}
