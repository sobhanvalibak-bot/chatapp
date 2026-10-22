import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'player.dart';
import 'utils.dart';

// ===========================================================================
// ضبط: ویس (صدا) و ویدیو مسیج دایره‌ای
// ===========================================================================

enum RecMode { voice, round }

enum RecPhase { idle, starting, held, locked }

class RecResult {
  final String path;
  final int durationMs;
  final String? waveform; // base64 (فقط ویس)
  final RecMode mode;
  RecResult(this.path, this.durationMs, this.waveform, this.mode);
}

class _RecError implements Exception {
  final String message;
  _RecError(this.message);
}

/// کنترل ضبط. دکمه‌ی ضبط: یک بار بزن = عوض شدن بین ویس و ویدیو، نگه داشتن = ضبط.
class MsgRecorder extends ChangeNotifier {
  static RecMode lastMode = RecMode.voice;
  static const Duration maxVoice = Duration(minutes: 15);
  static const Duration maxRound = Duration(seconds: 60);
  static const Duration minLength = Duration(milliseconds: 700);

  RecMode mode = lastMode;
  RecPhase phase = RecPhase.idle;
  Duration elapsed = Duration.zero;
  bool cancelZone = false;
  double lockProgress = 0; // 0..1 (کشیدن به بالا برای قفل)
  CameraController? camera;
  bool lastTooShort = false;
  bool paused = false;
  bool torch = false;
  /// دوربین جلو (انتخاب برای ویدیوی بعدی)
  static bool useFront = true;

  /// وقتی به حداکثر زمان رسید (ارسال خودکار)
  VoidCallback? onLimit;

  AudioRecorder? _rec;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _amps = [];
  Timer? _tick;
  final Stopwatch _sw = Stopwatch();
  String? _voicePath;
  int _gen = 0;
  bool _endReq = false;
  bool _disposed = false;

  bool get active => phase != RecPhase.idle;
  Duration get maxLen => mode == RecMode.voice ? maxVoice : maxRound;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void toggleMode() {
    if (active) return;
    mode = mode == RecMode.voice ? RecMode.round : RecMode.voice;
    lastMode = mode;
    _notify();
  }

