import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// A pedal held down with a thumb.
///
/// Pressed rather than measured: a phone has no travel to report, and inventing
/// a curve from how far up the pad a finger landed would be a number nobody
/// asked for. `InputState.value` reads a press as all of it, so the car gets
/// full throttle from a thumb and a trigger's real travel from a controller
/// without knowing which it has.
class Pedal extends StatefulWidget {
  const Pedal({
    super.key,
    required this.state,
    required this.action,
    required this.label,
    this.width = 84.0,
    this.height = 108.0,
  });

  final InputState state;
  final GameAction action;

  /// What it says to a screen reader. A player with low vision meets a pedal
  /// and gets "throttle" rather than an unnamed rectangle.
  final String label;

  final double width;
  final double height;

  @override
  State<Pedal> createState() => _PedalState();
}

class _PedalState extends State<Pedal> {
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
      child: Listener(
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
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: down ? const Color(0x66FFFFFF) : const Color(0x22FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x55FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
