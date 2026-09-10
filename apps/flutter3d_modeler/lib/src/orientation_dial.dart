/// The dial in the corner, as a widget.
///
/// **All the arithmetic is in `ground_grid.dart` and none of it is here.**
/// Where the six buttons sit, which one a press landed on and where each of
/// them points the camera are three questions with answers that do not need a
/// screen, and `OrientationGizmo` holds them so a test can ask without pumping
/// a widget. What is left is a circle, six discs, three labels and a hit test
/// that forwards — which is what a painter should be.
library;

import 'package:flutter/material.dart';

import 'ground_grid.dart';

/// A ⌀60 dial that shows which way the model is turned and turns it when
/// pressed.
class OrientationDial extends StatelessWidget {
  const OrientationDial({
    super.key,
    required this.yaw,
    required this.pitch,
    required this.onPressed,
    this.gizmo = const OrientationGizmo(),
  });

  /// Where the camera is now. Passed in rather than read from a controller,
  /// because a widget that held the controller would rebuild the dial and the
  /// viewport for the same frame and only one of them needs to.
  final double yaw;
  final double pitch;

  /// What to look down. The caller animates; the dial does not know the camera
  /// exists.
  final void Function(ViewAxis axis) onPressed;

  final OrientationGizmo gizmo;

  /// The box the dial lives in: the circle plus a ball's worth of room at each
  /// end, which is what stops a button being clipped when it swings out.
  double get _side => (gizmo.radius + gizmo.handleRadius) * 2;

  @override
  Widget build(BuildContext context) {
    final buttons = gizmo.buttonsAt(yaw: yaw, pitch: pitch);
    return SizedBox(
      width: _side,
      height: _side,
      child: GestureDetector(
        // Opaque, so a press that lands inside the box but between the balls is
        // swallowed rather than falling through to the viewport behind — which
        // would orbit the camera on a press that was aimed at the dial. Stated
        // here rather than left to the default, which defers to the child: a
        // `CustomPaint` decides its own hit testing through its painter, and
        // this one has no opinion, so the guarantee would depend on a class
        // that is not making it.
        behavior: HitTestBehavior.opaque,
        onTapUp: (TapUpDetails details) {
          final axis = gizmo.hitTest(
            buttons,
            details.localPosition.dx - _side / 2,
            details.localPosition.dy - _side / 2,
          );
          if (axis != null) onPressed(axis);
        },
        child: CustomPaint(painter: _DialPainter(buttons, gizmo)),
      ),
    );
  }
}

/// The circle, the six balls and the labels on the three facing the viewer.
class _DialPainter extends CustomPainter {
  const _DialPainter(this.buttons, this.gizmo);

  final List<GizmoButton> buttons;
  final OrientationGizmo gizmo;

  /// One per axis, matching the floor's own X and Z lines so the dial and the
  /// grid name the same axis the same colour. Y is the up axis, which the floor
  /// has no line for.
  static const Map<ViewAxis, Color> _colours = <ViewAxis, Color>{
    ViewAxis.xPositive: Color(0xFFC2566E),
    ViewAxis.xNegative: Color(0xFF7A3A48),
    ViewAxis.yPositive: Color(0xFF7FB069),
    ViewAxis.yNegative: Color(0xFF4A6B3E),
    ViewAxis.zPositive: Color(0xFF5A87B8),
    ViewAxis.zNegative: Color(0xFF35526E),
  };

  static const Map<ViewAxis, String> _labels = <ViewAxis, String>{
    ViewAxis.xPositive: 'X',
    ViewAxis.yPositive: 'Y',
    ViewAxis.zPositive: 'Z',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      centre,
      gizmo.radius + gizmo.handleRadius - 1,
      Paint()..color = const Color(0x66000000),
    );

    // In the order the gizmo hands them over, which is furthest away first: the
    // near balls then cover the far ones without this needing a depth buffer
    // for six discs.
    for (final GizmoButton button in buttons) {
      final at = centre + Offset(button.dx, button.dy);
      final colour = _colours[button.axis]!;
      // Facing runs from one to minus one. A ball turned away is drawn hollow,
      // which is the whole reading of the dial: the three you can see the
      // labels on are the three in front.
      final front = button.facing > 0;
      canvas.drawCircle(
        at,
        6,
        Paint()
          ..color = front ? colour : const Color(0xFF181C1D)
          ..style = PaintingStyle.fill,
      );
      if (!front) {
        canvas.drawCircle(
          at,
          6,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      final label = _labels[button.axis];
      if (label == null || !front) continue;
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0E1112),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => true;
}
