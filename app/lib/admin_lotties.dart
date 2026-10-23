import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'api.dart';
import 'lottie_emoji.dart';
import 'utils.dart';

const int _maxPickBytes = 2 * 1024 * 1024; // فایل tgs / json انتخاب‌شده
const int _maxJsonBytes = 3 * 1024 * 1024; // بعد از باز کردن tgs (مثل سرور)

/// ایموجی‌های آماده برای انتخاب (هر ایموجی دیگه‌ای رو هم میشه با کیبورد تایپ کرد)
final List<String> _pickerEmojis = ('😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥳 😏 😒 😞 😔 😟 😕 🙁 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 👹 👺 🤡 💩 👻 💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾 '
        '👋 🤚 ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 💪 🧠 👀 👁️ 👅 👄 '
        '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💯 💢 💥 💫 💦 💨 🕳️ 💣 💬 💭 💤 '
        '🔥 ✨ ⭐ 🌟 ⚡ ☄️ 🌈 ☀️ 🌤️ ⛅ ☁️ 🌧️ ⛈️ ❄️ ☃️ 🌊 💧 🌹 🌸 🌼 🌻 🍀 🍁 🌴 🌵 '
        '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🦆 🦅 🦉 🦇 🐺 🐴 🦄 🐝 🦋 🐌 🐞 🐢 🐍 🐙 🐬 🐳 🦈 '
        '🍎 🍕 🍔 🍟 🌭 🍿 🍩 🍪 🎂 🍰 🍫 🍬 🍭 ☕ 🍺 🍷 🥂 🍾 '
        '⚽ 🏀 🏈 ⚾ 🎾 🏐 🎱 🎮 🎯 🎲 🎵 🎶 🎤 🎧 🎉 🎊 🎁 🏆 🥇 👑 💎 💰 🚀 ✈️ 🚗 ⏰ 📱 💻 📷 🔔 🔒 🔑 ✅ ❌ ❓ ❗ ⚠️ 🚫 ➕ ➖ 💲 🆗 🆒 🆕 🔞')
    .split(' ')
    .where((e) => e.isNotEmpty)
    .toList();

void _snack(BuildContext context, String t) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
}

// ---------------------------------------------------------------------------
// لیست ایموجی‌های متحرک + دکمه‌ی افزودن
// ---------------------------------------------------------------------------
class AdminLottiesPage extends StatefulWidget {
  const AdminLottiesPage({super.key});

  @override
  State<AdminLottiesPage> createState() => _AdminLottiesPageState();
}

