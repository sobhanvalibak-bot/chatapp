import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import 'api.dart';
import 'ce_text.dart';
import 'custom_emoji.dart';
import 'gif_widgets.dart';
import 'utils.dart';

// ---------------------------------------------------------------------------
// ذخیره‌ی لیست ایموجی‌های متحرک (Lottie) که ادمین‌ها اضافه کردن
// ---------------------------------------------------------------------------
class LottieStore {
  LottieStore._();

  /// هر بار لیست عوض بشه یکی زیاد میشه (برای rebuild)
  static final ValueNotifier<int> tick = ValueNotifier(0);

  static List<Map<String, dynamic>> items = [];
  static bool loaded = false;

  static final Map<String, Map<String, dynamic>> _byKey = {};
  static final Map<String, Future<LottieComposition?>> _comps = {};
  static RegExp? _re;
  static String? _base;
  static StreamSubscription? _sub;
  static bool _loading = false;

  /// FE0F (انتخاب‌گر ایموجی) رو برمیداره تا ❤ و ❤️ یکی حساب بشن
  static String norm(String e) => e.replaceAll('\uFE0F', '');

  static bool get hasAny => _re != null;

  static Map<String, dynamic>? forEmoji(String e) => _byKey[norm(e)];

  /// همه‌ی ایموجی‌هایی از متن که لاتی دارن
  static List<RegExpMatch> matches(String text) {
    final re = _re;
    if (re == null || text.isEmpty) return const [];
    return re.allMatches(text).toList();
  }

  /// اگه متن فقط (تا ۳ تا) ایموجیِ لاتی‌دار باشه، آیتم‌هاشون رو برمیگردونه؛ وگرنه null
  static List<Map<String, dynamic>>? emojiOnly(String text) {
    final ms = matches(text);
    if (ms.isEmpty || ms.length > 3) return null;
    var rest = text;
    for (final m in ms.reversed) {
      rest = rest.replaceRange(m.start, m.end, '');
    }
    if (rest.trim().isNotEmpty) return null;
    final out = <Map<String, dynamic>>[];
    for (final m in ms) {
      final it = forEmoji(m.group(0)!);
      if (it != null) out.add(it);
    }
    return out.isEmpty ? null : out;
  }

  static void _ensureSub() {
    _sub ??= Api.events.listen((e) {
      final t = e['type'];
      if (t == 'lotties' || t == 'hello') load();
    });
  }

  static Future<void> load() async {
    _ensureSub();
    if (!Api.loggedIn) return;
    if (_base != Api.baseUrl) {
      _base = Api.baseUrl;
      items = [];
      _byKey.clear();
      _comps.clear();
      _re = null;
      loaded = false;
    }
    if (_loading) return;
    _loading = true;
    try {
      final l = await Api.lotties();
      items = l;
      _byKey.clear();
      for (final it in l) {
        _byKey[norm(it['emoji'] as String)] = it;
      }
      final ids = {for (final it in l) it['id'] as String};
      _comps.removeWhere((k, _) => !ids.contains(k));
      _re = _build(_byKey.keys);
      loaded = true;
      tick.value++;
    } catch (_) {
      // بی‌صدا؛ دفعه‌ی بعد دوباره تلاش میشه
    } finally {
      _loading = false;
    }
  }

