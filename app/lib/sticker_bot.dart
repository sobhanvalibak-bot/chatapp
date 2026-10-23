import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ce_text.dart';
import 'custom_emoji.dart';
import 'gif_widgets.dart';
import 'utils.dart';

// ---------------------------------------------------------------------------
// بات «Sticker»: تو سرچ صفحه‌ی اصلی پیدا میشه و هر کسی میتونه بازش کنه.
//  /new_gif   ← ویدیو بفرست، گیف میشه (تو «گیف‌های من» ذخیره میشه)
//  /new_pack  ← اسم پک، بعد فایل‌های tgs تکی‌تکی + ایموجی هر کدوم، آخرش /publish
// ---------------------------------------------------------------------------

class StickerBotAvatar extends StatelessWidget {
  final double size;
  const StickerBotAvatar({super.key, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB66CF5), Color(0xFF6A5AE0)],
        ),
      ),
      child: Icon(CupertinoIcons.smiley_fill, color: Colors.white, size: size * 0.52),
    );
  }
}

enum _Step { idle, gif, packTitle, packFile, packEmoji }

class _Msg {
  final bool mine;
  final String kind; // text | file | gif | emoji | pack
  final String text;
  final Map<String, dynamic>? data;
  final int at;
  _Msg(this.mine, this.kind, {this.text = '', this.data}) : at = DateTime.now().millisecondsSinceEpoch;
}

/// گفتگو و مرحله‌ی فعلی تا وقتی اپ بازه نگه داشته میشه (با بستن صفحه از بین نمیره)
class _Session {
  static int user = -1;
  static final List<_Msg> msgs = [];
  static _Step step = _Step.idle;
  static Uint8List? pendingTgs;

  static void ensureFor(int? uid) {
    if (user != (uid ?? -1)) {
      user = uid ?? -1;
      msgs.clear();
      step = _Step.idle;
      pendingTgs = null;
    }
  }
}

// دستور (/new_gif) یا لینک پک
final RegExp _tokenRe = RegExp(r'chatapp://emoji/[0-9a-f]{8}|/[A-Za-z][A-Za-z_]{1,31}');

class StickerBotPage extends StatefulWidget {
  const StickerBotPage({super.key});

  @override
  State<StickerBotPage> createState() => _StickerBotPageState();
}

