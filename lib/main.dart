import 'dart:io';
import 'dart:math' as math;

import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const KrudevApp());

double _clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class _Pal {
  static const bg = Color(0xFF0D0D12);
  static const panel = Color(0xFF16161E);
  static const panel2 = Color(0xFF20202B);
  static const accent = Color(0xFF8B7CFF);
  static const line = Color(0x1FFFFFFF);
}

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
        scaffoldBackgroundColor: _Pal.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _Pal.accent,
          brightness: Brightness.dark,
        ).copyWith(primary: _Pal.accent, surface: _Pal.panel),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _Pal.panel2,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const EditorPage(),
    );
  }
}

/// A text layer. Position is the layer centre as a fraction of the video
/// (0..1), size is a fraction of the video height, so it does not depend on
/// the phone screen size.
class TextLayer {
  TextLayer({
    required this.id,
    required this.text,
    required this.start,
    required this.end,
  });

  final int id;
  String text;
  double start;
  double end;
  double x = 0.5;
  double y = 0.5;
  double size = 0.06;
  double rotation = 0;
  double opacity = 1;
  Color color = Colors.white;
  bool bold = true;

  TextLayer copy(int newId) {
    final l = TextLayer(id: newId, text: text, start: start, end: end);
    l.x = x;
    l.y = _clampD(y + 0.08, 0.0, 1.0);
    l.size = size;
    l.rotation = rotation;
    l.opacity = opacity;
    l.color = color;
    l.bold = bold;
    return l;
  }
}

