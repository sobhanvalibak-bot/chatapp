import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';
import 'permissions_page.dart';
import 'player.dart';
import 'profile_page.dart';
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

  Future<void> _newChat() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewChatPage()));
    _load(silent: true);
  }

  void _openProfile(Map<String, dynamic> peer) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: peer['id'] as int, initial: peer)),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final peer = c['peer'] as Map<String, dynamic>;
    final last = c['last'] as Map<String, dynamic>;
    final unread = c['unread'] as int;
    final mine = last['from'] == Api.userId;
    final text = msgPreview(last).replaceAll('\n', ' ');
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
                          peer['username'] as String,
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
                        child: Text(
                          mine ? 'You: $text' : text,
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
    final list = _q.isEmpty
        ? _chats
        : _chats
            .where((c) => ((c['peer'] as Map)['username'] as String)
                .toLowerCase()
                .contains(_q.toLowerCase()))
            .toList();
    if (list.isEmpty) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 0.5, thickness: 0.5, indent: 78),
        itemBuilder: (_, i) => _tile(list[i]),
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
              placeholder: 'Search',
              onChanged: (v) => setState(() => _q = v),
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
                        title: Text(u['username'] as String,
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
