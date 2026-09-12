/// `ui-13`'s own `CustomPainter`: draws a [ProfileCurve] the way the design
/// hand-over's screen 09 describes it — a dashed axis, a filled profile
/// path, ⌀12 points, hollow control handles — and turns a drag into an edit
/// through whichever of the three chips (`Point` / `Curve` / `Axis`) is
/// armed.
///
/// **One coordinate space, and it is the profile's own.** A local pointer
/// offset maps straight onto a [Vector2] with a fixed axis margin and a
/// single flip — no separate zoom or pan, because the acceptance's own
/// numbers (⌀12 hit, 40 snap) are stated in the same units
/// `profile_editing.dart` already tests them in, and a scale factor between
/// the canvas and the model would make a `radius: 6` mean something
/// different on screen than it does in that file's own tests.
///
/// **Curve mode only ever authors a [QuadraticSegment], never a
/// [CubicSegment].** `profile_editing.dart`'s own flattening already
/// handles both, but a profile editor meant for a glass or a chair leg
/// needs one handle per bend, not two — the same scope [LatheShape]'s own
/// doc comment describes rounded primitives as being built from.  A cubic
/// segment already on a curve (there is no way to author one from this
/// widget, but nothing stops one arriving through a project file) still
/// draws and flattens correctly; it is simply never what a drag produces.
library;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../profile_editing.dart';

/// Which of the design's own three chips is armed, and so what a drag does.
enum ProfileEditTool {
  /// Drag an existing point, or start a drag on empty space to add one.
  point('Point'),

  /// Drag a straight segment to bend it, or drag its handle once it is
  /// already bent.
  curve('Curve'),

  /// Drag an existing point, snapping it onto the axis of revolution the
  /// same way `profile_editing.dart`'s own [snappedToAxis] does.
  axis('Axis');

  const ProfileEditTool(this.label);

  final String label;
}

/// The magenta the design hand-over gives the axis of revolution — screen
/// 09's own `#FF458E`, used nowhere else in [ModelerColors] because nothing
/// else in the shell draws an axis of revolution.
const Color _kAxisColor = Color(0xFFFF458E);

/// The teal the profile's own fill and outline are specified in — the same
/// `#004F58` the viewport's selection wash and [kModelerScheme]'s own
/// `primaryContainer` already use.
const Color _kProfileFill = Color(0x47004F58); // 0x47 ~= 28% alpha.
const Color _kProfileStroke = Color(0xFF5FD4E4); // kModelerScheme.primary.

/// Local-pixel radius an on-curve point is drawn at — the design's own
/// "точки ⌀12", so a radius of 6.
const double _kPointRadius = 6.0;

/// [local], a pointer offset inside a canvas of [size] with the axis drawn
/// [axisMargin] in from the left and [axisMargin] up from the bottom, as
/// the profile's own `(radius, height)` point.
Vector2 profileEditorToModel(Offset local, Size size, double axisMargin) =>
    Vector2(local.dx - axisMargin, size.height - axisMargin - local.dy);

/// The inverse of [profileEditorToModel] — where [model] draws on a canvas
/// of [size].
Offset profileEditorToLocal(Vector2 model, Size size, double axisMargin) =>
    Offset(model.x + axisMargin, size.height - axisMargin - model.y);

/// Draws [curve] the way screen 09 specifies it, plus a background grid at
/// [gridSpacing] — visual only, nothing snaps to it; the profile's own snap
/// is [snappedToAxis]'s "привязка 40", not a grid cell.
class ProfileEditorPainter extends CustomPainter {
  const ProfileEditorPainter({
    required this.curve,
    this.axisMargin = 24.0,
    this.gridSpacing = 40.0,
  });

