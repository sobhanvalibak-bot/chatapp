import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';
import 'utils.dart';

/// کنترل‌کننده‌ی پخش آهنگ (یک پلیر برای کل اپ).
/// just_audio_background خودش «مدیا سشن» رو میسازه: نوتیفیکیشن پخش، کنترل روی
/// لاک‌اسکرین، دکمه‌های هدفون/بلوتوث و نمایش متادیتا (عنوان، خواننده، کاور).
class AudioCtl {
  AudioCtl._();
  static final AudioCtl i = AudioCtl._();

  AudioPlayer? _p;
  List<Map<String, dynamic>> _queue = [];

  final current = ValueNotifier<Map<String, dynamic>?>(null);
  final playing = ValueNotifier<bool>(false);
  final buffering = ValueNotifier<bool>(false);
  final position = ValueNotifier<Duration>(Duration.zero);
  final duration = ValueNotifier<Duration>(Duration.zero);
  final speed = ValueNotifier<double>(1.0);
  final hasNext = ValueNotifier<bool>(false);
  final hasPrev = ValueNotifier<bool>(false);

  bool isCurrent(Object? id) => current.value != null && current.value!['id'] == id;

  AudioPlayer _player() {
    var p = _p;
    if (p != null) return p;
    p = AudioPlayer();
    _p = p;
    p.playerStateStream.listen((s) {
      playing.value = s.playing;
      buffering.value =
          s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering;
      if (s.processingState == ProcessingState.completed) _onCompleted();
    });
    p.positionStream.listen((d) => position.value = d);
    p.durationStream.listen((d) {
      if (d != null) duration.value = d;
    });
    p.currentIndexStream.listen((i) {
      if (i != null && i >= 0 && i < _queue.length) {
        final m = _queue[i];
        current.value = m;
        duration.value = audioDuration(m) ?? Duration.zero;
        hasPrev.value = i > 0;
        hasNext.value = i < _queue.length - 1;
      }
    });
    return p;
  }

  void _onCompleted() {
    final p = _p;
    if (p == null) return;
    p.pause();
    p.seek(Duration.zero, index: _queue.isEmpty ? 0 : _queue.length - 1);
  }

  MediaItem _item(Map<String, dynamic> m) {
    final meta = audioMeta(m);
    final cover = meta['cover'];
    return MediaItem(
      id: '${m['id']}',
      title: audioTitle(m),
      artist: audioArtist(m),
      album: meta['album'] is String ? meta['album'] as String : null,
      duration: audioDuration(m),
      artUri: cover is String && cover.isNotEmpty ? Uri.parse(Api.assetUrl(cover)) : null,
    );
  }

  /// پخش آهنگ شماره‌ی [index] از لیست [audios] (بقیه‌ی آهنگ‌ها هم پشت‌سرش میان)
  Future<void> playQueue(List<Map<String, dynamic>> audios, int index) async {
    final p = _player();
    _queue = List<Map<String, dynamic>>.from(audios);
    final sources = _queue
        .map((m) => AudioSource.uri(Uri.parse(Api.fileUrl(fileOf(m)!)), tag: _item(m)))
        .toList();
    current.value = _queue[index];
    position.value = Duration.zero;
    duration.value = audioDuration(_queue[index]) ?? Duration.zero;
    await p.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    unawaited(p.play());
  }

  Future<void> toggle(Map<String, dynamic> msg, List<Map<String, dynamic>> queue) async {
    final p = _p;
    if (p != null && isCurrent(msg['id'])) {
      if (p.playing) {
        await p.pause();
      } else {
        unawaited(p.play());
      }
      return;
    }
    var idx = queue.indexWhere((m) => m['id'] == msg['id']);
    var q = queue;
    if (idx < 0) {
      q = [msg];
      idx = 0;
    }
    await playQueue(q, idx);
  }

  Future<void> pause() async => _p?.pause();
  Future<void> resume() async {
    final p = _p;
    if (p != null) unawaited(p.play());
  }

  Future<void> seek(Duration d) async => _p?.seek(d);
  Future<void> next() async => _p?.seekToNext();
  Future<void> prev() async {
    final p = _p;
    if (p == null) return;
    // مثل بقیه‌ی پلیرها: اگه چند ثانیه از آهنگ گذشته، اول برگرده به اولش
    if (position.value.inSeconds > 3 || !hasPrev.value) {
      await p.seek(Duration.zero);
    } else {
      await p.seekToPrevious();
    }
  }

  Future<void> cycleSpeed() async {
    const list = [1.0, 1.25, 1.5, 2.0];
    final n = list[(list.indexOf(speed.value) + 1) % list.length];
    speed.value = n;
    await _p?.setSpeed(n);
  }

