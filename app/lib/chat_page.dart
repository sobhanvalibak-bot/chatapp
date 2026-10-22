import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'attach_sheet.dart';
import 'msg_menu.dart';
import 'file_widgets.dart';
import 'permissions_page.dart';
import 'player.dart';
import 'profile_page.dart';
import 'utils.dart';

/// فایلی که در حال آپلوده (قبل از اینکه سرور پیام رو بسازه)
class _Pending {
  final String name;
  final int size;
  double progress = 0;
  bool started = false; // false = تو صف انتظار
  final UploadCancel cancel = UploadCancel();
  _Pending(this.name, this.size);
}

class ChatPage extends StatefulWidget {
  final int peerId;
  final String peerName;
  const ChatPage({super.key, required this.peerId, required this.peerName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Map<String, dynamic>> _msgs = [];
  final _ctrl = TextEditingController();
  final _sc = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  final Map<int, GlobalKey> _bubKeys = {};
  StreamSubscription? _sub;
  bool _loading = true;
  String? _error;
  late Map<String, dynamic> _peer;
  Map<String, dynamic>? _editing;
  Map<String, dynamic>? _replying; // پیامی که داریم بهش ریپلای می‌کنیم
  final List<_Pending> _pending = [];
  int _pinIdx = -1; // اندیس پیام پینی که الان تو بنر نشون داده میشه (-1 = آخری)

  @override
  void initState() {
    super.initState();
    _peer = {'id': widget.peerId, 'username': widget.peerName};
    _load();
    _loadPeer();
    _sub = Api.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    _sc.dispose();
    super.dispose();
  }

  bool _mineMsg(Map<String, dynamic> m) => m['from'] == Api.userId;
  bool _inThisChat(Map m) => m['from'] == widget.peerId || m['to'] == widget.peerId;

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'message':
        final m1 = Map<String, dynamic>.from(e['message'] as Map);
        if (_inThisChat(m1)) {
          _add(m1);
          if (m1['from'] == widget.peerId) Api.markRead(widget.peerId);
        }
        break;
      case 'edit':
      case 'pin':
      case 'react':
        final m2 = Map<String, dynamic>.from(e['message'] as Map);
        if (_inThisChat(m2)) _replace(m2);
        break;
      case 'delete':
        if (_inThisChat(e)) {
          setState(() => _msgs.removeWhere((x) => x['id'] == e['id']));
        }
        break;
      case 'read':
        if (e['by'] == widget.peerId) {
          setState(() {
            for (final m in _msgs) {
              if (_mineMsg(m)) m['read'] = true;
            }
          });
        }
        break;
      case 'user':
        final u = e['user'];
        if (u is Map && u['id'] == widget.peerId) {
          setState(() => _peer = Map<String, dynamic>.from(u));
        }
        break;
      case 'hello': // اتصال دوباره: پیام‌های جا مونده رو بگیر
        _load(silent: true);
        _loadPeer();
        break;
    }
  }

