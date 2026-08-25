import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'game_action.dart';
import 'input_state.dart';

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