  /// بستن پلیر (نوار بالای چت و نوتیفیکیشن)
  Future<void> close() async {
    try {
      await _p?.stop();
    } catch (_) {}
    current.value = null;
    playing.value = false;
    buffering.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

/// آیکن پلی/پاز/لودینگ
class PlayPauseIcon extends StatelessWidget {
  final double size;
  final Color color;
  const PlayPauseIcon({super.key, this.size = 26, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    final c = AudioCtl.i;
    return AnimatedBuilder(
      animation: Listenable.merge([c.playing, c.buffering]),
      builder: (_, __) {
        if (c.buffering.value && c.playing.value) {
          return SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
          );
        }
        return Icon(c.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size, color: color);
      },
    );
  }
}

/// تصویر کاور آهنگ (یا آیکن نت موسیقی)
class CoverArt extends StatelessWidget {
  final Map<String, dynamic> msg;
  final double size;
  final double radius;
  const CoverArt({super.key, required this.msg, required this.size, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final cover = audioMeta(msg)['cover'];
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tgBlue, borderRadius: BorderRadius.circular(radius)),
      child: Icon(Icons.music_note_rounded, color: Colors.white, size: size * 0.5),
    );
    if (cover is! String || cover.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        Api.assetUrl(cover),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// نوار کوچک پلیر بالای صفحه (مثل تلگرام)
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AudioCtl.i;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: c.current,
      builder: (_, m, __) {
        if (m == null) return const SizedBox.shrink();
        final artist = audioArtist(m);
        return Material(
          color: context.barBg,
          child: InkWell(
            onTap: () => showFullPlayer(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (c.playing.value) {
                            c.pause();
                          } else {
                            c.resume();
                          }
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(color: tgBlue, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const PlayPauseIcon(size: 24),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(audioTitle(m),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: dirOf(audioTitle(m)),
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                            if (artist != null)
                              Text(artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: dirOf(artist),
                                  style: TextStyle(fontSize: 12.5, color: context.subText)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 22, color: context.subText),
                        onPressed: c.close,
                      ),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([c.position, c.duration]),
                  builder: (_, __) {
                    final total = c.duration.value.inMilliseconds;
                    final v = total <= 0 ? 0.0 : (c.position.value.inMilliseconds / total).clamp(0.0, 1.0);
                    return LinearProgressIndicator(
                      value: v,
                      minHeight: 2,
                      backgroundColor: context.fieldFill,
                      color: tgBlue,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void showFullPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _FullPlayer(),
  );
}

class _FullPlayer extends StatefulWidget {
  const _FullPlayer();

  @override
  State<_FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<_FullPlayer> {
  double? _drag; // وقتی کاربر اسلایدر رو میکشه (میلی‌ثانیه)

  @override
  Widget build(BuildContext context) {
    final c = AudioCtl.i;
    return SafeArea(
      child: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: c.current,
        builder: (ctx, m, __) {
          if (m == null) {
            // پلیر بسته شد
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
            return const SizedBox(height: 80);
          }
          final artist = audioArtist(m);
          final album = audioMeta(m)['album'];
          final sub = [
            if (artist != null) artist,
            if (album is String && album.isNotEmpty) album,
          ].join(' • ');
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: context.subText.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 22),
                CoverArt(msg: m, size: 220, radius: 18),
                const SizedBox(height: 22),
                Text(audioTitle(m),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(audioTitle(m)),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sub,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: dirOf(sub),
                      style: TextStyle(fontSize: 14.5, color: context.subText)),
                ],
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: Listenable.merge([c.position, c.duration]),
                  builder: (_, __) {
                    final total = c.duration.value.inMilliseconds.toDouble();
                    final max = total <= 0 ? 1.0 : total;
                    final pos = (_drag ?? c.position.value.inMilliseconds.toDouble()).clamp(0.0, max);
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: pos,
                            max: max,
                            activeColor: tgBlue,
                            onChanged: total <= 0 ? null : (v) => setState(() => _drag = v),
                            onChangeEnd: (v) {
                              c.seek(Duration(milliseconds: v.round()));
                              setState(() => _drag = null);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(fmtDur(Duration(milliseconds: pos.round())),
                                  style: TextStyle(fontSize: 12.5, color: context.subText)),
                              Text(total <= 0 ? '--:--' : fmtDur(c.duration.value),
                                  style: TextStyle(fontSize: 12.5, color: context.subText)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: c.speed,
                      builder: (_, sp, __) => TextButton(
                        onPressed: c.cycleSpeed,
                        child: Text('${sp == sp.roundToDouble() ? sp.toInt() : sp}x',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: c.hasPrev,
                      builder: (_, __) => IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: c.prev,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (c.playing.value) {
                          c.pause();
                        } else {
                          c.resume();
                        }
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(color: tgBlue, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const PlayPauseIcon(size: 38),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: c.hasNext,
                      builder: (_, __) => IconButton(
                        iconSize: 34,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: c.hasNext.value ? c.next : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        c.close();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