  static RegExp? _build(Iterable<String> keys) {
    final list = keys.where((k) => k.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (list.isEmpty) return null;
    final parts = <String>[];
    for (final k in list) {
      final b = StringBuffer();
      for (final r in k.runes) {
        b.write(RegExp.escape(String.fromCharCode(r)));
        b.write(r'\uFE0F?');
      }
      parts.add(b.toString());
    }
    // اگه بعد از ایموجی رنگ پوست یا ZWJ بود (ایموجیِ ترکیبیِ دیگه)، جایگزینش نکن
    return RegExp('(?:${parts.join('|')})' r'(?!\uD83C[\uDFFB-\uDFFF]|\u200D)');
  }

  /// انیمیشن یک بار دانلود و نگه داشته میشه تا همه‌ی ویجت‌ها ازش استفاده کنن
  static Future<LottieComposition?> composition(String id) {
    return _comps.putIfAbsent(id, () async {
      try {
        final bytes = await Api.lottieBytes(id);
        return await LottieComposition.fromBytes(bytes);
      } catch (_) {
        _comps.remove(id); // دفعه‌ی بعد دوباره تلاش کنه
        return null;
      }
    });
  }
}

// ---------------------------------------------------------------------------
// خود ایموجی متحرک
// ---------------------------------------------------------------------------
class AnimatedEmoji extends StatefulWidget {
  final Map<String, dynamic> item;
  final double size;
  final bool animate;
  const AnimatedEmoji({super.key, required this.item, this.size = 28, this.animate = true});

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> {
  late Future<LottieComposition?> _f;

  @override
  void initState() {
    super.initState();
    _f = LottieStore.composition(widget.item['id'] as String);
  }

  @override
  void didUpdateWidget(covariant AnimatedEmoji old) {
    super.didUpdateWidget(old);
    if (old.item['id'] != widget.item['id']) {
      _f = LottieStore.composition(widget.item['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return FutureBuilder<LottieComposition?>(
      future: _f,
      builder: (_, snap) {
        final c = snap.data;
        if (c == null) {
          // تا لود بشه (یا اگه نشد) همون ایموجی معمولی
          return SizedBox(
            width: size,
            height: size,
            child: Center(child: Text(widget.item['emoji'] as String, style: TextStyle(fontSize: size * 0.78))),
          );
        }
        return SizedBox(
          width: size,
          height: size,
          child: Lottie(
            composition: c,
            width: size,
            height: size,
            fit: BoxFit.contain,
            repeat: widget.animate,
            animate: widget.animate,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// متن پیام: ایموجی‌های لاتی‌دار جایگزین میشن
// ---------------------------------------------------------------------------

/// یک تکه از متن که باید جاش ویجت بیاد: ایموجی لاتی‌دار، ایموجی کاستوم یا لینک پک
class _Seg {
  final int start;
  final int end;
  final Map<String, dynamic>? lottie;
  final String? ceId;
  final String? packId;
  const _Seg(this.start, this.end, {this.lottie, this.ceId, this.packId});
  bool get isEmoji => lottie != null || ceId != null;
}

List<_Seg> _segments(String text, {bool links = false}) {
  if (text.isEmpty) return const [];
  final all = <_Seg>[];
  if (text.contains('\u2063')) {
    for (final m in ceRe.allMatches(text)) {
      all.add(_Seg(m.start, m.end, ceId: m.group(1)));
    }
  }
  for (final m in LottieStore.matches(text)) {
    final it = LottieStore.forEmoji(m.group(0)!);
    if (it != null) all.add(_Seg(m.start, m.end, lottie: it));
  }
  if (links && text.contains('chatapp://')) {
    for (final m in packLinkRe.allMatches(text)) {
      all.add(_Seg(m.start, m.end, packId: m.group(1)));
    }
  }
  if (all.isEmpty) return const [];
  all.sort((a, b) => a.start.compareTo(b.start));
  final out = <_Seg>[];
  var last = 0;
  for (final sg in all) {
    if (sg.start < last) continue; // همپوشانی
    out.add(sg);
    last = sg.end;
  }
  return out;
}

Widget _emojiWidget(_Seg s, double size) =>
    s.lottie != null ? AnimatedEmoji(item: s.lottie!, size: size) : CustomEmoji(id: s.ceId!, size: size);

/// اگه متن فقط (تا ۳ تا) ایموجی (لاتی یا کاستوم) باشه، تکه‌هاشون رو برمیگردونه؛ وگرنه null
List<_Seg>? _emojiOnlySegs(String text) {
  final segs = _segments(text);
  if (segs.isEmpty || segs.length > 3) return null;
  var rest = text;
  for (final sg in segs.reversed) {
    rest = rest.replaceRange(sg.start, sg.end, '');
  }
  if (rest.trim().isNotEmpty) return null;
  return segs;
}

/// متن رو به TextSpan تبدیل میکنه؛ ایموجی‌های لاتی‌دار/کاستوم میشن WidgetSpan.
/// اگه onPack بدیم، لینک پک‌ها (chatapp://emoji/...) هم قابل لمس میشن.
InlineSpan emojiSpan(String text, TextStyle style, {double? size, void Function(String packId)? onPack}) {
  final segs = _segments(text, links: onPack != null);
  if (segs.isEmpty) return TextSpan(text: text, style: style);
  final sz = size ?? (style.fontSize ?? 16) * 1.5;
  final kids = <InlineSpan>[];
  var i = 0;
  for (final sg in segs) {
    if (sg.start > i) kids.add(TextSpan(text: text.substring(i, sg.start)));
    if (sg.isEmoji) {
      kids.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _emojiWidget(sg, sz)));
    } else {
      final id = sg.packId!;
      kids.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => onPack!(id),
          child: Text(
            text.substring(sg.start, sg.end),
            textDirection: TextDirection.ltr,
            style: style.copyWith(color: tgBlue, decoration: TextDecoration.underline),
          ),
        ),
      ));
    }
    i = sg.end;
  }
  if (i < text.length) kids.add(TextSpan(text: text.substring(i)));
  return TextSpan(style: style, children: kids);
}

/// جای `Text` برای متن پیام‌ها. اگه پیام فقط ایموجی باشه (تا ۳ تا) بزرگ نشون میده.
class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextDirection? textDirection;
  const EmojiText({super.key, required this.text, required this.style, this.textDirection});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([LottieStore.tick, PackStore.tick]),
      builder: (_, __) {
        final plain = !text.contains('\u2063') && !text.contains('chatapp://') && !LottieStore.hasAny;
        if (plain) return Text(text, textDirection: textDirection, style: style);
        final only = _emojiOnlySegs(text);
        if (only != null) {
          final big = only.length == 1 ? 112.0 : 72.0;
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final sg in only) _emojiWidget(sg, big)],
          );
        }
        return Text.rich(
          emojiSpan(text, style, onPack: (id) => openPack(context, id)),
          textDirection: textDirection,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// تایپ‌باکس: ایموجی‌های لاتی‌دار و کاستوم همون‌جا متحرک نشون داده میشن
// ---------------------------------------------------------------------------
class LottieTextController extends TextEditingController {
  LottieTextController({super.text}) {
    LottieStore.tick.addListener(notifyListeners);
    PackStore.tick.addListener(notifyListeners);
  }

  @override
  void dispose() {
    LottieStore.tick.removeListener(notifyListeners);
    PackStore.tick.removeListener(notifyListeners);
    super.dispose();
  }

  /// ایموجی کاستوم یک «توکن» چندکاراکتریه؛ بک‌اسپیس نباید نصفش کنه،
  /// پس اگه حذف فقط بخشی از توکن رو گرفته، کل توکن حذف میشه
  @override
  set value(TextEditingValue newValue) {
    super.value = _atomic(value, newValue);
  }

  static TextEditingValue _atomic(TextEditingValue old, TextEditingValue nw) {
    final o = old.text;
    final n = nw.text;
    if (n.length >= o.length || !o.contains('\u2063')) return nw;
    var p = 0;
    while (p < n.length && o.codeUnitAt(p) == n.codeUnitAt(p)) {
      p++;
    }
    var a = p;
    var b = p + (o.length - n.length); // محدوده‌ی حذف‌شده تو متن قدیم
    var changed = false;
    for (final m in ceRe.allMatches(o)) {
      final overlaps = m.start < b && m.end > a;
      final whole = a <= m.start && b >= m.end;
      if (overlaps && !whole) {
        a = math.min(a, m.start);
        b = math.max(b, m.end);
        changed = true;
      }
    }
    if (!changed) return nw;
    return TextEditingValue(text: o.replaceRange(a, b, ''), selection: TextSelection.collapsed(offset: a));
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final t = text;
    final comp = value.composing;
    // وسط تایپ با کیبورد (composing) دست نمیزنیم تا اختلالی تو ورودی پیش نیاد
    if (t.isEmpty || (withComposing && comp.isValid && !comp.isCollapsed)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final segs = _segments(t);
    if (segs.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final sz = (style?.fontSize ?? 18) * 1.35;
    final kids = <InlineSpan>[];
    var i = 0;
    for (final sg in segs) {
      if (sg.start > i) kids.add(TextSpan(text: t.substring(i, sg.start)));
      kids.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _emojiWidget(sg, sz)));
      // WidgetSpan فقط ۱ واحد جا میگیره ولی ایموجی/توکن ممکنه چند واحد باشه؛
      // با کاراکترهای نامرئی پر میکنیم تا جای نشانگر/انتخاب (cursor) درست بمونه
      final pad = sg.end - sg.start - 1;
      if (pad > 0) {
        kids.add(TextSpan(text: '\u200B' * pad, style: const TextStyle(fontSize: 0.01)));
      }
      i = sg.end;
    }
    if (i < t.length) kids.add(TextSpan(text: t.substring(i)));
    return TextSpan(style: style, children: kids);
  }
}

/// متن رو جای نشانگر (یا جای انتخاب‌شده) تو کنترلر میذاره
void insertAtCursor(TextEditingController c, String s) {
  final v = c.value;
  var a = v.selection.isValid ? v.selection.start : v.text.length;
  var b = v.selection.isValid ? v.selection.end : v.text.length;
  if (a > b) {
    final tmp = a;
    a = b;
    b = tmp;
  }
  final out = v.text.replaceRange(a, b, s);
  c.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: a + s.length));
}

// ---------------------------------------------------------------------------
// تب Emoji: ایموجی‌های متحرک ادمین + پک‌های کاستوم اکانت من
// ---------------------------------------------------------------------------
class EmojiPanel extends StatefulWidget {
  /// متنی که باید تو تایپ‌باکس بره (ایموجی معمولی یا توکن ایموجی کاستوم)
  final void Function(String emoji) onPick;
  const EmojiPanel({super.key, required this.onPick});

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  /// آخرین بخشی که کاربر باز کرده ('basic' یا آیدی پک)
  static String _lastSel = 'basic';
  String _sel = _lastSel;

