import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// پشتیبانی از تم‌های تلگرام اندروید (.attheme)
///
/// فرمت فایل: هر خط `کلید=مقدار` (مقدار = عدد signed ARGB یا هگز #AARRGGBB / #RRGGBB).
/// بعد از خط `WPS` ممکنه عکس پس‌زمینه بیاد که تا `WPE` ادامه داره.
class AtTheme {
  final String name;
  final Map<String, Color> colors;
  final bool dark;
  final String? wallpaperPath;

  const AtTheme({
    required this.name,
    required this.colors,
    required this.dark,
    this.wallpaperPath,
  });

  /// تم فعال (null = تم پیش‌فرض اپ)
  static final ValueNotifier<AtTheme?> current = ValueNotifier<AtTheme?>(null);

  static const _kText = 'attheme_text';
  static const _kName = 'attheme_name';
  static const _wallFile = 'attheme_wallpaper.bin';

  // ------------------------------------------------------------ lookup

  /// اولین کلیدی که توی تم فعال وجود داشته باشه؛ اگه تم فعال نباشه null
  static Color? pick(List<String> keys) {
    final t = current.value;
    if (t == null) return null;
    for (final k in keys) {
      final c = t.colors[k];
      if (c != null) return c;
    }
    return null;
  }

  /// رنگ اصلی (accent) تم
  static Color? get accent => pick(const [
        'chats_actionBackground',
        'windowBackgroundWhiteBlueText',
        'windowBackgroundWhiteBlueText4',
        'featuredStickers_addButton',
        'chat_outSentCheckRead',
      ]);

  /// دکوراسیون پس‌زمینه‌ی چت (عکس والپیپر یا رنگ ساده)؛ بدون تم null
  static BoxDecoration? chatDecoration(Color fallback) {
    final t = current.value;
    if (t == null) return null;
    final wp = t.wallpaperPath;
    if (wp != null) {
      return BoxDecoration(
        color: fallback,
        image: DecorationImage(image: FileImage(File(wp)), fit: BoxFit.cover),
      );
    }
    return BoxDecoration(color: fallback);
  }

  // ------------------------------------------------------------ parsing

  static Color? _parseValue(String v) {
    v = v.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('#')) {
      final h = v.substring(1);
      final n = int.tryParse(h, radix: 16);
      if (n == null) return null;
      if (h.length == 6) return Color(0xFF000000 | n);
      if (h.length == 8) return Color(n & 0xFFFFFFFF);
      return null;
    }
    final n = int.tryParse(v);
    if (n == null) return null;
    return Color(n & 0xFFFFFFFF);
  }

  static int _indexOf(Uint8List b, List<int> pat, [int from = 0]) {
    for (var i = from; i <= b.length - pat.length; i++) {
      var ok = true;
      for (var j = 0; j < pat.length; j++) {
        if (b[i + j] != pat[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  static int _lastIndexOf(Uint8List b, List<int> pat) {
    for (var i = b.length - pat.length; i >= 0; i--) {
      var ok = true;
      for (var j = 0; j < pat.length; j++) {
        if (b[i + j] != pat[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  /// متن رنگ‌ها رو پارس می‌کنه. اگه هیچ رنگی پیدا نشه null برمی‌گردونه.
  static Map<String, Color>? parseColors(String text) {
    final out = <String, Color>{};
    final re = RegExp(r'^[A-Za-z0-9_]+$');
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      if (!re.hasMatch(key)) continue;
      final c = _parseValue(line.substring(eq + 1));
      if (c != null) out[key] = c;
    }
    return out.isEmpty ? null : out;
  }

  static bool _isDark(Map<String, Color> c) {
    final bg = c['windowBackgroundWhite'] ?? c['chat_wallpaper'] ?? c['actionBarDefault'] ?? Colors.white;
    return bg.computeLuminance() < 0.5;
  }

  // ------------------------------------------------------------ load / apply / remove

  /// موقع شروع اپ صدا زده میشه
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final text = p.getString(_kText);
      if (text == null) return;
      final colors = parseColors(text);
      if (colors == null) return;
      final wp = await _wallpaperFile();
      current.value = AtTheme(
        name: p.getString(_kName) ?? 'Custom theme',
        colors: colors,
        dark: _isDark(colors),
        wallpaperPath: await wp.exists() ? wp.path : null,
      );
    } catch (_) {}
  }

  static Future<File> _wallpaperFile() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/$_wallFile');
  }

  /// محتوای یه فایل .attheme رو اعمال و ذخیره می‌کنه. اگه فایل معتبر نباشه false.
  static Future<bool> applyBytes(Uint8List bytes, String fileName) async {
    try {
      final wps = utf8.encode('WPS\n');
      final wpe = utf8.encode('\nWPE\n');
      var textEnd = bytes.length;
      Uint8List? image;
      final i = _indexOf(bytes, wps);
      if (i >= 0 && (i == 0 || bytes[i - 1] == 10)) {
        textEnd = i;
        final start = i + wps.length;
        var end = _lastIndexOf(bytes, wpe);
        if (end < start) end = bytes.length;
        if (end > start) image = Uint8List.sublistView(bytes, start, end);
      }
      final text = utf8.decode(Uint8List.sublistView(bytes, 0, textEnd), allowMalformed: true);
      final colors = parseColors(text);
      if (colors == null) return false;

      final name = fileName.replaceAll(RegExp(r'\.attheme$', caseSensitive: false), '').trim();
      final wp = await _wallpaperFile();
      String? wpPath;
      if (image != null && image.length > 100 && image.length <= 12 * 1024 * 1024) {
        await wp.writeAsBytes(image, flush: true);
        wpPath = wp.path;
      } else if (await wp.exists()) {
        await wp.delete();
      }
      try {
        // کش عکس قبلی رو پاک کن تا والپیپر جدید نشون داده بشه
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}

      final p = await SharedPreferences.getInstance();
      await p.setString(_kText, text);
      await p.setString(_kName, name.isEmpty ? 'Custom theme' : name);

      current.value = AtTheme(
        name: name.isEmpty ? 'Custom theme' : name,
        colors: colors,
        dark: _isDark(colors),
        wallpaperPath: wpPath,
      );
      _rebuildAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// برگشت به تم پیش‌فرض
  static Future<void> remove() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kText);
      await p.remove(_kName);
      final wp = await _wallpaperFile();
      if (await wp.exists()) await wp.delete();
    } catch (_) {}
    current.value = null;
    _rebuildAll();
  }

  /// همه‌ی ویجت‌ها رو یک بار بازسازی می‌کنه تا رنگ‌های جدید (مثل tgBlue) همه‌جا اعمال بشن
  static void _rebuildAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}
