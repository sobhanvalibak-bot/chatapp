import 'package:flutter/material.dart';

import 'api.dart';

const tgBlue = Color(0xFF3390EC);

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
  Color get chatBg => dark ? const Color(0xFF0E1621) : const Color(0xFFE7EBF0);
  Color get bubbleMine => dark ? const Color(0xFF2B5278) : const Color(0xFFEFFDDE);
  Color get bubbleOther => dark ? const Color(0xFF182533) : Colors.white;
  Color get fieldFill => dark ? const Color(0xFF242F3D) : const Color(0xFFF1F3F5);
  Color get barBg => dark ? const Color(0xFF17212B) : Colors.white;
  Color get subText => dark ? const Color(0xFF7F91A4) : Colors.grey;
  Color get metaMine => dark ? const Color(0xFF7DA8D3) : const Color(0xFF5DAE55);
  Color get metaOther => dark ? const Color(0xFF7F91A4) : Colors.grey;
  Color get tickRead => dark ? const Color(0xFF6AB3F3) : const Color(0xFF3390EC);
  Color get mainText => dark ? Colors.white : Colors.black;
  Color get cardBg => dark ? const Color(0xFF17212B) : Colors.white;
}

/// جهت متن را از اولین حرف معنادار تشخیص می‌دهد (فارسی/عربی → راست‌به‌چپ)
TextDirection dirOf(String s) {
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
        name = (u['username'] as String?) ?? '?',
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

/// متن کوتاه یک پیام برای لیست گفتگوها / بنر پین
String msgPreview(Map m) {
  final text = ((m['text'] as String?) ?? '').trim();
  final f = fileOf(m);
  if (f == null) return text;
  String label;
  switch (f['kind']) {
    case 'audio':
      final a = audioArtist(m);
      label = '🎵 ${a != null ? '$a - ' : ''}${audioTitle(m)}';
      break;
    case 'image':
      label = '🖼 Photo';
      break;
    case 'video':
      label = '🎬 Video';
      break;
    default:
      label = '📎 ${f['name']}';
  }
  return text.isEmpty ? label : '$label  $text';
}
