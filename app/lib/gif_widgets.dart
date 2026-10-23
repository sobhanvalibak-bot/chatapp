import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'media_viewer.dart';
import 'utils.dart';

// ---------------------------------------------------------------------------
// ویدیوی بی‌صدا و لوپ‌شونده (گیف)
// ---------------------------------------------------------------------------

/// پخش خودکار، بی‌صدا و بی‌نهایت. برای اینکه گوشی ضعیف با چندین دیکودر همزمان له نشه،
/// حداکثر چند تا گیف همزمان پخش میشن؛ بقیه یه کاشی تیره (یا thumb) نشون میدن.
class GifVideo extends StatefulWidget {
  final String url;
  final String? thumb; // base64 JPEG ریز (اختیاری)
  final double width;
  final double? height; // null = از نسبت ویدیو حساب میشه
  final BorderRadius radius;
  final bool badge;
  const GifVideo({
    super.key,
    required this.url,
    required this.width,
    this.thumb,
    this.height,
    this.radius = const BorderRadius.all(Radius.circular(12)),
    this.badge = false,
  });

  @override
  State<GifVideo> createState() => _GifVideoState();
}

class _GifVideoState extends State<GifVideo> {
  static int _active = 0;
  static const int _maxActive = 6;

  VideoPlayerController? _c;
  bool _ready = false;
  bool _counted = false;
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    final t = widget.thumb;
    if (t != null && t.isNotEmpty) {
      try {
        _thumb = base64Decode(t);
      } catch (_) {}
    }
    _init();
  }

  Future<void> _init() async {
    if (_active >= _maxActive) return;
    _active++;
    _counted = true;
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _c = c;
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // پخش نشد؛ همون کاشی تیره نمایش داده میشه
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
    final c = _c;
    final ok = _ready && c != null && c.value.isInitialized && c.value.size.width > 0;
    double h = widget.height ?? w * 0.62;
    Widget video = const SizedBox.shrink();
    if (ok) {
      if (widget.height == null) {
        final ar = c.value.size.width / c.value.size.height;
        h = (w / ar).clamp(w * 0.55, w * 1.3);
      }
      video = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      );
    }
    return ClipRRect(
      borderRadius: widget.radius,
      child: Container(
        width: w,
        height: h,
        color: const Color(0xFF111111),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumb != null && !ok) Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true),
            video,
            if (widget.badge)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: const Text('GIF',
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// گیف داخل حباب پیام؛ با زدن روش پلیر تمام‌صفحه باز میشه
class GifBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final double width;
  const GifBubble({super.key, required this.msg, required this.width});

  @override
  Widget build(BuildContext context) {
    final f = fileOf(msg)!;
    return GestureDetector(
      onTap: () => openVideo(context, msg),
      child: GifVideo(url: Api.fileUrl(f), width: width, badge: true),
    );
  }
}

// ---------------------------------------------------------------------------
// پنل گیف‌ها (کنار دکمه‌ی ویس): گیف‌های ذخیره‌شده‌ی من
// ---------------------------------------------------------------------------

class GifPanel extends StatefulWidget {
  final double height;
  final void Function(Map<String, dynamic> gif) onPick;

  /// true = داخل MediaPanel (تب GIF)؛ کادر و ارتفاع رو خود MediaPanel میده
  final bool embedded;
  const GifPanel({super.key, required this.height, required this.onPick, this.embedded = false});

  @override
  State<GifPanel> createState() => _GifPanelState();
}

class _GifPanelState extends State<GifPanel> {
  List<Map<String, dynamic>> _gifs = [];
  bool _loading = true;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.gifs();
      if (!mounted) return;
      setState(() {
        _gifs = l;
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

  void _remove(Map<String, dynamic> g) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.deleteGif(g['id'] as String);
                if (mounted) setState(() => _gifs.removeWhere((x) => x['id'] == g['id']));
              } on ApiException catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            child: const Text('Remove from my GIFs'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> g, double w) {
    final isImage = g['kind'] == 'image';
    return GestureDetector(
      onTap: () => widget.onPick(g),
      onLongPress: () => _remove(g),
      child: isImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: w,
                height: w,
                child: Image.network(Api.fileUrl(g), fit: BoxFit.cover, gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF111111))),
              ),
            )
          : GifVideo(
              url: Api.fileUrl(g),
              thumb: g['thumb'] as String?,
              width: w,
              height: w,
              radius: BorderRadius.circular(10),
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
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.subText)),
            CupertinoButton(
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
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? _gifs : _gifs.where((g) => ((g['name'] as String?) ?? '').toLowerCase().contains(q)).toList();
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _gifs.isEmpty
                ? 'No GIFs yet.\nSend a video with sound off, then tap it in the chat and choose “Add to GIFs”.'
                : 'No GIFs found',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.subText, height: 1.6),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (_, cs) {
      const gap = 3.0;
      final w = (cs.maxWidth - gap * 3) / 2;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(gap, gap, gap, gap),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: 1,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _tile(list[i], math.max(w, 60)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: CupertinoSearchTextField(
              placeholder: 'Search GIFs',
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(child: _body()),
        ],
      );
    }
    final bottom = MediaQuery.of(context).padding.bottom;
    final dark = context.dark;
    return Container(
      height: widget.height + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111111) : const Color(0xFFF7F7F9),
        border: Border(top: BorderSide(color: dark ? Colors.white10 : Colors.black12, width: 0.6)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: CupertinoSearchTextField(
              placeholder: 'Search GIFs',
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
