import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'chat_page.dart';
import 'file_widgets.dart';
import 'gif_widgets.dart';
import 'media_viewer.dart';
import 'player.dart';
import 'utils.dart';

/// صفحه‌ی اطلاعات یک کاربر (با زدن روی پروفایلش باز میشه):
/// عکس‌های بزرگ بالا (سوایپ / زدن کنار عکس برای عوض کردن)، اسم، دکمه‌ها، آهنگ پروفایل،
/// بیو و یوزرنیم، و پایین‌تر مدیا / موزیک / فایل‌هایی که برای هم فرستادیم.
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
  final _pc = PageController();
  int _page = 0;
  List<Map<String, dynamic>> _shared = [];
  String _tab = 'media'; // media | music | files | gifs

  bool get _isMe => widget.userId == Api.userId;

  @override
  void initState() {
    super.initState();
    _u = widget.initial;
    _load();
    _loadShared();
    _sub = Api.events.listen((e) {
      if (!mounted) return;
      switch (e['type']) {
        case 'user':
          if (e['user'] is Map && e['user']['id'] == widget.userId) {
            setState(() => _u = Map<String, dynamic>.from(e['user']));
          }
          break;
        case 'hello':
          _load();
          _loadShared();
          break;
        case 'message':
          final m = e['message'];
          if (m is Map && m['file'] != null && (m['from'] == widget.userId || m['to'] == widget.userId)) {
            _loadShared();
          }
          break;
        case 'delete':
          if (e['from'] == widget.userId || e['to'] == widget.userId) _loadShared();
          break;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pc.dispose();
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

  Future<void> _loadShared() async {
    if (_isMe) return;
    try {
      final d = await Api.shared(widget.userId);
      if (mounted) setState(() => _shared = d);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- header
  Widget _letterBg(Map<String, dynamic> u) {
    final id = (u['id'] as num?)?.toInt() ?? 0;
    final name = (u['username'] as String?) ?? '?';
    final c = avatarColor(id);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(c, Colors.white, 0.2)!, Color.lerp(c, Colors.black, 0.35)!],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 140, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _photoTap(TapUpDetails d, Map<String, dynamic> u, int count, double width) {
    final x = d.localPosition.dx;
    if (count > 1 && x < width * 0.3) {
      if (_page > 0) _pc.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else if (count > 1 && x > width * 0.7) {
      if (_page < count - 1) _pc.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      openGallery(context, galleryFromUser(u), _page);
    }
  }

  static const Map<String, String> _tabNames = {'media': 'Media', 'music': 'Music', 'files': 'Files', 'gifs': 'GIFs'};

  double _lp(double a, double b, double t) => a + (b - a) * t;

  void _openChat(Map<String, dynamic> u) {
    if (widget.fromChat) {
      Navigator.of(context).maybePop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatPage(peerId: u['id'] as int, peerName: u['username'] as String),
        ),
      );
    }
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditPage()));
    _load();
  }

  /// هدر تلگرامی: t = 0 یعنی کاملاً باز (عکس بزرگ)، t = 1 یعنی جمع‌شده (نوار بالا با دایره‌ی کوچیک و اسم)
  Widget _header(Map<String, dynamic> u, double t) {
    final photos = userPhotos(u);
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final page = photos.isEmpty ? 0 : _page.clamp(0, photos.length - 1);
    final fadePhoto = (1 - t * 1.5).clamp(0.0, 1.0).toDouble();
    final ease = Curves.easeIn.transform(t);
    final fg = Color.lerp(Colors.white, context.mainText, ease)!;
    final online = u['online'] == true;
    final statusColor = Color.lerp(
        online ? const Color(0xFF8FD1FF) : Colors.white70, online ? tgBlue : context.subText, ease)!;
    final btnTop = topPad + _lp(photos.length > 1 ? 16 : 6, 4, t);
    final lightIcons = t < 0.6 || context.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (lightIcons ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: ClipRect(
        child: Stack(
          children: [
            // زیرلایه‌ی نوار بالا (وقتی عکس محو شد دیده میشه)
            Positioned.fill(child: ColoredBox(color: context.barBg)),
            // عکس‌ها
            Positioned.fill(
              child: IgnorePointer(
                ignoring: fadePhoto < 0.5,
                child: Opacity(
                  opacity: fadePhoto,
                  child: photos.isEmpty
                      ? _letterBg(u)
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _photoTap(d, u, photos.length, size.width),
                          child: PageView.builder(
                            controller: _pc,
                            itemCount: photos.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => Image.network(
                              '${Api.baseUrl}${photos[i]['url']}',
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => _letterBg(u),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // سایه‌ی بالا و پایین تا نوشته‌ها خوانا باشن
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: topPad + 110,
              child: IgnorePointer(
                child: Opacity(
                  opacity: fadePhoto,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 200,
              child: IgnorePointer(
                child: Opacity(
                  opacity: fadePhoto,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // نوار قسمت‌بندی‌شده‌ی بالای عکس (چندتا عکس)
            if (photos.length > 1)
              Positioned(
                left: 8,
                right: 8,
                top: topPad + 8,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: fadePhoto,
                    child: Row(
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i == page ? Colors.white : Colors.white38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            // خط پایین نوار وقتی کاملاً جمع شده
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Opacity(
                opacity: t >= 0.98 ? 1 : 0,
                child: Divider(height: 0.5, thickness: 0.5, color: context.subText.withOpacity(0.25)),
              ),
            ),
            // دایره‌ی کوچیک عکس کنار اسم (وقتی جمع شد)
            Positioned(
              left: 56,
              top: topPad + 10,
              child: Opacity(
                opacity: ((t - 0.7) / 0.3).clamp(0.0, 1.0).toDouble(),
                child: Avatar.fromUser(u, size: 36),
              ),
            ),
            // اسم و وضعیت: از پایین-چپ عکس میره کنار دایره‌ی کوچیک
            Positioned(
              left: _lp(18, 102, t),
              right: 56,
              bottom: _lp(14, 9, t),
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      u['username'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: _lp(32, 18, t),
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        shadows: t < 0.5 ? const [Shadow(blurRadius: 8, color: Colors.black54)] : null,
                      ),
                    ),
                    Text(
                      presenceText(u),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: _lp(15, 12.5, t), color: statusColor),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: btnTop,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: fg),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (_isMe)
              Positioned(
                right: 4,
                top: btnTop,
                child: IconButton(
                  icon: Icon(Icons.edit_rounded, color: fg),
                  onPressed: _editProfile,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- دکمه‌ی سریع + کارت اطلاعات
  Widget _quickActions(Map<String, dynamic> u) {
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 66,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: tgBlue, size: 24),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(color: tgBlue, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          if (_isMe)
            btn(Icons.edit_rounded, 'Edit profile', _editProfile)
          else
            btn(CupertinoIcons.chat_bubble_fill, 'Message', () => _openChat(u)),
        ],
      ),
    );
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied'), duration: const Duration(seconds: 1)));
  }

  Widget _infoRow(String value, String label, {String? copyLabel}) {
    return InkWell(
      onTap: () => _copy(value, copyLabel ?? label),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, textDirection: dirOf(value), style: const TextStyle(fontSize: 17, height: 1.3)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 13.5, color: context.subText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _musicInfoRow(Map<String, dynamic> u) {
    final pm = profileMusicMsg(u);
    if (pm == null) return const SizedBox.shrink();
    final c = AudioCtl.i;
    final artist = audioArtist(pm);
    final title = audioTitle(pm);
    final text = artist != null ? '$artist – $title' : title;
    return InkWell(
      onTap: () async {
        try {
          await c.toggle(pm, [pm]);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this song')));
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(text),
                      style: const TextStyle(fontSize: 17, height: 1.3)),
                  const SizedBox(height: 3),
                  Text('Profile music', style: TextStyle(fontSize: 13.5, color: context.subText)),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: Listenable.merge([c.current, c.playing]),
              builder: (_, __) => Icon(
                c.isCurrent(pm['id']) && c.playing.value ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: tgBlue,
                size: 34,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(Map<String, dynamic> u) {
    final bio = ((u['bio'] as String?) ?? '').trim();
    final rows = <Widget>[
      if (bio.isNotEmpty) _infoRow(bio, 'Bio'),
      _infoRow('@${u['username'] ?? ''}', 'Username'),
      if (u['music'] is Map) _musicInfoRow(u),
    ];
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(Divider(height: 0.5, thickness: 0.5, indent: 18, color: context.subText.withOpacity(0.2)));
      children.add(rows[i]);
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(14)),
      child: Column(children: children),
    );
  }

  // ---------------------------------------------------------------- shared media
  List<Map<String, dynamic>> _ofKind(Set<String> kinds) => _shared.where((m) => kinds.contains(fileKind(m))).toList();

  /// تب‌های چسبنده (مثل تلگرام): فقط تب‌هایی که چیزی توشون هست
  Widget _tabs(List<MapEntry<String, int>> items, String sel) {
    return Container(
      color: context.cardBg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in items)
              InkWell(
                onTap: () => setState(() => _tab = e.key),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: sel == e.key ? tgBlue : Colors.transparent, width: 2.5)),
                  ),
                  child: Text(
                    '${_tabNames[e.key] ?? e.key}  ${e.value}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: sel == e.key ? tgBlue : context.subText,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaTile(Map<String, dynamic> m, List<Map<String, dynamic>> images) {
    final f = fileOf(m)!;
    if (f['kind'] == 'gif') {
      return GestureDetector(
        onTap: () => openVideo(context, m),
        child: LayoutBuilder(
          builder: (_, c) => GifVideo(
            url: Api.fileUrl(f),
            width: c.maxWidth,
            height: c.maxHeight,
            radius: BorderRadius.zero,
          ),
        ),
      );
    }
    if (f['kind'] == 'video') {
      return GestureDetector(
        onTap: () => openVideo(context, m),
        child: Container(
          color: const Color(0xFF111111),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 38),
              Positioned(
                left: 5,
                bottom: 4,
                child: Text(fmtSize(f['size'] as num),
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        final i = images.indexWhere((x) => x['id'] == m['id']);
        openGallery(context, galleryFromMessages(images), i < 0 ? 0 : i);
      },
      child: Image.network(
        Api.fileUrl(f),
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        loadingBuilder: (_, child, p) => p == null ? child : Container(color: context.fieldFill),
        errorBuilder: (_, __, ___) => Container(
          color: context.fieldFill,
          child: Icon(Icons.broken_image_rounded, color: context.subText),
        ),
      ),
    );
  }

  Widget _musicRow(Map<String, dynamic> m, List<Map<String, dynamic>> all) {
    final c = AudioCtl.i;
    final artist = audioArtist(m);
    final title = audioTitle(m);
    final dur = audioDuration(m);
    return InkWell(
      onTap: () async {
        try {
          await c.toggle(m, all);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this song')));
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CoverArt(msg: m, size: 48, radius: 24),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([c.current, c.playing, c.buffering]),
                      builder: (_, __) => c.isCurrent(m['id'])
                          ? const PlayPauseIcon(size: 26)
                          : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(title),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (artist != null)
                    Text(artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: dirOf(artist),
                        style: TextStyle(fontSize: 13.5, color: context.subText)),
                ],
              ),
            ),
            if (dur != null) Text(fmtDur(dur), style: TextStyle(fontSize: 13, color: context.subText)),
          ],
        ),
      ),
    );
  }

  List<Widget> _sharedSlivers() {
    final media = _shared.where((m) {
      final k = fileKind(m);
      return (k == 'image' && !isGifMsg(m)) || k == 'video';
    }).toList();
    final gifs = _shared.where((m) => isGifMsg(m)).toList();
    final music = _ofKind({'audio'});
    final files = _ofKind({'file'});
    final items = <MapEntry<String, int>>[
      if (media.isNotEmpty) MapEntry('media', media.length),
      if (music.isNotEmpty) MapEntry('music', music.length),
      if (files.isNotEmpty) MapEntry('files', files.length),
      if (gifs.isNotEmpty) MapEntry('gifs', gifs.length),
    ];
    if (items.isEmpty) return [];
    var tab = _tab;
    if (!items.any((e) => e.key == tab)) tab = items.first.key;
    final images = media.where((m) => fileKind(m) == 'image').toList();

    Widget grid(List<Map<String, dynamic>> list) => SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _mediaTile(list[i], images),
            childCount: list.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
        );

    final Widget content;
    switch (tab) {
      case 'music':
        content = SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _musicRow(music[i], music),
            childCount: music.length,
          ),
        );
        break;
      case 'files':
        content = SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FileContent(msg: files[i], mine: false, audioQueue: const []),
            ),
            childCount: files.length,
          ),
        );
        break;
      case 'gifs':
        content = grid(gifs);
        break;
      default:
        content = grid(media);
    }
    return [
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      SliverPersistentHeader(
        pinned: true,
        delegate: _PinnedDelegate(height: 46, builder: (_) => _tabs(items, tab)),
      ),
      DecoratedSliver(
        decoration: BoxDecoration(color: context.cardBg),
        sliver: content,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final mq = MediaQuery.of(context);
    final maxH = (mq.size.width * 1.1).clamp(340.0, 520.0).toDouble();
    final minH = mq.padding.top + kToolbarHeight;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: context.chatBg,
        body: u == null
            ? SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: _error != null
                          ? Text(_error!, style: TextStyle(color: context.subText))
                          : const CupertinoActivityIndicator(radius: 14),
                    ),
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedDelegate(height: maxH, minHeight: minH, builder: (t) => _header(u, t)),
                      ),
                      SliverToBoxAdapter(child: _quickActions(u)),
                      SliverToBoxAdapter(child: _infoCard(u)),
                      ..._sharedSlivers(),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                  // نوار پلیر (برای آهنگ پروفایل / آهنگ‌های مشترک)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(top: false, child: const MiniPlayer()),
                  ),
                ],
              ),
      ),
    );
  }
}

/// هدر چسبنده: builder یه عدد t میگیره (۰ = کاملاً باز، ۱ = کاملاً جمع‌شده)
class _PinnedDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final double? minHeight;
  final Widget Function(double t) builder;
  _PinnedDelegate({required this.height, this.minHeight, required this.builder});

  @override
  double get maxExtent => height;

  @override
  double get minExtent => minHeight ?? height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0).toDouble();
    return builder(t);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}

// ===========================================================================
// ویرایش پروفایل خودم: چند عکس، یوزرنیم، بیو، آهنگ پروفایل
// ===========================================================================

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const int _maxPhotos = 10;

  final _name = TextEditingController();
  final _bio = TextEditingController();
  Map<String, dynamic> _me = {};
  bool _loading = true;
  bool _busy = false;
  double? _musicProgress;
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

  // ---- عکس‌ها ----
  Future<void> _addPhotos() async {
    final have = userPhotos(_me).length;
    final slots = _maxPhotos - have;
    if (slots <= 0) {
      setState(() => _error = 'You can have up to $_maxPhotos profile photos');
      return;
    }
    try {
      var picked = await ImagePicker().pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked.isEmpty) return;
      if (picked.length > slots) picked = picked.take(slots).toList();
      setState(() {
        _busy = true;
        _error = null;
      });
      // از آخر به اول آپلود میکنیم تا اولین عکس انتخابی بشه عکس اصلی
      for (final x in picked.reversed) {
        final bytes = await x.readAsBytes();
        final d = await Api.addPhoto(bytes);
        if (mounted) setState(() => _me = d);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photoAction(Future<Map<String, dynamic>> Function() run) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await run();
      if (mounted) setState(() => _me = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _photoMenu(int index) {
    final photos = userPhotos(_me);
    final p = photos[index];
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              openGallery(context, galleryFromUser(_me), index);
            },
            child: const Text('View'),
          ),
          if (index > 0)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _photoAction(() => Api.setMainPhoto(p['id'] as String));
              },
              child: const Text('Make main photo'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _photoAction(() => Api.deletePhoto(p['id'] as String));
            },
            child: const Text('Delete photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _photoTile(Map<String, dynamic> p, int index) {
    return GestureDetector(
      onTap: _busy ? null : () => _photoMenu(index),
      child: Container(
        width: 92,
        height: 92,
        margin: const EdgeInsets.only(right: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                '${Api.baseUrl}${p['url']}',
                fit: BoxFit.cover,
                cacheWidth: 300,
                errorBuilder: (_, __, ___) => Container(color: context.fieldFill),
              ),
              if (index == 0)
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Main', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photosRow() {
    final photos = userPhotos(_me);
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (photos.length < _maxPhotos)
            GestureDetector(
              onTap: _busy ? null : _addPhotos,
              child: Container(
                width: 92,
                height: 92,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: context.fieldFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _busy
                    ? const CupertinoActivityIndicator()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded, color: tgBlue, size: 30),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(color: tgBlue, fontSize: 13)),
                        ],
                      ),
              ),
            ),
          for (var i = 0; i < photos.length; i++) _photoTile(photos[i], i),
        ],
      ),
    );
  }

  // ---- آهنگ پروفایل ----
  Future<void> _pickMusic() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false, withData: false);
    } catch (_) {
      setState(() => _error = 'Could not open the file picker');
      return;
    }
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.path == null) {
      setState(() => _error = 'Could not read the file');
      return;
    }
    if (f.size > Api.maxFileBytes) {
      setState(() => _error = 'File is too large (max 30 MB)');
      return;
    }
    setState(() {
      _error = null;
      _musicProgress = 0;
    });
    try {
      final d = await Api.uploadMusic(f.path!, f.name, onProgress: (v) {
        if (mounted) setState(() => _musicProgress = v);
      });
      if (mounted) setState(() => _me = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _musicProgress = null);
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}
    }
  }

  Future<void> _removeMusic() async {
    await AudioCtl.i.close();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await Api.removeMusic();
      if (mounted) setState(() => _me = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _musicCard() {
    final pm = profileMusicMsg(_me);
    final uploading = _musicProgress != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.fieldFill, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pm != null)
            Row(
              children: [
                CoverArt(msg: pm, size: 48, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(audioTitle(pm),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dirOf(audioTitle(pm)),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      if (audioArtist(pm) != null)
                        Text(audioArtist(pm)!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: dirOf(audioArtist(pm)!),
                            style: TextStyle(fontSize: 13.5, color: context.subText)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935)),
                  onPressed: (_busy || uploading) ? null : _removeMusic,
                ),
              ],
            )
          else
            Text('No song on your profile yet', style: TextStyle(color: context.subText, fontSize: 14.5)),
          if (uploading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (_musicProgress ?? 0) <= 0 ? null : _musicProgress, minHeight: 3),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: (_busy || uploading) ? null : _pickMusic,
            icon: const Icon(Icons.music_note_rounded, size: 20),
            label: Text(pm == null ? 'Choose a song' : 'Change song'),
          ),
          Text(
            'Tip: in the music player, tap “Add to Profile” on any song you received.',
            style: TextStyle(fontSize: 12.5, color: context.subText),
          ),
        ],
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

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.subText)),
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
          Center(child: Avatar.fromUser(_me, size: 110)),
          const SizedBox(height: 8),
          _sectionTitle('PHOTOS (${userPhotos(_me).length}/$_maxPhotos) — the first one is your main photo'),
          _photosRow(),
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
          _sectionTitle('PROFILE MUSIC'),
          _musicCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
