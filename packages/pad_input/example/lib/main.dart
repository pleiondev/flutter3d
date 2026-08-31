/// Everything a gamepad is doing, on one screen.
///
///     flutter run                       # a browser, or macOS with no pad
///     flutter run -d <android device>   # where the native backend is
///
/// **This is the acceptance tool.** The package's own tests cover everything
/// above the platform channel, and the specification is explicit that what is
/// left can only be checked by a person with a controller in hand: whether half a
/// deflection is half a wish, whether letting go stops dead, whether a dead zone
/// wants to be bigger, whether going to the background lets go. None of that is a
/// screenshot, and all of it is visible here in seconds.
///
/// It lives in the package's example rather than in a game on purpose: the three
/// games in this repository have no Android runner, and the plan says the mobile
/// runtimes belong here — where the thing being tested is the device rather than
/// the game.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pad_input/pad_input.dart';

void main() => runApp(const GamepadExampleApp());

class GamepadExampleApp extends StatelessWidget {
  const GamepadExampleApp({super.key, this.home = const PadScreen()});

  /// The screen to show. An argument only so a test can hand in a screen wired
  /// to a fake pad; the application always uses the default.
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Gamepad',
        theme: ThemeData.dark(useMaterial3: true),
        home: home,
      );
}

class PadScreen extends StatefulWidget {
  const PadScreen({super.key, this.pad});

  /// The pad to watch. Injected by the test; the app uses the shared one.
  final Gamepad? pad;

  @override
  State<PadScreen> createState() => _PadScreenState();
}

class _PadScreenState extends State<PadScreen>
    with SingleTickerProviderStateMixin {
  late final Gamepad _pad = widget.pad ?? Gamepad.instance;

  /// Reused, as the package intends: this is read once a frame for as long as
  /// the application is open.
  final PadSnapshot _snapshot = PadSnapshot();

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _pad.read(_snapshot);
      // Every frame, because the point of this screen is latency: a value that
      // arrived a frame late is exactly the complaint a player would make.
      setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setDeadzone({double? stick, double? trigger}) => setState(() {
        _pad.deadzone = _pad.deadzone.copyWith(stick: stick, trigger: trigger);
      });

  @override
  Widget build(BuildContext context) {
    final connected = _snapshot.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gamepad'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28.0),
          child: _Banner(
            supported: _pad.isSupported,
            connected: connected,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _Stick(
                label: 'left stick',
                x: _snapshot.axis(PadAxis.leftStickX),
                y: _snapshot.axis(PadAxis.leftStickY),
              ),
              _Stick(
                label: 'right stick',
                x: _snapshot.axis(PadAxis.rightStickX),
                y: _snapshot.axis(PadAxis.rightStickY),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Bar(
            label: 'left trigger',
            value: _snapshot.axis(PadAxis.triggerLeft),
          ),
          _Bar(
            label: 'right trigger',
            value: _snapshot.axis(PadAxis.triggerRight),
          ),
          const SizedBox(height: 24),
          const Text('buttons', style: _label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final button in PadButton.known)
                _Lamp(id: button.id, on: _snapshot.down(button)),
            ],
          ),
          const SizedBox(height: 28),
          const Text('dead zone', style: _label),
          // The slider the acceptance asks for. Below the mark a resting stick
          // drifts; above it there is a hole in the middle of the travel. The
          // number can only be settled by moving this.
          _Setting(
            label: 'stick',
            value: _pad.deadzone.stick,
            onChanged: (double value) => _setDeadzone(stick: value),
          ),
          _Setting(
            label: 'trigger',
            value: _pad.deadzone.trigger,
            onChanged: (double value) => _setDeadzone(trigger: value),
          ),
        ],
      ),
    );
  }
}

const TextStyle _label = TextStyle(letterSpacing: 2, fontSize: 12);

/// What the platform can do, and what it is doing.
class _Banner extends StatelessWidget {
  const _Banner({required this.supported, required this.connected});

  final bool supported;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (!supported) {
      // Named rather than "not supported", because which platform this is is the
      // whole content of the answer.
      message = 'no backend for $_platform yet';
    } else if (connected) {
      message = 'a controller is connected';
    } else if (kIsWeb) {
      // Not a bug and not detectable: a browser hides gamepads from a page that
      // has never seen one used.
      message = 'press a button — a browser hides pads until you do';
    } else {
      message = 'no controller';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: connected ? Colors.greenAccent : Colors.orangeAccent,
        ),
      ),
    );
  }

  static String get _platform => kIsWeb ? 'the web' : defaultTargetPlatform.name;
}

/// One stick, as a dot in a circle, with the numbers beside it.
///
/// The numbers matter as much as the dot: "half a deflection is half a wish" is
/// an acceptance item, and half is something you read rather than see.
class _Stick extends StatelessWidget {
  const _Stick({required this.label, required this.x, required this.y});

  final String label;
  final double x;
  final double y;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(label, style: _label),
        const SizedBox(height: 8),
        CustomPaint(
          size: const Size.square(120),
          painter: _StickPainter(x: x, y: y),
        ),
        const SizedBox(height: 6),
        Text(
          '${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}',
          style: const TextStyle(fontFeatures: <FontFeature>[
            FontFeature.tabularFigures(),
          ]),
        ),
      ],
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({required this.x, required this.y});

  final double x;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white24,
    );
    canvas.drawLine(
      Offset(centre.dx - radius, centre.dy),
      Offset(centre.dx + radius, centre.dy),
      Paint()..color = Colors.white12,
    );
    canvas.drawLine(
      Offset(centre.dx, centre.dy - radius),
      Offset(centre.dx, centre.dy + radius),
      Paint()..color = Colors.white12,
    );
    // Y is not flipped: a pad reports positive downwards and so does a screen,
    // so the dot goes where the thumb is.
    canvas.drawCircle(
      centre + Offset(x * radius, y * radius),
      7,
      Paint()..color = Colors.lightBlueAccent,
    );
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.x != x || old.y != y;
}

/// A trigger, which is a proportion and not a bit.
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(width: 110, child: Text(label, style: _label)),
          Expanded(
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 10,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFeatures: <FontFeature>[
                FontFeature.tabularFigures(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One button, lit while it is held.
///
/// Labelled by its **identifier**, not by what is printed on the hardware: the
/// identifier is what a rebinding writes down, and checking that
/// `pad:face.south` is the button under the thumb is an acceptance item.
class _Lamp extends StatelessWidget {
  const _Lamp({required this.id, required this.on});

  final String id;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? Colors.lightBlueAccent : Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        id,
        style: TextStyle(
          fontSize: 12,
          color: on ? Colors.black : Colors.white70,
        ),
      ),
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 110, child: Text(label, style: _label)),
        Expanded(
          child: Slider(
            value: math.min(value, 0.4),
            max: 0.4,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFeatures: <FontFeature>[
              FontFeature.tabularFigures(),
            ]),
          ),
        ),
      ],
    );
  }
}
