import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'admin_page.dart';
import 'api.dart';
import 'attheme.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'permissions_page.dart';
import 'player.dart';
import 'profile_page.dart';
import 'utils.dart';

/// صفحه‌ی اصلی: نوار شناور پایین با سه تب Profile / Chat / Settings
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 1; // Chat
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _sub = Api.events.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'user') {
        final u = e['user'];
        if (u is Map && u['id'] == Api.userId) {
          Api.me = Map<String, dynamic>.from(u);
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      await Api.refreshMe();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchTo(Account a) async {
    if (a.id == Api.userId) return;
    await AudioCtl.i.close();
    await Api.switchTo(a);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (r) => false,
    );
  }

  /// منوی شیشه‌ای حساب‌ها (نگه داشتن روی تب Profile)
  void _accountMenu() {
    HapticFeedback.mediumImpact();
    final bottom = MediaQuery.of(context).padding.bottom;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Accounts',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim, _) {
        final dark = ctx.dark;
        Widget row(Widget leading, String label, {bool on = false, Color? color, required VoidCallback onTap}) {
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 17, color: color ?? (dark ? Colors.white : Colors.black87))),
                  ),
                  if (on) Icon(CupertinoIcons.check_mark, size: 18, color: tgBlue),
                ],
              ),
            ),
          );
        }

        final items = <Widget>[];
        for (final a in Api.accounts) {
          if (items.isNotEmpty) items.add(Divider(height: 1, thickness: 0.6, color: dark ? Colors.white12 : Colors.black12));
          final mineNow = a.id == Api.userId;
          items.add(row(
            Avatar(id: a.id, name: a.username, size: 34, url: mineNow ? (Api.me?['avatar'] as String?) : null),
            a.username,
            on: mineNow,
            onTap: () => _switchTo(a),
          ));
        }
        items.add(Divider(height: 1, thickness: 0.6, color: dark ? Colors.white12 : Colors.black12));
        items.add(row(
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? Colors.white12 : Colors.black12),
            child: Icon(CupertinoIcons.plus, size: 18, color: tgBlue),
          ),
          'Add account',
          color: tgBlue,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage(addingAccount: true)),
          ),
        ));

        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 18, bottom: 96 + bottom),
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              alignment: Alignment.bottomLeft,
              child: FadeTransition(
                opacity: anim,
                child: Material(
                  type: MaterialType.transparency,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                      child: Container(
                        width: 250,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: dark
                                ? const [Color(0xDD3A3550), Color(0xDD2A3A4C), Color(0xDD4A3430)]
                                : const [Color(0xEEEFE4F0), Color(0xEEDDEBF0), Color(0xEEF2E3E0)],
                          ),
                          border: Border.all(color: dark ? Colors.white10 : Colors.white54, width: 0.8),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: items),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tabItem({
    required int index,
    required String label,
    required Widget icon,
    VoidCallback? onLong,
  }) {
    final on = _tab == index;
    final color = on ? tgBlue : (context.dark ? const Color(0xFFC5D0DC) : Colors.black54);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        onLongPress: onLong,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: on ? tgBlue.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 26, child: Center(child: icon)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    final dark = context.dark;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 18,
      right: 18,
      bottom: 14 + bottom,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: dark ? const Color(0xB31C2733) : const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: dark ? Colors.white12 : Colors.black12, width: 0.8),
            ),
            child: Row(
              children: [
                _tabItem(
                  index: 0,
                  label: 'Profile',
                  // عکس پروفایل؛ اگه نبود حرف اول اسم
                  icon: Avatar(
                    id: Api.userId ?? 0,
                    name: Api.username ?? '?',
                    size: 26,
                    url: Api.me?['avatar'] as String?,
                  ),
                  onLong: _accountMenu,
                ),
                _tabItem(
                  index: 1,
                  label: 'Chat',
                  icon: Icon(CupertinoIcons.chat_bubble_2_fill,
                      size: 24, color: _tab == 1 ? tgBlue : (dark ? const Color(0xFFC5D0DC) : Colors.black54)),
                ),
                _tabItem(
                  index: 2,
                  label: 'Settings',
                  icon: Icon(CupertinoIcons.settings,
                      size: 24, color: _tab == 2 ? tgBlue : (dark ? const Color(0xFFC5D0DC) : Colors.black54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              _ProfileTab(onChanged: () => setState(() {})),
              const HomePage(),
              const _SettingsTab(),
            ],
          ),
          _bar(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// تب Profile
// ---------------------------------------------------------------------------
class _ProfileTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _ProfileTab({required this.onChanged});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  @override
  void initState() {
    super.initState();
    Api.meTick.addListener(_onMe);
  }

  @override
  void dispose() {
    Api.meTick.removeListener(_onMe);
    super.dispose();
  }

  void _onMe() {
    if (mounted) setState(() {});
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// انتخاب فایل .attheme از حافظه و اعمالش
  Future<void> _importTheme() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        _snack('Could not read the file');
        return;
      }
      final ok = await AtTheme.applyBytes(bytes, f.name);
      if (mounted) setState(() {});
      _snack(ok ? 'Theme applied' : 'This is not a valid .attheme file');
    } catch (_) {
      _snack('Could not import the theme');
    }
  }

  void _themeMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) {
        Widget item(String label, ThemeMode m) => CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                if (AtTheme.current.value != null) AtTheme.remove();
                Api.setTheme(m);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (Api.themeMode.value == m && AtTheme.current.value == null) ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.check_mark, size: 18),
                  ],
                ],
              ),
            );
        return CupertinoActionSheet(
          title: const Text('Appearance'),
          actions: [
            item('Light', ThemeMode.light),
            item('Dark', ThemeMode.dark),
            item('System default', ThemeMode.system),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _importTheme();
              },
              child: Text(AtTheme.current.value == null
                  ? 'Import theme (.attheme)'
                  : 'Import another theme (.attheme)'),
            ),
            if (AtTheme.current.value != null)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () async {
                  Navigator.pop(ctx);
                  await AtTheme.remove();
                  if (mounted) setState(() {});
                },
                child: Text('Remove "${AtTheme.current.value!.name}"'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        );
      },
    );
  }

  Widget _row(IconData icon, String label, VoidCallback onTap, {Color? color, String? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? tgBlue),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: TextStyle(fontSize: 16.5, color: color))),
            if (trailing != null) Text(trailing, style: TextStyle(color: context.subText, fontSize: 14)),
            if (color == null) Icon(CupertinoIcons.chevron_right, size: 16, color: context.subText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = Api.me;
    final name = (me?['username'] as String?) ?? Api.username ?? '';
    final bio = ((me?['bio'] as String?) ?? '').trim();
    final themeLabel = AtTheme.current.value != null
        ? AtTheme.current.value!.name
        : Api.themeMode.value == ThemeMode.dark
        ? 'Dark'
        : (Api.themeMode.value == ThemeMode.light ? 'Light' : 'System');
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 110),
        children: [
          Center(
            child: Avatar(id: Api.userId ?? 0, name: name, size: 104, url: me?['avatar'] as String?),
          ),
          const SizedBox(height: 12),
          Center(child: Text(displayNameOf(me ?? {}, fallback: name), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          Center(child: Text('@$name', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 14.5, color: tgBlue))),
          if (bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
              child: Text(bio, textAlign: TextAlign.center, textDirection: dirOf(bio), style: TextStyle(color: context.subText, fontSize: 15)),
            ),
          const SizedBox(height: 22),
          _row(CupertinoIcons.pencil, 'Edit profile', () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditPage()));
            try {
              await Api.refreshMe();
            } catch (_) {}
            if (mounted) setState(() {});
            widget.onChanged();
          }),
          const Divider(height: 0.5, thickness: 0.5, indent: 54),
          _row(CupertinoIcons.moon_fill, 'Appearance', () async {
            _themeMenu();
          }, trailing: themeLabel),
          const Divider(height: 0.5, thickness: 0.5, indent: 54),
          if (Api.isAdmin) ...[
            _row(CupertinoIcons.lock_shield_fill, 'Admin panel',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage()))),
            const Divider(height: 0.5, thickness: 0.5, indent: 54),
          ],
          _row(CupertinoIcons.shield_lefthalf_fill, 'Permissions',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsPage()))),
          const Divider(height: 0.5, thickness: 0.5, indent: 54),
          _row(CupertinoIcons.globe, 'Server address', () async {
            await showServerDialog(context);
          }),
          const Divider(height: 0.5, thickness: 0.5, indent: 54),
          _row(CupertinoIcons.square_arrow_right, 'Log out @$name', () async {
            await AudioCtl.i.close();
            await Api.logout();
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => Api.loggedIn ? const MainShell() : const LoginPage()),
              (r) => false,
            );
          }, color: const Color(0xFFFF5A52)),
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Center(
              child: Text('Hold the Profile tab to switch accounts', style: TextStyle(color: context.subText, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// تب Settings: ویرایش اسم، فامیلی، یوزرنیم، بیو و عکس پروفایل
// ---------------------------------------------------------------------------
class _Field {
  final String label;
  final String value;
  final int maxLen;
  final int lines;
  final String? prefix;
  final bool ltr;
  const _Field(this.label, this.value, {this.maxLen = 40, this.lines = 1, this.prefix, this.ltr = false});
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    Api.meTick.addListener(_onMe);
    Api.refreshMe().catchError((_) => <String, dynamic>{});
  }

  @override
  void dispose() {
    Api.meTick.removeListener(_onMe);
    super.dispose();
  }

  void _onMe() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'Version ${i.version} (build ${i.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _version = 'Version 1.0.0');
    }
  }

  Future<void> _prompt(String title, List<_Field> fields, Future<void> Function(List<String>) onSave) async {
    final ctrls = [for (final f in fields) TextEditingController(text: f.value)];
    String? err;
    bool busy = false;
    await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TextField(
                      controller: ctrls[i],
                      autofocus: i == 0,
                      maxLength: fields[i].maxLen,
                      minLines: fields[i].lines,
                      maxLines: fields[i].lines > 1 ? 5 : 1,
                      autocorrect: !fields[i].ltr,
                      textDirection: fields[i].ltr ? TextDirection.ltr : null,
                      decoration: InputDecoration(labelText: fields[i].label, prefixText: fields[i].prefix),
                    ),
                  ),
                if (err != null)
                  Text(err!, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await onSave([for (final c in ctrls) c.text.trim()]);
                        if (dctx.mounted) Navigator.of(dctx).pop(true);
                      } on ApiException catch (e) {
                        setD(() {
                          busy = false;
                          err = e.message;
                        });
                      }
                    },
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    for (final c in ctrls) {
      c.dispose();
    }
    try {
      await Api.refreshMe();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _editName() {
    final me = Api.me ?? {};
    _prompt(
      'Name',
      [
        _Field('First name', (me['firstName'] as String?) ?? ''),
        _Field('Last name', (me['lastName'] as String?) ?? ''),
      ],
      (v) async {
        await Api.updateProfile(firstName: v[0], lastName: v[1]);
      },
    );
  }

  void _editUsername() {
    final me = Api.me ?? {};
    final cur = (me['username'] as String?) ?? Api.username ?? '';
    _prompt(
      'Username',
      [_Field('Username', cur, maxLen: 32, prefix: '@', ltr: true)],
      (v) async {
        if (v[0].isEmpty) throw ApiException('Username cannot be empty');
        if (v[0] != cur) await Api.updateProfile(username: v[0]);
      },
    );
  }

  void _editBio() {
    final me = Api.me ?? {};
    _prompt(
      'Bio',
      [_Field('Bio', (me['bio'] as String?) ?? '', maxLen: 200, lines: 3)],
      (v) async {
        await Api.updateProfile(bio: v[0]);
      },
    );
  }

  Future<void> _openEditPage() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditPage()));
    try {
      await Api.refreshMe();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Widget _tile(IconData icon, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: tgBlue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(value),
                      style: const TextStyle(fontSize: 16.5)),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(fontSize: 13, color: context.subText)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: context.subText),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.subText)),
      );

  @override
  Widget build(BuildContext context) {
    final me = Api.me ?? {'id': Api.userId ?? 0, 'username': Api.username ?? ''};
    final username = (me['username'] as String?) ?? Api.username ?? '';
    final full = displayNameOf(me, fallback: username);
    final first = ((me['firstName'] as String?) ?? '').trim();
    final last = ((me['lastName'] as String?) ?? '').trim();
    final nameValue = '$first $last'.trim();
    final bio = ((me['bio'] as String?) ?? '').trim();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 110),
        children: [
          Center(
            child: GestureDetector(
              onTap: _openEditPage,
              child: Avatar.fromUser(me, size: 96),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(full, textDirection: dirOf(full), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          Center(child: Text('@$username', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 14.5, color: context.subText))),
          Center(
            child: TextButton(
              onPressed: _openEditPage,
              child: const Text('Change profile photo', style: TextStyle(fontSize: 15)),
            ),
          ),
          _section('ACCOUNT'),
          _tile(CupertinoIcons.person_fill, 'Name', nameValue.isEmpty ? 'Not set' : nameValue, _editName),
          const Divider(height: 0.5, thickness: 0.5, indent: 56),
          _tile(CupertinoIcons.at, 'Username', '@$username', _editUsername),
          const Divider(height: 0.5, thickness: 0.5, indent: 56),
          _tile(CupertinoIcons.info_circle_fill, 'Bio', bio.isEmpty ? 'Add a few words about yourself' : bio, _editBio),
          const Divider(height: 0.5, thickness: 0.5, indent: 56),
          _tile(CupertinoIcons.photo_fill_on_rectangle_fill, 'Profile photos, music and more', 'Edit profile', _openEditPage),
          // فقط برای ادمین‌ها نمایش داده میشه
          if (Api.isAdmin) ...[
            _section('ADMIN'),
            _tile(
              CupertinoIcons.lock_shield_fill,
              'Manage users and invite codes',
              'Admin panel',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPage())),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: Center(child: Text(_version, style: TextStyle(fontSize: 13.5, color: context.subText))),
          ),
        ],
      ),
    );
  }
}
