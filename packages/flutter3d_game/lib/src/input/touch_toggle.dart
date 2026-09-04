import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A round button that is **set** rather than held: tapped once it is on,
/// tapped again it is off.
///
/// **The control [TouchButton] cannot be.** A button that holds an action for
/// as long as a finger is on it is right for a trigger and wrong for anything
/// that lasts: on a handset one thumb is already on the stick, so pinning the
/// other to a button for the length of a climb leaves nothing to aim with. The
/// platformer's sprint was simply unreachable on a phone for that reason, and
/// the crypt's map is the same shape of control — something that is on, not
/// something that is being pressed.
///
/// **Stateless, and the caller owns [on].** What "on" means differs by control:
/// sprint is a held action inside an [InputState], and a map is a widget's own
/// bool. A button that kept its own answer would be able to disagree with
/// either — the classic checkbox that says off while the thing is on — so this
/// draws what it is told and reports the tap.
class TouchToggle extends StatelessWidget {
  const TouchToggle({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.radius = 30.0,
  });

  final String label;

  /// Whether the thing this switches is switched on, asked of whatever owns it.
  final bool on;

  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // `toggled` rather than `button`, so a reader says "sprint, on" instead of
    // naming a button that gives no clue which way it is set. Same reasoning as
    // [TouchButton]'s label: a player with low vision meets these controls, and
    // the one that latches is the one where the state is the whole message.
    return Semantics(
      toggled: on,
      label: label,
      // The `Text` below says the same word, and a reader that merged the two
      // would announce it twice.
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          size: Size.square(radius * 2),
          painter: _TogglePainter(on: on, radius: radius),
          child: SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: on ? const Color(0xFF101010) : const Color(0xCCFFFFFF),
                  fontSize: math.min(14.0, radius * 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  _TogglePainter({required this.on, required this.radius});

  final bool on;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    // Filled when it is on rather than merely brighter: a held button is
    // brighter for as long as the finger is there, and a control that stays on
    // after the finger has gone has to look like a different kind of thing or
    // nobody can tell whether their tap landed.
    canvas
      ..drawCircle(
        centre,
        radius,
        Paint()..color = on ? const Color(0xE6FFFFFF) : const Color(0x33FFFFFF),
      )
      ..drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x88FFFFFF),
      );
  }

  @override
  bool shouldRepaint(_TogglePainter old) => old.on != on;
}
