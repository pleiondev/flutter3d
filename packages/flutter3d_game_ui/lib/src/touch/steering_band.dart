import 'package:flutter/widgets.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../theme/game_ui_theme.dart';

/// A strip a thumb slides along to steer: one analogue axis, as two actions'
/// magnitudes.
///
/// **Analogue, and that is the point of it.** A car steered by two buttons is a
/// car that is either straight or at full lock, which is undriveable at speed —
/// the reason a game steering with this reads `InputState.value` instead of
/// `held`. How far along the strip the thumb is *is* how far the wheel is
/// turned: [left] gets the distance left of centre, [right] the distance right
/// of it, each from 0 to 1.
///
/// Not labelled for a screen reader: a wheel under a reader is a gesture nobody
/// can perform. The pedals are labelled, because they are buttons — see
/// `TouchButton.pedal`.
class SteeringBand extends StatefulWidget {
  const SteeringBand({
    super.key,
    required this.state,
    required this.left,
    required this.right,
    this.width = 220.0,
    this.height = 72.0,
    this.axis,
  });

  final InputState state;
  final GameAction left;
  final GameAction right;

  /// The steering as one [AxisAction], from −1 at full left to 1 at full
  /// right, written beside [left] and [right] — for a game that reads its
  /// wheel as an axis of its action set rather than as two magnitudes. Let
  /// go of with the thumb, as the magnitudes are.
  final AxisAction? axis;

  /// The band's width, in logical pixels.
  final double width;

  /// The band's height, in logical pixels.
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
    if (widget.axis case final AxisAction axis) widget.state.setAxis(axis, to);
  }

  void _letGo() {
    widget.state
      ..clearActionValue(widget.left)
      ..clearActionValue(widget.right);
    if (widget.axis case final AxisAction axis) widget.state.clearAxis(axis);
  }

  void _release() {
    _pointer = null;
    setState(() => _at = 0.0);
    // Withdrawn rather than set to nought, which is the difference that lets a
    // keyboard take the wheel back afterwards — see [InputState.clearActionValue].
    _letGo();
  }

  @override
  void dispose() {
    // Unmounted mid-corner — the settings panel hides the wheel, a circuit
    // change swaps the stack — is a normal path, and no pointer-up ever
    // reaches a widget that is gone. The [InputState] is shared and outlives
    // this band, so the magnitudes have to be withdrawn here or the car stays
    // at lock for good.
    if (_pointer != null) _letGo();
    super.dispose();
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
      painter: _BandPainter(at: _at, theme: GameUiTheme.of(context)),
    ),
  );
}

class _BandPainter extends CustomPainter {
  const _BandPainter({required this.at, required this.theme});

  final GameUiTheme theme;

  /// Where the thumb is, −1 to 1 of the band's half-width; unitless.
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
      ..drawRRect(track, Paint()..color = theme.touchTrack)
      ..drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = theme.touchOutline,
      )
      // The straight-ahead mark, so a thumb can find centre without looking.
      ..drawLine(
        Offset(size.width / 2, middle - 18),
        Offset(size.width / 2, middle + 18),
        Paint()..color = theme.touchHeld,
      )
      ..drawCircle(
        Offset(size.width / 2 * (1 + at), middle),
        20,
        Paint()..color = theme.touchPressed,
      );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.at != at || old.theme != theme;
}
