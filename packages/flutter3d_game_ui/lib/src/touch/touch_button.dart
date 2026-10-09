import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../theme/game_ui_theme.dart';

/// A button that holds an action down while a finger is on it: round for a
/// thumb's cluster, or a pedal ([TouchButton.pedal]) for a control held
/// for whole corners at a time.
///
/// Pressed rather than measured: a phone has no travel to report, and
/// inventing a curve from how far up the pad a finger landed would be a
/// number nobody asked for. `InputState.value` reads a press as all of it, so
/// a game gets full throttle from a thumb and a trigger's real travel from a
/// controller without knowing which it has.
///
/// One pointer owns it: a second finger landing on a held button does not
/// take it over, and the press is let go when the finger that made it lifts,
/// is cancelled, or the widget is unmounted under it.
///
/// Labelled for a screen reader with [label], which is also what it says on
/// its face: a player with low vision meets "jump" or "throttle" rather than
/// an unnamed shape.
class TouchButton extends StatefulWidget {
  /// A round button of [radius].
  const TouchButton({
    super.key,
    required this.state,
    required this.action,
    required this.label,
    this.radius = 34.0,
  }) : pedal = null;

  /// A pedal: a rounded rectangle of [width] by [height], its label across
  /// it. Until 1.0.0-rc.1 this was a widget of its own, `Pedal`, doing the
  /// same job as the round button in another shape.
  const TouchButton.pedal({
    super.key,
    required this.state,
    required this.action,
    required this.label,
    double width = 84.0,
    double height = 108.0,
  }) : radius = 0.0,
       pedal = (width: width, height: height);

  final InputState state;
  final GameAction action;

  /// What it says, on its face and to a screen reader.
  final String label;

  /// The radius of a round button, in logical pixels; nought for a pedal.
  final double radius;

  /// A pedal's width and height, in logical pixels, or null for a round
  /// button.
  final ({double width, double height})? pedal;

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
      child: switch (widget.pedal) {
        final pedal? => _pedal(pedal, down),
        null => _round(down),
      },
    );
  }

  Widget _round(bool down) => CustomPaint(
    size: Size.square(widget.radius * 2),
    painter: _ButtonPainter(
      down: down,
      radius: widget.radius,
      theme: GameUiTheme.of(context),
    ),
    child: SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: Center(
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: GameUiTheme.of(context).touchGlyph,
            fontSize: math.min(15.0, widget.radius * 0.5),
          ),
        ),
      ),
    ),
  );

  Widget _pedal(({double width, double height}) pedal, bool down) {
    final theme = GameUiTheme.of(context);
    return Container(
      width: pedal.width,
      height: pedal.height,
      decoration: BoxDecoration(
        color: down ? theme.touchHeld : theme.touchTrack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.touchOutline),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.label,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: theme.touchGlyph,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  _ButtonPainter({
    required this.down,
    required this.radius,
    required this.theme,
  });

  final bool down;

  /// The radius, in logical pixels.
  final double radius;
  final GameUiTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = down ? theme.touchPressed : theme.touchFill,
    );
  }

  @override
  bool shouldRepaint(_ButtonPainter old) =>
      old.down != down || old.theme != theme;
}
