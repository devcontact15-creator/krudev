import 'dart:io';

import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const KrudevApp());

double _clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class KrudevApp extends StatelessWidget {
  const KrudevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krudev',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A45),
          brightness: Brightness.dark,
        ),
      ),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  VideoPlayerController? _c;
  String? _path;
  final List<String> _history = [];
  List<String?> _thumbs = [];
  int _thumbToken = 0;
  double _total = 1;
  RangeValues _range = const RangeValues(0, 1);
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  final Stopwatch _seekWatch = Stopwatch()..start();

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _fmt(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  // Loops playback inside the selected range. No setState here,
  // so the screen is not rebuilt on every video frame.
  void _onTick() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (c.value.isPlaying && pos >= _range.end) {
      c.pause();
      c.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
    }
  }

  void _seekTo(double sec, {bool force = false}) {
    final c = _c;
    if (c == null) return;
    if (!force && _seekWatch.elapsedMilliseconds < 120) return;
    _seekWatch.reset();
    final s = _clampD(sec, 0.0, _total);
    c.seekTo(Duration(milliseconds: (s * 1000).round()));
  }

  Future<void> _load(String path) async {
    final old = _c;
    old?.removeListener(_onTick);
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    final total = c.value.duration.inMilliseconds / 1000.0;
    c.addListener(_onTick);
    setState(() {
      _c = c;
      _path = path;
      _total = total <= 0 ? 1 : total;
      _range = RangeValues(0, _total);
      _thumbs = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    c.play();
    _makeThumbs(path, c.value.aspectRatio);
  }

  Future<void> _makeThumbs(String path, double aspect) async {
    final token = ++_thumbToken;
    const count = 10;
    const h = 120;
    final totalMs = (_total * 1000).round();
    final w = (h * (aspect <= 0 ? 1.0 : aspect)).round().clamp(60, 360).toInt();
    setState(() => _thumbs = List<String?>.filled(count, null));
    for (var i = 0; i < count; i++) {
      if (!mounted || token != _thumbToken) return;
      try {
        final p = await VideoEditorBuilder(videoPath: path).generateThumbnail(
          positionMs: ((i + 0.5) * totalMs / count).round(),
          quality: 60,
          width: w,
          height: h,
        );
        if (!mounted || token != _thumbToken) return;
        setState(() => _thumbs[i] = p);
      } catch (_) {
        // If a thumbnail fails, the timeline just shows a plain block.
      }
    }
  }

  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      _history.clear();
      await _load(f.path);
    } catch (e) {
      _msg('Could not open video: $e');
    }
  }

  Future<void> _run(
    String label,
    VideoEditorBuilder Function(VideoEditorBuilder b) apply,
  ) async {
    final path = _path;
    if (path == null || _busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = label;
    });
    try {
      _c?.pause();
      final editor = apply(VideoEditorBuilder(videoPath: path));
      final String? out = await editor.export(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (out == null) throw 'No output file was created';
      _history.add(path);
      await _load(out);
      _msg('$label done ✅');
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addClip() async {
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      await _run('Add clip', (b) => b.merge(otherVideoPaths: [f.path]));
    } catch (e) {
      _msg('Could not open video: $e');
    }
  }

  Future<void> _undo() async {
    if (_history.isEmpty || _busy) return;
    final prev = _history.removeLast();
    try {
      await _load(prev);
    } catch (e) {
      _msg('Undo error: $e');
    }
  }

  Future<void> _save() async {
    final path = _path;
    if (path == null || _busy) return;
    try {
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(path);
      _msg('Saved to gallery ✅');
    } catch (e) {
      _msg('Save error: $e');
    }
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      final pos = c.value.position.inMilliseconds / 1000.0;
      if (pos >= _range.end - 0.05 || pos < _range.start) {
        c.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      }
      c.play();
    }
  }

  Future<void> _speedSheet() async {
    final s = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.5, 2.0]
              .map((v) => ListTile(
                    title: Text('${v}x'),
                    onTap: () => Navigator.pop(ctx, v),
                  ))
              .toList(),
        ),
      ),
    );
    if (s != null) {
      await _run('Speed ${s}x', (b) => b.speed(speed: s));
    }
  }

  Future<void> _cropSheet() async {
    final options = <String, VideoAspectRatio>{
      '9:16 (Reels / Shorts)': VideoAspectRatio.ratio9x16,
      '1:1 (Square)': VideoAspectRatio.ratio1x1,
      '16:9 (Widescreen)': VideoAspectRatio.ratio16x9,
      '4:3': VideoAspectRatio.ratio4x3,
      '3:4': VideoAspectRatio.ratio3x4,
    };
    final r = await showModalBottomSheet<VideoAspectRatio>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => ListTile(
                    title: Text(e.key),
                    onTap: () => Navigator.pop(ctx, e.value),
                  ))
              .toList(),
        ),
      ),
    );
    if (r != null) {
      await _run('Crop', (b) => b.crop(aspectRatio: r));
    }
  }

  @override
  void dispose() {
    _thumbToken++;
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  Widget _tool(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final off = _busy || c == null;
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KRUDEV',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'New project',
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: c == null
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('New Project'),
                    ),
                  )
                : GestureDetector(
                    onTap: _toggle,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
          ),
          if (c != null && !_busy) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, v, _) =>
                        Text(_fmt(v.position.inMilliseconds / 1000.0)),
                  ),
                  Text(' / ${_fmt(_total)}',
                      style: TextStyle(color: dim, fontSize: 12)),
                  const Spacer(),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, v, _) => IconButton(
                      iconSize: 32,
                      onPressed: _toggle,
                      icon: Icon(
                        v.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text('Selected ${_fmt(_range.end - _range.start)}',
                      style: TextStyle(color: dim, fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Timeline(
                controller: c,
                thumbs: _thumbs,
                total: _total,
                range: _range,
                onRange: (r) => setState(() => _range = r),
                onSeek: (s) => _seekTo(s),
                onSeekEnd: (s) => _seekTo(s, force: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text(
                'Drag the orange handles to select a range. '
                'Drag anywhere else to scrub.',
                style: TextStyle(fontSize: 11, color: dim),
              ),
            ),
          ],
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('$_status...'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _tool(
                    Icons.content_cut,
                    'Trim',
                    off
                        ? null
                        : () => _run(
                              'Trim',
                              (b) => b.trim(
                                startTimeMs: (_range.start * 1000).round(),
                                endTimeMs: (_range.end * 1000).round(),
                              ),
                            ),
                  ),
                  _tool(Icons.speed, 'Speed', off ? null : _speedSheet),
                  _tool(
                    Icons.rotate_right,
                    'Rotate',
                    off
                        ? null
                        : () => _run(
                              'Rotate',
                              (b) => b.rotate(degree: RotationDegree.degree90),
                            ),
                  ),
                  _tool(
                    Icons.flip,
                    'Flip H',
                    off
                        ? null
                        : () => _run(
                              'Flip',
                              (b) => b.flip(
                                flipDirection: FlipDirection.horizontal,
                              ),
                            ),
                  ),
                  _tool(
                    Icons.swap_vert,
                    'Flip V',
                    off
                        ? null
                        : () => _run(
                              'Flip',
                              (b) => b.flip(
                                flipDirection: FlipDirection.vertical,
                              ),
                            ),
                  ),
                  _tool(Icons.crop, 'Crop', off ? null : _cropSheet),
                  _tool(
                    Icons.volume_off,
                    'Mute',
                    off ? null : () => _run('Mute', (b) => b.removeAudio()),
                  ),
                  _tool(
                    Icons.add_box_outlined,
                    'Add clip',
                    off ? null : _addClip,
                  ),
                  _tool(
                    Icons.undo,
                    'Undo',
                    (off || _history.isEmpty) ? null : _undo,
                  ),
                  _tool(Icons.save_alt, 'Save', off ? null : _save),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Drag { none, start, end, head }

class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.controller,
    required this.thumbs,
    required this.total,
    required this.range,
    required this.onRange,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final VideoPlayerController controller;
  final List<String?> thumbs;
  final double total;
  final RangeValues range;
  final ValueChanged<RangeValues> onRange;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSeekEnd;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const double _minLen = 0.3;
  _Drag _drag = _Drag.none;
  double _lastSec = 0;

  double _total() => widget.total <= 0 ? 1.0 : widget.total;

  double _toSec(double x, double w) =>
      _clampD(x / w, 0.0, 1.0) * _total();

  void _start(double x, double w) {
    final sx = widget.range.start / _total() * w;
    final ex = widget.range.end / _total() * w;
    final ds = (x - sx).abs();
    final de = (x - ex).abs();
    if (ds < 28 && ds <= de) {
      _drag = _Drag.start;
    } else if (de < 28) {
      _drag = _Drag.end;
    } else {
      _drag = _Drag.head;
      _lastSec = _toSec(x, w);
      widget.onSeek(_lastSec);
    }
  }

  void _update(double x, double w) {
    final sec = _toSec(x, w);
    final r = widget.range;
    final total = _total();
    if (_drag == _Drag.start) {
      final s = _clampD(sec, 0.0, _clampD(r.end - _minLen, 0.0, total));
      _lastSec = s;
      widget.onRange(RangeValues(s, r.end));
      widget.onSeek(s);
    } else if (_drag == _Drag.end) {
      final e = _clampD(sec, _clampD(r.start + _minLen, 0.0, total), total);
      _lastSec = e;
      widget.onRange(RangeValues(r.start, e));
      widget.onSeek(e);
    } else if (_drag == _Drag.head) {
      _lastSec = sec;
      widget.onSeek(sec);
    }
  }

  void _end() {
    final t = _lastSec;
    final wasDrag = _drag != _Drag.none;
    _drag = _Drag.none;
    if (wasDrag) widget.onSeekEnd(t);
  }

  Widget _thumb(int i) {
    final list = widget.thumbs;
    final p = i < list.length ? list[i] : null;
    if (p == null) return Container(color: Colors.white12);
    return Image.file(
      File(p),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => Container(color: Colors.white12),
    );
  }

  Widget _handle(Color accent) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Container(width: 2, height: 18, color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final total = _total();
        final sx = _clampD(widget.range.start / total * w, 0.0, w);
        final ex = _clampD(widget.range.end / total * w, 0.0, w);
        final slots = widget.thumbs.isEmpty ? 10 : widget.thumbs.length;
        return SizedBox(
          height: 72,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onSeekEnd(_toSec(d.localPosition.dx, w)),
            onPanStart: (d) => _start(d.localPosition.dx, w),
            onPanUpdate: (d) => _update(d.localPosition.dx, w),
            onPanEnd: (_) => _end(),
            onPanCancel: _end,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < slots; i++)
                          Expanded(child: _thumb(i)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sx,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Colors.black54),
                  ),
                ),
                Positioned(
                  left: ex,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Colors.black54),
                  ),
                ),
                Positioned(
                  left: sx,
                  top: 0,
                  bottom: 0,
                  width: _clampD(ex - sx, 0.0, w),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: accent, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: sx - 7,
                  top: -2,
                  bottom: -2,
                  width: 14,
              
