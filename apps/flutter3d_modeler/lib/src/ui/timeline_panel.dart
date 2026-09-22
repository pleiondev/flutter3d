/// `anim-07`'s own timeline: a ruler, one row per track with its keyframe
/// diamonds, and a playhead — dragging a diamond reports through
/// [TimelinePanel.onMoveKeys] with the real [MoveKeys] command's own shape,
/// exactly the acceptance's own "перетаскивание ромба — `MoveKeys`".
/// `S2` adds the other half of a row's own gesture: a plain tap on empty
/// track space, reported through [TimelinePanel.onSetKey].
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

// `PointerSignalEvent`/`PointerScrollEvent` for `ux-46`'s own wheel zoom,
// and `HardwareKeyboard` for its shift-click.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.selectedKeys = const <(int, int)>{},
    this.frameSnap = false,
    this.onZoom,
    this.onMoveKeys,
    this.onSeek,
    this.onSelectKey,
    this.onSetKey,
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

  /// Every key picked, as `(track, key)` pairs — `ux-46`.
  ///
  /// **A set beside the single pair rather than instead of it.** A caller
  /// that only ever picks one key keeps reading [selectedTrack]/[selectedKey]
  /// and is unchanged; one that lets a person shift-click a handful hands
  /// both, and the painter draws the union. Nudging four keys of one joint
  /// by a frame is the thing an animator does that picking them one at a
  /// time makes not worth doing.
  final Set<(int, int)> selectedKeys;

  /// Whether a dragged key lands on a frame — `ProjectProfile.frameSnap`,
  /// which nothing read before this row (`ux-46`).
  ///
  /// **A drag ends wherever a finger left it, which is never a frame.** A
  /// clip whose keys sit a thousandth of a second either side of the frames
  /// they were meant for exports as a clip that stutters, and the difference
  /// is invisible until somebody plays it back at speed. `KeyTable
  /// .snappedToFrame` is the arithmetic; this is the switch the profile
  /// already carried and nothing obeyed.
  final bool frameSnap;

  /// A wheel turn over the rows asks for a new [pixelsPerSecond] — `ux-46`.
  ///
  /// Reported rather than applied here for the same reason [onSeek] is: the
  /// zoom belongs to whatever else is looking at the same clip — a curve
  /// editor beside this one has to agree about the scale — and a panel that
  /// kept its own would be a second answer.
  final ValueChanged<double>? onZoom;

  /// A drag on a diamond ended — the real [MoveKeys] shape, ready to hand
  /// to a `Cubit`'s own history.
  final ValueChanged<MoveKeys>? onMoveKeys;

  /// The ruler was tapped or dragged at this time, clamped to the clip's
  /// own duration by the caller.
  final ValueChanged<double>? onSeek;

  /// A diamond was picked (drag start, or a plain tap that moved nothing).
  ///
  /// [add] is `ux-46`'s own shift: true means "and this one too" rather than
  /// "this one instead".
  final void Function(int trackIndex, int keyIndex, {bool add})? onSelectKey;

  /// `S2`'s own row: empty space inside track [trackIndex]'s own row was
  /// tapped — not dragged, and not near a diamond — at [time] seconds. A
  /// caller turns this into `PoseJoint` for that track's own object and
  /// path, the way `animation_wiring.dart`'s own `poseJointForSetKey` does;
  /// this panel reports the fact and nothing more, the same as [onSeek]
  /// reports a time rather than building `SetKey`/`MoveKeys` itself.
  final void Function(int trackIndex, double time)? onSetKey;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  _KeyDrag? _drag;

  /// Where a pointer went down when it hit no diamond — the candidate start
  /// of a tap on empty track space, kept only long enough for [_onPanEnd] to
  /// tell a stationary tap from a drag that simply started somewhere empty.
  Offset? _emptyTapStart;

  /// Whether the pointer travelled far enough past [_emptyTapStart] to stop
  /// counting as a tap — [kKeyHitRadius] again, the same "how close is close
  /// enough" radius a diamond hit test already uses, so a hand that has
  /// learned one has learned both.
  bool _emptyTapMoved = false;

  double get _rowHeight => ModelerMetrics.row;

  /// The track row [local] falls in, or null past the last one — used only
  /// by [onSetKey]'s own tap: [_hitTest] already answers "which row, which
  /// diamond" for a hit, but empty space inside a real row is still a row a
  /// caller can key, and [_hitTest] alone has no way to say so.
  int? _rowIndexAt(Offset local) {
    final rowIndex = (local.dy / _rowHeight).floor();
    if (rowIndex < 0 || rowIndex >= widget.clip.tracks.length) return null;
    return rowIndex;
  }

  /// [time] on a frame boundary, where the profile asks for one.
  double _snapped(double time) =>
      widget.frameSnap ? KeyTable.snappedToFrame(time, widget.fps) : time;

  /// A wheel notch over the rows, as a scale factor on [pixelsPerSecond].
  ///
  /// **Multiplicative, and clamped at both ends.** A step of the same number
  /// of pixels feels different at every zoom — the same reason
  /// `OrbitController.zoom` is multiplicative — and a timeline at half a
  /// pixel a second is a clip nobody can aim at while one at ten thousand is
  /// a single frame filling the window.
  void _wheel(PointerSignalEvent event) {
    final ValueChanged<double>? onZoom = widget.onZoom;
    if (onZoom == null || event is! PointerScrollEvent) return;
    final double factor = event.scrollDelta.dy > 0 ? 1 / 1.2 : 1.2;
    onZoom(
      (widget.pixelsPerSecond * factor).clamp(
        kTimelineZoomOut,
        kTimelineZoomIn,
      ),
    );
  }

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
    if (hit == null) {
      // Nothing to grab — the candidate start of a tap on empty track
      // space, not yet reported: [_onPanEnd] decides whether the pointer
      // ever moved far enough to stop counting as one.
      _emptyTapStart = local;
      _emptyTapMoved = false;
      return;
    }
    setState(
      () => _drag = _KeyDrag(
        trackIndex: hit.trackIndex,
        keyIndex: hit.keyIndex,
        startX: local.dx,
      ),
    );
    widget.onSelectKey?.call(
      hit.trackIndex,
      hit.keyIndex,
      // `ux-46`: shift adds to the picked set rather than replacing it —
      // the modifier every list in every application already uses for
      // exactly this, so nobody has to be told.
      add: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void _onPanUpdate(Offset local) {
    final drag = _drag;
    if (drag == null) {
      final start = _emptyTapStart;
      if (start != null && (local - start).distance > kKeyHitRadius) {
        _emptyTapMoved = true;
      }
      return;
    }
    final deltaTime = xToTime(local.dx - drag.startX, widget.pixelsPerSecond);
    // Snapped while the drag is live, not only when it lands, so the
    // diamond a person is watching sits where it is going to end up.
    final double from =
        widget.clip.tracks[drag.trackIndex].track.times[drag.keyIndex];
    setState(
      () => _drag = drag.withDeltaTime(_snapped(from + deltaTime) - from),
    );
  }

  void _onPanEnd() {
    final drag = _drag;
    if (drag == null) {
      final start = _emptyTapStart;
      if (start != null && !_emptyTapMoved) {
        final rowIndex = _rowIndexAt(start);
        if (rowIndex != null) {
          final time = xToTime(start.dx, widget.pixelsPerSecond);
          widget.onSetKey?.call(rowIndex, time < 0.0 ? 0.0 : time);
        }
      }
      _emptyTapStart = null;
      _emptyTapMoved = false;
      return;
    }
    setState(() => _drag = null);
    if (drag.deltaTime == 0.0) return;
    // `ux-46`: every picked key on the dragged key's own track moves with
    // it. `MoveKeys` is one track at a time — a key's index only means
    // anything inside its own track — so a selection spanning several
    // tracks becomes one command per track, which is also what makes each
    // of them undoable on its own terms.
    final Map<int, List<int>> byTrack = <int, List<int>>{};
    for (final (int track, int key) in <(int, int)>{
      ...widget.selectedKeys,
      (drag.trackIndex, drag.keyIndex),
    }) {
      (byTrack[track] ??= <int>[]).add(key);
    }
    for (final MapEntry<int, List<int>> each in byTrack.entries) {
      widget.onMoveKeys?.call(
        MoveKeys(
          clipIndex: widget.clipIndex,
          trackIndex: each.key,
          indices: each.value..sort(),
          deltaTime: drag.deltaTime,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.clip.tracks;
    final double duration = tracks.isEmpty
        ? 0.0
        : tracks
              .map((ProjectTrack t) => t.track.endTime)
              .reduce((double a, double b) => a > b ? a : b);
    // **The ruler is pinned and the rows scroll under it** — `ux-46`. A
    // seventeen-bone rig is fifty-one tracks, which at the row height this
    // panel uses is two and a half times the height the shell gives it: the
    // old `Column` simply painted the overflow stripes over the bottom
    // half. A ruler that scrolled away with them would be worse than the
    // overflow, since a key's own time is the one thing a row cannot say.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(width: widget.labelWidth, height: widget.rulerHeight),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails details) =>
                    _seekAt(details.localPosition.dx),
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    _seekAt(details.localPosition.dx),
                child: SizedBox(
                  height: widget.rulerHeight,
                  child: CustomPaint(
                    painter: _RulerPainter(
                      duration: duration,
                      pixelsPerSecond: widget.pixelsPerSecond,
                      fps: widget.fps,
                      time: widget.time,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: tracks.length * _rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: widget.labelWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (var i = 0; i < tracks.length; i++)
                          SizedBox(
                            height: _rowHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
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
                      child: Listener(
                        onPointerSignal: _wheel,
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
                              selectedKeys: widget.selectedKeys,
                              drag: _drag,
                              selectedColor: kModelerScheme.tertiary,
                              keyColor: kModelerScheme.primary,
                              lineColor: ModelerColors.dark.gridMajor,
                              playheadColor: ModelerColors.dark.selected,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The narrowest and widest a wheel may zoom the timeline to, in pixels a
/// second — `ux-46`.
///
/// Below the first a clip is a smear nobody can aim a key at; past the
/// second one frame fills the window and the ruler has nothing to label.
const double kTimelineZoomOut = 4.0;
const double kTimelineZoomIn = 2000.0;

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
    required this.selectedKeys,
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

  /// `ux-46`'s own multi-selection, drawn in the same colour the single one
  /// is: a person who picked four keys should see four picked keys, not one
  /// picked key and three ordinary ones.
  final Set<(int, int)> selectedKeys;
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
        final bool picked =
            (selectedTrack == t && selectedKey == k) ||
            selectedKeys.contains((t, k));
        var timeValue = times[k];
        // Every picked key moves with the dragged one — see `_onPanEnd`,
        // which sends the same set as commands.
        final bool moving =
            drag != null &&
            ((drag!.trackIndex == t && drag!.keyIndex == k) || picked);
        if (moving) timeValue += drag!.deltaTime;
        final x = timeToX(timeValue, pixelsPerSecond);
        final selected = picked;
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
      !_sameSet(oldDelegate.selectedKeys, selectedKeys) ||
      oldDelegate.drag != drag;

  static bool _sameSet(Set<(int, int)> a, Set<(int, int)> b) =>
      a.length == b.length && a.containsAll(b);
}