enum _Mode { edit, text }

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

  _Mode _mode = _Mode.edit;
  final List<TextLayer> _layers = [];
  int? _selected;
  int _nextId = 1;
  double _baseSize = 0.06;
  double _baseRot = 0;

  TextLayer? get _selectedLayer {
    for (final l in _layers) {
      if (l.id == _selected) return l;
    }
    return null;
  }

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
      _layers.clear();
      _selected = null;
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
    if (_layers.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _Pal.panel,
          title: const Text('Text layers not included'),
          content: const Text(
            'Exporting text layers into the video is coming in the next '
            'update. Save the video without them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
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
      backgroundColor: _Pal.panel,
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
      backgroundColor: _Pal.panel,
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

  // ---------------------------------------------------------------- layers

  Future<String?> _askText(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _Pal.panel,
        title: const Text('Text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Type your text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addText() async {
    final c = _c;
    if (c == null) return;
    final text = await _askText('');
    if (text == null || text.trim().isEmpty) return;
    final t = c.value.position.inMilliseconds / 1000.0;
    var start = _clampD(t, 0.0, _total);
    var end = start + 3;
    if (end > _total) {
      end = _total;
      start = _clampD(end - 3, 0.0, end);
    }
    final layer = TextLayer(
      id: _nextId++,
      text: text.trim(),
      start: start,
      end: end,
    );
    setState(() {
      _layers.add(layer);
      _selected = layer.id;
    });
  }

  Future<void> _editText() async {
    final l = _selectedLayer;
    if (l == null) return;
    final text = await _askText(l.text);
    if (text == null || text.trim().isEmpty) return;
    setState(() => l.text = text.trim());
  }

  void _duplicateLayer() {
    final l = _selectedLayer;
    if (l == null) return;
    final copy = l.copy(_nextId++);
    setState(() {
      _layers.add(copy);
      _selected = copy.id;
    });
  }

  void _deleteLayer() {
    final l = _selectedLayer;
    if (l == null) return;
    setState(() {
      _layers.remove(l);
      _selected = null;
    });
  }

  Future<void> _styleSheet() async {
    final l = _selectedLayer;
    if (l == null) return;
    const swatches = <Color>[
      Colors.white,
      Colors.black,
      Colors.yellow,
      Colors.redAccent,
      Colors.lightBlueAccent,
      Colors.greenAccent,
      Color(0xFFFF7A45),
      Color(0xFF8B7CFF),
    ];
    await showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.transparent,
      backgroundColor: _Pal.panel,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void upd(VoidCallback f) {
            f();
            setSheet(() {});
            setState(() {});
          }

          Widget slider(
            String label,
            double value,
            double min,
            double max,
            String shown,
            ValueChanged<double> onChanged,
          ) {
            return Row(
              children: [
                SizedBox(width: 64, child: Text(label)),
                Expanded(
                  child: Slider(
                    value: _clampD(value, min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(shown, textAlign: TextAlign.end),
                ),
              ],
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  slider(
                    'Size',
                    l.size,
                    0.02,
                    0.3,
                    '${(l.size * 100).round()}',
                    (v) => upd(() => l.size = v),
                  ),
                  slider(
                    'Rotate',
                    l.rotation * 180 / math.pi,
                    -180,
                    180,
                    '${(l.rotation * 180 / math.pi).round()}°',
                    (v) => upd(() => l.rotation = v * math.pi / 180),
                  ),
                  slider(
                    'Opacity',
                    l.opacity,
                    0.1,
                    1,
                    '${(l.opacity * 100).round()}%',
                    (v) => upd(() => l.opacity = v),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final col in swatches)
                          GestureDetector(
                            onTap: () => upd(() => l.color = col),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: l.color == col
                                      ? Colors.white
                                      : Colors.white24,
                                  width: l.color == col ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Bold'),
                      const Spacer(),
                      Switch(
                        value: l.bold,
                        onChanged: (v) => upd(() => l.bold = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _scaleStart(ScaleStartDetails d) {
    final l = _selectedLayer;
    if (l == null) return;
    _baseSize = l.size;
    _baseRot = l.rotation;
  }

  void _scaleUpdate(ScaleUpdateDetails d, double w, double h) {
    final l = _selectedLayer;
    final c = _c;
    if (l == null || c == null || _busy) return;
    final t = c.value.position.inMilliseconds / 1000.0;
    if (t < l.start || t > l.end) return;
    setState(() {
      l.x = _clampD(l.x + d.focalPointDelta.dx / w, 0.0, 1.0);
      l.y = _clampD(l.y + d.focalPointDelta.dy / h, 0.0, 1.0);
      if (d.scale != 1.0 || d.rotation != 0.0) {
        l.size = _clampD(_baseSize * d.scale, 0.02, 0.3);
        l.rotation = _baseRot + d.rotation;
      }
    });
  }

  Widget _layerView(TextLayer l, double w, double h) {
    final selected = l.id == _selected;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _CenterAt(l.x, l.y),
        child: Transform.rotate(
          angle: l.rotation,
          child: Opacity(
            opacity: l.opacity,
            child: GestureDetector(
              onTap: () => setState(() => _selected = l.id),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: selected
                      ? Border.all(color: _Pal.accent, width: 1.5)
                      : null,
                ),
                child: Text(
                  l.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: l.color,
                    fontSize: l.size * h,
                    height: 1.15,
                    fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500,
                    shadows: const [
                      Shadow(blurRadius: 6, color: Colors.black54),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _thumbToken++;
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------- UI

  Widget _emptyState() {
    return Center(
      child: GestureDetector(
        onTap: _busy ? null : _pick,
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF2A2250), Color(0xFF16161E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _Pal.accent.withAlpha(120)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  size: 44, color: _Pal.accent),
              SizedBox(height: 14),
              Text(
                'New Project',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Import a video to start',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(VideoPlayerController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final h = box.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  onScaleStart: _scaleStart,
                  onScaleUpdate: (d) => _scaleUpdate(d, w, h),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(c),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: c,
                        builder: (context, v, _) {
                          final t = v.position.inMilliseconds / 1000.0;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              for (final l in _layers)
                                if (t >= l.start && t <= l.end)
                                  _layerView(l, w, h),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _transport(VideoPlayerController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => Text(
              _fmt(v.position.inMilliseconds / 1000.0),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            ' / ${_fmt(_total)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => IconButton.filledTonal(
              onPressed: _toggle,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  v.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(v.isPlaying),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Range ${_fmt(_range.end - _range.start)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _timelinePanel(VideoPlayerController c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _Pal.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Pal.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Timeline(
            controller: c,
            thumbs: _thumbs,
            total: _total,
            range: _range,
            onRange: (r) => setState(() => _range = r),
            onSeek: (s) => _seekTo(s),
            onSeekEnd: (s) => _seekTo(s, force: true),
          ),
          _LayerRows(
            controller: c,
            layers: _layers,
            total: _total,
            selected: _selected,
            onSelect: (id) => setState(() => _selected = id),
            onToggle: (id) =>
                setState(() => _selected = _selected == id ? null : id),
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _busyPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Pal.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Pal.line),
      ),
      child: Column(
        children: [
          Text('$_status...'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _progress > 0 ? _progress : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_Mode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _Mode.edit,
              icon: Icon(Icons.tune_rounded, size: 18),
              label: Text('Edit'),
            ),
            ButtonSegment(
              value: _Mode.text,
              icon: Icon(Icons.text_fields_rounded, size: 18),
              label: Text('Text'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
      ),
    );
  }

  Widget _editTools(bool off) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        _ToolButton(
          icon: Icons.content_cut_rounded,
          label: 'Trim',
          onTap: off
              ? null
              : () => _run(
                    'Trim',
                    (b) => b.trim(
                      startTimeMs: (_range.start * 1000).round(),
                      endTimeMs: (_range.end * 1000).round(),
                    ),
                  ),
        ),
        _ToolButton(
          icon: Icons.speed_rounded,
          label: 'Speed',
          onTap: off ? null : _speedSheet,
        ),
        _ToolButton(
          icon: Icons.rotate_right_rounded,
          label: 'Rotate',
          onTap: off
              ? null
              : () => _run(
                    'Rotate',
                    (b) => b.rotate(degree: RotationDegree.degree90),
                  ),
        ),
        _ToolButton(
          icon: Icons.flip_rounded,
          label: 'Flip H',
          onTap: off
              ? null
              : () => _run(
                    'Flip',
                    (b) => b.flip(flipDirection: FlipDirection.horizontal),
                  ),
        ),
        _ToolButton(
          icon: Icons.swap_vert_rounded,
          label: 'Flip V',
          onTap: off
              ? null
              : () => _run(
                    'Flip',
                    (b) => b.flip(flipDirection: FlipDirection.vertical),
                  ),
        ),
        _ToolButton(
          icon: Icons.crop_rounded,
          label: 'Crop',
          onTap: off ? null : _cropSheet,
        ),
        _ToolButton(
          icon: Icons.volume_off_rounded,
          label: 'Mute',
          onTap: off ? null : () => _run('Mute', (b) => b.removeAudio()),
        ),
        _ToolButton(
          icon: Icons.add_box_rounded,
          label: 'Add clip',
          onTap: off ? null : _addClip,
        ),
        _ToolButton(
          icon: Icons.undo_rounded,
          label: 'Undo',
          onTap: (off || _history.isEmpty) ? null : _undo,
        ),
      ],
    );
  }

  Widget _textTools(bool off) {
    final has = _selectedLayer != null;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        _ToolButton(
          icon: Icons.title_rounded,
          label: 'Add text',
          onTap: off ? null : _addText,
        ),
        _ToolButton(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: (off || !has) ? null : _editText,
        ),
        _ToolButton(
          icon: Icons.palette_rounded,
          label: 'Style',
          onTap: (off || !has) ? null : _styleSheet,
        ),
        _ToolButton(
          icon: Icons.content_copy_rounded,
          label: 'Duplicate',
          onTap: (off || !has) ? null : _duplicateLayer,
        ),
        _ToolButton(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: (off || !has) ? null : _deleteLayer,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final off = _busy || c == null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: _Pal.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'KRUDEV',
              style: TextStyle(
                letterSpacing: 4,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New project',
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: off ? null : _save,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: c == null ? _emptyState() : _preview(c)),
          if (c != null && !_busy) ...[
            _transport(c),
            _timelinePanel(c),
          ],
          if (_busy) _busyPanel(),
          if (c != null) ...[
            _modeTabs(),
            SafeArea(
              top: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  key: ValueKey(_mode),
                  height: 92,
                  child: _mode == _Mode.edit ? _editTools(off) : _textTools(off),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CenterAt extends SingleChildLayoutDelegate {
  _CenterAt(this.x, this.y);

  final double x;
  final double y;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
        x * size.width - childSize.width / 2,
        y * size.height - childSize.height / 2,
      );

  @override
  bool shouldRelayout(covariant _CenterAt oldDelegate) =>
      oldDelegate.x != x || oldDelegate.y != y;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap!();
              }
            : null,
        child: SizedBox(
          width: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _Pal.panel2,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _Pal.line),
                ),
                child: Icon(icon, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
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

  double _toSec(double x, double w) => _clampD(x / w, 0.0, 1.0) * _total();

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
                  child: _handle(accent),
                ),
                Positioned(
                  left: ex - 7,
                  top: -2,
                  bottom: -2,
                  width: 14,
                  child: _handle(accent),
                ),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: widget.controller,
                  builder: (context, v, _) {
                    final px = v.position.inMilliseconds / 1000.0 / total * w;
                    return Positioned(
                      left: _clampD(px, 0.0, w) - 1,
                      top: -6,
                      bottom: -6,
                      width: 2,
                      child: const IgnorePointer(
                        child: ColoredBox(color: Colors.white),
                      ),
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

enum _RowDrag { none, left, right, move }

/// After Effects style layer rows: one bar per layer, same time axis as the
/// filmstrip. Drag the bar to move it, drag its ends to change in/out points.
class _LayerRows extends StatefulWidget {
  const _LayerRows({
    required this.controller,
    required this.layers,
    required this.total,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    required this.onChanged,
  });

  final VideoPlayerController controller;
  final List<TextLayer> layers;
  final double total;
  final int? selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onToggle;
  final VoidCallback onChanged;

  @override
  State<_LayerRows> createState() => _LayerRowsState();
}

class _LayerRowsState extends State<_LayerRows> {
  _RowDrag _mode = _RowDrag.none;
  double _grab = 0;

  double _tot() => widget.total <= 0 ? 1.0 : widget.total;

  double _sec(double x, double w) => _clampD(x / w, 0.0, 1.0) * _tot();

  void _dragStart(TextLayer l, double x, double w) {
    final tot = _tot();
    final sx = l.start / tot * w;
    final ex = l.end / tot * w;
    final ds = (x - sx).abs();
    final de = (x - ex).abs();
    widget.onSelect(l.id);
    if (ds < 20 && ds <= de) {
      _mode = _RowDrag.left;
    } else if (de < 20) {
      _mode = _RowDrag.right;
    } else if (x >= sx && x <= ex) {
      _mode = _RowDrag.move;
      _grab = _sec(x, w) - l.start;
    } else {
      _mode = _RowDrag.none;
    }
  }

  void _dragUpdate(TextLayer l, double x, double w) {
    final sec = _sec(x, w);
    final tot = _tot();
    if (_mode == _RowDrag.left) {
      l.start = _clampD(sec, 0.0, _clampD(l.end - 0.3, 0.0, tot));
    } else if (_mode == _RowDrag.right) {
      l.end = _clampD(sec, _clampD(l.start + 0.3, 0.0, tot), tot);
    } else if (_mode == _RowDrag.move) {
      final len = l.end - l.start;
      final ns = _clampD(sec - _grab, 0.0, _clampD(tot - len, 0.0, tot));
      l.start = ns;
      l.end = ns + len;
    } else {
      return;
    }
    widget.onChanged();
  }

  Widget _row(TextLayer l, double w) {
    final tot = _tot();
    final sx = _clampD(l.start / tot * w, 0.0, w);
    final ex = _clampD(l.end / tot * w, 0.0, w);
    final sel = l.id == widget.selected;
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onToggle(l.id),
      onHorizontalDragStart: (d) => _dragStart(l, d.localPosition.dx, w),
      onHorizontalDragUpdate: (d) => _dragUpdate(l, d.localPosition.dx, w),
      onHorizontalDragEnd: (_) => _mode = _RowDrag.none,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _Pal.panel2,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            left: sx,
            width: _clampD(ex - sx, 0.0, w),
            top: 3,
            bottom: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: accent.withAlpha(sel ? 210 : 110),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: sel ? Colors.white : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                l.text.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.layers.length;
    if (n == 0) return const SizedBox.shrink();
    final rows = n > 3 ? 3 : n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: rows * 32.0,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final tot = _tot();
            return Stack(
              children: [
                ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: 32,
                  itemCount: n,
                  itemBuilder: (context, i) => _row(widget.layers[i], w),
                ),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: widget.controller,
                  builder: (context, v, _) {
                    final px = v.position.inMilliseconds / 1000.0 / tot * w;
                    return Positioned(
                      left: _clampD(px, 0.0, w) - 1,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: const IgnorePointer(
                        child: ColoredBox(color: Colors.white),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