class _StickerBotPageState extends State<StickerBotPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _Session.ensureFor(Api.userId);
    PackStore.load();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- کمک‌ها ----
  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _add(_Msg m) {
    _Session.msgs.add(m);
    if (mounted) setState(() {});
  }

  void _bot(String text) => _add(_Msg(false, 'text', text: text));

  static const String _menu = '/new_gif\n/new_pack\n/my_packs';

  String get _welcome => 'Hi! 👋 I’m the Sticker bot.\n\n'
      '/new_gif — turn a video into a GIF\n'
      '/new_pack — create your own pack of animated emoji (.tgs)\n'
      '/my_packs — your packs and their links\n\n'
      'Tap a command to start.';

  // ---- ورودی کاربر ----
  Future<void> _send(String raw) async {
    final t = raw.trim();
    if (t.isEmpty || _busy) return;
    _ctrl.clear();
    _add(_Msg(true, 'text', text: t));
    await _handle(t);
  }

  Future<void> _handle(String t) async {
    if (t.startsWith('/')) {
      final cmd = t.split(RegExp(r'\s+')).first.toLowerCase().split('@').first;
      await _command(cmd);
      return;
    }
    switch (_Session.step) {
      case _Step.packTitle:
        await _setTitle(t);
        break;
      case _Step.packEmoji:
        await _setEmoji(t);
        break;
      case _Step.gif:
        _bot('Please send me a video with the 📎 button, or /cancel to stop.');
        break;
      case _Step.packFile:
        _bot('Please send a .tgs file with the 📎 button.\nWhen you are done, send /publish — or /cancel to stop.');
        break;
      case _Step.idle:
        _bot('I didn’t get that. Pick one:\n\n$_menu');
        break;
    }
  }

  Future<void> _command(String cmd) async {
    switch (cmd) {
      case '/start':
      case '/help':
        _bot(_welcome);
        break;
      case '/new_gif':
        await _dropDraft();
        _Session.step = _Step.gif;
        _bot('Send me a video (📎 button) and I’ll turn it into a GIF.\n\n/cancel to go back.');
        break;
      case '/new_pack':
        await _dropDraft();
        _Session.step = _Step.packTitle;
        _bot('Let’s make a new animated emoji pack.\n\nFirst, send a name for your pack.\n\n/cancel to stop.');
        break;
      case '/publish':
        await _publish();
        break;
      case '/cancel':
        await _cancel();
        break;
      case '/my_packs':
        await _myPacks();
        break;
      default:
        _bot('I don’t know that command. Pick one:\n\n$_menu');
    }
  }

  Future<void> _dropDraft() async {
    _Session.pendingTgs = null;
    if (_Session.step == _Step.packFile || _Session.step == _Step.packEmoji || _Session.step == _Step.packTitle) {
      try {
        await Api.packCancel();
      } catch (_) {}
    }
  }

  Future<void> _cancel() async {
    if (_Session.step == _Step.idle) {
      _bot('Nothing to cancel. Pick one:\n\n$_menu');
      return;
    }
    await _dropDraft();
    _Session.step = _Step.idle;
    _bot('Cancelled.\n\n$_menu');
  }

  // ---- /new_gif ----
  Future<void> _onVideo(String path, String name) async {
    _add(_Msg(true, 'file', text: '🎬 $name'));
    _bot('Converting to GIF…');
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final gif = await Api.stickerGif(path, name, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      _add(_Msg(false, 'gif', data: gif));
      _Session.step = _Step.idle;
      _bot('Done! ✅ Your GIF is saved in your GIFs — open the GIF panel next to the message box in any chat to send it.\n\nMake another: /new_gif');
    } on ApiException catch (e) {
      _bot('Couldn’t convert that: ${e.message}\n\nSend another video, or /cancel.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  // ---- /new_pack ----
  Future<void> _setTitle(String t) async {
    if (t.length > 60) {
      _bot('That name is too long (max 60 characters). Send a shorter one.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.packStart(t);
      _Session.step = _Step.packFile;
      _bot('Pack “$t” started. 🎉\n\nNow send the first .tgs file with the 📎 button (one file at a time).\n\nWhen you are done, send /publish.');
    } on ApiException catch (e) {
      _bot('Couldn’t start the pack: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onTgs(String path, String name) async {
    _add(_Msg(true, 'file', text: '📎 $name'));
    try {
      final f = File(path);
      final bytes = await f.readAsBytes();
      final gz = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
      final jsonLike = bytes.isNotEmpty && bytes[0] == 0x7b; // '{'
      if (!gz && !jsonLike) {
        _bot('That doesn’t look like an animated sticker. Please send a .tgs file.');
        return;
      }
      _Session.pendingTgs = bytes;
      _Session.step = _Step.packEmoji;
      _bot('Got it ✅\n\nNow send the emoji for this sticker (just one emoji).');
    } catch (_) {
      _bot('I couldn’t read that file. Try another one.');
    }
  }

  Future<void> _setEmoji(String t) async {
    final bytes = _Session.pendingTgs;
    if (bytes == null) {
      _Session.step = _Step.packFile;
      _bot('Send the .tgs file first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Api.packAddItem(t, bytes);
      final item = Map<String, dynamic>.from(r['item'] as Map);
      PackStore.remember([item]);
      _Session.pendingTgs = null;
      _Session.step = _Step.packFile;
      _add(_Msg(false, 'emoji', data: item));
      _bot('Added ✅ (${r['count']} in this pack)\n\nSend the next .tgs file, or /publish to finish.');
    } on ApiException catch (e) {
      if (e.message.startsWith('Send exactly one')) {
        _bot('Please send just one emoji (like 😀).');
      } else if (e.message.startsWith('No pack in progress')) {
        _Session.pendingTgs = null;
        _Session.step = _Step.idle;
        _bot('${e.message}\n\n$_menu');
      } else {
        // مشکل از فایله
        _Session.pendingTgs = null;
        _Session.step = _Step.packFile;
        _bot('${e.message}\n\nSend another .tgs file, or /publish.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final skipped = _Session.step == _Step.packEmoji;
    setState(() => _busy = true);
    try {
      final p = await Api.packPublish();
      PackStore.remember((p['items'] as List?) ?? const []);
      _Session.step = _Step.idle;
      _Session.pendingTgs = null;
      final id = p['id'] as String;
      _bot('Your pack “${p['title']}” is ready with ${p['count']} animated emoji! 🎉\n\n'
          'It’s already in your emoji panel. Send this link to anyone so they can add it:\n\n${packLink(id)}'
          '${skipped ? '\n\n(The last file had no emoji yet, so it was left out.)' : ''}');
      _add(_Msg(false, 'pack', data: p));
      unawaited(PackStore.load());
    } on ApiException catch (e) {
      if (e.message.startsWith('No pack in progress')) {
        _Session.step = _Step.idle;
        _bot('${e.message}\n\n$_menu');
      } else {
        _bot('${e.message}\n\nSend a .tgs file first.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _myPacks() async {
    setState(() => _busy = true);
    try {
      await PackStore.load();
      final mine = PackStore.packs.where((p) => p['mine'] == true).toList();
      if (mine.isEmpty) {
        _bot('You haven’t made any packs yet.\n\n/new_pack');
      } else {
        final b = StringBuffer('Your packs:\n');
        for (final p in mine) {
          b.write('\n• ${p['title']} (${p['count']})\n${p['link']}\n');
        }
        _bot(b.toString().trimRight());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- پیوست ----
  Future<void> _attach() async {
    if (_busy) return;
    final st = _Session.step;
    if (st != _Step.gif && st != _Step.packFile) {
      _snack(st == _Step.packEmoji
          ? 'Send the emoji for the last file first'
          : 'Start with /new_gif or /new_pack first');
      return;
    }
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(
        type: st == _Step.gif ? FileType.video : FileType.any,
        allowMultiple: false,
        withData: false,
      );
    } catch (_) {
      _snack('Could not open the file picker');
      return;
    }
    if (r == null || r.files.isEmpty) return;
    final pf = r.files.first;
    final path = pf.path;
    if (path == null) return;
    if (st == _Step.gif) {
      await _onVideo(path, pf.name);
    } else {
      await _onTgs(path, pf.name);
    }
  }

  // ---- ظاهر ----
  List<String> get _quick {
    switch (_Session.step) {
      case _Step.idle:
        return const ['/new_gif', '/new_pack', '/my_packs'];
      case _Step.packFile:
        return const ['/publish', '/cancel'];
      default:
        return const ['/cancel'];
    }
  }

  String get _hint {
    switch (_Session.step) {
      case _Step.packTitle:
        return 'Pack name';
      case _Step.packEmoji:
        return 'Send one emoji';
      default:
        return 'Message';
    }
  }

  /// متن بات: دستورها (/new_gif) و لینک پک‌ها قابل لمس میشن؛ دستور با لمس خودکار ارسال میشه
  InlineSpan _botSpan(String text, TextStyle style) {
    final kids = <InlineSpan>[];
    var i = 0;
    for (final m in _tokenRe.allMatches(text)) {
      if (m.start > i) kids.add(TextSpan(text: text.substring(i, m.start)));
      final tok = m.group(0)!;
      final isLink = tok.startsWith('chatapp://');
      kids.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () {
            if (isLink) {
              final id = tok.substring(tok.lastIndexOf('/') + 1);
              openPack(context, id);
            } else {
              _send(tok);
            }
          },
          child: Text(
            tok,
            textDirection: TextDirection.ltr,
            style: style.copyWith(color: tgBlue, decoration: isLink ? TextDecoration.underline : null),
          ),
        ),
      ));
      i = m.end;
    }
    if (i < text.length) kids.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: style, children: kids);
  }

  Widget _bubble(_Msg m) {
    final mine = m.mine;
    final maxW = MediaQuery.of(context).size.width * 0.8;
    const r = Radius.circular(18);
    const tail = Radius.circular(4);
    final metaColor = mine ? context.metaMine : context.metaOther;
    final txtColor = mine ? context.msgTextOut : context.msgTextIn;
    final style = TextStyle(fontSize: 16, height: 1.3, color: txtColor ?? context.mainText);

    Widget content;
    var pad = const EdgeInsets.fromLTRB(12, 7, 12, 5);
    switch (m.kind) {
      case 'gif':
        pad = const EdgeInsets.all(3);
        content = ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: GifVideo(url: Api.fileUrl(m.data!), width: math.min(240, maxW - 6), badge: true),
        );
        break;
      case 'emoji':
        content = CustomEmoji(id: m.data!['id'] as String, size: 96);
        break;
      case 'pack':
        content = _PackCard(pack: m.data!);
        break;
      default:
        final text = m.text;
        content = Text.rich(
          mine ? TextSpan(text: text, style: style) : _botSpan(text, style),
          textDirection: dirOf(text),
        );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: pad,
          decoration: BoxDecoration(
            color: mine ? context.bubbleMine : context.bubbleOther,
            borderRadius: BorderRadius.only(
              topLeft: r,
              topRight: r,
              bottomLeft: mine ? r : tail,
              bottomRight: mine ? tail : r,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(alignment: Alignment.centerLeft, child: content),
              const SizedBox(height: 2),
              Padding(
                padding: m.kind == 'gif' ? const EdgeInsets.only(right: 8, bottom: 3) : EdgeInsets.zero,
                child: Text(fmtHm(m.at), style: TextStyle(fontSize: 11, color: metaColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputArea() {
    final bottom = MediaQuery.of(context).padding.bottom;
    if (_Session.msgs.isEmpty) {
      // مثل تلگرام: اول فقط دکمه‌ی START
      return Container(
        color: context.barBg,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _send('/start'),
            style: FilledButton.styleFrom(
              backgroundColor: tgBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('START', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
        ),
      );
    }
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      color: context.barBg,
      padding: EdgeInsets.fromLTRB(8, 6, 8, 6 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in _quick)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(c, style: TextStyle(color: tgBlue, fontWeight: FontWeight.w600)),
                      backgroundColor: context.fieldFill,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      onPressed: _busy ? null : () => _send(c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(CupertinoIcons.paperclip, color: context.subText, size: 26),
                onPressed: _busy ? null : _attach,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: context.fieldFill, borderRadius: BorderRadius.circular(22)),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: _hint,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(CupertinoIcons.arrow_up_circle_fill, color: hasText && !_busy ? tgBlue : context.subText, size: 34),
                onPressed: hasText && !_busy ? () => _send(_ctrl.text) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _Session.msgs;
    return Scaffold(
      backgroundColor: context.chatBg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const StickerBotAvatar(size: 38),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sticker', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text('bot', style: TextStyle(fontSize: 12.5, color: context.subText)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) LinearProgressIndicator(minHeight: 2, value: (_progress != null && _progress! > 0 && _progress! < 1) ? _progress : null),
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StickerBotAvatar(size: 84),
                          const SizedBox(height: 14),
                          const Text('Sticker', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            'Turn videos into GIFs and make your own animated emoji packs.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.subText, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _bubble(msgs[msgs.length - 1 - i]),
                  ),
          ),
          _inputArea(),
        ],
      ),
    );
  }
}

/// کارت پک بعد از ساخته شدن: پیش‌نمایش ایموجی‌ها + کپی لینک
class _PackCard extends StatelessWidget {
  final Map<String, dynamic> pack;
  const _PackCard({required this.pack});

  @override
  Widget build(BuildContext context) {
    final items = ((pack['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final id = pack['id'] as String;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pack['title'] as String? ?? 'Emoji pack', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${items.length} animated emoji', style: TextStyle(fontSize: 13, color: context.subText)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final it in items.take(8)) CustomEmoji(id: it['id'] as String, size: 40)],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: packLink(id)));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                },
                icon: const Icon(CupertinoIcons.link, size: 18),
                label: const Text('Copy link'),
              ),
              TextButton(onPressed: () => openPack(context, id), child: const Text('Open')),
            ],
          ),
        ],
      ),
    );
  }
}