  /// شروع ضبط؛ اگه مشکلی باشه (مثلاً مجوز) متن خطا برمی‌گردونه
  Future<String?> start() async {
    if (phase != RecPhase.idle) return null;
    final gen = ++_gen;
    phase = RecPhase.starting;
    _endReq = false;
    elapsed = Duration.zero;
    cancelZone = false;
    lockProgress = 0;
    lastTooShort = false;
    paused = false;
    torch = false;
    _amps.clear();
    _notify();
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        throw _RecError(mic.isPermanentlyDenied
            ? 'Microphone is blocked. Allow it in Settings → Apps → Chat → Permissions'
            : 'Microphone permission is needed');
      }
      if (mode == RecMode.round) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) {
          throw _RecError(cam.isPermanentlyDenied
              ? 'Camera is blocked. Allow it in Settings → Apps → Chat → Permissions'
              : 'Camera permission is needed');
        }
      }
      if (gen != _gen || _endReq) {
        if (_endReq) lastTooShort = true;
        _reset();
        return null;
      }
      // موزیک و ویس و ویدیوهای دیگه ساکت بشن
      unawaited(AudioCtl.i.pause());
      unawaited(VoiceCtl.i.stop());
      RoundCtl.i.stopAll();

      if (mode == RecMode.voice) {
        await _startVoice();
      } else {
        await _startRound();
      }
      if (gen != _gen || _endReq) {
        if (_endReq) lastTooShort = true;
        await _disposeHardware();
        _reset();
        return null;
      }
      HapticFeedback.mediumImpact();
      phase = RecPhase.held;
      _sw
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        elapsed = _sw.elapsed;
        if (elapsed >= maxLen) {
          _tick?.cancel();
          elapsed = maxLen;
          _notify();
          onLimit?.call();
          return;
        }
        _notify();
      });
      _notify();
      return null;
    } on _RecError catch (e) {
      await _disposeHardware();
      _reset();
      return e.message;
    } catch (_) {
      await _disposeHardware();
      _reset();
      return mode == RecMode.voice ? 'Could not start recording' : 'Could not open the camera';
    }
  }

  Future<void> _startVoice() async {
    final r = AudioRecorder();
    _rec = r;
    if (!await r.hasPermission()) throw _RecError('Microphone permission is needed');
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await r.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    _voicePath = path;
    _ampSub = r.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      if (!paused) _amps.add(a.current);
    });
  }

  Future<void> _startRound() async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw _RecError('No camera found on this phone');
    final want = useFront ? CameraLensDirection.front : CameraLensDirection.back;
    final desc = cams.firstWhere(
      (c) => c.lensDirection == want,
      orElse: () => cams.first,
    );
    final c = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: true,
      videoBitrate: 1500000,
      audioBitrate: 64000,
    );
    camera = c;
    await c.initialize();
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    _notify(); // پیش‌نمایش دوربین نشون داده بشه
    await c.startVideoRecording();
  }

  /// مکث / ادامه‌ی ضبط (فقط وقتی قفل شده)
  Future<void> togglePause() async {
    if (phase != RecPhase.locked && phase != RecPhase.held) return;
    try {
      if (!paused) {
        if (mode == RecMode.voice) {
          await _rec?.pause();
        } else {
          await camera?.pauseVideoRecording();
        }
        _sw.stop();
        paused = true;
      } else {
        if (mode == RecMode.voice) {
          await _rec?.resume();
        } else {
          await camera?.resumeVideoRecording();
        }
        _sw.start();
        paused = false;
      }
    } catch (_) {}
    HapticFeedback.selectionClick();
    _notify();
  }

  /// چراغ قوه‌ی دوربین حین ضبط
  Future<void> toggleTorch() async {
    final c = camera;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFlashMode(torch ? FlashMode.off : FlashMode.torch);
      torch = !torch;
    } catch (_) {}
    _notify();
  }

  /// عوض کردن دوربین جلو/عقب. وسط ضبط ممکن نیست (فیلم از بین میره)؛ برای ویدیوی بعدی ذخیره میشه.
  /// true یعنی همین الان اعمال شد.
  bool flipCamera() {
    useFront = !useFront;
    _notify();
    return !active;
  }

  /// حرکت انگشت نسبت به نقطه‌ی شروع (برای لغو با کشیدن به چپ / قفل با کشیدن به بالا)
  void drag(Offset o) {
    if (phase != RecPhase.held) return;
    final cz = o.dx < -90;
    final lp = (-o.dy / 80).clamp(0.0, 1.0).toDouble();
    var changed = false;
    if (cz != cancelZone) {
      cancelZone = cz;
      changed = true;
      HapticFeedback.selectionClick();
    }
    if ((lp - lockProgress).abs() > 0.02) {
      lockProgress = lp;
      changed = true;
    }
    if (lp >= 1 && !cz) {
      phase = RecPhase.locked;
      cancelZone = false;
      HapticFeedback.mediumImpact();
      changed = true;
    }
    if (changed) _notify();
  }

  /// انگشت برداشته شد
  Future<RecResult?> release() async {
    if (phase == RecPhase.locked) return null; // قفل شده؛ با دکمه‌ی ارسال/سطل زباله تموم میشه
    return finish(send: !cancelZone);
  }

  /// پایان ضبط. send=false یعنی دور انداختن.
  Future<RecResult?> finish({required bool send}) async {
    if (phase == RecPhase.idle) return null;
    if (phase == RecPhase.starting) {
      _endReq = true; // هنوز مجوز/دوربین آماده نشده؛ start خودش جمع میکنه
      return null;
    }
    _tick?.cancel();
    _sw.stop();
    final el = _sw.elapsed;
    final m = mode;
    String? path;
    try {
      if (m == RecMode.voice) {
        await _ampSub?.cancel();
        _ampSub = null;
        path = await _rec?.stop();
        path ??= _voicePath;
      } else {
        final c = camera;
        if (c != null && c.value.isRecordingVideo) {
          final x = await c.stopVideoRecording();
          path = x.path;
        }
      }
    } catch (_) {
      path = null;
    }
    final wf = m == RecMode.voice ? _waveform() : null;
    await _disposeHardware();
    _reset();
    if (path == null) return null;
    if (!send) {
      _del(path);
      return null;
    }
    if (el < minLength) {
      lastTooShort = true;
      _del(path);
      return null;
    }
    return RecResult(path, el.inMilliseconds, wf, m);
  }

  void _del(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  String? _waveform() {
    final len = _amps.length;
    if (len == 0) return null;
    const n = 40;
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final a = math.min((i * len / n).floor(), len - 1);
      final b = math.min(math.max(((i + 1) * len / n).ceil(), a + 1), len);
      var mx = -160.0;
      for (var j = a; j < b; j++) {
        mx = math.max(mx, _amps[j]);
      }
      final v = ((mx + 45) / 45).clamp(0.0, 1.0).toDouble();
      out.add((v * 255).round());
    }
    return base64Encode(out);
  }

  Future<void> _disposeHardware() async {
    try {
      await _ampSub?.cancel();
    } catch (_) {}
    _ampSub = null;
    final r = _rec;
    _rec = null;
    if (r != null) {
      try {
        if (await r.isRecording()) await r.cancel();
      } catch (_) {}
      try {
        await r.dispose();
      } catch (_) {}
    }
    final c = camera;
    camera = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  void _reset() {
    _tick?.cancel();
    _sw
      ..stop()
      ..reset();
    phase = RecPhase.idle;
    elapsed = Duration.zero;
    cancelZone = false;
    lockProgress = 0;
    paused = false;
    torch = false;
    _voicePath = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _tick?.cancel();
    final p = _voicePath;
    final r = _rec;
    final c = camera;
    _rec = null;
    camera = null;
    () async {
      try {
        await _ampSub?.cancel();
      } catch (_) {}
      try {
        if (r != null && await r.isRecording()) await r.cancel();
        await r?.dispose();
      } catch (_) {}
      try {
        await c?.dispose();
      } catch (_) {}
      if (p != null) _del(p);
    }();
    super.dispose();
  }
}

