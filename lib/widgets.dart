import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'core.dart';

/// Places its child so that the child's CENTRE sits at (x, y), both given as
/// fractions (0..1) of the available space.
class CenterAt extends SingleChildLayoutDelegate {
  CenterAt(this.x, this.y);

  final double x;
  final double y;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().copyWith(maxWidth: constraints.maxWidth * 0.96);

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
        x * size.width - childSize.width / 2,
        y * size.height - childSize.height / 2,
      );

  @override
  bool shouldRelayout(covariant CenterAt oldDelegate) =>
      oldDelegate.x != x || oldDelegate.y != y;
}

/// A rounded tool button with an icon and a label. [active] lights it up.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

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
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? Pal.accent.withAlpha(60) : Pal.panel2,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: active ? Pal.accent : Pal.line,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: active ? Pal.accent : Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- timeline

enum _Drag { none, start, end, head }

/// Filmstrip with a playhead and two trim handles.
class FilmTimeline extends StatefulWidget {
  const FilmTimeline({
    super.key,
    required this.controller,
    required this.thumbs,
    required this.total,
    required this.range,
    required this.onRange,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final VideoPlayerController controller;
  final List<Uint8List?> thumbs;
  final double total;
  final RangeValues range;
  final ValueChanged<RangeValues> onRange;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSeekEnd;

  @override
  State<FilmTimeline> createState() => _FilmTimelineState();
}

class _FilmTimelineState extends State<FilmTimeline> {
  static const double _minLen = 0.3;
  _Drag _drag = _Drag.none;
  double _lastSec = 0;

  double _total() => widget.total <= 0 ? 1.0 : widget.total;

  double _toSec(double x, double w) => clampD(x / w, 0.0, 1.0) * _total();

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
      final s = clampD(sec, 0.0, clampD(r.end - _minLen, 0.0, total));
      _lastSec = s;
      widget.onRange(RangeValues(s, r.end));
      widget.onSeek(s);
    } else if (_drag == _Drag.end) {
      final e = clampD(sec, clampD(r.start + _minLen, 0.0, total), total);
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
    return Image.memory(
      p,
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
        final sx = clampD(widget.range.start / total * w, 0.0, w);
        final ex = clampD(widget.range.end / total * w, 0.0, w);
        final slots = widget.thumbs.isEmpty ? 12 : widget.thumbs.length;
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
                  width: clampD(ex - sx, 0.0, w),
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
                      left: clampD(px, 0.0, w) - 1,
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

// ------------------------------------------------------------- layer rows

enum _RowDrag { none, left, right, move }

/// After Effects style layer rows: one bar per layer on the same time axis as
/// the filmstrip. Drag the bar to move it, drag its ends to change the in and
/// out points. White diamonds are keyframes.
class LayerRows extends StatefulWidget {
  const LayerRows({
    super.key,
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
  State<LayerRows> createState() => _LayerRowsState();
}

class _LayerRowsState extends State<LayerRows> {
  _RowDrag _mode = _RowDrag.none;
  double _grab = 0;

  double _tot() => widget.total <= 0 ? 1.0 : widget.total;

  double _sec(double x, double w) => clampD(x / w, 0.0, 1.0) * _tot();

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
      l.start = clampD(sec, 0.0, clampD(l.end - 0.3, 0.0, tot));
    } else if (_mode == _RowDrag.right) {
      l.end = clampD(sec, clampD(l.start + 0.3, 0.0, tot), tot);
    } else if (_mode == _RowDrag.move) {
      final len = l.end - l.start;
      final ns = clampD(sec - _grab, 0.0, clampD(tot - len, 0.0, tot));
      final shift = ns - l.start;
      l.start = ns;
      l.end = ns + len;
      for (final k in l.keys) {
        k.t += shift;
      }
    } else {
      return;
    }
    widget.onChanged();
  }

  Widget _row(TextLayer l, double w) {
    final tot = _tot();
    final sx = clampD(l.start / tot * w, 0.0, w);
    final ex = clampD(l.end / tot * w, 0.0, w);
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
                  color: Pal.panel2,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            left: sx,
            width: clampD(ex - sx, 0.0, w),
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
          for (final k in l.keys)
            Positioned(
              left: clampD(k.t / tot * w, 0.0, w) - 4,
              top: 12,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 8, height: 8, color: Colors.white),
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
                      left: clampD(px, 0.0, w) - 1,
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