class _AdminLottiesPageState extends State<AdminLottiesPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LottieStore.tick.addListener(_refresh);
    LottieStore.load();
  }

  @override
  void dispose() {
    LottieStore.tick.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_busy) return;
    FilePickerResult? r;
    try {
      // FileType.any: روی بعضی گوشی‌ها پسوند tgs تو فیلتر سیستم نیست و فایل مخفی میشه
      r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: false);
    } catch (_) {
      if (mounted) _snack(context, 'Could not open the file picker');
      return;
    }
    if (r == null || r.files.isEmpty) return;
    final pf = r.files.first;
    final path = pf.path;
    if (path == null) return;
    final lower = pf.name.toLowerCase();
    if (!lower.endsWith('.tgs') && !lower.endsWith('.json')) {
      if (mounted) _snack(context, 'Choose a .tgs or .json file');
      return;
    }
    setState(() => _busy = true);
    Uint8List bytes = Uint8List(0);
    try {
      final f = File(path);
      if (await f.length() > _maxPickBytes) {
        if (mounted) _snack(context, 'File is too large (max 2 MB)');
        return;
      }
      bytes = await f.readAsBytes();
      // tgs = JSON فشرده با gzip
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      if (bytes.length > _maxJsonBytes) {
        if (mounted) _snack(context, 'The animation is too large (max 3 MB)');
        return;
      }
      final j = json.decode(utf8.decode(bytes));
      if (j is! Map || j['layers'] is! List) throw const FormatException('not lottie');
    } catch (_) {
      if (mounted) _snack(context, 'This is not a valid Lottie file');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final base = pf.name.replaceFirst(RegExp(r'\.(tgs|json)$', caseSensitive: false), '');
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddLottiePage(name: base, bytes: bytes)),
    );
    if (added == true) {
      await LottieStore.load();
      if (mounted) _snack(context, 'Animated emoji added');
    }
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${it['emoji']}?'),
        content: const Text('This animation will disappear for everyone. Messages keep the normal emoji.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.adminDeleteLottie(it['id'] as String);
      await LottieStore.load();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = LottieStore.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Animated emojis'),
        actions: [
          IconButton(
            tooltip: 'Add Lottie',
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CupertinoActivityIndicator())
                : const Icon(CupertinoIcons.add),
            onPressed: _busy ? null : _add,
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      LottieStore.loaded
                          ? 'No animated emojis yet.\nUpload a .tgs or .json Lottie file and choose the emoji it replaces.'
                          : 'Loading…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.subText, height: 1.6),
                    ),
                    if (LottieStore.loaded)
                      CupertinoButton(onPressed: _busy ? null : _add, child: const Text('Add Lottie')),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 0.5, thickness: 0.5, indent: 76),
              itemBuilder: (_, i) {
                final it = items[i];
                return ListTile(
                  leading: AnimatedEmoji(item: it, size: 48),
                  title: Text(it['emoji'] as String, style: const TextStyle(fontSize: 22)),
                  subtitle: Text((it['name'] as String?) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.trash, size: 20, color: Color(0xFFFF5A52)),
                    onPressed: () => _delete(it),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// بعد از انتخاب فایل: پیش‌نمایش + انتخاب ایموجی + ثبت
// ---------------------------------------------------------------------------
class AddLottiePage extends StatefulWidget {
  final String name;
  final Uint8List bytes; // JSON انیمیشن (tgs قبلاً باز شده)
  const AddLottiePage({super.key, required this.name, required this.bytes});

  @override
  State<AddLottiePage> createState() => _AddLottiePageState();
}

class _AddLottiePageState extends State<AddLottiePage> {
  final _emoji = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _renderFailed = false;

  @override
  void dispose() {
    _emoji.dispose();
    super.dispose();
  }

  String get _val => _emoji.text.trim();

  /// تشخیص اولیه‌ی «یه ایموجی»؛ تایید نهایی با سرور
  bool get _looksLikeEmoji {
    final v = _val;
    if (v.isEmpty || v.length > 24) return false;
    if (RegExp(r'[A-Za-z\s]').hasMatch(v)) return false;
    return v.runes.any((r) => r > 0x2000);
  }

  bool get _taken => LottieStore.forEmoji(_val) != null;

  Future<void> _save() async {
    if (!_looksLikeEmoji || _taken || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.adminAddLottie(widget.name, _val, widget.bytes);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _looksLikeEmoji && !_taken && !_busy && !_renderFailed;
    String? hint = _error;
    if (hint == null && _val.isNotEmpty && !_looksLikeEmoji) hint = 'Choose a single emoji';
    if (hint == null && _taken) hint = 'This emoji already has an animation';
    return Scaffold(
      appBar: AppBar(title: const Text('Add animated emoji')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              width: 170,
              child: Lottie.memory(
                widget.bytes,
                fit: BoxFit.contain,
                repeat: true,
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_renderFailed) setState(() => _renderFailed = true);
                  });
                  return Center(
                    child: Text('Could not play this animation', textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.subText)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: TextField(
                controller: _emoji,
                onChanged: (_) => setState(() => _error = null),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28),
                decoration: InputDecoration(
                  labelText: 'Emoji to replace',
                  helperText: 'Pick one below or type any emoji with your keyboard',
                  errorText: hint,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 48),
                itemCount: _pickerEmojis.length,
                itemBuilder: (_, i) {
                  final e = _pickerEmojis[i];
                  final used = LottieStore.forEmoji(e) != null;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _emoji.text = e;
                      _error = null;
                    }),
                    child: Center(
                      child: Opacity(opacity: used ? 0.3 : 1, child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CupertinoActivityIndicator(color: Colors.white))
                      : const Text('Add'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