// ===========================================================================
// پخش ویس (با video_player تا با پلیر آهنگ‌ها و مدیا سشن قاطی نشه)
// ===========================================================================

class VoiceCtl {
  VoiceCtl._();
  static final VoiceCtl i = VoiceCtl._();

  VideoPlayerController? _c;
  int _gen = 0;

  final currentId = ValueNotifier<Object?>(null);
  final playing = ValueNotifier<bool>(false);
  final loading = ValueNotifier<bool>(false);
  final position = ValueNotifier<Duration>(Duration.zero);
  final duration = ValueNotifier<Duration>(Duration.zero);
  final speed = ValueNotifier<double>(1.0);

  bool isCurrent(Object? id) => currentId.value != null && currentId.value == id;

  void _prepOthers() {
    unawaited(AudioCtl.i.pause());
    RoundCtl.i.stopAll();
  }

  Future<void> toggle(Map<String, dynamic> msg) async {
    final id = msg['id'];
    final cur = _c;
    if (cur != null && isCurrent(id)) {
      final v = cur.value;
      if (v.isPlaying) {
        await cur.pause();
        return;
      }
      if (v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 150)) {
        await cur.seekTo(Duration.zero);
      }
      _prepOthers();
      await cur.play();
      return;
    }
    await stop();
    final gen = ++_gen;
    _prepOthers();
    currentId.value = id;
    loading.value = true;
    duration.value = audioDuration(msg) ?? Duration.zero;
    final nc = VideoPlayerController.networkUrl(Uri.parse(Api.fileUrl(fileOf(msg)!)));
    _c = nc;
    try {
      await nc.initialize();
      if (gen != _gen || _c != nc) return; // وسط راه بسته شده
      nc.addListener(_onTick);
      await nc.setPlaybackSpeed(speed.value);
      loading.value = false;
      await nc.play();
    } catch (_) {
      if (gen == _gen) {
        await stop();
        rethrow;
      }
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null) return;
    final v = c.value;
    playing.value = v.isPlaying;
    position.value = v.position;
    if (v.duration > Duration.zero) duration.value = v.duration;
    loading.value = v.isBuffering;
    if (v.duration > Duration.zero && v.position >= v.duration && !v.isPlaying) {
      // تموم شد؛ برگرد اول
      position.value = Duration.zero;
      c.seekTo(Duration.zero);
      c.pause();
    }
  }

  Future<void> seekFraction(double f) async {
    final c = _c;
    if (c == null) return;
    final d = c.value.duration;
    if (d <= Duration.zero) return;
    final t = Duration(milliseconds: (d.inMilliseconds * f.clamp(0.0, 1.0)).round());
    position.value = t;
    await c.seekTo(t);
  }

  Future<void> cycleSpeed() async {
    const list = [1.0, 1.5, 2.0];
    final n = list[(list.indexOf(speed.value) + 1) % list.length];
    speed.value = n;
    try {
      await _c?.setPlaybackSpeed(n);
    } catch (_) {}
  }

  Future<void> stop() async {
    _gen++;
    final c = _c;
    _c = null;
    c?.removeListener(_onTick);
    currentId.value = null;
    playing.value = false;
    loading.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    try {
      await c?.dispose();
    } catch (_) {}
  }
}

