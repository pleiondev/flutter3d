import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// A wheel and two pedals, drawn over a game nobody can reach a keyboard for.
///
/// **`TouchControls` does not fit and should not be made to.** It is a thumb
/// stick and a row of buttons, which is a platformer's hands and a shooter's; a
/// car has no stick, its steering is one axis rather than two, and its two most
/// important controls are held for whole corners at a time rather than tapped.
/// Bending the shared widget into this shape would have made it worse at the
/// two games that already use it.
///
/// It lives in this application rather than in `flutter3d_game_racing` for the rule
/// the repository keeps everywhere else: there is one racing game. The day
/// there are two, this moves.
class TouchDrive extends StatelessWidget {
  const TouchDrive({
    super.key,
    required this.state,
    required this.steerLeft,
    required this.steerRight,
    required this.throttle,
    required this.brake,
    this.handbrake,
  });

  final InputState state;

  final GameAction steerLeft;
  final GameAction steerRight;
  final GameAction throttle;
  final GameAction brake;

  /// Optional, because a game may not have one and a control for nothing is
  /// worse than a gap.
  final GameAction? handbrake;

  @override
  Widget build(BuildContext context) {
    final hand = handbrake;
    return SafeArea(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 24,
            bottom: 24,
            child: SteeringBand(
              state: state,
              left: steerLeft,
              right: steerRight,
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (hand != null) ...<Widget>[
                  Pedal(state: state, action: hand, label: 'handbrake'),
                  const SizedBox(width: 14),
                ],
                Pedal(state: state, action: brake, label: 'brake'),
                const SizedBox(width: 14),
                // Nearest the thumb, because it is the one that is held for the
                // whole lap.
                Pedal(state: state, action: throttle, label: 'throttle'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A strip a thumb slides along to steer.
///
/// **Analogue, and that is the point of it.** A car steered by two buttons is a
/// car that is either straight or at full lock, which is undriveable at speed —
/// the same complaint that made this game read `InputState.value` instead of
/// `held`. How far along the strip the thumb is *is* how far the wheel is
/// turned.
///
/// Not labelled for a screen reader: a wheel under a reader is a gesture nobody
/// can perform. The pedals are labelled, because they are buttons.
class SteeringBand extends StatefulWidget {
  const SteeringBand({
    super.key,
    required this.state,
    required this.left,
    required this.right,
    this.width = 220.0,
    this.height = 72.0,
  });

  final InputState state;
  final GameAction left;
  final GameAction right;
  final double width;
  final double height;

  @override
  State<SteeringBand> createState() => _SteeringBandState();
}

class _SteeringBandState extends State<SteeringBand> {
  /// Which finger owns the wheel. One control, one pointer — a player braking
  /// and steering has two fingers down, and a band that took the newest would
  /// snap to full lock the moment they touched the brake.
  int? _pointer;

  /// Where the wheel is, from −1 (full left) to 1 (full right).
  double _at = 0.0;

  void _steer(Offset local) {
    final half = widget.width / 2;
    final to = ((local.dx - half) / half).clamp(-1.0, 1.0);
    setState(() => _at = to);

    // **Both sides are set, including the one at nought, and the difference is
    // not decoration.** A magnitude present is authoritative and a magnitude
    // absent falls back to whatever is held — see [InputState.value] — so
    // withdrawing the idle side would let a key held down on a machine that has
    // both a keyboard and a screen steer against the thumb that is on the
    // wheel. The control being moved is the one the player means, which is the
    // same rule the pad's triggers follow.
    widget.state
      ..setActionValue(widget.left, to < 0 ? -to : 0.0)
      ..setActionValue(widget.right, to > 0 ? to : 0.0);
  }

  void _release() {
    _pointer = null;
    setState(() => _at = 0.0);
    // Withdrawn rather than set to nought, which is the difference that lets a
    // keyboard take the wheel back afterwards — see [InputState.clearActionValue].
    widget.state
      ..clearActionValue(widget.left)
      ..clearActionValue(widget.right);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent event) {
          if (_pointer != null) return;
          _pointer = event.pointer;
          _steer(event.localPosition);
        },
        onPointerMove: (PointerMoveEvent event) {
          if (event.pointer != _pointer) return;
          _steer(event.localPosition);
        },
        onPointerUp: (PointerUpEvent event) {
          if (event.pointer == _pointer) _release();
        },
        // A pointer the system took away — a notification pulled down mid-
        // corner. Treated as a release, or the player comes back at full lock.
        onPointerCancel: (PointerCancelEvent event) {
          if (event.pointer == _pointer) _release();
        },
        child: CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _BandPainter(at: _at),
        ),
      );
}

class _BandPainter extends CustomPainter {
  const _BandPainter({required this.at});

  /// Where the thumb is, −1 to 1.
  final double at;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final track = RRect.fromLTRBR(
      0,
      middle - 14,
      size.width,
      middle + 14,
      const Radius.circular(14),
    );
    canvas
      ..drawRRect(track, Paint()..color = const Color(0x22FFFFFF))
      ..drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x55FFFFFF),
      )
      // The straight-ahead mark, so a thumb can find centre without looking.
      ..drawLine(
        Offset(size.width / 2, middle - 18),
        Offset(size.width / 2, middle + 18),
        Paint()..color = const Color(0x66FFFFFF),
      )
      ..drawCircle(
        Offset(size.width / 2 * (1 + at), middle),
        20,
        Paint()..color = const Color(0x99FFFFFF),
      );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.at != at;
}

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