  final ProfileCurve curve;
  final double axisMargin;
  final double gridSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintAxis(canvas, size);
    _paintProfile(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF232A2C)
      ..strokeWidth = 1;
    for (var x = axisMargin; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = size.height - axisMargin; y > 0; y -= gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintAxis(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kAxisColor
      ..strokeWidth = 2;
    const dash = 6.0;
    const gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(axisMargin, y),
        Offset(axisMargin, (y + dash).clamp(0, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  void _paintProfile(Canvas canvas, Size size) {
    if (curve.points.isEmpty) return;

    final polyline = curve.toPolyline();
    if (polyline.length >= 2) {
      final locals = <Offset>[
        for (final point in polyline) profileEditorToLocal(point, size, axisMargin),
      ];

      // The fill closes back to the axis at the first and last point's own
      // height, not at the corner of the canvas — a profile that starts or
      // ends off the axis (a bowl with no foot, a tube open at both ends)
      // would otherwise fill a triangle of nothing it never drew.
      final fill = Path()..moveTo(axisMargin, locals.first.dy);
      for (final local in locals) {
        fill.lineTo(local.dx, local.dy);
      }
      fill
        ..lineTo(axisMargin, locals.last.dy)
        ..close();
      canvas.drawPath(fill, Paint()..color = _kProfileFill);

      final stroke = Path()..moveTo(locals.first.dx, locals.first.dy);
      for (final local in locals.skip(1)) {
        stroke.lineTo(local.dx, local.dy);
      }
      canvas.drawPath(
        stroke,
        Paint()
          ..color = _kProfileStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    final fillPaint = Paint()..color = _kProfileStroke;
    final hollowPaint = Paint()
      ..color = _kProfileStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in curve.points) {
      final local = profileEditorToLocal(point.position, size, axisMargin);
      canvas.drawCircle(local, _kPointRadius, fillPaint);
    }
    for (final segment in curve.segments) {
      switch (segment) {
        case LineSegment():
          break;
        case QuadraticSegment(:final control):
          canvas.drawCircle(
            profileEditorToLocal(control, size, axisMargin),
            _kPointRadius,
            hollowPaint,
          );
        case CubicSegment(:final control1, :final control2):
          canvas.drawCircle(
            profileEditorToLocal(control1, size, axisMargin),
            _kPointRadius,
            hollowPaint,
          );
          canvas.drawCircle(
            profileEditorToLocal(control2, size, axisMargin),
            _kPointRadius,
            hollowPaint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ProfileEditorPainter oldDelegate) =>
      !identical(oldDelegate.curve, curve) ||
      oldDelegate.axisMargin != axisMargin ||
      oldDelegate.gridSpacing != gridSpacing;
}

/// What is being dragged, from the pointer-down that started it.
sealed class _DragTarget {
  const _DragTarget();
}

final class _PointDrag extends _DragTarget {
  const _PointDrag(this.index);
  final int index;
}

final class _SegmentHandleDrag extends _DragTarget {
  const _SegmentHandleDrag(this.segment);
  final int segment;
}

/// The interactive half of `ui-13`'s screen 09: [ProfileEditorPainter] plus
/// the gesture handling that turns a drag into a call to [onChanged].
///
/// A single [onPanStart]/[onPanUpdate] pair rather than `onTap` alongside
/// them: Flutter's gesture arena treats a tap and a pan on the same
/// [GestureDetector] as competing recognizers, and resolving that (a
/// `Timer`, a movement threshold) is exactly what a pan already does for
/// free. `Point` mode reads "nothing under the finger" at `onPanStart` as
/// "add a point here" and drags that new point from the same gesture, so a
/// stationary tap and a drag-to-place both go through one path.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.curve,
    required this.tool,
    required this.onChanged,
    this.axisMargin = 24.0,
  });

  final ProfileCurve curve;
  final ProfileEditTool tool;
  final ValueChanged<ProfileCurve> onChanged;
  final double axisMargin;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  _DragTarget? _drag;

  /// What is actually painted and hit-tested against, kept in sync with
  /// [ProfileEditor.curve] by [didUpdateWidget] whenever nothing is being
  /// dragged.
  ///
  /// **Not [ProfileEditor.curve] directly, because a drag outruns its own
  /// parent's rebuild.** `ProfileEditor` is controlled — every edit goes out
  /// through [ProfileEditor.onChanged] and comes back in as a new `curve`
  /// once the caller's own `setState` rebuilds this widget — and nothing
  /// requires that round trip to finish before the next pointer-move event
  /// arrives. Reading `widget.curve` inside a still-in-flight drag's own
  /// update would then be reading the curve as it stood *before* the drag's
  /// own first move, index a point that move had already added and throw.
  /// [_working] is this widget's own running answer instead, applied
  /// immediately and reported outward, so a second move in the same drag
  /// never has to wait on anyone else's frame.
  late ProfileCurve _working = widget.curve;

  @override
  void didUpdateWidget(covariant ProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_drag == null) _working = widget.curve;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (DragStartDetails details) =>
              _onPanStart(details.localPosition, size),
          onPanUpdate: (DragUpdateDetails details) =>
              _onPanUpdate(details.localPosition, size),
          onPanEnd: (_) => _drag = null,
          child: CustomPaint(
            size: size,
            painter: ProfileEditorPainter(
              curve: _working,
              axisMargin: widget.axisMargin,
            ),
          ),
        );
      },
    );
  }

  void _onPanStart(Offset local, Size size) {
    final at = profileEditorToModel(local, size, widget.axisMargin);
    ProfileCurve? next;
    switch (widget.tool) {
      case ProfileEditTool.point:
        final hit = _working.nearestPointWithin(at);
        if (hit != null) {
          _drag = _PointDrag(hit);
        } else {
          _drag = _PointDrag(_working.points.length);
          next = _working.withPointAdded(at);
        }
      case ProfileEditTool.axis:
        final hit = _working.nearestPointWithin(at);
        if (hit != null) _drag = _PointDrag(hit);
      case ProfileEditTool.curve:
        final handle = _nearestControlHandle(at);
        if (handle != null) {
          _drag = _SegmentHandleDrag(handle);
        } else {
          final segment = _working.nearestSegmentWithin(at);
          if (segment != null) {
            _drag = _SegmentHandleDrag(segment);
            next = _working.withSegment(segment, QuadraticSegment(at));
          }
        }
    }
    if (next != null) _apply(next);
  }

  void _onPanUpdate(Offset local, Size size) {
    final drag = _drag;
    if (drag == null) return;
    final at = profileEditorToModel(local, size, widget.axisMargin);
    final next = switch (drag) {
      _PointDrag(:final index) => _working.withPointMoved(
        index,
        widget.tool == ProfileEditTool.axis ? snappedToAxis(at) : at,
      ),
      _SegmentHandleDrag(:final segment) => _working.withSegment(
        segment,
        QuadraticSegment(at),
      ),
    };
    _apply(next);
  }

  void _apply(ProfileCurve next) {
    setState(() => _working = next);
    widget.onChanged(next);
  }

  /// The index of whichever curved segment's own control handle sits within
  /// [_kPointRadius] of [at] — checked before [ProfileCurve.nearestSegmentWithin]
  /// so that re-dragging a handle moves the handle rather than re-bending the
  /// chord under it.
  int? _nearestControlHandle(Vector2 at) {
    final segments = _working.segments;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment is QuadraticSegment &&
          (segment.control - at).length <= _kPointRadius) {
        return i;
      }
    }
    return null;
  }
}
