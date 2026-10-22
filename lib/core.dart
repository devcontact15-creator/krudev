import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ------------------------------------------------------------------ errors
// Any uncaught error is shown on screen and saved to krudev_error.log, so a
// screenshot tells us exactly what went wrong.

final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

Future<void> logError(String msg) async {
  errorNotifier.value = msg.length > 240 ? msg.substring(0, 240) : msg;
  try {
    final d = await getTemporaryDirectory();
    await File('${d.path}/krudev_error.log').writeAsString(
      '${DateTime.now()}  $msg\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

// ------------------------------------------------------------------ helpers

double clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class Pal {
  static const bg = Color(0xFF0D0D12);
  static const panel = Color(0xFF16161E);
  static const panel2 = Color(0xFF20202B);
  static const accent = Color(0xFF8B7CFF);
  static const line = Color(0x1FFFFFFF);
}

enum EditorMode { edit, text }

// ------------------------------------------------------------------ models

/// Where a layer is at one moment: centre as a fraction of the frame (0..1),
/// size as a fraction of the frame height, rotation in radians, opacity 0..1.
class LayerPose {
  LayerPose(this.x, this.y, this.size, this.rotation, this.opacity);

  double x;
  double y;
  double size;
  double rotation;
  double opacity;
}

LayerPose copyPose(LayerPose p) =>
    LayerPose(p.x, p.y, p.size, p.rotation, p.opacity);

class PoseKey {
  PoseKey(this.t, this.pose);

  double t;
  LayerPose pose;
}

/// A text layer. With no keyframes it is static. With keyframes it animates
/// between them (like After Effects), and an edit made at a new time creates
/// a new keyframe automatically.
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
  bool outline = true;
  bool smooth = true;
  final List<PoseKey> keys = [];

  LayerPose get base => LayerPose(x, y, size, rotation, opacity);

  int keyIndexNear(double t) {
    for (var i = 0; i < keys.length; i++) {
      if ((keys[i].t - t).abs() < 0.06) return i;
    }
    return -1;
  }

  /// The layer's pose at time [t] (seconds on the source timeline).
  LayerPose at(double t) {
    if (keys.isEmpty) return base;
    if (t <= keys.first.t) return copyPose(keys.first.pose);
    if (t >= keys.last.t) return copyPose(keys.last.pose);
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = b.t - a.t;
        var u = span <= 0 ? 1.0 : (t - a.t) / span;
        if (smooth) u = Curves.easeInOut.transform(u);
        double mix(double p, double q) => p + (q - p) * u;
        return LayerPose(
          mix(a.pose.x, b.pose.x),
          mix(a.pose.y, b.pose.y),
          mix(a.pose.size, b.pose.size),
          mix(a.pose.rotation, b.pose.rotation),
          mix(a.pose.opacity, b.pose.opacity),
        );
      }
    }
    return copyPose(keys.last.pose);
  }

  /// Edits the pose at time [t]. Static layer: changes the layer itself.
  /// Animated layer: updates the keyframe at [t], or creates one.
  void setAt(double t, LayerPose s) {
    if (keys.isEmpty) {
      x = s.x;
      y = s.y;
      size = s.size;
      rotation = s.rotation;
      opacity = s.opacity;
      return;
    }
    final i = keyIndexNear(t);
    if (i >= 0) {
      keys[i].pose = s;
      return;
    }
    keys.add(PoseKey(t, s));
    keys.sort((a, b) => a.t.compareTo(b.t));
  }

  TextLayer copy(int newId) {
    final l = TextLayer(id: newId, text: text, start: start, end: end);
    l.x = x;
    l.y = clampD(y + 0.08, 0.0, 1.0);
    l.size = size;
    l.rotation = rotation;
    l.opacity = opacity;
    l.color = color;
    l.bold = bold;
    l.outline = outline;
    l.smooth = smooth;
    for (final k in keys) {
      l.keys.add(PoseKey(k.t, copyPose(k.pose)));
    }
    return l;
  }
}

/// A snapshot of the non-destructive edits, for Undo.
class EditSnap {
  EditSnap(
    this.speed,
    this.turns,
    this.flipX,
    this.flipY,
    this.crop,
    this.mute,
  );

  final double speed;
  final int turns;
  final bool flipX;
  final bool flipY;
  final double? crop;
  final bool mute;
}

/// A rendered text image, ready to be used as a video overlay.
class RenderedPng {
  RenderedPng(this.bytes, this.w, this.h);

  final Uint8List bytes;
  final int w;
  final int h;
}
