/// `anim-07`'s own timeline: a ruler, one row per track with its keyframe
/// diamonds, and a playhead — dragging a diamond reports through
/// [TimelinePanel.onMoveKeys] with the real [MoveKeys] command's own shape,
/// exactly the acceptance's own "перетаскивание ромба — `MoveKeys`".
///
/// **A dumb widget over [ProjectClip], the way [ModifierStackPanel] is one
/// over a modifier stack.** Rows are derived from `clip.tracks` at build
/// time rather than taken as a separate, invented list — an editor that added
/// a track already changed `clip`, and a panel with its own row list would be
/// a second place that edit had to reach.
///
/// **One coordinate space:** [pixelsPerSecond] maps a track's own
/// `AnimationTrack.times` straight onto local x, the same "no separate zoom"
/// choice `ProfileEditor`'s own doc comment makes and for the same reason —
/// the numbers this file's own tests compute by hand stay the numbers a
/// caller sees.
library;

import 'package:flutter/material.dart';
// `Key` hidden: `flutter3d_model_core`'s own is `KeyTable`'s keyframe class,
// and this file names a widget `Key` instead — `Widget.key`'s own type,
// which every other panel in this directory gets from `material.dart`
// without a second thought until a package with a `Key` of its own joins it.
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

import 'theme.dart';

/// Local x for a time, at [pixelsPerSecond] — the inverse of [xToTime].
double timeToX(double time, double pixelsPerSecond) => time * pixelsPerSecond;

/// The time a local x names, at [pixelsPerSecond] — the inverse of [timeToX].
double xToTime(double x, double pixelsPerSecond) => x / pixelsPerSecond;

/// How close a pointer has to land to a diamond to grab it, in logical
/// pixels — the same radius `anim-08`'s own joint picking uses, so a hand
/// that has learned one hit target has learned both.
const double kKeyHitRadius = 8.0;

/// The ruler and the rows' own canvases, wrapped in one [RepaintBoundary] —
/// what `modeler-timeline`'s own golden captures. Drawn entirely in vectors
/// (ticks, diamonds, the playhead) and never a glyph, unlike the label
/// column beside it: a golden built from this key never depends on which
/// font the machine running the test happens to have, the same
/// no-GPU-no-font independence `flutter3d_testing`'s own goldens already
/// hold for a 3D scene.
const Key kTimelineCanvasKey = ValueKey<String>('timeline-canvas');

/// One row's own default label — `path.name`, title-cased, plus the object
/// id it drives: real information a caller need not supply just to see rows
/// with something in them, and overridable through [TimelinePanel.labelOf]
/// the moment a caller can say more (a joint's own name, say).
String _defaultLabel(int trackIndex, ProjectTrack track) {
  final path = track.track.path.name;
  final title = path[0].toUpperCase() + path.substring(1);
  return '$title · obj ${track.objectId}';
}

/// A diamond mid-drag: which track and key, where the drag started, and how
/// far it has moved so far — the panel's own working state, reported through
/// [TimelinePanel.onMoveKeys] only once the drag ends.
@immutable
class _KeyDrag {
  const _KeyDrag({
    required this.trackIndex,
    required this.keyIndex,
    required this.startX,
    this.deltaTime = 0.0,
  });

  final int trackIndex;
  final int keyIndex;
  final double startX;
  final double deltaTime;

  _KeyDrag withDeltaTime(double next) => _KeyDrag(
    trackIndex: trackIndex,
    keyIndex: keyIndex,
    startX: startX,
    deltaTime: next,
  );
}

