import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'utils.dart';

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
  StreamSubscription? _sub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Api.messages.listen((m) {
      if (m['from'] == widget.peerId || m['to'] == widget.peerId) {
        _add(m);
        if (m['from'] == widget.peerId) Api.markRead(widget.peerId);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      if (!mounted) return;
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

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    try {
      final m = await Api.send(widget.peerId, t);
      _add(m);
    } on ApiException catch (e) {
      if (!mounted) return;
      _ctrl.text = t;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['from'] == Api.userId;
    final text = m['text'] as String;
    const r = Radius.circular(18);
    const tail = Radius.circular(4);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFEFFDDE) : Colors.white,
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
            Text(text, textDirection: dirOf(text), style: const TextStyle(fontSize: 16, height: 1.3)),
            const SizedBox(height: 2),
            Text(
              fmtHm(m['createdAt'] as int),
              style: TextStyle(
                fontSize: 11,
                color: mine ? const Color(0xFF5DAE55) : Colors.grey,
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
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    if (_msgs.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text('اولین پیام را بفرستید 👋', style: TextStyle(color: Colors.black54)),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _msgs.length,
      itemBuilder: (_, i) => _bubble(_msgs[_msgs.length - 1 - i]),
    );
  }

  Widget _inputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'پیام',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, v, __) {
                final can = v.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: can ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: can ? tgBlue : Colors.grey.shade300,
                    ),
                    child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 22),
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
    return Scaffold(
      backgroundColor: const Color(0xFFE7EBF0),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(id: widget.peerId, name: widget.peerName, size: 34),
            const SizedBox(width: 10),
            Text(widget.peerName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _list()),
          _inputBar(),
        ],
      ),
    );
  }
}
