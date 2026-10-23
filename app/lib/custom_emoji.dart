import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import 'api.dart';
import 'ce_text.dart';
import 'utils.dart';

// ---------------------------------------------------------------------------
// پک‌های ایموجی کاستوم (ساخته‌شده با بات Sticker) که تو اکانت من هستن
// ---------------------------------------------------------------------------
class PackStore {
  PackStore._();

  /// هر بار لیست عوض بشه یکی زیاد میشه (برای rebuild)
  static final ValueNotifier<int> tick = ValueNotifier(0);

  /// [{id, title, ownerId, mine, count, link, items: [{id, emoji}]}]
  static List<Map<String, dynamic>> packs = [];
  static bool loaded = false;

  static final Map<String, String> _emojiOf = {}; // id آیتم -> ایموجی معمولی
  static final Map<String, Future<LottieComposition?>> _comps = {};
  static StreamSubscription? _sub;
  static bool _loading = false;
  static int? _uid;
  static String? _base;

  static String? emojiFor(String itemId) => _emojiOf[itemId];

  /// ایموجی معمولیِ آیتم‌ها رو یادداشت میکنه (برای پیش‌نمایش متن)
  static void remember(Iterable items) {
    for (final it in items) {
      if (it is Map && it['id'] is String && it['emoji'] is String) {
        _emojiOf[it['id'] as String] = it['emoji'] as String;
      }
    }
  }

  static void _ensureSub() {
    ceFallback = (id) => _emojiOf[id] ?? '🙂';
    _sub ??= Api.events.listen((e) {
      final t = e['type'];
      if (t == 'packs' || t == 'hello') load();
    });
  }

  static bool has(String packId) => packs.any((p) => p['id'] == packId);

  static Future<void> load() async {
    _ensureSub();
    if (!Api.loggedIn) return;
    if (_base != Api.baseUrl || _uid != Api.userId) {
      // سرور یا اکانت عوض شده
      _base = Api.baseUrl;
      _uid = Api.userId;
      packs = [];
      loaded = false;
      _comps.clear();
    }
    if (_loading) return;
    _loading = true;
    try {
      final l = await Api.myPacks();
      packs = l;
      for (final p in l) {
        remember((p['items'] as List?) ?? const []);
      }
      loaded = true;
      tick.value++;
    } catch (_) {
      // بی‌صدا؛ دفعه‌ی بعد دوباره تلاش میشه
    } finally {
      _loading = false;
    }
  }

  /// انیمیشن یک بار دانلود و نگه داشته میشه تا همه‌ی ویجت‌ها ازش استفاده کنن
  static Future<LottieComposition?> composition(String itemId) {
    return _comps.putIfAbsent(itemId, () async {
      try {
        final bytes = await Api.cemojiBytes(itemId);
        return await LottieComposition.fromBytes(bytes);
      } catch (_) {
        _comps.remove(itemId); // دفعه‌ی بعد دوباره تلاش کنه
        return null;
      }
    });
  }
}

// ---------------------------------------------------------------------------
// خود ایموجی کاستوم (متحرک)
// ---------------------------------------------------------------------------
class CustomEmoji extends StatefulWidget {
  final String id;
  final double size;
  final bool animate;
  const CustomEmoji({super.key, required this.id, this.size = 28, this.animate = true});

  @override
  State<CustomEmoji> createState() => _CustomEmojiState();
}

class _CustomEmojiState extends State<CustomEmoji> {
  late Future<LottieComposition?> _f;

  @override
  void initState() {
    super.initState();
    _f = PackStore.composition(widget.id);
  }

  @override
  void didUpdateWidget(covariant CustomEmoji old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _f = PackStore.composition(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return FutureBuilder<LottieComposition?>(
      future: _f,
      builder: (_, snap) {
        final c = snap.data;
        if (c == null) {
          // تا لود بشه همون ایموجی معمولی (اگه میدونیم)، وگرنه جای خالی
          final e = PackStore.emojiFor(widget.id);
          return SizedBox(
            width: size,
            height: size,
            child: e == null ? null : Center(child: Text(e, style: TextStyle(fontSize: size * 0.7))),
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
// صفحه‌ی پک (با زدن روی لینک پک تو چت باز میشه)
// ---------------------------------------------------------------------------
void openPack(BuildContext context, String packId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PackPage(packId: packId)));
}

class PackPage extends StatefulWidget {
  final String packId;
  const PackPage({super.key, required this.packId});

  @override
  State<PackPage> createState() => _PackPageState();
}

class _PackPageState extends State<PackPage> {
  Map<String, dynamic>? _pack;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.packInfo(widget.packId);
      PackStore.remember((p['items'] as List?) ?? const []);
      if (!mounted) return;
      setState(() {
        _pack = p;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _toggle() async {
    final p = _pack;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (p['added'] == true) {
        await Api.removePack(widget.packId);
      } else {
        await Api.addPack(widget.packId);
      }
      await PackStore.load();
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete this pack?'),
        content: const Text('It will be removed for everyone who added it.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deletePack(widget.packId);
      await PackStore.load();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pack;
    final items = ((p?['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final added = p?['added'] == true;
    final mine = p?['mine'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Emoji pack' : (p['title'] as String? ?? 'Emoji pack')),
        actions: [
          if (p != null)
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(CupertinoIcons.link, size: 22),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: packLink(widget.packId)));
                _snack('Link copied');
              },
            ),
          if (mine)
            IconButton(
              tooltip: 'Delete pack',
              icon: const Icon(CupertinoIcons.delete, size: 22),
              onPressed: _delete,
            ),
        ],
      ),
      body: p == null
          ? Center(
              child: _error == null
                  ? const CupertinoActivityIndicator(radius: 14)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
                          TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _load();
                            },
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${items.length} animated emoji${p['owner'] != null ? '  •  by @${p['owner']}' : ''}',
                      style: TextStyle(color: context.subText, fontSize: 13.5),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 72,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => Center(child: CustomEmoji(id: items[i]['id'] as String, size: 58)),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: added
                          ? OutlinedButton(
                              onPressed: _busy ? null : _toggle,
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text('Remove ${items.length} emoji'),
                            )
                          : FilledButton(
                              onPressed: _busy ? null : _toggle,
                              style: FilledButton.styleFrom(
                                  backgroundColor: tgBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text('Add ${items.length} emoji'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
