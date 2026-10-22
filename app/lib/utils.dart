import 'package:flutter/material.dart';

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

class Avatar extends StatelessWidget {
  final int id;
  final String name;
  final double size;
  const Avatar({super.key, required this.id, required this.name, this.size = 54});

  @override
  Widget build(BuildContext context) {
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
}