/// The scrubber, the per-track rows and the drag-to-move-a-key interaction —
/// `anim-07`'s own `TimelinePanel`.
class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.clipIndex,
    required this.clip,
    required this.time,
    this.fps = 30.0,
    this.pixelsPerSecond = 100.0,
    this.rulerHeight = 24.0,
    this.labelWidth = 120.0,
    this.labelOf = _defaultLabel,
    this.selectedTrack,
    this.selectedKey,
    this.onMoveKeys,
    this.onSeek,
    this.onSelectKey,
  });

  /// Which of [ProjectClip]'s own siblings this is — carried straight into
  /// every [MoveKeys] this panel builds, unread otherwise.
  final int clipIndex;

  final ProjectClip clip;

  /// The playhead, in seconds.
  final double time;

  final double fps;

  final double pixelsPerSecond;
  final double rulerHeight;

  /// Width of the label column at the left of each row.
  final double labelWidth;

  /// A row's own label, given its index into `clip.tracks` and the track
  /// itself.
  final String Function(int trackIndex, ProjectTrack track) labelOf;

  final int? selectedTrack;
  final int? selectedKey;

  /// A drag on a diamond ended — the real [MoveKeys] shape, ready to hand
  /// to a `Cubit`'s own history.
  final ValueChanged<MoveKeys>? onMoveKeys;

  /// The ruler was tapped or dragged at this time, clamped to the clip's
  /// own duration by the caller.
  final ValueChanged<double>? onSeek;

  /// A diamond was picked (drag start, or a plain tap that moved nothing).
  final void Function(int trackIndex, int keyIndex)? onSelectKey;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  _KeyDrag? _drag;

  double get _rowHeight => ModelerMetrics.row;

  void _seekAt(double localX) {
    final time = xToTime(localX, widget.pixelsPerSecond);
    widget.onSeek?.call(time < 0.0 ? 0.0 : time);
  }

  ({int trackIndex, int keyIndex})? _hitTest(Offset local) {
    final rowIndex = (local.dy / _rowHeight).floor();
    if (rowIndex < 0 || rowIndex >= widget.clip.tracks.length) return null;
    final track = widget.clip.tracks[rowIndex].track;

    int? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i < track.times.length; i++) {
      final x = timeToX(track.times[i], widget.pixelsPerSecond);
      final distance = (x - local.dx).abs();
      if (distance <= kKeyHitRadius && distance < nearestDistance) {
        nearest = i;
        nearestDistance = distance;
      }
    }
    if (nearest == null) return null;
    return (trackIndex: rowIndex, keyIndex: nearest);
  }

  void _onPanStart(Offset local) {
    final hit = _hitTest(local);
    if (hit == null) return;
    setState(
      () => _drag = _KeyDrag(
        trackIndex: hit.trackIndex,
        keyIndex: hit.keyIndex,
        startX: local.dx,
      ),
    );
    widget.onSelectKey?.call(hit.trackIndex, hit.keyIndex);
  }

  void _onPanUpdate(Offset local) {
    final drag = _drag;
    if (drag == null) return;
    final deltaTime = xToTime(local.dx - drag.startX, widget.pixelsPerSecond);
    setState(() => _drag = drag.withDeltaTime(deltaTime));
  }

  void _onPanEnd() {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    if (drag.deltaTime == 0.0) return;
    widget.onMoveKeys?.call(
      MoveKeys(
        clipIndex: widget.clipIndex,
        trackIndex: drag.trackIndex,
        indices: <int>[drag.keyIndex],
        deltaTime: drag.deltaTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.clip.tracks;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: widget.labelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(height: widget.rulerHeight),
              for (var i = 0; i < tracks.length; i++)
                SizedBox(
                  height: _rowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        widget.labelOf(i, tracks[i]),
                        overflow: TextOverflow.ellipsis,
                        style: i == widget.selectedTrack
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RepaintBoundary(
            key: kTimelineCanvasKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails details) =>
                      _seekAt(details.localPosition.dx),
                  onHorizontalDragUpdate: (DragUpdateDetails details) =>
                      _seekAt(details.localPosition.dx),
                  child: SizedBox(
                    height: widget.rulerHeight,
                    child: CustomPaint(
                      painter: _RulerPainter(
                        duration: widget.clip.tracks.isEmpty
                            ? 0.0
                            : widget.clip.tracks
                                  .map((ProjectTrack t) => t.track.endTime)
                                  .reduce(
                                    (double a, double b) => a > b ? a : b,
                                  ),
                        pixelsPerSecond: widget.pixelsPerSecond,
                        fps: widget.fps,
                        time: widget.time,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (DragStartDetails details) =>
                        _onPanStart(details.localPosition),
                    onPanUpdate: (DragUpdateDetails details) =>
                        _onPanUpdate(details.localPosition),
                    onPanEnd: (_) => _onPanEnd(),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TimelineRowsPainter(
                        tracks: tracks,
                        rowHeight: _rowHeight,
                        pixelsPerSecond: widget.pixelsPerSecond,
                        time: widget.time,
                        selectedTrack: widget.selectedTrack,
                        selectedKey: widget.selectedKey,
                        drag: _drag,
                        selectedColor: kModelerScheme.tertiary,
                        keyColor: kModelerScheme.primary,
                        lineColor: ModelerColors.dark.gridMajor,
                        playheadColor: ModelerColors.dark.selected,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The time ruler: tick marks at every whole frame's own second, and the
/// playhead.
class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.duration,
    required this.pixelsPerSecond,
    required this.fps,
    required this.time,
  });

  final double duration;
  final double pixelsPerSecond;
  final double fps;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()..color = ModelerColors.dark.gridMinor;
    final seconds = duration.ceil() + 1;
    for (var s = 0; s <= seconds; s++) {
      final x = timeToX(s.toDouble(), pixelsPerSecond);
      canvas.drawLine(
        Offset(x, size.height * 0.4),
        Offset(x, size.height),
        tickPaint,
      );
    }

    final playheadPaint = Paint()
      ..color = ModelerColors.dark.selected
      ..strokeWidth = 2;
    final playheadX = timeToX(time, pixelsPerSecond);
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.duration != duration ||
      oldDelegate.pixelsPerSecond != pixelsPerSecond ||
      oldDelegate.time != time;
}

/// Every row's own baseline and diamonds, plus the playhead running through
/// all of them.
class _TimelineRowsPainter extends CustomPainter {
  const _TimelineRowsPainter({
    required this.tracks,
    required this.rowHeight,
    required this.pixelsPerSecond,
    required this.time,
    required this.selectedTrack,
    required this.selectedKey,
    required this.drag,
    required this.selectedColor,
    required this.keyColor,
    required this.lineColor,
    required this.playheadColor,
  });

  final List<ProjectTrack> tracks;
  final double rowHeight;
  final double pixelsPerSecond;
  final double time;
  final int? selectedTrack;
  final int? selectedKey;
  final _KeyDrag? drag;
  final Color selectedColor;
  final Color keyColor;
  final Color lineColor;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final keyPaint = Paint()..color = keyColor;
    final selectedPaint = Paint()..color = selectedColor;

    for (var t = 0; t < tracks.length; t++) {
      final centerY = t * rowHeight + rowHeight / 2;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        linePaint,
      );

      final times = tracks[t].track.times;
      for (var k = 0; k < times.length; k++) {
        var timeValue = times[k];
        if (drag != null && drag!.trackIndex == t && drag!.keyIndex == k) {
          timeValue += drag!.deltaTime;
        }
        final x = timeToX(timeValue, pixelsPerSecond);
        final selected = selectedTrack == t && selectedKey == k;
        _drawDiamond(
          canvas,
          Offset(x, centerY),
          selected ? selectedPaint : keyPaint,
        );
      }
    }

    final playheadPaint = Paint()
      ..color = playheadColor
      ..strokeWidth = 2;
    final playheadX = timeToX(time, pixelsPerSecond);
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  void _drawDiamond(Canvas canvas, Offset center, Paint paint) {
    const half = 5.0;
    final path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half, center.dy)
      ..lineTo(center.dx, center.dy + half)
      ..lineTo(center.dx - half, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TimelineRowsPainter oldDelegate) =>
      !identical(oldDelegate.tracks, tracks) ||
      oldDelegate.time != time ||
      oldDelegate.selectedTrack != selectedTrack ||
      oldDelegate.selectedKey != selectedKey ||
      oldDelegate.drag != drag;
}
