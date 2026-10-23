import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'admin_page.dart';
import 'api.dart';
import 'chat_page.dart';
import 'permissions_page.dart';
import 'player.dart';
import 'profile_page.dart';
import 'sticker_bot.dart';
import 'utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  final _searchCtrl = TextEditingController();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMe();
    _sub = Api.events.listen(_onEvent);
    // بار اول: صفحه‌ی مجوزها (اعلان‌ها، عکس، ویدیو، موسیقی) رو نشون بده
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAskPermissions(context);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'user':
        final u = e['user'];
        if (u is! Map) return;
        if (u['id'] == Api.userId) {
          Api.me = Map<String, dynamic>.from(u);
          Api.meTick.value++;
          setState(() {});
        }
        var changed = false;
        for (final c in _chats) {
          final p = c['peer'] as Map;
          if (p['id'] == u['id']) {
            c['peer'] = Map<String, dynamic>.from(u);
            changed = true;
          }
        }
        if (changed) setState(() {});
        break;
      default:
        _load(silent: true);
    }
  }

  Future<void> _loadMe() async {
    try {
      await Api.refreshMe();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final d = await Api.chats();
      if (!mounted) return;
      setState(() {
        _chats = d;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  Future<void> _open(int id, String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(peerId: id, peerName: name)),
    );
    _load(silent: true);
  }

  /// اگه متن سرچ یه کد ادمین بود (با Enter) مصرفش میکنه
  Future<void> _onSearchSubmit(String v) async {
    final code = v.trim();
    if (!code.startsWith('admin(pass)')) return;
    FocusScope.of(context).unfocus();
    try {
      final fresh = await Api.redeemAdminCode(code);
      if (!mounted) return;
      _searchCtrl.clear();
      setState(() => _q = '');
      if (fresh) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are now an admin')));
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage()));
      _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _newChat() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewChatPage()));
    _load(silent: true);
  }

  void _openProfile(Map<String, dynamic> peer) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: peer['id'] as int, initial: peer)),
    );
  }

  /// آیتم ثابت «Saved Messages» بالای لیست؛ همیشه هست، حتی اگه هنوز پیامی ذخیره نشده
  Widget _savedTile(Map<String, dynamic>? c) {
    final last = c?['last'] as Map<String, dynamic>?;
    final thumb = last == null ? null : previewThumb(last, size: 20);
    final text = last == null
        ? 'Forward or send anything here to save it'
        : msgPreview(last, icon: thumb == null).replaceAll('\n', ' ');
    return InkWell(
      onTap: () => _open(Api.userId ?? 0, 'Saved Messages'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const SavedAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Saved Messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (last != null)
                        Text(fmtTime(last['createdAt'] as int),
                            style: TextStyle(fontSize: 12.5, color: context.subText)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (thumb != null) ...[thumb, const SizedBox(width: 4)],
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dirOf(text),
                          style: TextStyle(fontSize: 14.5, color: context.subText),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بات «Sticker»؛ تو نتایج سرچ نشون داده میشه و همه میتونن بازش کنن
  Widget _botTile() {
    return InkWell(
      onTap: () async {
        FocusScope.of(context).unfocus();
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StickerBotPage()));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const StickerBotAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Sticker', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: tgBlue, borderRadius: BorderRadius.circular(5)),
                        child: const Text('BOT',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Make GIFs and animated emoji packs',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: context.subText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final peer = c['peer'] as Map<String, dynamic>;
    final last = c['last'] as Map<String, dynamic>;
    final unread = c['unread'] as int;
    final mine = last['from'] == Api.userId;
    final thumb = previewThumb(last, size: 20);
    // وقتی پیش‌نمایش عکس/فریم ویدیو داریم، به جای ایموجی همون رو نشون میدیم
    final text = msgPreview(last, icon: thumb == null).replaceAll('\n', ' ');
    return InkWell(
      onTap: () => _open(peer['id'] as int, peer['username'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _openProfile(peer),
              child: Avatar.fromUser(peer, showOnline: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayNameOf(peer),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (mine) ...[
                        Icon(last['read'] == true ? Icons.done_all : Icons.done,
                            size: 16, color: last['read'] == true ? context.tickRead : context.subText),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        fmtTime(last['createdAt'] as int),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: unread > 0 ? tgBlue : context.subText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (mine) const TextSpan(text: 'You: '),
                              if (thumb != null) ...[
                                WidgetSpan(alignment: PlaceholderAlignment.middle, child: thumb),
                                const TextSpan(text: ' '),
                              ],
                              TextSpan(text: text),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dirOf(text),
                          style: TextStyle(fontSize: 14.5, color: context.subText),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: tgBlue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    // چت با خودم = Saved Messages؛ جدا از بقیه و ثابت بالای لیست
    Map<String, dynamic>? saved;
    final others = <Map<String, dynamic>>[];
    for (final c in _chats) {
      if ((c['peer'] as Map)['id'] == Api.userId) {
        saved = c;
      } else {
        others.add(c);
      }
    }
    final list = _q.isEmpty
        ? others
        : others
            .where((c) => ('${displayNameOf(c['peer'] as Map)} ${(c['peer'] as Map)['username']}')
                .toLowerCase()
                .contains(_q.toLowerCase()))
            .toList();
    final showSaved = _q.isEmpty || 'saved messages'.contains(_q.toLowerCase());
    // بات Sticker فقط وقتی سرچ می‌کنیم (اسمش یا بخشی از اسمش)
    final ql = _q.trim().toLowerCase().replaceAll('@', '');
    final showBot = ql.isNotEmpty && ('sticker bot'.contains(ql) || ql.contains('sticker'));
    if (list.isEmpty && !showSaved && !showBot) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No chats yet.\nTap the button at the top to start a new chat.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.subText, height: 1.7),
          ),
        ),
      );
    }
    final extra = (showSaved ? 1 : 0) + (showBot ? 1 : 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: list.length + extra,
        separatorBuilder: (_, __) => const Divider(height: 0.5, thickness: 0.5, indent: 78),
        itemBuilder: (_, i) {
          if (showSaved && i == 0) return _savedTile(saved);
          if (showBot && i == (showSaved ? 1 : 0)) return _botTile();
          return _tile(list[i - extra]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.square_pencil, size: 24),
            onPressed: _newChat,
          ),
        ],
      ),
      body: Column(
        children: [
          const MiniPlayer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Search',
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: _onSearchSubmit,
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    setState(() => _loading = true);
    try {
      final d = await Api.users(q.trim());
      if (!mounted || my != _seq) return;
      setState(() {
        _users = d;
        _loading = false;
      });
    } on ApiException {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: CupertinoSearchTextField(
              placeholder: 'Search username',
              autofocus: true,
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _users.isEmpty && !_loading
                ? Center(child: Text('No users found', style: TextStyle(color: context.subText)))
                : ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 0.5, thickness: 0.5, indent: 68),
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProfilePage(userId: u['id'] as int, initial: u),
                            ),
                          ),
                          child: Avatar.fromUser(u, size: 44, showOnline: true),
                        ),
                        title: Text(displayNameOf(u),
                            textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                        subtitle: Text(presenceText(u),
                            style: TextStyle(
                                fontSize: 12.5,
                                color: u['online'] == true ? tgBlue : context.subText)),
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                                peerId: u['id'] as int, peerName: u['username'] as String),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
