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

  /// حالت پخش: 0 = به ترتیب، 1 = تصادفی، 2 = تکرار همین آهنگ
  final mode = ValueNotifier<int>(0);

  List<Map<String, dynamic>> get queue => _queue;

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
        final pl = _p;
        hasPrev.value = pl?.hasPrevious ?? i > 0;
        hasNext.value = pl?.hasNext ?? i < _queue.length - 1;
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
    if (mode.value != 0) {
      mode.value = 0;
      await p.setShuffleModeEnabled(false);
      await p.setLoopMode(LoopMode.off);
    }
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

  /// پخش آهنگ شماره‌ی [i] از صف فعلی
  Future<void> playIndex(int i) async {
    final p = _p;
    if (p == null || i < 0 || i >= _queue.length) return;
    await p.seek(Duration.zero, index: i);
    unawaited(p.play());
  }

  /// به ترتیب ← تصادفی ← تکرار یک آهنگ
  Future<void> cycleMode() async {
    final n = (mode.value + 1) % 3;
    mode.value = n;
    final p = _p;
    if (p == null) return;
    await p.setShuffleModeEnabled(n == 1);
    await p.setLoopMode(n == 2 ? LoopMode.one : LoopMode.off);
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

/// نوار کوچک پلیر بالای صفحه (مثل تلگرام): «خواننده – آهنگ» + دکمه‌ی بستن
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
        final title = audioTitle(m);
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          decoration: BoxDecoration(
            color: context.dark ? const Color(0xFF1C1C1E) : context.fieldFill,
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showFullPlayer(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: PlayPauseIcon(size: 28, color: tgBlue),
                          onPressed: () {
                            if (c.playing.value) {
                              c.pause();
                            } else {
                              c.resume();
                            }
                          },
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              if (artist != null)
                                TextSpan(text: artist, style: const TextStyle(fontWeight: FontWeight.w600)),
                              TextSpan(
                                text: artist != null ? ' – $title' : title,
                                style: TextStyle(color: artist != null ? context.subText : null),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
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
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: v,
                          child: Container(height: 2.5, color: tgBlue),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// «Add to Profile»: آهنگ این پیام / پروفایل رو میذاره روی پروفایل خودم
Future<void> addToProfile(BuildContext context, Map<String, dynamic> m) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String t) => messenger?.showSnackBar(SnackBar(content: Text(t)));
  try {
    final id = m['id'];
    if (id is int) {
      await Api.setMusicFromMessage(id);
    } else if (id is String && id.startsWith('pm_')) {
      final uid = (m['from'] as num).toInt();
      if (uid == Api.userId) {
        snack('This song is already on your profile');
        return;
      }
      await Api.setMusicFromUser(uid);
    } else {
      return;
    }
    snack('Added to your profile');
  } on ApiException catch (e) {
    snack(e.message);
  } catch (_) {
    snack('Could not add the song to your profile');
  }
}

bool _canAddToProfile(Map<String, dynamic> m) {
  final id = m['id'];
  if (id is int) return true;
  if (id is String && id.startsWith('pm_')) return (m['from'] as num?)?.toInt() != Api.userId;
  return false;
}

void showFullPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.dark ? const Color(0xFF1C1C1E) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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

  Widget _queueRow(BuildContext context, Map<String, dynamic> m, int index) {
    final c = AudioCtl.i;
    final artist = audioArtist(m);
    final title = audioTitle(m);
    return InkWell(
      onTap: () {
        if (c.isCurrent(m['id'])) {
          if (c.playing.value) {
            c.pause();
          } else {
            c.resume();
          }
        } else {
          c.playIndex(index);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CoverArt(msg: m, size: 52, radius: 26),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([c.current, c.playing, c.buffering]),
                      builder: (_, __) => c.isCurrent(m['id'])
                          ? const PlayPauseIcon(size: 30)
                          : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.subText.withOpacity(0.18))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: dirOf(title),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    if (artist != null)
                      Text(artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: dirOf(artist),
                          style: TextStyle(fontSize: 15, color: context.subText)),
                  ],
                ),
              ),
            ),
            if (_canAddToProfile(m))
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: context.subText),
                onSelected: (_) => addToProfile(context, m),
                itemBuilder: (_) => const [PopupMenuItem(value: 'profile', child: Text('Add to Profile'))],
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(int m) => m == 1 ? Icons.shuffle_rounded : (m == 2 ? Icons.repeat_one_rounded : Icons.swap_vert_rounded);

  @override
  Widget build(BuildContext context) {
    final c = AudioCtl.i;
    final h = MediaQuery.of(context).size.height;
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
          final queue = c.queue;
          return SizedBox(
            height: h * 0.78,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: context.subText.withOpacity(0.5), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: queue.length,
                    itemBuilder: (_, i) => _queueRow(context, queue[i], i),
                  ),
                ),
                Container(height: 1, color: context.subText.withOpacity(0.18)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(audioTitle(m),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: dirOf(audioTitle(m)),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                            if (artist != null) ...[
                              const SizedBox(height: 2),
                              Text(artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: dirOf(artist),
                                  style: TextStyle(fontSize: 18, color: context.subText)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      CoverArt(msg: m, size: 66, radius: 8),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: Listenable.merge([c.position, c.duration]),
                  builder: (_, __) {
                    final total = c.duration.value.inMilliseconds.toDouble();
                    final max = total <= 0 ? 1.0 : total;
                    final pos = (_drag ?? c.position.value.inMilliseconds.toDouble()).clamp(0.0, max);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(fmtDur(Duration(milliseconds: pos.round())),
                                    style: TextStyle(fontSize: 14, color: context.subText)),
                                Text(total <= 0 ? '--:--' : fmtDur(c.duration.value),
                                    style: TextStyle(fontSize: 14, color: context.subText)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: c.mode,
                        builder: (_, md, __) => IconButton(
                          iconSize: 28,
                          color: md == 0 ? context.subText : tgBlue,
                          icon: Icon(_modeIcon(md)),
                          onPressed: c.cycleMode,
                        ),
                      ),
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: c.prev,
                      ),
                      GestureDetector(
                        onTap: () {
                          if (c.playing.value) {
                            c.pause();
                          } else {
                            c.resume();
                          }
                        },
                        child: const SizedBox(
                          width: 64,
                          height: 64,
                          child: Center(child: PlayPauseIcon(size: 56, color: tgBlue)),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: c.hasNext,
                        builder: (_, __) => IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: c.hasNext.value ? c.next : null,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: context.subText),
                        onSelected: (v) {
                          if (v == 'speed') c.cycleSpeed();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'speed',
                            child: ValueListenableBuilder<double>(
                              valueListenable: c.speed,
                              builder: (_, sp, __) => Text('Speed: ${sp == sp.roundToDouble() ? sp.toInt() : sp}x  (tap to change)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canAddToProfile(m))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () => addToProfile(context, m),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Add to Profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tgBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}
