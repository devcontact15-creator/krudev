import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' as pve;
import 'package:video_player/video_player.dart';

import 'core.dart';

/// Part 3 (I): the editor's STATE and basic actions: playback, loading a
/// video, thumbnails, and the non-destructive edits (speed, rotate, flip,
/// crop, mute, undo). Edits show live in the preview and are applied
/// together, once, when you press Export (see editor_tools.dart).
mixin EditorBase<T extends StatefulWidget> on State<T> {
  // ----------------------------------------------------------------- state
  VideoPlayerController? video;
  String? srcPath;
  Size srcSize = Size.zero;
  List<Uint8List?> thumbs = [];
  int thumbToken = 0;
  double total = 1;
  RangeValues range = const RangeValues(0, 1);
  final Stopwatch seekWatch = Stopwatch()..start();

  double speed = 1.0;
  int turns = 0;
  bool flipX = false;
  bool flipY = false;
  double? cropAspect;
  bool mute = false;
  final List<EditSnap> undoStack = [];

  EditorMode mode = EditorMode.edit;
  final List<TextLayer> layers = [];
  int? selectedId;
  int nextId = 1;
  LayerPose gBase = LayerPose(0.5, 0.5, 0.06, 0, 1);

  bool busy = false;
  double progress = 0;
  String status = '';
  String? renderId;
  bool cancelled = false;

  TextLayer? get selectedLayer {
    for (final l in layers) {
      if (l.id == selectedId) return l;
    }
    return null;
  }

  // -------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    errorNotifier.addListener(onError);
    cleanTemp();
  }

  @override
  void dispose() {
    errorNotifier.removeListener(onError);
    thumbToken++;
    video?.removeListener(onTick);
    video?.dispose();
    super.dispose();
  }

  void onError() {
    final e = errorNotifier.value;
    if (e != null) msg('Error: $e');
  }

  Future<void> cleanTemp() async {
    try {
      final d = await getTemporaryDirectory();
      await for (final f in d.list()) {
        final name = f.path.split('/').last;
        if (f is File && name.startsWith('krudev_') && name.endsWith('.mp4')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  void msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String fmt(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  Duration dur(double sec) => Duration(milliseconds: (sec * 1000).round());

  double posSec() {
    final c = video;
    if (c == null) return 0;
    return c.value.position.inMilliseconds / 1000.0;
  }

  // ---------------------------------------------------------------- playback

  /// Loops playback inside the selected range. No setState here.
  void onTick() {
    final c = video;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    if (c.value.isPlaying && pos >= range.end) {
      c.pause();
      c.seekTo(dur(range.start));
    }
  }

  void seekTo(double sec, {bool force = false}) {
    final c = video;
    if (c == null) return;
    if (!force && seekWatch.elapsedMilliseconds < 120) return;
    seekWatch.reset();
    c.seekTo(dur(clampD(sec, 0.0, total)));
  }

  void togglePlay() {
    final c = video;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      final pos = posSec();
      if (pos >= range.end - 0.05 || pos < range.start) {
        c.seekTo(dur(range.start));
      }
      c.play();
    }
  }

  Future<void> loadVideo(String path) async {
    final old = video;
    old?.removeListener(onTick);
    final c = VideoPlayerController.file(File(path));
    await c.initialize();
    await c.setPlaybackSpeed(speed);
    await c.setVolume(mute ? 0 : 1);
    final t = c.value.duration.inMilliseconds / 1000.0;
    c.addListener(onTick);
    setState(() {
      video = c;
      srcPath = path;
      srcSize = c.value.size;
      total = t <= 0 ? 1 : t;
      range = RangeValues(0, total);
      thumbs = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    c.play();
    makeThumbs(path);
  }

  Future<void> makeThumbs(String path) async {
    final token = ++thumbToken;
    const count = 12;
    final totalMs = (total * 1000).round();
    setState(() => thumbs = List<Uint8List?>.filled(count, null));
    try {
      final configs = pve.ThumbnailConfigs(
        video: pve.EditorVideo.file(File(path)),
        outputSize: const Size(120, 120),
        timestamps: [
          for (var i = 0; i < count; i++)
            Duration(milliseconds: ((i + 0.5) * totalMs / count).round()),
        ],
        maxParallelDecoders: 1,
      );
      await for (final frame
          in pve.ProVideoEditor.instance.getThumbnailStream(configs)) {
        if (!mounted || token != thumbToken) return;
        setState(() {
          for (final idx in frame.indices) {
            if (idx >= 0 && idx < thumbs.length) thumbs[idx] = frame.bytes;
          }
        });
      }
    } catch (_) {
      // Thumbnails are optional: the timeline still works without them.
    }
  }

  Future<void> pickVideo() async {
    if (busy) return;
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      undoStack.clear();
      layers.clear();
      selectedId = null;
      speed = 1.0;
      turns = 0;
      flipX = false;
      flipY = false;
      cropAspect = null;
      mute = false;
      await loadVideo(f.path);
    } catch (e) {
      msg('Could not open video: $e');
    }
  }

  // ------------------------------------------------- non-destructive edits

  void pushUndo() {
    undoStack.add(EditSnap(speed, turns, flipX, flipY, cropAspect, mute));
    if (undoStack.length > 30) undoStack.removeAt(0);
  }

  void undoEdit() {
    if (undoStack.isEmpty || busy) return;
    final s = undoStack.removeLast();
    setState(() {
      speed = s.speed;
      turns = s.turns;
      flipX = s.flipX;
      flipY = s.flipY;
      cropAspect = s.crop;
      mute = s.mute;
    });
    video?.setPlaybackSpeed(speed);
    video?.setVolume(mute ? 0 : 1);
  }

  void rotate() {
    pushUndo();
    setState(() => turns = (turns + 1) % 4);
  }

  void flipH() {
    pushUndo();
    setState(() => flipX = !flipX);
  }

  void flipV() {
    pushUndo();
    setState(() => flipY = !flipY);
  }

  void toggleMute() {
    pushUndo();
    setState(() => mute = !mute);
    video?.setVolume(mute ? 0 : 1);
  }

  Future<void> speedSheet() async {
    final s = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Pal.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
              .map((v) => ListTile(
                    title: Text('${v}x'),
                    trailing:
                        v == speed ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(ctx, v),
                  ))
              .toList(),
        ),
      ),
    );
    if (s == null) return;
    pushUndo();
    setState(() => speed = s);
    video?.setPlaybackSpeed(s);
  }

  Future<void> cropSheet() async {
    final options = <String, double>{
      'Original': -1,
      '9:16 (Reels / Shorts)': 9 / 16,
      '1:1 (Square)': 1,
      '16:9 (Widescreen)': 16 / 9,
      '4:3': 4 / 3,
      '3:4': 3 / 4,
    };
    final r = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Pal.panel,
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
    if (r == null) return;
    pushUndo();
    setState(() => cropAspect = r < 0 ? null : r);
  }
}