  Future<void> _loadPeer() async {
    try {
      final u = await Api.user(widget.peerId);
      if (mounted) setState(() => _peer = u);
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final d = await Api.history(widget.peerId);
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(d);
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _add(Map<String, dynamic> m) {
    if (!mounted) return;
    if (_msgs.any((x) => x['id'] == m['id'])) return;
    setState(() => _msgs.add(m));
  }

  void _replace(Map<String, dynamic> m) {
    if (!mounted) return;
    final i = _msgs.indexWhere((x) => x['id'] == m['id']);
    setState(() {
      if (i >= 0) {
        _msgs[i] = m;
      } else {
        _msgs.add(m);
      }
    });
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;

    final ed = _editing;
    if (ed != null) {
      if (t == ed['text']) {
        _cancelEdit();
        return;
      }
      _ctrl.clear();
      setState(() => _editing = null);
      try {
        final m = await Api.editMessage(ed['id'] as int, t);
        _replace(m);
      } on ApiException catch (e) {
        if (!mounted) return;
        _ctrl.text = t;
        _snack(e.message);
      }
      return;
    }

    final rp = _replying;
    _ctrl.clear();
    setState(() => _replying = null);
    try {
      final m = await Api.send(widget.peerId, t, replyTo: rp?['id'] as int?);
      _add(m);
    } on ApiException catch (e) {
      if (!mounted) return;
      _ctrl.text = t;
      setState(() => _replying = rp);
      _snack(e.message);
    }
  }

  // ---- ارسال فایل (تا ۳۰ مگابایت) ----
  List<Map<String, dynamic>> get _audioQueue => _msgs.where((m) => fileKind(m) == 'audio').toList();
  List<Map<String, dynamic>> get _imageQueue => _msgs
      .where((m) => fileKind(m) == 'image' && ((fileOf(m)!['size'] as num).toInt() <= kInlineImageMax))
      .toList();

  Future<void> _attach() async {
    // اولین بار در هر اجرا، اگه مجوزی داده نشده، صفحه‌ی مجوزها رو نشون بده
    if (!Perm.askedThisSession) {
      Perm.askedThisSession = true;
      if (!await Perm.allGranted()) {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsPage()));
      }
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final picked = await showAttachSheet(context, maxCount: _maxBatch);
    if (picked == null || picked.isEmpty || !mounted) return;
    final items = <AttachItem>[];
    for (final f in picked) {
      if (f.size > Api.maxFileBytes) {
        _snack('"${f.name}" is too large (max 30 MB)');
        continue;
      }
      if (f.size == 0) {
        _snack('"${f.name}" is empty');
        continue;
      }
      items.add(f);
    }
    if (items.isEmpty) return;
    if (items.length > _maxBatch) items.removeRange(_maxBatch, items.length);
    // متنی که تو کادر نوشته شده میشه کپشن اولین فایل
    var caption = '';
    if (_editing == null) {
      caption = _ctrl.text.trim();
      if (caption.isNotEmpty) _ctrl.clear();
    }
    await _uploadAll(items, caption);
  }

  static const int _maxBatch = 10;

  /// همه‌ی فایل‌ها یکجا تو صف میان (با حباب «Waiting…») و پشت‌سرهم آپلود میشن
  Future<void> _uploadAll(List<AttachItem> items, String caption) async {
    final rp = _replying;
    if (rp != null && mounted) setState(() => _replying = null);
    final pendings = items.map((i) => _Pending(i.name, i.size)).toList();
    setState(() => _pending.addAll(pendings));
    for (var i = 0; i < items.length; i++) {
      final p = pendings[i];
      if (!mounted) break;
      if (p.cancel.cancelled) {
        setState(() => _pending.remove(p));
        continue;
      }
      await _upload(items[i], p, i == 0 ? caption : '', i == 0 ? rp?['id'] as int? : null);
    }
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
  }

  Future<void> _upload(AttachItem it, _Pending p, String caption, int? replyTo) async {
    if (mounted) setState(() => p.started = true);
    try {
      final m = await Api.sendFile(
        widget.peerId,
        it.path,
        it.name,
        caption: caption,
        replyTo: replyTo,
        cancel: p.cancel,
        onProgress: (v) {
          if (mounted && ((v - p.progress) >= 0.01 || v >= 1)) setState(() => p.progress = v);
        },
      );
      _add(m);
    } on ApiException catch (e) {
      if (!p.cancel.cancelled) _snack(e.message);
      if (caption.isNotEmpty && _ctrl.text.isEmpty && mounted) _ctrl.text = caption;
    } finally {
      if (mounted) setState(() => _pending.remove(p));
    }
  }

  void _startEdit(Map<String, dynamic> m) {
    setState(() {
      _editing = m;
      _replying = null;
    });
    _ctrl.text = m['text'] as String;
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _ctrl.clear();
  }

  Future<void> _togglePin(Map<String, dynamic> m) async {
    try {
      final out = await Api.pinMessage(m['id'] as int, m['pinned'] != true);
      _replace(out);
      _pinIdx = -1;
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> m, {required bool everyone}) async {
    try {
      await Api.deleteMessage(m['id'] as int, everyone: everyone);
      if (mounted) setState(() => _msgs.removeWhere((x) => x['id'] == m['id']));
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _deleteMenu(Map<String, dynamic> m) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Delete message?'),
        actions: [
          if (_mineMsg(m))
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                _delete(m, everyone: true);
              },
              child: const Text('Delete for everyone'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _delete(m, everyone: false);
            },
            child: const Text('Delete for me'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _startReply(Map<String, dynamic> m) {
    setState(() {
      _editing = null;
      _replying = m;
    });
  }

  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    HapticFeedback.selectionClick();
    try {
      final out = await Api.reactMessage(m['id'] as int, emoji);
      _replace(out);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  String? _myReaction(Map<String, dynamic> m) {
    final r = m['reactions'];
    if (r is Map) return r['${Api.userId}'] as String?;
    return null;
  }

  void _menu(Map<String, dynamic> m) {
    final box = _bubKeys[m['id'] as int]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    HapticFeedback.mediumImpact();
    final rect = box.localToGlobal(Offset.zero) & box.size;
    showMsgMenu(
      context,
      rect: rect,
      mine: _mineMsg(m),
      bubble: _bubbleBox(m),
      myReaction: _myReaction(m),
      onReact: (e) => _react(m, e),
      actions: [
        MsgMenuAction('Reply', CupertinoIcons.reply, () => _startReply(m)),
        if (((m['text'] as String?) ?? '').isNotEmpty)
          MsgMenuAction('Copy', CupertinoIcons.doc_on_doc, () {
            Clipboard.setData(ClipboardData(text: m['text'] as String));
          }),
        MsgMenuAction(m['pinned'] == true ? 'Unpin' : 'Pin',
            m['pinned'] == true ? CupertinoIcons.pin_slash : CupertinoIcons.pin, () => _togglePin(m)),
        if (_mineMsg(m) && m['file'] == null) MsgMenuAction('Edit', CupertinoIcons.pencil, () => _startEdit(m)),
        MsgMenuAction('Delete', CupertinoIcons.trash, () => _deleteMenu(m), destructive: true),
      ],
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(userId: widget.peerId, initial: _peer, fromChat: true),
      ),
    );
  }

  // ---- پیام پین‌شده ----
  List<Map<String, dynamic>> get _pinned => _msgs.where((m) => m['pinned'] == true).toList();

  void _jumpTo(int id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.5);
      return;
    }
    final idx = _msgs.indexWhere((m) => m['id'] == id);
    if (idx < 0 || !_sc.hasClients) return;
    final rev = _msgs.length - 1 - idx;
    _sc.jumpTo((rev * 64.0).clamp(0.0, _sc.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[id]?.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.5);
      }
    });
  }

  Widget _pinBanner() {
    final list = _pinned;
    if (list.isEmpty) return const SizedBox.shrink();
    var i = _pinIdx;
    if (i < 0 || i >= list.length) i = list.length - 1;
    final m = list[i];
    final text = msgPreview(m).replaceAll('\n', ' ');
    return Material(
      color: context.barBg,
      child: InkWell(
        onTap: () {
          _jumpTo(m['id'] as int);
          setState(() => _pinIdx = (i - 1 + list.length) % list.length);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Container(width: 3, height: 34, decoration: BoxDecoration(color: tgBlue, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.length > 1 ? 'Pinned message #${i + 1}' : 'Pinned message',
                      style: const TextStyle(color: tgBlue, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: dirOf(text),
                        style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.push_pin, size: 18, color: tgBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = _mineMsg(m);
    final key = _keys.putIfAbsent(m['id'] as int, () => GlobalKey());
    final bk = _bubKeys.putIfAbsent(m['id'] as int, () => GlobalKey());
    return Align(
      key: key,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
        child: GestureDetector(
          onLongPress: () => _menu(m),
          child: _bubbleBox(m, key: bk),
        ),
      ),
    );
  }

  /// خود حباب (بدون margin)؛ هم تو لیست استفاده میشه هم تو منوی نگه‌داشتن
  Widget _bubbleBox(Map<String, dynamic> m, {Key? key}) {
    final mine = _mineMsg(m);
    final text = (m['text'] as String?) ?? '';
    final hasFile = m['file'] != null;
    final read = m['read'] == true;
    const r = Radius.circular(18);
    const tail = Radius.circular(4);
    final metaColor = mine ? context.metaMine : context.metaOther;
    return Container(
      key: key,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
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
          if (m['reply'] is Map) _replyQuote(m['reply'] as Map, mine),
          if (hasFile)
            Align(
              alignment: Alignment.centerLeft,
              child: FileContent(msg: m, mine: mine, audioQueue: _audioQueue, imageQueue: _imageQueue),
            ),
          if (hasFile && text.isNotEmpty) const SizedBox(height: 6),
          if (text.isNotEmpty)
            Align(
              alignment: dirOf(text) == TextDirection.rtl ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(text, textDirection: dirOf(text), style: const TextStyle(fontSize: 16, height: 1.3)),
            ),
          _reactionChips(m),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m['pinned'] == true) ...[
                Icon(Icons.push_pin, size: 12, color: metaColor),
                const SizedBox(width: 3),
              ],
              if (m['edited'] == true) ...[
                Text('edited', style: TextStyle(fontSize: 11, color: metaColor)),
                const SizedBox(width: 4),
              ],
              Text(fmtHm(m['createdAt'] as int), style: TextStyle(fontSize: 11, color: metaColor)),
              if (mine) ...[
                const SizedBox(width: 3),
                Icon(read ? Icons.done_all : Icons.done, size: 15, color: read ? context.tickRead : metaColor),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// کادر نقل‌قول بالای پیام ریپلای‌شده
  Widget _replyQuote(Map reply, bool mine) {
    final text = ((reply['text'] as String?) ?? '').replaceAll('\n', ' ');
    final from = reply['from'];
    final name = from == null
        ? ''
        : (from == Api.userId ? 'You' : ((_peer['username'] as String?) ?? widget.peerName));
    final accent = mine ? context.tickRead : tgBlue;
    final id = reply['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: id is int && from != null ? () => _jumpTo(id) : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty)
                Text(name, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: dirOf(text),
                  style: TextStyle(fontSize: 13.5, color: from == null ? context.subText : null)),
            ],
          ),
        ),
      ),
    );
  }

  /// ری‌اکشن‌های زیر پیام؛ زدن روی هر کدوم، ری‌اکشن خودم رو عوض/برمی‌داره
  Widget _reactionChips(Map<String, dynamic> m) {
    final rs = m['reactions'];
    if (rs is! Map || rs.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    rs.forEach((_, e) {
      if (e is String) counts[e] = (counts[e] ?? 0) + 1;
    });
    final mineE = _myReaction(m);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          children: counts.entries.map((en) {
            final on = mineE == en.key;
            return GestureDetector(
              onTap: () => _react(m, en.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: on ? tgBlue.withOpacity(0.45) : Colors.black.withOpacity(context.dark ? 0.25 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(en.key, style: const TextStyle(fontSize: 15)),
                    if (en.value > 1) ...[
                      const SizedBox(width: 3),
                      Text('${en.value}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _dayKey(Map m) {
    final d = DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int);
    return '${d.year}-${d.month}-${d.day}';
  }

  Widget _dayChip(Map m) {
    final d = DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int);
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Yesterday'
            : '${mon[d.month - 1]} ${d.day}${d.year != now.year ? ', ${d.year}' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.black.withOpacity(context.dark ? 0.35 : 0.14),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: context.dark ? Colors.white70 : Colors.black54)),
          ),
        ),
      ),
    );
  }

  Widget _pendingBubble(_Pending p) {
    final pct = (p.progress * 100).round();
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.bubbleMine,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                p.cancel.cancel();
                if (!p.started && mounted) setState(() => _pending.remove(p));
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: tgBlue, shape: BoxShape.circle),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                        value: p.progress <= 0 ? null : p.progress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(p.name),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(p.started ? 'Sending… $pct% • ${fmtSize(p.size)}' : 'Waiting… • ${fmtSize(p.size)}',
                      style: TextStyle(fontSize: 12.5, color: context.metaMine)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
        ),
      );
    }
    if (_msgs.isEmpty && _pending.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(context.dark ? 0.25 : 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('Send the first message 👋',
              style: TextStyle(color: context.dark ? Colors.white70 : Colors.black54)),
        ),
      );
    }
    return ListView.builder(
      controller: _sc,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _msgs.length + _pending.length,
      itemBuilder: (_, i) {
        if (i < _pending.length) return _pendingBubble(_pending[_pending.length - 1 - i]);
        final idx = _msgs.length - 1 - (i - _pending.length);
        final m = _msgs[idx];
        final showDay = idx == 0 || _dayKey(_msgs[idx - 1]) != _dayKey(m);
        if (!showDay) return _bubble(m);
        return Column(children: [_dayChip(m), _bubble(m)]);
      },
    );
  }

  Widget _editBar() {
    final ed = _editing;
    if (ed == null) return const SizedBox.shrink();
    final text = (ed['text'] as String).replaceAll('\n', ' ');
    return Container(
      color: context.barBg,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 18, color: tgBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Edit message',
                    style: TextStyle(color: tgBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(text),
                    style: TextStyle(fontSize: 13.5, color: context.subText)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _cancelEdit),
        ],
      ),
    );
  }