/// هماهنگی بین ویدیو مسیج‌های دایره‌ای (هر لحظه فقط یکی پخش بشه)
class RoundCtl {
  RoundCtl._();
  static final RoundCtl i = RoundCtl._();
  final active = ValueNotifier<Object?>(null);
  void stopAll() => active.value = Object();
}

// ===========================================================================
// UI: حباب ویس
// ===========================================================================

List<double> _waveBars(Map msg) {
  final wf = audioMeta(msg)['waveform'];
  if (wf is String && wf.isNotEmpty) {
    try {
      final b = base64Decode(wf);
      if (b.isNotEmpty) return b.map((e) => (e / 255.0).clamp(0.08, 1.0).toDouble()).toList();
    } catch (_) {}
  }
  final rnd = math.Random(((msg['id'] as num?)?.toInt() ?? 7) * 7919);
  return List<double>.generate(40, (_) => 0.15 + rnd.nextDouble() * 0.6);
}

class _WavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color on;
  final Color off;
  _WavePainter(this.bars, this.progress, this.on, this.off);

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0) return;
    const gap = 2.0;
    final bw = math.max(1.5, (size.width - gap * (n - 1)) / n);
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final h = math.max(3.0, bars[i] * size.height);
      final x = i * (bw + gap);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, bw, h),
        Radius.circular(bw / 2),
      );
      p.color = (i + 0.5) / n <= progress ? on : off;
      canvas.drawRRect(r, p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.progress != progress || o.on != on || o.off != off || o.bars != bars;
}

class VoiceBubble extends StatefulWidget {
  final Map<String, dynamic> msg;
  final bool mine;
  final double width;
  const VoiceBubble({super.key, required this.msg, required this.mine, required this.width});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late final List<double> _bars = _waveBars(widget.msg);

