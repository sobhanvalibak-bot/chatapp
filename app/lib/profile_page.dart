import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'chat_page.dart';
import 'file_widgets.dart';
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
  int _tab = 0; // 0 = Media, 1 = Music, 2 = Files

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

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _musicPill(Map<String, dynamic> u) {
    final pm = profileMusicMsg(u);
    if (pm == null) return const SizedBox.shrink();
    final c = AudioCtl.i;
    final artist = audioArtist(pm);
    final title = audioTitle(pm);
    final text = artist != null ? '$artist – $title' : title;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () async {
          try {
            await c.toggle(pm, [pm]);
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this song')));
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(22)),
          child: Row(
            children: [
              const Icon(Icons.music_note_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(text),
                    style: const TextStyle(color: Colors.white, fontSize: 14.5)),
              ),
              AnimatedBuilder(
                animation: Listenable.merge([c.current, c.playing]),
                builder: (_, __) => Icon(
                  c.isCurrent(pm['id']) && c.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> u) {
    final photos = userPhotos(u);
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final h = (size.width * 1.3).clamp(380.0, 600.0);
    final page = photos.isEmpty ? 0 : _page.clamp(0, photos.length - 1);
    final hasMusic = u['music'] is Map;
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
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
          // سایه‌ی بالا و پایین تا نوشته‌ها خوانا باشن
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: topPad + 110,
            child: const IgnorePointer(
              child: DecoratedBox(
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 340,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
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
          Positioned(
            left: 4,
            top: topPad + (photos.length > 1 ? 18 : 6),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  u['username'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  presenceText(u),
                  style: TextStyle(
                    fontSize: 15,
                    color: u['online'] == true ? const Color(0xFF8FD1FF) : Colors.white70,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_isMe)
                      _actionTile(Icons.edit_rounded, 'Edit profile', () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditPage()));
                        _load();
                      })
                    else
                      _actionTile(CupertinoIcons.chat_bubble_fill, 'Message', () {
                        if (widget.fromChat) {
                          Navigator.of(context).maybePop();
                        } else {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ChatPage(peerId: u['id'] as int, peerName: u['username'] as String),
                            ),
                          );
                        }
                      }),
                  ],
                ),
                if (hasMusic) _musicPill(u),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- info rows
  Widget _info(String value, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(value, textDirection: dirOf(value), style: const TextStyle(fontSize: 18, height: 1.35)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 14, color: context.subText)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- shared media
  List<Map<String, dynamic>> _ofKind(Set<String> kinds) => _shared.where((m) => kinds.contains(fileKind(m))).toList();

  Widget _tabs(int media, int music, int files, int tab) {
    Widget t(int i, String label, int n) {
      final sel = tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: sel ? tgBlue : Colors.transparent, width: 2.5),
              ),
            ),
            child: Text(
              '$label  $n',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: sel ? tgBlue : context.subText,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.subText.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          if (media > 0) t(0, 'Media', media),
          if (music > 0) t(1, 'Music', music),
          if (files > 0) t(2, 'Files', files),
        ],
      ),
    );
  }

  Widget _mediaTile(Map<String, dynamic> m, List<Map<String, dynamic>> images) {
    final f = fileOf(m)!;
    if (f['kind'] == 'video' || f['kind'] == 'gif') {
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
    final media = _ofKind({'image', 'video', 'gif'});
    final music = _ofKind({'audio'});
    final files = _ofKind({'file'});
    if (media.isEmpty && music.isEmpty && files.isEmpty) return [];
    var tab = _tab;
    final counts = [media.length, music.length, files.length];
    if (counts[tab] == 0) tab = counts.indexWhere((n) => n > 0);
    final images = media.where((m) => fileKind(m) == 'image').toList();
    return [
      SliverToBoxAdapter(child: _tabs(media.length, music.length, files.length, tab)),
      if (tab == 0)
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _mediaTile(media[i], images),
            childCount: media.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
        )
      else if (tab == 1)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _musicRow(music[i], music),
            childCount: music.length,
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FileContent(msg: files[i], mine: false, audioQueue: const []),
            ),
            childCount: files.length,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
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
                      SliverToBoxAdapter(child: _header(u)),
                      if (((u['bio'] as String?) ?? '').isNotEmpty)
                        SliverToBoxAdapter(child: _info(u['bio'] as String, 'Bio')),
                      SliverToBoxAdapter(child: _info('@${u['username'] ?? ''}', 'Username')),
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
