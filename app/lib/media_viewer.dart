import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'player.dart';
import 'utils.dart';

// ---------------------------------------------------------------------------
// گالری عکس (چند عکس، سوایپ بین‌شون، زوم)
// ---------------------------------------------------------------------------

class GalleryImage {
  final String url;
  final String title;
  const GalleryImage(this.url, this.title);
}

/// عکس‌های پیام‌ها (عکس‌های داخل چت)
List<GalleryImage> galleryFromMessages(List<Map<String, dynamic>> msgs) => msgs
    .map((m) => GalleryImage(Api.fileUrl(fileOf(m)!), (fileOf(m)!['name'] as String?) ?? 'Photo'))
    .toList();

/// عکس‌های پروفایل یه کاربر
List<GalleryImage> galleryFromUser(Map<String, dynamic> u) => userPhotos(u)
    .map((p) => GalleryImage('${Api.baseUrl}${p['url']}', (u['username'] as String?) ?? ''))
    .toList();

void openGallery(BuildContext context, List<GalleryImage> images, int index) {
  if (images.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => GalleryPage(images: images, index: index.clamp(0, images.length - 1))),
  );
}

class GalleryPage extends StatefulWidget {
  final List<GalleryImage> images;
  final int index;
  const GalleryPage({super.key, required this.images, required this.index});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgs = widget.images;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(imgs[_i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            if (imgs.length > 1)
              Text('${_i + 1} / ${imgs.length}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: imgs.length,
        onPageChanged: (v) => setState(() => _i = v),
        itemBuilder: (_, i) => Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              imgs[i].url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : Center(
                      child: CircularProgressIndicator(
                        value: p.expectedTotalBytes == null ? null : p.cumulativeBytesLoaded / p.expectedTotalBytes!,
                        color: Colors.white,
                      ),
                    ),
              errorBuilder: (_, __, ___) =>
                  const Text('Could not load the image', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ویدیو: پیش‌نمایش داخل حباب + پلیر تمام‌صفحه
// ---------------------------------------------------------------------------

void openVideo(BuildContext context, Map<String, dynamic> msg) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoViewerPage(msg: msg)));
}

/// پیش‌نمایش ویدیو داخل حباب پیام (فریم اول + دکمه‌ی پخش). با زدن روش، پلیر بزرگ باز میشه.
class VideoThumb extends StatefulWidget {
  final Map<String, dynamic> msg;
  final double width;
  const VideoThumb({super.key, required this.msg, required this.width});

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  // برای اینکه گوشی ضعیف با چندین دیکودر همزمان له نشه
  static int _active = 0;
  static const int _maxActive = 4;

  VideoPlayerController? _c;
  bool _ready = false;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (_active >= _maxActive) return;
    _active++;
    _counted = true;
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(Api.fileUrl(fileOf(widget.msg)!)),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _c = c;
      await c.initialize();
      await c.setVolume(0);
      try {
        await c.seekTo(const Duration(milliseconds: 100));
      } catch (_) {}
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // پیش‌نمایش نشد؛ همون کاشی تیره با دکمه‌ی پخش نمایش داده میشه
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    if (_counted) _active--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final f = fileOf(widget.msg)!;
    final c = _c;
    double h = w * 0.62;
    Widget video = const SizedBox.shrink();
    if (_ready && c != null && c.value.isInitialized && c.value.size.width > 0) {
      final ar = c.value.size.width / c.value.size.height;
      h = (w / ar).clamp(w * 0.55, w * 1.3);
      video = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      );
    }
    final dur = (_ready && c != null) ? c.value.duration : Duration.zero;
    return GestureDetector(
      onTap: () => openVideo(context, widget.msg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: w,
          height: h,
          color: const Color(0xFF111111),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: video),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    dur > Duration.zero ? '${fmtDur(dur)} • ${fmtSize((f['size'] as num))}' : fmtSize((f['size'] as num)),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// پلیر تمام‌صفحه‌ی ویدیو (پخش/توقف، seek، ±۱۰ ثانیه، سرعت، چرخش صفحه)
class VideoViewerPage extends StatefulWidget {
  final Map<String, dynamic> msg;
  const VideoViewerPage({super.key, required this.msg});

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  late final VideoPlayerController _c;
  bool _ready = false;
  String? _error;
  bool _ui = true;
  bool _landscape = false;
  double? _drag; // میلی‌ثانیه، وقتی اسلایدر کشیده میشه
  double _speed = 1.0;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    unawaited(AudioCtl.i.pause()); // موزیک با صدای ویدیو قاطی نشه
    final f = fileOf(widget.msg)!;
    _c = VideoPlayerController.networkUrl(Uri.parse(Api.fileUrl(f)));
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
      _autoHide();
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not play this video');
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying && _drag == null) setState(() => _ui = false);
    });
  }

  void _toggleUi() {
    setState(() => _ui = !_ui);
    if (_ui) _autoHide();
  }

  void _playPause() {
    if (_c.value.isPlaying) {
      _c.pause();
      _hide?.cancel();
    } else {
      // اگه تموم شده بود از اول
      if (_c.value.position >= _c.value.duration && _c.value.duration > Duration.zero) {
        _c.seekTo(Duration.zero);
      }
      _c.play();
      _autoHide();
    }
    setState(() {});
  }

  void _skip(int sec) {
    final v = _c.value;
    var t = v.position + Duration(seconds: sec);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.duration) t = v.duration;
    _c.seekTo(t);
    _autoHide();
  }

  void _rotate() {
    setState(() => _landscape = !_landscape);
    if (_landscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _autoHide();
  }

  void _cycleSpeed() {
    const list = [0.5, 1.0, 1.25, 1.5, 2.0];
    final n = list[(list.indexOf(_speed) + 1) % list.length];
    setState(() => _speed = n);
    _c.setPlaybackSpeed(n);
    _autoHide();
  }

  @override
  Widget build(BuildContext context) {
    final f = fileOf(widget.msg)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleUi,
              child: Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.white70))
                    : !_ready
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
              ),
            ),
          ),
          if (_ready)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_ui,
                child: AnimatedOpacity(
                  opacity: _ui ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _controls(f),
                ),
              ),
            ),
          if (!_ready)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls(Map<String, dynamic> f) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
          stops: [0, 0.22, 0.7, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    (f['name'] as String?) ?? 'Video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
            const Spacer(),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _c,
              builder: (_, v, __) {
                final total = v.duration.inMilliseconds.toDouble();
                final max = total <= 0 ? 1.0 : total;
                final pos = (_drag ?? v.position.inMilliseconds.toDouble()).clamp(0.0, max);
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          icon: const Icon(Icons.replay_10_rounded),
                          onPressed: () => _skip(-10),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _playPause,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: v.isBuffering
                                ? const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                  )
                                : Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white, size: 44),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          iconSize: 36,
                          color: Colors.white,
                          icon: const Icon(Icons.forward_10_rounded),
                          onPressed: () => _skip(10),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Text(fmtDur(Duration(milliseconds: pos.round())),
                              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: pos,
                                max: max,
                                activeColor: tgBlue,
                                inactiveColor: Colors.white30,
                                onChangeStart: (_) => _hide?.cancel(),
                                onChanged: total <= 0 ? null : (x) => setState(() => _drag = x),
                                onChangeEnd: (x) {
                                  _c.seekTo(Duration(milliseconds: x.round()));
                                  setState(() => _drag = null);
                                  _autoHide();
                                },
                              ),
                            ),
                          ),
                          Text(total <= 0 ? '--:--' : fmtDur(v.duration),
                              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _cycleSpeed,
                          child: Text('${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: Icon(_landscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              color: Colors.white, size: 28),
                          onPressed: _rotate,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
