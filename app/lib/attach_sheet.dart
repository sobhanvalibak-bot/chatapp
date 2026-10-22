import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'api.dart';
import 'utils.dart';

/// یک فایل انتخاب‌شده برای ارسال
class AttachItem {
  final String name;
  final String path;
  final int size;
  AttachItem(this.name, this.path, this.size);
}

/// نتیجه‌ی شیت: لیست فایل‌های انتخاب‌شده (یا null اگه بسته شد)
Future<List<AttachItem>?> showAttachSheet(BuildContext context, {int maxCount = 10}) {
  return showModalBottomSheet<List<AttachItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _AttachSheet(maxCount: maxCount),
  );
}

enum _Tab { gallery, music, file }

class _AttachSheet extends StatefulWidget {
  final int maxCount;
  const _AttachSheet({required this.maxCount});

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  _Tab _tab = _Tab.gallery;
  final List<AssetEntity> _selected = [];
  bool _busy = false;

  Color get _bg => context.dark ? const Color(0xFF111111) : const Color(0xFFF7F7F9);

  void _toggle(AssetEntity a) {
    setState(() {
      if (_selected.contains(a)) {
        _selected.remove(a);
      } else if (_selected.length >= widget.maxCount) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You can send up to ${widget.maxCount} files at once')));
      } else {
        _selected.add(a);
      }
    });
  }

  Future<void> _sendSelected() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    final out = <AttachItem>[];
    for (final a in _selected) {
      try {
        final f = await a.originFile;
        if (f == null) continue;
        final size = await f.length();
        var name = await a.titleAsync;
        if (name.isEmpty) name = f.path.split('/').last;
        out.add(AttachItem(name, f.path, size));
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context, out);
  }

  Future<void> _browse() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true, withData: false);
      if (r == null || r.files.isEmpty || !mounted) return;
      final out = <AttachItem>[];
      for (final f in r.files) {
        if (f.path != null) out.add(AttachItem(f.name, f.path!, f.size));
      }
      Navigator.pop(context, out);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the file picker')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.62, 0.95],
      builder: (ctx, sc) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: Container(
            color: _bg,
            child: Stack(
              children: [
                Column(
                  children: [
                    // دستگیره
                    SizedBox(
                      height: 26,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: context.dark ? Colors.white24 : Colors.black26,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: switch (_tab) {
                        _Tab.gallery => _AssetGrid(
                            key: const ValueKey('g'),
                            type: RequestType.common,
                            controller: sc,
                            selected: _selected,
                            onToggle: _toggle,
                            bottomPad: 100 + bottomInset,
                          ),
                        _Tab.music => _AudioList(
                            key: const ValueKey('m'),
                            controller: sc,
                            selected: _selected,
                            onToggle: _toggle,
                            bottomPad: 100 + bottomInset,
                          ),
                        _Tab.file => _FileTab(onBrowse: _browse, controller: sc),
                      },
                    ),
                  ],
                ),
                // دکمه‌ی ارسال
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 78 + bottomInset,
                  child: IgnorePointer(
                    ignoring: _selected.isEmpty,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      offset: _selected.isEmpty ? const Offset(0, 1.5) : Offset.zero,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _selected.isEmpty ? 0 : 1,
                        child: Center(
                          child: GestureDetector(
                            onTap: _sendSelected,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                              decoration: BoxDecoration(
                                color: tgBlue,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))],
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 20, height: 20, child: CupertinoActivityIndicator(color: Colors.white))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                        const SizedBox(width: 8),
                                        Text('Send ${_selected.length}',
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // نوار پایین: فقط سه گزینه
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 10 + bottomInset,
                  child: _bar(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar() {
    final dark = context.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 62,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: dark ? const Color(0xCC1C1C1E) : const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: dark ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            children: [
              _barItem(_Tab.gallery, Icons.photo_library_rounded, 'Gallery'),
              _barItem(_Tab.music, Icons.music_note_rounded, 'Music'),
              _barItem(_Tab.file, Icons.insert_drive_file_rounded, 'File'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barItem(_Tab t, IconData icon, String label) {
    final on = _tab == t;
    final dark = context.dark;
    final color = on ? const Color(0xFFE255C8) : (dark ? Colors.white : Colors.black87);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE255C8).withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// بارگذاری رسانه‌ها با photo_manager (مجوز رو خودش می‌گیره)
// ---------------------------------------------------------------------------
class _AssetLoader extends ChangeNotifier {
  final RequestType type;
  final List<AssetEntity> items = [];
  AssetPathEntity? _path;
  int _page = 0;
  bool loading = true;
  bool denied = false;
  bool _more = true;
  static const int _size = 90;

  _AssetLoader(this.type);

  Future<void> init() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        denied = true;
        loading = false;
        notifyListeners();
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: type,
        filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
      );
      if (paths.isNotEmpty) _path = paths.first;
    } catch (_) {}
    await more();
  }

  Future<void> more() async {
    final p = _path;
    if (p == null || !_more) {
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final l = await p.getAssetListPaged(page: _page, size: _size);
      _page++;
      if (l.length < _size) _more = false;
      items.addAll(l);
    } catch (_) {
      _more = false;
    }
    loading = false;
    notifyListeners();
  }

  bool get hasMore => _more;
}

class _AssetGrid extends StatefulWidget {
  final RequestType type;
  final ScrollController controller;
  final List<AssetEntity> selected;
  final void Function(AssetEntity) onToggle;
  final double bottomPad;
  const _AssetGrid(
      {super.key,
      required this.type,
      required this.controller,
      required this.selected,
      required this.onToggle,
      required this.bottomPad});

  @override
  State<_AssetGrid> createState() => _AssetGridState();
}

class _AssetGridState extends State<_AssetGrid> {
  late final _AssetLoader _l = _AssetLoader(widget.type)..addListener(() => mounted ? setState(() {}) : null);
  void _onScroll() {
    final c = widget.controller;
    if (c.hasClients && c.position.pixels > c.position.maxScrollExtent - 600 && _l.hasMore) _l.more();
  }

  @override
  void initState() {
    super.initState();
    _l.init();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _l.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_l.loading && _l.items.isEmpty) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_l.denied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Allow access to your photos', style: TextStyle(color: context.subText, fontSize: 16)),
            const SizedBox(height: 10),
            CupertinoButton(onPressed: PhotoManager.openSetting, child: const Text('Open settings')),
          ],
        ),
      );
    }
    if (_l.items.isEmpty) {
      return Center(child: Text('Nothing here', style: TextStyle(color: context.subText)));
    }
    return GridView.builder(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(2, 2, 2, widget.bottomPad),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: _l.items.length,
      itemBuilder: (_, i) {
        final a = _l.items[i];
        final idx = widget.selected.indexOf(a);
        final on = idx >= 0;
        return GestureDetector(
          onTap: () => widget.onToggle(a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: on ? 0.9 : 1,
                child: AssetEntityImage(a, isOriginal: false, thumbnailSize: const ThumbnailSize.square(260), fit: BoxFit.cover),
              ),
              if (a.type == AssetType.video)
                Positioned(
                  left: 6,
                  bottom: 5,
                  child: Row(
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 3),
                      Text(_fmtDur(a.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 3)])),
                    ],
                  ),
                ),
              Positioned(top: 6, right: 6, child: _check(on, idx + 1)),
            ],
          ),
        );
      },
    );
  }
}