  @override
  void initState() {
    super.initState();
    LottieStore.load();
    PackStore.load();
  }

  void _packMenu(Map<String, dynamic> pack) {
    final id = pack['id'] as String;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(pack['title'] as String? ?? 'Emoji pack'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: packLink(id)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
            child: const Text('Copy link'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.removePack(id);
                await PackStore.load();
              } on ApiException catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            child: const Text('Remove from my emoji'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _tab({required bool selected, required Widget child, required VoidCallback onTap, VoidCallback? onLong}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        width: 42,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? (context.dark ? Colors.white12 : Colors.black12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([LottieStore.tick, PackStore.tick]),
      builder: (_, __) {
        final basic = LottieStore.items;
        final packs = PackStore.packs.where((p) => ((p['items'] as List?) ?? const []).isNotEmpty).toList();
        if (basic.isEmpty && packs.isEmpty) {
          if (!LottieStore.loaded && !PackStore.loaded) return const Center(child: CupertinoActivityIndicator(radius: 14));
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No animated emojis yet.\nCreate your own pack with the Sticker bot (search “Sticker”).',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.subText, height: 1.6),
              ),
            ),
          );
        }
        // بخش انتخاب‌شده معتبر نیست؟ اولین بخش
        var sel = _sel;
        final valid = (sel == 'basic' && basic.isNotEmpty) || packs.any((p) => p['id'] == sel);
        if (!valid) sel = basic.isNotEmpty ? 'basic' : (packs.first['id'] as String);

        Widget grid;
        if (sel == 'basic') {
          grid = GridView.builder(
            key: const ValueKey('basic'),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 62,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: basic.length,
            itemBuilder: (_, i) {
              final it = basic[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onPick(it['emoji'] as String);
                },
                child: Center(child: AnimatedEmoji(item: it, size: 46)),
              );
            },
          );
        } else {
          final pack = packs.firstWhere((p) => p['id'] == sel);
          final items = ((pack['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          grid = GridView.builder(
            key: ValueKey('pack_$sel'),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 62,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final id = items[i]['id'] as String;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  // خودِ ایموجی کاستوم میره تو متن (نه یه ایموجی معمولی)
                  widget.onPick(ceToken(id));
                },
                child: Center(child: CustomEmoji(id: id, size: 46)),
              );
            },
          );
        }

        return Column(
          children: [
            if (packs.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                  children: [
                    if (basic.isNotEmpty)
                      _tab(
                        selected: sel == 'basic',
                        onTap: () => setState(() => _sel = _lastSel = 'basic'),
                        child: const Text('😀', style: TextStyle(fontSize: 22)),
                      ),
                    for (final p in packs)
                      _tab(
                        selected: sel == p['id'],
                        onTap: () => setState(() => _sel = _lastSel = p['id'] as String),
                        onLong: () => _packMenu(p),
                        child: CustomEmoji(
                          id: ((p['items'] as List).first as Map)['id'] as String,
                          size: 28,
                          animate: false,
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// پنل پایین تایپ‌باکس: دو تب Emoji / GIF
// ---------------------------------------------------------------------------
class MediaPanel extends StatefulWidget {
  final double height;
  final void Function(Map<String, dynamic> gif) onPickGif;
  final void Function(String emoji) onPickEmoji;
  const MediaPanel({super.key, required this.height, required this.onPickGif, required this.onPickEmoji});

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> {
  /// آخرین تبی که کاربر باز کرده؛ دفعه‌ی بعد همون باز میشه
  static int _lastTab = 0; // 0 = Emoji, 1 = GIF
  int _tab = _lastTab;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final dark = context.dark;
    return Container(
      height: widget.height + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111111) : const Color(0xFFF7F7F9),
        border: Border(top: BorderSide(color: dark ? Colors.white10 : Colors.black12, width: 0.6)),
      ),
      child: Column(
        children: [
          Expanded(
            child: _tab == 0
                ? EmojiPanel(onPick: widget.onPickEmoji)
                : GifPanel(height: 0, embedded: true, onPick: widget.onPickGif),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 4, 40, 8),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _tab,
                children: const {
                  0: Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('Emoji')),
                  1: Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('GIF')),
                },
                onValueChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _tab = v;
                    _lastTab = v;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
