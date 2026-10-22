import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'chat_page.dart';
import 'utils.dart';

/// نمایش تمام‌صفحه‌ی عکس پروفایل
void showPhoto(BuildContext context, Map<String, dynamic> u) {
  final url = u['avatar'] as String?;
  if (url == null || url.isEmpty) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(u['username'] as String? ?? '', style: const TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network('${Api.baseUrl}$url', fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
}

/// صفحه‌ی اطلاعات یک کاربر (با زدن روی پروفایلش باز میشه)
class ProfilePage extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? initial;
  final bool fromChat;
  const ProfilePage({super.key, required this.userId, this.initial, this.fromChat = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _u;
  String? _error;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _u = widget.initial;
    _load();
    _sub = Api.events.listen((e) {
      if (e['type'] == 'user' && e['user'] is Map && e['user']['id'] == widget.userId) {
        if (mounted) setState(() => _u = Map<String, dynamic>.from(e['user']));
      } else if (e['type'] == 'hello') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.user(widget.userId);
      if (!mounted) return;
      setState(() {
        _u = d;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && _u == null) setState(() => _error = e.message);
    }
  }

  Widget _card(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: context.fieldFill, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: context.subText)),
          const SizedBox(height: 4),
          Text(value, textDirection: dirOf(value), style: const TextStyle(fontSize: 16, height: 1.35)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: u == null
          ? Center(
              child: _error != null
                  ? Text(_error!, style: TextStyle(color: context.subText))
                  : const CupertinoActivityIndicator(radius: 14),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () => showPhoto(context, u),
                    child: Avatar.fromUser(u, size: 120),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    u['username'] as String? ?? '',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    presenceText(u),
                    style: TextStyle(
                      fontSize: 14,
                      color: u['online'] == true ? tgBlue : context.subText,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _card('Username', '@${u['username'] ?? ''}'),
                if (((u['bio'] as String?) ?? '').isNotEmpty) _card('Bio', u['bio'] as String),
                if (!widget.fromChat && u['id'] != Api.userId)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                                peerId: u['id'] as int, peerName: u['username'] as String),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.chat_bubble_fill, size: 18),
                        label: const Text('Send message',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tgBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// ویرایش پروفایل خودم: عکس، یوزرنیم، بیو
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  Map<String, dynamic> _me = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _me = Api.me ?? {'id': Api.userId ?? 0, 'username': Api.username ?? ''};
    _name.text = (_me['username'] as String?) ?? '';
    _bio.text = (_me['bio'] as String?) ?? '';
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.refreshMe();
      if (!mounted) return;
      setState(() {
        _me = d;
        _name.text = (d['username'] as String?) ?? '';
        _bio.text = (d['bio'] as String?) ?? '';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _pick() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final bytes = await x.readAsBytes();
      final d = await Api.uploadAvatar(bytes);
      if (mounted) setState(() => _me = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await Api.removeAvatar();
      if (mounted) setState(() => _me = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _photoMenu() {
    final has = ((_me['avatar'] as String?) ?? '').isNotEmpty;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pick();
            },
            child: const Text('Choose from gallery'),
          ),
          if (has)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                _removePhoto();
              },
              child: const Text('Remove photo'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final bio = _bio.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Username cannot be empty');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.updateProfile(
        username: name == _me['username'] ? null : name,
        bio: bio == ((_me['bio'] as String?) ?? '') ? null : bio,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        filled: true,
        fillColor: context.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _busy || _loading ? null : _save,
            child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _photoMenu,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Avatar.fromUser(_me, size: 110),
                  if (_busy)
                    Container(
                      width: 110,
                      height: 110,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
                      child: const CupertinoActivityIndicator(color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _photoMenu,
              child: const Text('Set new photo'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            maxLength: 32,
            decoration: _dec('Username', prefix: '@'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _bio,
            maxLength: 200,
            minLines: 2,
            maxLines: 5,
            decoration: _dec('Bio'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