  Widget _replyBar() {
    final rp = _replying;
    if (rp == null) return const SizedBox.shrink();
    final text = msgPreview(rp).replaceAll('\n', ' ');
    final name = _mineMsg(rp) ? 'You' : ((_peer['username'] as String?) ?? widget.peerName);
    return Container(
      color: context.barBg,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
      child: Row(
        children: [
          const Icon(CupertinoIcons.reply, size: 20, color: tgBlue),
          const SizedBox(width: 10),
          Container(width: 3, height: 34, decoration: BoxDecoration(color: tgBlue, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reply to $name',
                    style: const TextStyle(color: tgBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(text),
                    style: TextStyle(fontSize: 13.5, color: context.subText)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _replying = null)),
        ],
      ),
    );
  }

  Widget _glassCircle({required Widget child, VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? (context.dark ? const Color(0xAA1C2733) : const Color(0xCCFFFFFF)),
              border: Border.all(color: context.dark ? Colors.white12 : Colors.black12, width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _glassCircle(
              onTap: _attach,
              child: Icon(Icons.attach_file_rounded, color: context.subText, size: 23),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      color: context.dark ? const Color(0xAA1C2733) : const Color(0xCCFFFFFF),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: context.dark ? Colors.white12 : Colors.black12, width: 0.8),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, v, __) {
                final can = v.text.trim().isNotEmpty;
                return _glassCircle(
                  onTap: can ? _send : null,
                  color: can ? tgBlue : null,
                  child: Icon(
                    _editing != null ? Icons.check : CupertinoIcons.arrow_up,
                    color: can ? Colors.white : context.subText,
                    size: 22,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = _peer['online'] == true;
    return Scaffold(
      backgroundColor: context.chatBg,
      appBar: AppBar(
        backgroundColor: context.barBg.withOpacity(0.78),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: const SizedBox.expand()),
        ),
        centerTitle: false,
        titleSpacing: 0,
        title: InkWell(
          onTap: _openProfile,
          child: Row(
            children: [
              Avatar.fromUser(_peer, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (_peer['username'] as String?) ?? widget.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    if (_peer.containsKey('lastSeen'))
                      Text(
                        presenceText(_peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: online ? tgBlue : context.subText,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: context.dark
                ? const [Color(0xFF0E1621), Color(0xFF131B2E), Color(0xFF1A1530)]
                : const [Color(0xFFE7EBF0), Color(0xFFE3E9F4), Color(0xFFEBE3F0)],
          ),
        ),
        child: Column(
        children: [
          _pinBanner(),
          const MiniPlayer(),
          Expanded(child: _list()),
          _editBar(),
          _replyBar(),
          _inputBar(),
        ],
      ),
      ),
    );
  }
}
