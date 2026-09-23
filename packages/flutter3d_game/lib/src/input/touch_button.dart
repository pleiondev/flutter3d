import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';

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

  /// What the finger on this button pressed, and where.
  ///
  /// Remembered rather than read back off [widget] at the release: the
  /// buttons are laid out by position, so a game that changes its list while
  /// a thumb is down — out of the car, into a menu — hands this state a
  /// different action, and releasing *that* one leaves the pressed action
  /// held for good.
  (InputState, GameAction)? _pressed;

  void _release() {
    _pointer = null;
    setState(() {});
    _letGo();
  }

  void _letGo() {
    final pressed = _pressed;
    _pressed = null;
    if (pressed != null) pressed.$1.release(pressed.$2);
  }

  @override
  void dispose() {
    // Unmounted mid-hold — settings opened over the control, a level swapped
    // out under it — is a normal path, and no pointer-up ever reaches a widget
    // that is gone. The [InputState] is shared and outlives this button, so
    // the press has to be let go here or the action stays held for good.
    _letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final down = _pointer != null;
    return Semantics(button: true, label: widget.label, child: _listener(down));
  }

  Widget _listener(bool down) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        setState(() {});
        _pressed = (widget.state, widget.action);
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
