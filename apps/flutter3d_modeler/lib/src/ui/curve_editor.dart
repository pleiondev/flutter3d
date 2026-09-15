/// `S2`'s own curve editor: one track's own component, drawn as a line
/// through [curveSamples], its keys as points and — while the track is
/// [AnimationInterpolation.cubicSpline] — a pair of draggable tangent
/// handles either side of each one, from [tangentHandles].
///
/// **One raw component at a time, never a converted one.** [eulerOf] reads
/// here too, but only for the small read-out above the canvas on a rotation
/// track's own selected key — "pitch 12° · yaw 45° · roll 0°" — never for the
/// curve itself. [eulerOf]'s own doc comment says why: nothing downstream
/// reads a rotation as three Euler angles, so a curve drawn in that space
/// would need a lossy round trip back to a quaternion the moment a person
/// dragged it. Drawing the *stored* component — `x`/`y`/`z`/`w` for a
/// rotation track, same as `translation`/`scale` — keeps a drag exactly
/// invertible: [SetKey]/[SetTangent] write back the one component that
/// moved and nothing else, the same "leave every other field untouched"
/// contract [PoseJoint]'s own three-components-in-one-transaction pattern
/// depends on elsewhere.
///
/// **A key moves only vertically here.** Its time is [TimelinePanel]'s own
/// business — dragging a diamond there is `MoveKeys` — so this widget reads
/// [AnimationTrack.times] but never writes it; dragging a key point changes
/// only [component]'s own value at the time it already has, which is what
/// makes it a plain [SetKey] rather than a second way to move a keyframe in
/// time that could disagree with the first.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:vector_math/vector_math.dart' show Quaternion;

import 'theme.dart';
import 'timeline_panel.dart' show kKeyHitRadius, timeToX;

/// The captured region of [CurveEditor]'s own golden — the curve, its keys
/// and its tangent handles, drawn entirely in vectors, the same
/// no-glyph promise [kTimelineCanvasKey] already keeps for the timeline.
const Key kCurveEditorCanvasKey = ValueKey<String>('curve-editor-canvas');

/// How far into the vertical space each edge of the value range is padded,
/// as a fraction of the canvas height — so a curve that touches its own
/// extremes is not drawn flush against the top and bottom edges. Public for
/// the same reason [kKeyHitRadius] is: a test driving a drag by hand needs
/// the exact value-to-pixel mapping this widget itself uses.
const double kCurveEditorVerticalMargin = 0.12;

String _componentLabel(AnimationPath path, int component) => switch (path) {
  AnimationPath.translation ||
  AnimationPath.scale => const <String>['X', 'Y', 'Z'][component],
  AnimationPath.rotation => const <String>['X', 'Y', 'Z', 'W'][component],
  AnimationPath.weights => 'W$component',
};

/// Which handle of a key is being dragged, or the key's own value.
enum _DragTarget { value, inTangent, outTangent }

@immutable
class _Drag {
  const _Drag({required this.keyIndex, required this.target, required this.y});

  final int keyIndex;
  final _DragTarget target;

  /// The pointer's own current y, updated on every move — the one thing
  /// [CurveEditorPainter] needs to draw the point where it actually is
  /// rather than where the key started.
  final double y;

  _Drag withY(double newY) =>
      _Drag(keyIndex: keyIndex, target: target, y: newY);
}

