import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../theme/game_ui_theme.dart';

/// A stick under a thumb, reporting into a [DualAxisAction] — walking,
/// [DualAxisAction.move], unless told otherwise.
class TouchStick extends StatefulWidget {
  const TouchStick({
    super.key,
    required this.state,
    this.radius = 64.0,
    this.action = DualAxisAction.move,
  });

  final InputState state;

  /// The radius, in logical pixels.
  final double radius;

  /// What the stick asks for. [DualAxisAction.move] is the stick part of
  /// [InputState.moveAxis], as it always was; any other dual axis — a
  /// strategy map's pan, a turret's aim — is set while a thumb is on it and
  /// let go when it lifts.
  final DualAxisAction action;

  @override
  State<TouchStick> createState() => _TouchStickState();
}

class _TouchStickState extends State<TouchStick> {
  /// Which finger owns the stick, if any. See the class doc on multi-touch.
  int? _pointer;
  Offset _knob = Offset.zero;

  void _move(Offset local) {
    final center = Offset(widget.radius, widget.radius);
    var offset = local - center;
    final distance = offset.distance;
    if (distance > widget.radius) {
      // **This clamp is about the picture, not the value.** It keeps the knob
      // inside the ring it is drawn in; the axis itself needs no bounding here
      // because `InputState._recomputeMoveAxis` already clamps the sum to one,
      // which is what stops a diagonal being worth 1.41 of a straight push.
      //
      // Worth saying because the comment here used to claim the second job and
      // a mutation proved it could not have it: deleting this line changes
      // nothing a test of the movement axis can see.
      offset = offset * (widget.radius / distance);
    }
    setState(() => _knob = offset);
    widget.state.setDualAxis(
      widget.action,
      offset.dx / widget.radius,
      // Screen coordinates grow downwards and forward is positive, so the flip
      // happens here, in the open, exactly as the pad's translator does it.
      -offset.dy / widget.radius,
    );
  }

  void _release() {
    _pointer = null;
    setState(() => _knob = Offset.zero);
    // Dry, not decaying. A stick that eased back to centre would keep the
    // player walking after they let go, which is the first thing anybody
    // notices and the last thing they forgive.
    widget.state.clearDualAxis(widget.action);
  }

  @override
  void dispose() {
    // Unmounted mid-push — settings opened over the stick, a level swapped
    // out under it — is a normal path, and no pointer-up ever reaches a widget
    // that is gone. The [InputState] is shared and outlives this stick, so the
    // axis has to be zeroed here or the player keeps walking for good.
    if (_pointer != null) widget.state.clearDualAxis(widget.action);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        _move(event.localPosition);
      },
      onPointerMove: (PointerMoveEvent event) {
        if (event.pointer != _pointer) return;
        _move(event.localPosition);
      },
      onPointerUp: (PointerUpEvent event) {
        if (event.pointer == _pointer) _release();
      },
      // A cancel is a pointer the system took away — a notification shade pulled
      // down mid-run. Treated exactly as a release, because the alternative is a
      // player who comes back walking into a wall.
      onPointerCancel: (PointerCancelEvent event) {
        if (event.pointer == _pointer) _release();
      },
      child: CustomPaint(
        size: Size.square(size),
        painter: _StickPainter(
          knob: _knob,
          radius: widget.radius,
          theme: GameUiTheme.of(context),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({
    required this.knob,
    required this.radius,
    required this.theme,
  });

  final Offset knob;

  /// The radius, in logical pixels.
  final double radius;
  final GameUiTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas
      ..drawCircle(center, radius, Paint()..color = theme.touchTrack)
      ..drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = theme.touchOutline,
      )
      ..drawCircle(
        center + knob,
        radius * 0.42,
        Paint()..color = theme.touchKnob,
      );
  }

  @override
  bool shouldRepaint(_StickPainter old) =>
      old.knob != knob || old.theme != theme;
}
