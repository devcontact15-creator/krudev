import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' as pve;
import 'package:video_player/video_player.dart';

import 'core.dart';

/// All the editing logic of Krudev. The screen (main.dart) only draws things
/// and calls these methods.
///
/// Edits (speed, rotate, flip, crop, mute, trim range) are NON-destructive:
/// they show live in the preview and are applied together, in one go, when
/// you press Export. Text layers are rendered to images and laid over the
/// video by the native engine, with keyframes.
mixin EditorLogic<T extends StatefulWidget> on State<T> {
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

  // ------------------------------------------------------------------ layers

  Future<String?> askText(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.panel,
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

  Future<void> addText() async {
    final c = video;
    if (c == null) return;
    c.pause();
    final text = await askText('');
    if (text == null || text.trim().isEmpty) return;
    var start = clampD(posSec(), 0.0, total);
    var end = start + 3;
    if (end > total) {
      end = total;
      start = clampD(end - 3, 0.0, end);
    }
    final layer = TextLayer(
      id: nextId++,
      text: text.trim(),
      start: start,
      end: end,
    );
    setState(() {
      layers.add(layer);
      selectedId = layer.id;
    });
  }

  Future<void> editText() async {
    final l = selectedLayer;
    if (l == null) return;
    final text = await askText(l.text);
    if (text == null || text.trim().isEmpty) return;
    setState(() => l.text = text.trim());
  }

  void duplicateLayer() {
    final l = selectedLayer;
    if (l == null) return;
    final copy = l.copy(nextId++);
    setState(() {
      layers.add(copy);
      selectedId = copy.id;
    });
  }

  void deleteLayer() {
    final l = selectedLayer;
    if (l == null) return;
    setState(() {
      layers.remove(l);
      selectedId = null;
    });
  }

  /// Adds a keyframe at the playhead, or removes the one that is there.
  void toggleKey() {
    final l = selectedLayer;
    if (l == null) return;
    final t = posSec();
    if (t < l.start || t > l.end) {
      msg('Move the playhead inside the layer first');
      return;
    }
    setState(() {
      final i = l.keyIndexNear(t);
      if (i >= 0) {
        final removed = l.keys.removeAt(i);
        if (l.keys.isEmpty) {
          l.x = removed.pose.x;
          l.y = removed.pose.y;
          l.size = removed.pose.size;
          l.rotation = removed.pose.rotation;
          l.opacity = removed.pose.opacity;
        }
      } else {
        l.keys.add(PoseKey(t, l.at(t)));
        l.keys.sort((a, b) => a.t.compareTo(b.t));
      }
    });
  }

  Future<void> styleSheet() async {
    final l = selectedLayer;
    if (l == null) return;
    video?.pause();
    final t0 = posSec();
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
      backgroundColor: Pal.panel,
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
                    value: clampD(value, min, max),
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

          final p = l.at(t0);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  slider(
                    'Size',
                    p.size,
                    0.02,
                    0.4,
                    '${(p.size * 100).round()}',
                    (v) => upd(() {
                      final q = l.at(t0);
                      q.size = v;
                      l.setAt(t0, q);
                    }),
                  ),
                  slider(
                    'Rotate',
                    p.rotation * 180 / math.pi,
                    -180,
                    180,
                    '${(p.rotation * 180 / math.pi).round()}°',
                    (v) => upd(() {
                      final q = l.at(t0);
                      q.rotation = v * math.pi / 180;
                      l.setAt(t0, q);
                    }),
                  ),
                  slider(
                    'Opacity',
                    p.opacity,
                    0.0,
                    1.0,
                    '${(p.opacity * 100).round()}%',
                    (v) => upd(() {
                      final q = l.at(t0);
                      q.opacity = v;
                      l.setAt(t0, q);
                    }),
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
                  Row(
                    children: [
                      const Text('Outline'),
                      const Spacer(),
                      Switch(
                        value: l.outline,
                        onChanged: (v) => upd(() => l.outline = v),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Smooth motion'),
                      const Spacer(),
                      Switch(
                        value: l.smooth,
                        onChanged: (v) => upd(() => l.smooth = v),
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

  void scaleStart(ScaleStartDetails d) {
    final l = selectedLayer;
    if (l == null) return;
    video?.pause();
    gBase = l.at(posSec());
  }

  void scaleUpdate(ScaleUpdateDetails d, double w, double h) {
    final l = selectedLayer;
    if (l == null || busy) return;
    final t = posSec();
    if (t < l.start || t > l.end) return;
    final cur = l.at(t);
    final pinch = d.scale != 1.0 || d.rotation != 0.0;
    setState(() {
      l.setAt(
        t,
        LayerPose(
          clampD(cur.x + d.focalPointDelta.dx / w, 0.0, 1.0),
          clampD(cur.y + d.focalPointDelta.dy / h, 0.0, 1.0),
          pinch ? clampD(gBase.size * d.scale, 0.02, 0.4) : cur.size,
          pinch ? gBase.rotation + d.rotation : cur.rotation,
          cur.opacity,
        ),
      );
    });
  }

  // ------------------------------------------------------------------ export

  /// Draws a text layer into a transparent PNG at [sizeFrac] of the frame
  /// height [fh]. The native engine lays this image over the video.
  Future<RenderedPng> renderTextPng(
    TextLayer l,
    double sizeFrac,
    double fw,
    double fh,
  ) async {
    final fontSize = math.max(8.0, sizeFrac * fh);
    final base = TextStyle(
      fontSize: fontSize,
      height: 1.15,
      fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500,
    );
    TextPainter mk(TextStyle st) => TextPainter(
          text: TextSpan(text: l.text, style: st),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: fw * 0.96);
    final fill = mk(base.copyWith(color: l.color));
    final TextPainter? stroke = l.outline
        ? mk(base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize * 0.12
              ..color = Colors.black
              ..strokeJoin = StrokeJoin.round,
          ))
        : null;
    final pad = l.outline ? fontSize * 0.1 : 2.0;
    final w = (fill.width + pad * 2).ceil();
    final h = (fill.height + pad * 2).ceil();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    stroke?.paint(canvas, Offset(pad, pad));
    fill.paint(canvas, Offset(pad, pad));
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return RenderedPng(data!.buffer.asUint8List(), w, h);
  }

  /// Turns the text layers into native image layers with keyframes.
  /// [rs]/[re] is the trimmed part of the source, [spd] the playback speed;
  /// layer times are converted from source time to output time.
  Future<List<pve.ImageLayer>> buildImageLayers(
    double fw,
    double fh,
    double rs,
    double re,
    double spd,
  ) async {
    final out = <pve.ImageLayer>[];
    for (final l in layers) {
      final ws = math.max(l.start, rs);
      final we = math.min(l.end, re);
      if (we - ws < 0.05) continue;
      final times = <double>[ws];
      for (final k in l.keys) {
        if (k.t > ws + 0.001 && k.t < we - 0.001) times.add(k.t);
      }
      times.add(we);
      final states = [for (final t in times) l.at(t)];
      final maxSize = states.fold<double>(0.0, (a, s) => math.max(a, s.size));
      final png = await renderTextPng(l, maxSize, fw, fh);
      Duration ms(double src) =>
          Duration(milliseconds: (((src - rs) / spd) * 1000).round());
      final curve =
          l.smooth ? pve.AnimationCurve.easeInOut : pve.AnimationCurve.linear;
      final kfs = <pve.TimelineKeyframe>[];
      for (var i = 0; i < times.length; i++) {
        final s = states[i];
        kfs.add(pve.TimelineKeyframe(
          time: ms(times[i]),
          offset: Offset(s.x * fw - png.w / 2, s.y * fh - png.h / 2),
          scale: s.size / maxSize,
          rotation: s.rotation,
          opacity: clampD(s.opacity, 0.0, 1.0),
          curve: curve,
        ));
      }
      out.add(pve.ImageLayer(
        image: pve.EditorLayerImage.memory(png.bytes),
        startTime: ms(ws),
        endTime: ms(we),
        offset: kfs.first.offset,
        size: Size(png.w.toDouble(), png.h.toDouble()),
        keyframes: kfs,
      ));
    }
    return out;
  }

  /// Runs one native render and returns the output file path.
  Future<String> renderPass(pve.VideoRenderData data, int i, int n) async {
    final dir = await getTemporaryDirectory();
    final out =
        '${dir.path}/krudev_${DateTime.now().microsecondsSinceEpoch}.mp4';
    renderId = data.id;
    final sub = pve.ProVideoEditor.instance
        .progressStreamById(data.id)
        .listen((p) {
      if (mounted) setState(() => progress = (i + p.progress) / n);
    });
    try {
      await pve.ProVideoEditor.instance.renderVideoToFile(out, data);
    } finally {
      await sub.cancel();
    }
    return out;
  }

  Future<void> cancelExport() async {
    final id = renderId;
    if (id == null) return;
    cancelled = true;
    try {
      await pve.ProVideoEditor.instance.cancel(id);
    } catch (_) {}
  }

  /// Applies every edit in as few native passes as possible, then saves the
  /// result to the gallery:
  ///   1. trim + speed + mute + rotate (+ flip when there is no rotation)
  ///   2. flip (only when combined with a rotation)
  ///   3. crop
  ///   4. text layers
  Future<void> exportVideo() async {
    final src = srcPath;
    final c = video;
    if (src == null || c == null || busy) return;
    c.pause();
    final temps = <String>[];
    setState(() {
      busy = true;
      progress = 0;
      status = 'Exporting';
      cancelled = false;
    });
    try {
      final rs = range.start;
      final re = range.end;
      final needTrim = rs > 0.05 || re < total - 0.05;
      final tq = turns % 4;
      final flipIn1 = tq == 0 && (flipX || flipY);
      final pass1 = needTrim || speed != 1.0 || mute || tq != 0 || flipIn1;
      final flipPass = !flipIn1 && (flipX || flipY);
      final cropPass = cropAspect != null;
      final layersPass = layers.isNotEmpty;
      final n = (pass1 ? 1 : 0) +
          (flipPass ? 1 : 0) +
          (cropPass ? 1 : 0) +
          (layersPass ? 1 : 0);
      var input = src;
      var i = 0;
      var fw = tq.isOdd ? srcSize.height : srcSize.width;
      var fh = tq.isOdd ? srcSize.width : srcSize.height;

      if (pass1) {
        final data = pve.VideoRenderData(
          videoSegments: [
            pve.VideoSegment(
              video: pve.EditorVideo.file(File(input)),
              startTime: needTrim ? dur(rs) : null,
              endTime: needTrim ? dur(re) : null,
              playbackSpeed: speed != 1.0 ? speed : null,
            ),
          ],
          enableAudio: !mute,
          transform: pve.ExportTransform(
            rotateTurns: tq,
            flipX: flipIn1 && flipX,
            flipY: flipIn1 && flipY,
          ),
          outputFormat: pve.VideoOutputFormat.mp4,
        );
        input = await renderPass(data, i++, n);
        temps.add(input);
      }

      if (flipPass) {
        final data = pve.VideoRenderData(
          videoSegments: [
            pve.VideoSegment(video: pve.EditorVideo.file(File(input))),
          ],
          transform: pve.ExportTransform(flipX: flipX, flipY: flipY),
          outputFormat: pve.VideoOutputFormat.mp4,
        );
        input = await renderPass(data, i++, n);
        temps.add(input);
      }

      if (cropPass) {
        final r = cropAspect!;
        double cw;
        double ch;
        if (fw / fh > r) {
          ch = fh;
          cw = fh * r;
        } else {
          cw = fw;
          ch = fw / r;
        }
        final cwI = (cw ~/ 2) * 2;
        final chI = (ch ~/ 2) * 2;
        final xI = (((fw - cwI) / 2) ~/ 2) * 2;
        final yI = (((fh - chI) / 2) ~/ 2) * 2;
        final data = pve.VideoRenderData(
          videoSegments: [
            pve.VideoSegment(video: pve.EditorVideo.file(File(input))),
          ],
          transform: pve.ExportTransform(
            x: xI,
            y: yI,
            width: cwI,
            height: chI,
          ),
          outputFormat: pve.VideoOutputFormat.mp4,
        );
        input = await renderPass(data, i++, n);
        temps.add(input);
        fw = cwI.toDouble();
        fh = chI.toDouble();
      }

      if (layersPass) {
        final imageLayers = await buildImageLayers(
          fw,
          fh,
          needTrim ? rs : 0.0,
          needTrim ? re : total,
          speed,
        );
        if (imageLayers.isNotEmpty) {
          final data = pve.VideoRenderData(
            videoSegments: [
              pve.VideoSegment(video: pve.EditorVideo.file(File(input))),
            ],
            imageLayers: imageLayers,
            outputFormat: pve.VideoOutputFormat.mp4,
          );
          input = await renderPass(data, i++, n);
          temps.add(input);
        }
      }

      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(input);
      msg('Exported to gallery ✅');
    } catch (e) {
      if (cancelled) {
        msg('Export cancelled');
      } else {
        msg('Export error: $e');
      }
    } finally {
      for (final f in temps) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
      renderId = null;
      if (mounted) setState(() => busy = false);
    }
  }

  /// Joins another clip to the end of the current video (one fast native
  /// render) and continues editing the joined result.
  Future<void> addClip() async {
    final src = srcPath;
    if (src == null || busy) return;
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      setState(() {
        busy = true;
        progress = 0;
        status = 'Joining clips';
        cancelled = false;
      });
      video?.pause();
      final data = pve.VideoRenderData(
        videoSegments: [
          pve.VideoSegment(video: pve.EditorVideo.file(File(src))),
          pve.VideoSegment(video: pve.EditorVideo.file(File(f.path))),
        ],
        outputFormat: pve.VideoOutputFormat.mp4,
      );
      final out = await renderPass(data, 0, 1);
      await loadVideo(out);
      msg('Clip added ✅');
    } catch (e) {
      msg(cancelled ? 'Cancelled' : 'Could not add clip: $e');
    } finally {
      renderId = null;
      if (mounted) setState(() => busy = false);
    }
  }
}
