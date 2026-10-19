import 'dart:io';

import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const KrudevApp());

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
  double _total = 1;
  RangeValues _range = const RangeValues(0, 1);
  bool _busy = false;
  double _progress = 0;
  String _status = '';

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _fmt(double s) => '${s.toStringAsFixed(1)}s';

  void _onTick() {
    final c = _c;
    if (c == null) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (c.value.isPlaying && pos >= _range.end) {
      c.pause();
      c.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
    }
    if (mounted) setState(() {});
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
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    c.play();
  }

  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      _history.clear();
      await _load(f.path);
    } catch (e) {
      _msg('Video nahi khul paya: $e');
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
      if (out == null) throw 'Output nahi bana';
      _history.add(path);
      await _load(out);
      _msg('$label ho gaya ✅');
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
      await _run('Clip jodna', (b) => b.merge(otherVideoPaths: [f.path]));
    } catch (e) {
      _msg('Video nahi khul paya: $e');
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
      _msg('Gallery mein save ho gaya ✅');
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
      if (pos >= _range.end || pos < _range.start) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KRUDEV',
          style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Naya project',
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start ${_fmt(_range.start)}'),
                  Text('End ${_fmt(_range.end)}'),
                ],
              ),
            ),
            RangeSlider(
              min: 0,
              max: _total,
              values: _range,
              onChanged: (v) {
                final startMoved = v.start != _range.start;
                setState(() => _range = v);
                final t = startMoved ? v.start : v.end;
                c.seekTo(Duration(milliseconds: (t * 1000).round()));
              },
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
                              (b) => b.rotate(degree: RotationDegree.d90),
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
