import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// A strip a thumb slides along to steer.
///
/// **Analogue, and that is the point of it.** A car steered by two buttons is a
/// car that is either straight or at full lock, which is undriveable at speed —
/// the same complaint that made this game read `InputState.value` instead of
/// `held`. How far along the strip the thumb is *is* how far the wheel is
/// turned.
///
/// Not labelled for a screen reader: a wheel under a reader is a gesture nobody
/// can perform. The pedals are labelled, because they are buttons — see
/// `pedal.dart`.
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