class _AudioList extends StatefulWidget {
  final ScrollController controller;
  final List<AssetEntity> selected;
  final void Function(AssetEntity) onToggle;
  final double bottomPad;
  const _AudioList({super.key, required this.controller, required this.selected, required this.onToggle, required this.bottomPad});

  @override
  State<_AudioList> createState() => _AudioListState();
}

class _AudioListState extends State<_AudioList> {
  late final _AssetLoader _l = _AssetLoader(RequestType.audio)..addListener(() => mounted ? setState(() {}) : null);
  void _onScroll() {
    final c = widget.controller;
    if (c.hasClients && c.position.pixels > c.position.maxScrollExtent - 600 && _l.hasMore) _l.more();
  }

  @override
  void initState() {
    super.initState();
    _l.init();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _l.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_l.loading && _l.items.isEmpty) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_l.denied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Allow access to your music', style: TextStyle(color: context.subText, fontSize: 16)),
            const SizedBox(height: 10),
            CupertinoButton(onPressed: PhotoManager.openSetting, child: const Text('Open settings')),
          ],
        ),
      );
    }
    if (_l.items.isEmpty) {
      return Center(child: Text('No music found', style: TextStyle(color: context.subText)));
    }
    return ListView.builder(
      controller: widget.controller,
      padding: EdgeInsets.only(bottom: widget.bottomPad),
      itemCount: _l.items.length,
      itemBuilder: (_, i) {
        final a = _l.items[i];
        final idx = widget.selected.indexOf(a);
        return InkWell(
          onTap: () => widget.onToggle(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF6B8B), Color(0xFFD72C55)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: FutureBuilder<String>(
                    future: a.titleAsync,
                    builder: (_, snap) {
                      final t = snap.data ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.isEmpty ? 'Audio' : t,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_fmtDur(a.duration), style: TextStyle(fontSize: 13, color: context.subText)),
                        ],
                      );
                    },
                  ),
                ),
                _check(idx >= 0, idx + 1),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileTab extends StatelessWidget {
  final VoidCallback onBrowse;
  final ScrollController controller;
  const _FileTab({required this.onBrowse, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: [
        InkWell(
          onTap: onBrowse,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Color(0xFF6CC46C), shape: BoxShape.circle),
                  child: const Icon(Icons.storage_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Internal Storage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Browse your file system', style: TextStyle(fontSize: 15, color: context.subText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(color: context.dark ? Colors.white12 : Colors.black12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Up to 10 files at once, max ${Api.maxFileBytes ~/ (1024 * 1024)} MB each',
              style: TextStyle(color: context.subText, fontSize: 13.5)),
        ),
      ],
    );
  }
}

Widget _check(bool on, int n) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? tgBlue : Colors.black26,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: on ? Text('$n', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)) : null,
  );
}

String _fmtDur(int sec) {
  final m = sec ~/ 60;
  final s = sec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