  Future<void> _toggle() async {
    try {
      await VoiceCtl.i.toggle(widget.msg);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this voice message')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = VoiceCtl.i;
    final id = widget.msg['id'];
    final total = audioDuration(widget.msg) ?? Duration.zero;
    final accent = widget.mine ? context.tickRead : tgBlue;
    return SizedBox(
      width: widget.width,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: Listenable.merge([c.currentId, c.playing, c.loading]),
                builder: (_, __) {
                  final cur = c.isCurrent(id);
                  if (cur && c.loading.value && !c.playing.value) {
                    return const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    );
                  }
                  return Icon(
                    cur && c.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (_, cs) {
                    double frac(double dx) => (dx / cs.maxWidth).clamp(0.0, 1.0).toDouble();
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        if (c.isCurrent(id)) {
                          c.seekFraction(frac(d.localPosition.dx));
                        } else {
                          _toggle();
                        }
                      },
                      onHorizontalDragUpdate: (d) {
                        if (c.isCurrent(id)) c.seekFraction(frac(d.localPosition.dx));
                      },
                      child: SizedBox(
                        height: 30,
                        width: double.infinity,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([c.currentId, c.position, c.duration]),
                          builder: (_, __) {
                            final cur = c.isCurrent(id);
                            final dur = cur && c.duration.value > Duration.zero ? c.duration.value : total;
                            var prog = 0.0;
                            if (cur && dur.inMilliseconds > 0) {
                              prog = (c.position.value.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble();
                            }
                            return CustomPaint(
                              painter: _WavePainter(_bars, prog, accent, accent.withOpacity(0.35)),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([c.currentId, c.position, c.duration]),
                      builder: (_, __) {
                        final cur = c.isCurrent(id);
                        final t = cur && c.position.value > Duration.zero ? c.position.value : total;
                        return Text(fmtDur(t), style: TextStyle(fontSize: 12, color: context.subText));
                      },
                    ),
                    const Spacer(),
                    AnimatedBuilder(
                      animation: Listenable.merge([c.currentId, c.speed]),
                      builder: (_, __) {
                        if (!c.isCurrent(id)) return const SizedBox.shrink();
                        final sp = c.speed.value;
                        return GestureDetector(
                          onTap: c.cycleSpeed,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '${sp == sp.roundToDouble() ? sp.toInt() : sp}×',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// UI: ویدیو مسیج دایره‌ای (پخش داخل خود دایره)
// ===========================================================================

class RoundVideoBubble extends StatefulWidget {
  final Map<String, dynamic> msg;
  final double size;
  const RoundVideoBubble({super.key, required this.msg, required this.size});

  @override
  State<RoundVideoBubble> createState() => _RoundVideoBubbleState();
}

class _RoundVideoBubbleState extends State<RoundVideoBubble> {
  // برای اینکه گوشی ضعیف با چندین دیکودر همزمان له نشه
  static int _active = 0;
  static const int _maxActive = 4;

  VideoPlayerController? _c;
  bool _ready = false;
  bool _counted = false;
  bool _started = false; // از اولش پخش شده (حلقه‌ی پیشرفت نشون داده میشه)
  bool _busy = false;
  bool _failed = false;

  Object? get _id => widget.msg['id'];

  @override
  void initState() {
    super.initState();
    RoundCtl.i.active.addListener(_onActive);
    if (_active < _maxActive) _init();
  }

  Future<void> _init() async {
    if (_c != null && !_failed) return;
    if (_failed) {
      // تلاش دوباره بعد از خطا
      _c?.removeListener(_onTick);
      try {
        await _c?.dispose();
      } catch (_) {}
      _c = null;
      _failed = false;
      if (_counted) {
        _active--;
        _counted = false;
      }
    }
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
      await c.setLooping(false);
      try {
        await c.seekTo(const Duration(milliseconds: 100));
      } catch (_) {}
      c.addListener(_onTick);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      _failed = true;
      if (mounted) setState(() {});
    }
  }

  void _onActive() {
    final c = _c;
    if (c == null || !_ready) return;
    if (RoundCtl.i.active.value != _id && c.value.isPlaying) {
      c.pause();
      c.setVolume(0);
    }
  }

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (_started && !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 80)) {
      // تموم شد؛ برگرد به فریم اول
      _started = false;
      c.setVolume(0);
      c.seekTo(const Duration(milliseconds: 100));
    }
    setState(() {});
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!_ready) {
        _failed = false;
        await _init();
      }
      final c = _c;
      if (c == null || !c.value.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this video')));
        }
        return;
      }
      if (c.value.isPlaying) {
        await c.pause();
        return;
      }
      final v = c.value;
      if (v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 200)) {
        await c.seekTo(Duration.zero);
      }
      unawaited(AudioCtl.i.pause());
      unawaited(VoiceCtl.i.stop());
      RoundCtl.i.active.value = _id;
      _started = true;
      await c.setVolume(1);
      await c.play();
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    RoundCtl.i.active.removeListener(_onActive);
    _c?.removeListener(_onTick);
    _c?.dispose();
    if (_counted) _active--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    final c = _c;
    final ok = _ready && c != null && c.value.isInitialized && c.value.size.width > 0;
    final playing = ok && c!.value.isPlaying;
    final metaDur = audioDuration(widget.msg) ?? Duration.zero;
    final total = ok && c!.value.duration > Duration.zero ? c.value.duration : metaDur;
    final pos = ok ? c!.value.position : Duration.zero;
    final showRing = _started || playing;
    final frac = (showRing && total.inMilliseconds > 0)
        ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble()
        : 0.0;

    Widget video = const SizedBox.shrink();
    if (ok) {
      video = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c!.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: SizedBox(
        width: d,
        height: d,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Container(
                width: d,
                height: d,
                color: const Color(0xFF111111),
                child: video,
              ),
            ),
            if (showRing)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.linear,
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 3.5,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ),
            if (!playing)
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: _failed
                    ? const Icon(Icons.refresh_rounded, color: Colors.white, size: 30)
                    : (_busy && !ok
                        ? const Padding(
                            padding: EdgeInsets.all(15),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
              ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fmtDur(showRing && pos > Duration.zero ? pos : total),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    if (!showRing) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.volume_off_rounded, color: Colors.white, size: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// UI ضبط: دکمه‌ی نگه‌داشتن، نوار ضبط، پیش‌نمایش دایره‌ای، قفل
// ===========================================================================

/// تشخیص «یک بار زدن» (عوض کردن حالت) و «نگه داشتن» (ضبط) روی یک دکمه
class RecordGesture extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final void Function(Offset offsetFromOrigin) onMove;
  final VoidCallback onEnd;
  final VoidCallback onAbort;
  const RecordGesture({
    super.key,
    required this.child,
    required this.onTap,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (g) => g.onTap = onTap,
        ),
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 220)),
          (g) {
            g.onLongPressStart = (_) => onStart();
            g.onLongPressMoveUpdate = (d) => onMove(d.offsetFromOrigin);
            g.onLongPressEnd = (_) => onEnd();
            g.onLongPressCancel = onAbort;
          },
        ),
      },
      child: child,
    );
  }
}

/// نوار وسط کادر پیام وقتی داریم ضبط می‌کنیم: نقطه‌ی قرمز + زمان + «Slide to cancel»
class RecordingStrip extends StatefulWidget {
  final MsgRecorder rec;
  final VoidCallback onTrash;
  const RecordingStrip({super.key, required this.rec, required this.onTrash});

  @override
  State<RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<RecordingStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rec;
    final locked = r.phase == RecPhase.locked;
    final cz = r.cancelZone;
    final t = fmtDur(r.elapsed);
    final tenth = (r.elapsed.inMilliseconds.remainder(1000) ~/ 100);
    const red = Color(0xFFE53935);
    final dot = Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
    );
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 18, right: 12),
          child: r.paused
              ? Opacity(opacity: 0.3, child: dot)
              : FadeTransition(opacity: Tween<double>(begin: 0.25, end: 1).animate(_pulse), child: dot),
        ),
        Text('$t,$tenth', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        Expanded(
          child: locked
              ? Center(
                  child: GestureDetector(
                    onTap: widget.onTrash,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: tgBlue,
                        ),
                      ),
                    ),
                  ),
                )
              : Opacity(
                  opacity: cz ? 1 : (1 - (r.lockProgress * 0.6)),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left_rounded, size: 20, color: cz ? red : context.subText),
                        Text(
                          cz ? 'Release to cancel' : 'Slide to cancel',
                          style: TextStyle(fontSize: 14, color: cz ? red : context.subText),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// پیش‌نمایش دایره‌ای دوربین وسط صفحه + حلقه‌ی زمان (فقط برای ویدیو مسیج)
class RoundRecordOverlay extends StatelessWidget {
  final MsgRecorder rec;
  const RoundRecordOverlay({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    if (!rec.active || rec.mode != RecMode.round) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (_, cs) {
        final d = math.max(120.0, math.min(cs.maxWidth * 0.92, cs.maxHeight * 0.92) - 14);
        final cam = rec.camera;
        Widget inner;
        if (cam != null && cam.value.isInitialized && cam.value.previewSize != null) {
          final ps = cam.value.previewSize!;
          inner = ClipOval(
            child: SizedBox(
              width: d,
              height: d,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: ps.height, height: ps.width, child: CameraPreview(cam)),
              ),
            ),
          );
        } else {
          inner = Container(
            width: d,
            height: d,
            decoration: const BoxDecoration(color: Color(0xFF111111), shape: BoxShape.circle),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54)),
          );
        }
        final frac = (rec.elapsed.inMilliseconds / rec.maxLen.inMilliseconds).clamp(0.0, 1.0).toDouble();
        return Container(
          color: Colors.black.withOpacity(0.55),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: d + 14,
                height: d + 14,
                child: CircularProgressIndicator(
                  value: frac,
                  strokeWidth: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white30,
                ),
              ),
              inner,
            ],
          ),
        );
      },
    );
  }
}

