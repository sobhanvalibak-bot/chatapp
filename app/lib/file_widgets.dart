import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'api.dart';
import 'player.dart';
import 'utils.dart';

/// عکس‌های کوچک‌تر از این حجم مستقیم داخل حباب نشون داده میشن
const int kInlineImageMax = 5 * 1024 * 1024;

/// نمایش تمام‌صفحه‌ی عکس داخل خود اپ
void openImageViewer(BuildContext context, Map<String, dynamic> msg) {
  final f = fileOf(msg)!;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(f['name'] as String? ?? 'Photo',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              Api.fileUrl(f),
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
    ),
  );
}

IconData _iconFor(Map<String, dynamic> f) {
  final name = ((f['name'] as String?) ?? '').toLowerCase();
  if (f['kind'] == 'video') return Icons.movie_rounded;
  if (name.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(name)) return Icons.folder_zip_rounded;
  if (RegExp(r'\.(doc|docx|txt|rtf|odt)$').hasMatch(name)) return Icons.description_rounded;
  if (RegExp(r'\.(xls|xlsx|csv|ods)$').hasMatch(name)) return Icons.table_chart_rounded;
  if (RegExp(r'\.(ppt|pptx|odp)$').hasMatch(name)) return Icons.slideshow_rounded;
  if (name.endsWith('.apk')) return Icons.android_rounded;
  return Icons.insert_drive_file_rounded;
}

/// محتوای فایل داخل حباب پیام: آهنگ (با پلیر)، عکس، یا کارت فایل
class FileContent extends StatefulWidget {
  final Map<String, dynamic> msg;
  final bool mine;
  final List<Map<String, dynamic>> audioQueue;
  const FileContent({super.key, required this.msg, required this.mine, required this.audioQueue});

  @override
  State<FileContent> createState() => _FileContentState();
}

class _FileContentState extends State<FileContent> {
  double? _progress; // null = در حال دانلود نیست
  bool _downloaded = false;

  Map<String, dynamic> get _f => fileOf(widget.msg)!;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await Api.localPath(widget.msg);
    if (mounted && (p != null) != _downloaded) setState(() => _downloaded = p != null);
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// دانلود (اگه لازم بود) و بعد باز کردن با برنامه‌ی مناسب
  Future<void> _downloadAndOpen() async {
    if (_progress != null) return;
    try {
      var path = await Api.localPath(widget.msg);
      if (path == null) {
        setState(() => _progress = 0);
        path = await Api.downloadFile(widget.msg, onProgress: (v) {
          if (mounted && (v - (_progress ?? 0) >= 0.01 || v >= 1)) setState(() => _progress = v);
        });
      }
      if (mounted) {
        setState(() {
          _progress = null;
          _downloaded = true;
        });
      }
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && r.type != ResultType.noAppToOpen) {
        _snack('Could not open the file');
      } else if (r.type == ResultType.noAppToOpen) {
        _snack('Saved, but no app on this phone can open it');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _progress = null);
      _snack(e.message);
    } catch (_) {
      if (mounted) setState(() => _progress = null);
      _snack('Could not open the file');
    }
  }

  Future<void> _playAudio() async {
    try {
      await AudioCtl.i.toggle(widget.msg, widget.audioQueue);
    } catch (e) {
      _snack('Could not play this audio file');
    }
  }

  // ------------------------------------------------------------------ audio
  Widget _audio(double w) {
    final m = widget.msg;
    final c = AudioCtl.i;
    final title = audioTitle(m);
    final artist = audioArtist(m);
    final dur = audioDuration(m);
    final size = (_f['size'] as num).toInt();
    final cover = audioMeta(m)['cover'];
    final hasCover = cover is String && cover.isNotEmpty;

    return SizedBox(
      width: w,
      child: Row(
        children: [
          GestureDetector(
            onTap: _playAudio,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (hasCover) CoverArt(msg: m, size: 50, radius: 25) else Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(color: tgBlue, shape: BoxShape.circle),
                  ),
                  AnimatedBuilder(
                    animation: Listenable.merge([c.current, c.playing, c.buffering]),
                    builder: (_, __) {
                      final cur = c.isCurrent(m['id']);
                      return Container(
                        width: hasCover ? 30 : 50,
                        height: hasCover ? 30 : 50,
                        decoration: hasCover
                            ? BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle)
                            : null,
                        alignment: Alignment.center,
                        child: cur
                            ? const PlayPauseIcon(size: 26)
                            : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(title),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (artist != null)
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(artist),
                      style: TextStyle(fontSize: 13, color: context.subText)),
                AnimatedBuilder(
                  animation: Listenable.merge([c.current, c.position, c.duration]),
                  builder: (_, __) {
                    final cur = c.isCurrent(m['id']);
                    final total = cur && c.duration.value > Duration.zero ? c.duration.value : dur;
                    final String t;
                    if (cur) {
                      t = '${fmtDur(c.position.value)} / ${total == null ? '--:--' : fmtDur(total)}';
                    } else {
                      t = '${dur == null ? '' : '${fmtDur(dur)} • '}${fmtSize(size)}';
                    }
                    double? v;
                    if (cur && total != null && total.inMilliseconds > 0) {
                      v = (c.position.value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        if (v != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 3,
                              color: tgBlue,
                              backgroundColor: context.subText.withOpacity(0.25),
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(t, style: TextStyle(fontSize: 12, color: context.subText)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ image
  Widget _image(double w) {
    final f = _f;
    return GestureDetector(
      onTap: () => openImageViewer(context, widget.msg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: w,
          constraints: BoxConstraints(minHeight: 120, maxHeight: w * 1.3),
          color: context.fieldFill,
          child: Image.network(
            Api.fileUrl(f),
            width: w,
            fit: BoxFit.cover,
            cacheWidth: (w * 3).round(),
            gaplessPlayback: true,
            loadingBuilder: (_, child, p) => p == null
                ? child
                : SizedBox(
                    width: w,
                    height: 160,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        value: p.expectedTotalBytes == null ? null : p.cumulativeBytesLoaded / p.expectedTotalBytes!,
                      ),
                    ),
                  ),
            errorBuilder: (_, __, ___) => SizedBox(
              width: w,
              height: 120,
              child: Center(child: Icon(Icons.broken_image_rounded, color: context.subText, size: 32)),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ file card
  Widget _card(double w) {
    final f = _f;
    final name = (f['name'] as String?) ?? 'file';
    final size = (f['size'] as num).toInt();
    final busy = _progress != null;
    return GestureDetector(
      onTap: _downloadAndOpen,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: w,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: tgBlue, shape: BoxShape.circle),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (busy)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: (_progress ?? 0) <= 0 ? null : _progress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  Icon(
                    (busy || !_downloaded) ? Icons.arrow_downward_rounded : _iconFor(f),
                    color: Colors.white,
                    size: busy ? 20 : 24,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(name),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    busy
                        ? '${fmtSize(size * (_progress ?? 0))} / ${fmtSize(size)}'
                        : (_downloaded ? '${fmtSize(size)} • Tap to open' : '${fmtSize(size)} • Tap to download'),
                    style: TextStyle(fontSize: 12.5, color: context.subText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = math.min(240.0, MediaQuery.of(context).size.width * 0.78 - 26);
    final f = _f;
    final size = (f['size'] as num).toInt();
    switch (f['kind']) {
      case 'audio':
        return _audio(w);
      case 'image':
        if (size <= kInlineImageMax) return _image(w);
        return _card(w);
      default:
        return _card(w);
    }
  }
}
