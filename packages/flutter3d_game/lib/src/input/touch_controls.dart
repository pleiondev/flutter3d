import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'game_action.dart';
import 'input_state.dart';

/// A thumb stick and some buttons, drawn over a game that has no keyboard.
///
/// The third translator, beside `DesktopInput` and `PadInput`, and the one the
/// device-independent input was written for in the first place —
/// [InputState.setStickAxis] has said "for a stick or a d-pad" since before
/// either existed, and its class doc has always promised that the touch build
/// and the desktop build run the same game code. This is that promise being
/// collected.
///
/// ## Widgets, and why that is not a layering mistake
///
/// Everything else in this package is free of Flutter's widget tree. This is
/// not, because a touch control **is** its own picture: there is no operating
/// system offering one, no plugin to ask, and nothing to translate from. A
/// package that held only the arithmetic would leave every game drawing its own
/// stick, and the first one to get the dead centre wrong would be the only one
/// to find out.
///
/// What is *not* here is what the buttons say, which is the game's: a platformer
/// wants jump and dash, a shooter wants fire and a slot. [TouchControls] takes
/// them as a list.
///
/// ## Labelled, even though a blind player is not playing this
///
/// Each button says what it does to a screen reader. That is not the
/// contradiction it looks like: a player with low vision, or one whose reader is
/// on for something else entirely, meets these controls and gets "jump" rather
/// than an unnamed circle. The stick is not labelled, because a thumb stick
/// under a reader is a gesture nobody can perform.
///
/// ## One finger per control
///
/// Every control tracks the pointer id that claimed it, which is the whole of
/// multi-touch and is not optional: a player walking and jumping is holding two
/// fingers down at once, and a control that took the most recent pointer would
/// snap the stick to the jump button.
class TouchControls extends StatelessWidget {
  const TouchControls({
    super.key,
    required this.state,
    required this.buttons,
    this.stickRadius = 64.0,
    this.buttonRadius = 34.0,
    this.margin = 28.0,
  });

  final InputState state;

  /// What the buttons on the right do, in the order they are drawn: the last is
  /// nearest the thumb.
  ///
  /// A list rather than a fixed set, because "jump, dash, drop through" is a
  /// platformer's answer and "fire" is a shooter's.
  final List<TouchAction> buttons;

  final double stickRadius;
  final double buttonRadius;

  /// How far the controls sit from the edges. Generous, because the edges of a
  /// phone are where the system's own gestures live.
  final double margin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: margin,
            bottom: margin,
            child: TouchStick(state: state, radius: stickRadius),
          ),
          Positioned(
            right: margin,
            bottom: margin,
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.end,
              children: <Widget>[
                for (final button in buttons)
                  TouchButton(
                    state: state,
                    action: button.action,
                    label: button.label,
                    radius: buttonRadius,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled button on a touch screen.
final class TouchAction {
  const TouchAction(this.action, this.label);

  final GameAction action;

  /// What is written on it. Short — a word does not fit on a thumb.
  final String label;
}

/// A stick under a thumb, reporting into [InputState.setStickAxis].
class TouchStick extends StatefulWidget {
  const TouchStick({super.key, required this.state, this.radius = 64.0});

  final InputState state;
  final double radius;

  @override
  State<TouchStick> createState() => _TouchStickState();
}

class _TouchStickState extends State<TouchStick> {
  /// Which finger owns the stick, if any. See the class doc on multi-touch.
  int? _pointer;
  Offset _knob = Offset.zero;

  void _move(Offset local) {
    final centre = Offset(widget.radius, widget.radius);
    var offset = local - centre;
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
    widget.state.setStickAxis(
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
    widget.state.setStickAxis(0.0, 0.0);
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
        painter: _StickPainter(knob: _knob, radius: widget.radius),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({required this.knob, required this.radius});

  final Offset knob;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas
      ..drawCircle(
        centre,
        radius,
        Paint()..color = const Color(0x22FFFFFF),
      )
      ..drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x55FFFFFF),
      )
      ..drawCircle(
        centre + knob,
        radius * 0.42,
        Paint()..color = const Color(0x88FFFFFF),
      );
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob;
}

/// A round button that holds an action down while a finger is on it.
class TouchButton extends StatefulWidget {
  const TouchButton({
    super.key,
    required this.state,
    required this.action,
    required this.label,
    this.radius = 34.0,
  });

  final InputState state;
  final GameAction action;
  final String label;
  final double radius;

  @override
  State<TouchButton> createState() => _TouchButtonState();
}

class _TouchButtonState extends State<TouchButton> {
  int? _pointer;

  void _release() {
    _pointer = null;
    setState(() {});
    widget.state.release(widget.action);
  }

  @override
  Widget build(BuildContext context) {
    final down = _pointer != null;
    return Semantics(
      button: true,
      label: widget.label,
      child: _listener(down),
    );
  }

  Widget _listener(bool down) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        setState(() {});
        widget.state.press(widget.action);
      },
      onPointerUp: (PointerUpEvent event) {
        if (event.pointer == _pointer) _release();
      },
      onPointerCancel: (PointerCancelEvent event) {
        if (event.pointer == _pointer) _release();
      },
      child: CustomPaint(
        size: Size.square(widget.radius * 2),
        painter: _ButtonPainter(down: down, radius: widget.radius),
        child: SizedBox(
          width: widget.radius * 2,
          height: widget.radius * 2,
          child: Center(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: const Color(0xCCFFFFFF),
                fontSize: math.min(15.0, widget.radius * 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  _ButtonPainter({required this.down, required this.radius});

  final bool down;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = down ? const Color(0x99FFFFFF) : const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_ButtonPainter old) => old.down != down;
}