/// دکمه‌های گوشه‌ی پایین-چپ حین ضبط ویدیو: عوض کردن دوربین و چراغ قوه
class RoundTools extends StatelessWidget {
  final MsgRecorder rec;
  final VoidCallback onFlip;
  const RoundTools({super.key, required this.rec, required this.onFlip});

  @override
  Widget build(BuildContext context) {
    if (!rec.active || rec.mode != RecMode.round) return const SizedBox.shrink();
    Widget btn(IconData icon, VoidCallback onTap, {bool on = false}) => GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 28, color: on ? tgBlue : Colors.white),
          ),
        );
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC15151A),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white12, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(Icons.flip_camera_android_rounded, onFlip),
              btn(rec.torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, rec.toggleTorch, on: rec.torch),
            ],
          ),
        ),
      ),
    );
  }
}

/// دکمه‌ی مکث/ادامه بالای دکمه‌ی ارسال (فقط وقتی ضبط قفل شده)
class PauseButton extends StatelessWidget {
  final MsgRecorder rec;
  const PauseButton({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    if (rec.phase != RecPhase.locked) return const SizedBox.shrink();
    final resumeIcon = rec.mode == RecMode.voice ? Icons.mic_rounded : Icons.videocam_rounded;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 14, bottom: 12),
        child: GestureDetector(
          onTap: rec.togglePause,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: context.dark ? const Color(0xE61C2733) : const Color(0xF2FFFFFF),
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: Icon(rec.paused ? resumeIcon : Icons.pause_rounded, color: tgBlue, size: 30),
          ),
        ),
      ),
    );
  }
}

/// آیکن قفل بالای دکمه‌ی ضبط وقتی انگشت روشه (برای «کشیدن به بالا = قفل»)
class LockHint extends StatelessWidget {
  final MsgRecorder rec;
  const LockHint({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    if (rec.phase != RecPhase.held) return const SizedBox.shrink();
    final p = rec.lockProgress;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.only(right: 10, bottom: 14 + 36 * p),
        child: Container(
          width: 42,
          height: 86,
          decoration: BoxDecoration(
            color: context.dark ? const Color(0xE61C2733) : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(21),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 20, color: p > 0.5 ? tgBlue : context.subText),
              const SizedBox(height: 4),
              Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: context.subText),
            ],
          ),
        ),
      ),
    );
  }
}
