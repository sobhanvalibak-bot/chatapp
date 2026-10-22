import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'chat_page.dart';
import 'profile_page.dart';
import 'utils.dart';

String _fmtDateTime(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}

void _snack(BuildContext context, String t) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
}

// ---------------------------------------------------------------------------
// لیست کاربران
// ---------------------------------------------------------------------------
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  int _seq = 0;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final my = ++_seq;
    try {
      final d = await Api.adminUsers(_q.trim());
      if (!mounted || my != _seq) return;
      setState(() {
        _users = d;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _openUser(Map<String, dynamic> u) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserPage(user: u)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          IconButton(
            tooltip: 'Admin codes',
            icon: const Icon(CupertinoIcons.ticket),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminCodesPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: CupertinoSearchTextField(
              placeholder: 'Search users',
              onChanged: (v) {
                _q = v;
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_users.length} users', style: TextStyle(color: context.subText, fontSize: 13)),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(child: Text('No users found', style: TextStyle(color: context.subText)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _users.length,
        separatorBuilder: (_, __) => const Divider(height: 0.5, thickness: 0.5, indent: 68),
        itemBuilder: (_, i) {
          final u = _users[i];
          return ListTile(
            leading: Avatar.fromUser(u, size: 44, showOnline: true),
            title: Row(
              children: [
                Flexible(
                  child: Text(u['username'] as String,
                      overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                ),
                if (u['isAdmin'] == true) ...[
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.lock_shield_fill, size: 15, color: tgBlue),
                ],
              ],
            ),
            subtitle: Text(presenceText(u),
                style: TextStyle(fontSize: 12.5, color: u['online'] == true ? tgBlue : context.subText)),
            trailing: Icon(CupertinoIcons.chevron_right, size: 16, color: context.subText),
            onTap: () => _openUser(u),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// اطلاعات یه کاربر
// ---------------------------------------------------------------------------
class AdminUserPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const AdminUserPage({super.key, required this.user});

  @override
  State<AdminUserPage> createState() => _AdminUserPageState();
}

class _AdminUserPageState extends State<AdminUserPage> {
  late Map<String, dynamic> _u;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _u = Map<String, dynamic>.from(widget.user);
  }

  bool get _isMe => _u['id'] == Api.userId;

  Future<void> _toggleAdmin() async {
    final make = _u['isAdmin'] != true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(make ? 'Make admin?' : 'Remove admin?'),
        content: Text(make
            ? '@${_u['username']} will get full admin access.'
            : '@${_u['username']} will lose admin access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(make ? 'Make admin' : 'Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final d = await Api.adminSetAdmin(_u['id'] as int, make);
      if (!mounted) return;
      setState(() {
        _u = {..._u, ...d};
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context, e.message);
    }
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: context.subText, fontSize: 14.5))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15.5))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _u['username'] as String;
    final bio = ((_u['bio'] as String?) ?? '').trim();
    final music = _u['music'];
    return Scaffold(
      appBar: AppBar(title: Text('@$name', textDirection: TextDirection.ltr)),
      body: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 40),
        children: [
          Center(child: Avatar.fromUser(_u, size: 104, showOnline: true)),
          const SizedBox(height: 12),
          Center(child: Text(name, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          Center(child: Text(presenceText(_u), style: TextStyle(color: _u['online'] == true ? tgBlue : context.subText))),
          const SizedBox(height: 18),
          const Divider(height: 0.5, thickness: 0.5),
          _info('ID', '${_u['id']}'),
          _info('Username', '@$name'),
          _info('Bio', bio.isEmpty ? '—' : bio),
          _info('Role', _u['isAdmin'] == true ? 'Admin' : 'User'),
          _info('Joined', _fmtDateTime((_u['createdAt'] as num?)?.toInt() ?? 0)),
          _info('Last seen', _u['online'] == true ? 'online' : _fmtDateTime((_u['lastSeen'] as num?)?.toInt() ?? 0)),
          _info('Profile photos', '${(_u['photos'] as List?)?.length ?? 0}'),
          _info('Profile music', music is Map ? ((music['meta']?['title'] as String?) ?? music['name'] as String) : '—'),
          _info('Messages sent', '${_u['sentCount'] ?? 0}'),
          _info('Messages received', '${_u['receivedCount'] ?? 0}'),
          const Divider(height: 0.5, thickness: 0.5),
          const SizedBox(height: 16),
          if (!_isMe)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatPage(peerId: _u['id'] as int, peerName: name)),
                ),
                icon: const Icon(CupertinoIcons.chat_bubble_fill, size: 18),
                label: const Text('Open chat'),
              ),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfilePage(userId: _u['id'] as int, initial: _u)),
              ),
              icon: const Icon(CupertinoIcons.person_crop_circle, size: 18),
              label: const Text('View profile'),
            ),
          ),
          if (!_isMe) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _toggleAdmin,
                icon: Icon(CupertinoIcons.lock_shield, size: 18, color: _u['isAdmin'] == true ? const Color(0xFFFF5A52) : null),
                label: Text(_u['isAdmin'] == true ? 'Remove admin' : 'Make admin',
                    style: TextStyle(color: _u['isAdmin'] == true ? const Color(0xFFFF5A52) : null)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// کدهای یک‌بارمصرف
// ---------------------------------------------------------------------------
class AdminCodesPage extends StatefulWidget {
  const AdminCodesPage({super.key});

  @override
  State<AdminCodesPage> createState() => _AdminCodesPageState();
}

class _AdminCodesPageState extends State<AdminCodesPage> {
  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;
  bool _busy = false;
  String? _newCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.adminCodes();
      if (!mounted) return;
      setState(() {
        _codes = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, e.message);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final d = await Api.adminCreateCode();
      if (!mounted) return;
      setState(() {
        _newCode = d['code'] as String;
        _busy = false;
      });
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context, e.message);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await Api.adminDeleteCode(id);
      _load();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin codes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
        children: [
          Text(
            'Each code works once. When someone types it in the search box and presses Enter, '
            'the code is deleted and they become an admin.',
            style: TextStyle(color: context.subText, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: const Text('Generate new code'),
          ),
          if (_newCode != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tgBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New code (shown only once):', style: TextStyle(fontSize: 13.5)),
                  const SizedBox(height: 8),
                  SelectableText(_newCode!,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _newCode!));
                      _snack(context, 'Copied');
                    },
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Unused codes (${_codes.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CupertinoActivityIndicator()))
          else if (_codes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No unused codes', style: TextStyle(color: context.subText)),
            )
          else
            for (final c in _codes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(CupertinoIcons.ticket, color: tgBlue),
                title: Text('Created ${_fmtDateTime((c['createdAt'] as num).toInt())}'),
                subtitle: Text(c['createdBy'] == null ? 'by the system' : 'by @${c['createdBy']}'),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(CupertinoIcons.delete, color: Color(0xFFFF5A52), size: 20),
                  onPressed: () => _delete(c['id'] as String),
                ),
              ),
        ],
      ),
    );
  }
}
