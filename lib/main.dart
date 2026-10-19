import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_native_video_trimmer/flutter_native_video_trimmer.dart';
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
      theme: ThemeData.dark(useMaterial3: true),
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
  double _total = 1;
  RangeValues _range = const RangeValues(0, 1);
  bool _busy = false;

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

  Future<void> _pick() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    _c?.removeListener(_onTick);
    await _c?.dispose();
    final c = VideoPlayerController.file(File(f.path));
    await c.initialize();
    final total = c.value.duration.inMilliseconds / 1000.0;
    c.addListener(_onTick);
    setState(() {
      _c = c;
      _path = f.path;
      _total = total <= 0 ? 1 : total;
      _range = RangeValues(0, _total);
    });
    c.play();
  }

  Future<void> _trimAndSave() async {
    final path = _path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      _c?.pause();
      final trimmer = VideoTrimmer();
      await trimmer.loadVideo(path);
      final out = await trimmer.trimVideo(
        startTimeMs: (_range.start * 1000).round(),
        endTimeMs: (_range.end * 1000).round(),
      );
      if (out == null) throw 'Trim nahi hua';
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(out);
      _msg('Gallery mein save ho gaya ✅');
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Krudev')),
      body: Column(
        children: [
          Expanded(
            child: c == null
                ? const Center(child: Text('Koi video nahi chuna'))
                : Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
          ),
          if (c != null) ...[
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.video_library),
                  label: const Text('Video chuno'),
                ),
                if (c != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      if (c.value.isPlaying) {
                        c.pause();
                      } else {
                        final pos = c.value.position.inMilliseconds / 1000.0;
                        if (pos >= _range.end || pos < _range.start) {
                          c.seekTo(Duration(
                              milliseconds: (_range.start * 1000).round()));
                        }
                        c.play();
                      }
                    },
                    icon: Icon(
                      c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _trimAndSave,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.content_cut),
                    label: const Text('Trim + Save'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
