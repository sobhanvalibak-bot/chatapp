import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

class PermItem {
  final Permission permission;
  final String title;
  final String why;
  final IconData icon;
  const PermItem(this.permission, this.title, this.why, this.icon);
}

/// مجوزهایی که اپ برای کار با فایل‌ها لازم داره (بسته به نسخه‌ی اندروید)
class Perm {
  static List<PermItem>? _cache;
  static bool askedThisSession = false;

  static Future<int> _sdk() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      return 33;
    }
  }

  static Future<List<PermItem>> needed() async {
    if (_cache != null) return _cache!;
    final sdk = await _sdk();
    final list = <PermItem>[
      const PermItem(Permission.notification, 'Notifications',
          'Show the music player in the notification bar and lock screen, with play/pause controls.', Icons.notifications_rounded),
    ];
    if (sdk >= 33) {
      list.addAll(const [
        PermItem(Permission.photos, 'Photos', 'Pick and send pictures from your gallery.', Icons.image_rounded),
        PermItem(Permission.videos, 'Videos', 'Pick and send videos from your gallery.', Icons.videocam_rounded),
        PermItem(Permission.audio, 'Music & audio', 'Pick and send songs, and read their title, artist and cover.',
            Icons.music_note_rounded),
      ]);
    } else {
      list.add(const PermItem(Permission.storage, 'Files & media',
          'Pick and send photos, videos, music and other files from your phone.', Icons.folder_rounded));
    }
    return _cache = list;
  }

  static Future<bool> allGranted() async {
    for (final it in await needed()) {
      final s = await it.permission.status;
      if (!(s.isGranted || s.isLimited)) return false;
    }
    return true;
  }
}

/// بار اول (بعد از ورود) اگه مجوزی داده نشده باشه صفحه‌ی مجوزها رو نشون میده
Future<void> maybeAskPermissions(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('permsAsked') == true) return;
    if (await Perm.allGranted()) {
      await p.setBool('permsAsked', true);
      return;
    }
    await p.setBool('permsAsked', true);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsPage()));
  } catch (_) {}
}

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> with WidgetsBindingObserver {
  List<PermItem> _items = [];
  final Map<Permission, PermissionStatus> _status = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // وقتی از تنظیمات سیستم برمی‌گرده، وضعیت‌ها رو دوباره بخون
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final items = await Perm.needed();
    for (final it in items) {
      _status[it.permission] = await it.permission.status;
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _request(PermItem it) async {
    final s = _status[it.permission];
    if (s != null && s.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    final r = await it.permission.request();
    if (!mounted) return;
    setState(() => _status[it.permission] = r);
  }

  Future<void> _requestAll() async {
    for (final it in _items) {
      final s = _status[it.permission];
      if (s != null && (s.isGranted || s.isLimited)) continue;
      if (s != null && s.isPermanentlyDenied) continue;
      final r = await it.permission.request();
      if (!mounted) return;
      setState(() => _status[it.permission] = r);
    }
    final blocked = _items.any((it) => _status[it.permission]?.isPermanentlyDenied == true);
    if (blocked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some permissions are blocked. Tap "Settings" next to them.')),
      );
    }
  }

  bool _ok(PermissionStatus? s) => s != null && (s.isGranted || s.isLimited);

  Widget _chip(PermissionStatus? s) {
    String t;
    Color c;
    if (_ok(s)) {
      t = 'Allowed';
      c = const Color(0xFF4CD964);
    } else if (s != null && s.isPermanentlyDenied) {
      t = 'Blocked';
      c = Colors.redAccent;
    } else {
      t = 'Not allowed';
      c = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(t, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _card(PermItem it) {
    final s = _status[it.permission];
    final ok = _ok(s);
    final blocked = s != null && s.isPermanentlyDenied;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tgBlue.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(it.icon, color: tgBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    _chip(s),
                  ],
                ),
                const SizedBox(height: 4),
                Text(it.why, style: TextStyle(fontSize: 13.5, color: context.subText)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!ok)
            TextButton(
              onPressed: () => _request(it),
              child: Text(blocked ? 'Settings' : 'Allow'),
            )
          else
            const Icon(Icons.check_circle, color: Color(0xFF4CD964)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _items.isNotEmpty && _items.every((it) => _ok(_status[it.permission]));
    return Scaffold(
      backgroundColor: context.chatBg,
      appBar: AppBar(title: const Text('Permissions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
                  child: Text(
                    'To send and play files (up to 30 MB), the app needs access to your media and notifications. '
                    'You can change these any time from here or from Android settings.',
                    style: TextStyle(fontSize: 14, color: context.subText),
                  ),
                ),
                for (final it in _items) _card(it),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: tgBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: allOk ? () => Navigator.of(context).maybePop() : _requestAll,
                      child: Text(allOk ? 'All set' : 'Allow all', style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
                if (_items.any((it) => _status[it.permission]?.isPermanentlyDenied == true))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: openAppSettings,
                      child: const Text('Open Android app settings'),
                    ),
                  ),
              ],
            ),
    );
  }
}