/// `S2`'s own curve editor over one [track]'s own [component].
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    super.key,
    required this.clipIndex,
    required this.trackIndex,
    required this.track,
    this.selectedKeyIndex,
    this.currentTime = 0.0,
    this.pixelsPerSecond = 100.0,
    this.sampleCount = 120,
    this.onSelectKey,
    this.onSetKey,
    this.onSetTangent,
  });

  /// Carried straight into every [SetKey]/[SetTangent] this widget builds,
  /// unread otherwise.
  final int clipIndex;
  final int trackIndex;

  final AnimationTrack track;

  /// Which key a drag started on is selected on its own — this is only the
  /// *initial* highlight, before a person has touched anything.
  final int? selectedKeyIndex;

  /// The playhead, in seconds — drawn as the same vertical line
  /// [TimelinePanel]'s own ruler draws, so switching the `Keys`/`Curves`
  /// toggle mid-scrub never loses sight of where the scrubber actually is.
  final double currentTime;

  /// The same coordinate convention [TimelinePanel] draws its own ruler in,
  /// so switching the transport's `Keys`/`Curves` toggle does not also slide
  /// the horizontal axis out from under a person's eye.
  final double pixelsPerSecond;

  final int sampleCount;

  final ValueChanged<int>? onSelectKey;
  final ValueChanged<SetKey>? onSetKey;
  final ValueChanged<SetTangent>? onSetTangent;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  int _component = 0;
  _Drag? _drag;
  Size _canvasSize = Size.zero;

  @override
  void didUpdateWidget(covariant CurveEditor old) {
    super.didUpdateWidget(old);
    // A track switch can leave `_component` past the new track's own count —
    // clamped rather than left to throw the next time a sample is read.
    if (_component >= widget.track.componentCount) {
      _component = 0;
    }
  }

  KeyTable get _table => KeyTable.fromAnimationTrack(widget.track);

  double get _handleLength => 10.0 / widget.pixelsPerSecond;

  ({double min, double max}) _range(KeyTable table) {
    final raw = valueRange(table, _component);
    if (raw.max > raw.min) return raw;
    // A flat curve — every key shares one value — is padded by a whole unit
    // either side so it draws as a visible line rather than a single point
    // with nowhere for a drag to go.
    return (min: raw.min - 1.0, max: raw.max + 1.0);
  }

  double _valueToY(double value, double min, double max, double height) {
    final margin = height * kCurveEditorVerticalMargin;
    final usable = height - margin * 2;
    final t = (value - min) / (max - min);
    return margin + (1.0 - t) * usable;
  }

  double _yToValue(double y, double min, double max, double height) {
    final margin = height * kCurveEditorVerticalMargin;
    final usable = height - margin * 2;
    final t = usable <= 0.0 ? 0.0 : 1.0 - (y - margin) / usable;
    return min + t * (max - min);
  }

  void _onPanStart(Offset local) {
    final table = _table;
    final range = _range(table);
    final height = _canvasSize.height;
    final cubic = table.interpolation == AnimationInterpolation.cubicSpline;

    for (var i = 0; i < table.keyCount; i++) {
      final key = table.keys[i];
      if (cubic) {
        final handles = tangentHandles(
          table,
          i,
          _component,
          handleLength: _handleLength,
        );
        final inScreen = Offset(
          timeToX(handles.inHandle.x, widget.pixelsPerSecond),
          _valueToY(handles.inHandle.y, range.min, range.max, height),
        );
        final outScreen = Offset(
          timeToX(handles.outHandle.x, widget.pixelsPerSecond),
          _valueToY(handles.outHandle.y, range.min, range.max, height),
        );
        if ((local - inScreen).distance <= kKeyHitRadius) {
          widget.onSelectKey?.call(i);
          setState(
            () => _drag = _Drag(
              keyIndex: i,
              target: _DragTarget.inTangent,
              y: local.dy,
            ),
          );
          return;
        }
        if ((local - outScreen).distance <= kKeyHitRadius) {
          widget.onSelectKey?.call(i);
          setState(
            () => _drag = _Drag(
              keyIndex: i,
              target: _DragTarget.outTangent,
              y: local.dy,
            ),
          );
          return;
        }
      }
      final keyScreen = Offset(
        timeToX(key.time, widget.pixelsPerSecond),
        _valueToY(key.values[_component], range.min, range.max, height),
      );
      if ((local - keyScreen).distance <= kKeyHitRadius) {
        widget.onSelectKey?.call(i);
        setState(
          () => _drag = _Drag(
            keyIndex: i,
            target: _DragTarget.value,
            y: local.dy,
          ),
        );
        return;
      }
    }
  }

  void _onPanUpdate(Offset local) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = drag.withY(local.dy));
  }

  void _onPanEnd() {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);

    final table = _table;
    if (drag.keyIndex < 0 || drag.keyIndex >= table.keyCount) return;
    final range = _range(table);
    final key = table.keys[drag.keyIndex];
    final newValue = _yToValue(
      drag.y,
      range.min,
      range.max,
      _canvasSize.height,
    );

    switch (drag.target) {
      case _DragTarget.value:
        final values = List<double>.of(key.values)..[_component] = newValue;
        widget.onSetKey?.call(
          SetKey(
            clipIndex: widget.clipIndex,
            trackIndex: widget.trackIndex,
            time: key.time,
            values: values,
            inTangent: key.inTangent,
            outTangent: key.outTangent,
          ),
        );
      case _DragTarget.inTangent:
        final slope = (key.values[_component] - newValue) / _handleLength;
        final inTangent = List<double>.of(
          key.inTangent ?? List<double>.filled(table.componentCount, 0.0),
        )..[_component] = slope;
        widget.onSetTangent?.call(
          SetTangent(
            clipIndex: widget.clipIndex,
            trackIndex: widget.trackIndex,
            index: drag.keyIndex,
            inTangent: inTangent,
          ),
        );
      case _DragTarget.outTangent:
        final slope = (newValue - key.values[_component]) / _handleLength;
        final outTangent = List<double>.of(
          key.outTangent ?? List<double>.filled(table.componentCount, 0.0),
        )..[_component] = slope;
        widget.onSetTangent?.call(
          SetTangent(
            clipIndex: widget.clipIndex,
            trackIndex: widget.trackIndex,
            index: drag.keyIndex,
            outTangent: outTangent,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = _table;
    final theme = Theme.of(context);
    final componentCount = widget.track.componentCount;
    final int? selectedKey = widget.selectedKeyIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              for (var c = 0; c < componentCount; c++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_componentLabel(widget.track.path, c)),
                    selected: c == _component,
                    onSelected: (_) => setState(() => _component = c),
                  ),
                ),
              if (widget.track.path == AnimationPath.rotation &&
                  selectedKey != null &&
                  selectedKey < table.keyCount)
                Expanded(
                  child: Text(
                    _eulerReadout(table.keys[selectedKey].values),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              _canvasSize = constraints.biggest;
              return RepaintBoundary(
                key: kCurveEditorCanvasKey,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (DragStartDetails d) =>
                      _onPanStart(d.localPosition),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _onPanUpdate(d.localPosition),
                  onPanEnd: (_) => _onPanEnd(),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _CurveEditorPainter(
                      table: table,
                      component: _component,
                      pixelsPerSecond: widget.pixelsPerSecond,
                      handleLength: _handleLength,
                      selectedKey: selectedKey,
                      drag: _drag,
                      range: _range(table),
                      currentTime: widget.currentTime,
                      lineColor: kModelerScheme.primary,
                      keyColor: ModelerColors.dark.wire,
                      selectedColor: kModelerScheme.tertiary,
                      handleColor: ModelerColors.dark.gridMajor,
                      playheadColor: ModelerColors.dark.selected,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _eulerReadout(List<double> values) {
    final q = Quaternion(values[0], values[1], values[2], values[3]);
    final euler = eulerOf(q);
    String deg(double radians) => (radians * 180 / math.pi).toStringAsFixed(1);
    return 'pitch ${deg(euler.x)}° · yaw ${deg(euler.y)}° · roll ${deg(euler.z)}°';
  }
}

/// The curve line, its keys and — while cubic — their tangent handles.
class _CurveEditorPainter extends CustomPainter {
  const _CurveEditorPainter({
    required this.table,
    required this.component,
    required this.pixelsPerSecond,
    required this.handleLength,
    required this.selectedKey,
    required this.drag,
    required this.range,
    required this.currentTime,
    required this.lineColor,
    required this.keyColor,
    required this.selectedColor,
    required this.handleColor,
    required this.playheadColor,
  });

  final KeyTable table;
  final int component;
  final double pixelsPerSecond;
  final double handleLength;
  final int? selectedKey;
  final _Drag? drag;
  final ({double min, double max}) range;
  final double currentTime;
  final Color lineColor;
  final Color keyColor;
  final Color selectedColor;
  final Color handleColor;
  final Color playheadColor;

  double _valueToY(double value, double height) {
    final margin = height * kCurveEditorVerticalMargin;
    final usable = height - margin * 2;
    final t = (value - range.min) / (range.max - range.min);
    return margin + (1.0 - t) * usable;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (table.keyCount == 0) return;
    final cubic = table.interpolation == AnimationInterpolation.cubicSpline;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final samples = curveSamples(table, component, sampleCount: 120);
    if (samples.length > 1) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final (t, v) = samples[i];
        final point = Offset(
          timeToX(t, pixelsPerSecond),
          _valueToY(v, size.height),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    final handlePaint = Paint()
      ..color = handleColor
      ..strokeWidth = 1;
    final keyPaint = Paint()..color = keyColor;
    final selectedPaint = Paint()..color = selectedColor;

    for (var i = 0; i < table.keyCount; i++) {
      final key = table.keys[i];
      var value = key.values[component];
      if (drag case final _Drag d
          when d.keyIndex == i && d.target == _DragTarget.value) {
        value = _yToValueForDrag(d.y, size.height);
      }
      final keyPoint = Offset(
        timeToX(key.time, pixelsPerSecond),
        _valueToY(value, size.height),
      );

      if (cubic) {
        final handles = tangentHandles(
          table,
          i,
          component,
          handleLength: handleLength,
        );
        var inHandle = Offset(
          timeToX(handles.inHandle.x, pixelsPerSecond),
          _valueToY(handles.inHandle.y, size.height),
        );
        var outHandle = Offset(
          timeToX(handles.outHandle.x, pixelsPerSecond),
          _valueToY(handles.outHandle.y, size.height),
        );
        if (drag case final _Drag d when d.keyIndex == i) {
          if (d.target == _DragTarget.inTangent) {
            inHandle = Offset(inHandle.dx, d.y);
          } else if (d.target == _DragTarget.outTangent) {
            outHandle = Offset(outHandle.dx, d.y);
          }
        }
        canvas.drawLine(inHandle, keyPoint, handlePaint);
        canvas.drawLine(keyPoint, outHandle, handlePaint);
        canvas.drawCircle(inHandle, 3, handlePaint..style = PaintingStyle.fill);
        canvas.drawCircle(
          outHandle,
          3,
          handlePaint..style = PaintingStyle.fill,
        );
      }

      canvas.drawCircle(
        keyPoint,
        4,
        i == selectedKey ? selectedPaint : keyPaint,
      );
    }

    final playheadPaint = Paint()
      ..color = playheadColor
      ..strokeWidth = 2;
    final playheadX = timeToX(currentTime, pixelsPerSecond);
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  double _yToValueForDrag(double y, double height) {
    final margin = height * kCurveEditorVerticalMargin;
    final usable = height - margin * 2;
    final t = usable <= 0.0 ? 0.0 : 1.0 - (y - margin) / usable;
    return range.min + t * (range.max - range.min);
  }

  @override
  bool shouldRepaint(covariant _CurveEditorPainter oldDelegate) =>
      !identical(oldDelegate.table, table) ||
      oldDelegate.component != component ||
      oldDelegate.selectedKey != selectedKey ||
      oldDelegate.drag != drag ||
      oldDelegate.range != range ||
      oldDelegate.currentTime != currentTime;
}
