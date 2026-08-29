import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pointer_lock/pointer_lock.dart';

/// Shows the raw output of the plugin and nothing else.
///
/// The point is isolation. Mouse capture goes wrong in ways that look identical
/// to a broken camera — the view does not turn, or turns too far, or stops when
/// the window loses focus — and telling those apart inside a 3D game means
/// debugging two things at once. Here the numbers are the whole product.
void main() {
  runApp(const PointerLockExample());
}

class PointerLockExample extends StatefulWidget {
  const PointerLockExample({super.key});

  @override
  State<PointerLockExample> createState() => _PointerLockExampleState();
}

class _PointerLockExampleState extends State<PointerLockExample>
    with SingleTickerProviderStateMixin {
  final PointerLock _capture = PointerLock.instance;

  late final Ticker _ticker;

  /// Held so [dispose] can cancel it: the listener calls `setState`, and a
  /// subscription that outlives the state would do so into a defunct widget.
  late final StreamSubscription<CaptureState> _events;

  Offset _lastDelta = Offset.zero;
  Offset _total = Offset.zero;
  int _steps = 0;
  String _lastEvent = 'none';

  @override
  void initState() {
    super.initState();

    // Drained on a ticker rather than in a stream listener, because that is how
    // the consumer actually uses it: once per simulation step.
    _ticker = createTicker((_) {
      final delta = _capture.takeDelta();
      if (delta == Offset.zero && _lastDelta == Offset.zero) return;
      setState(() {
        _lastDelta = delta;
        _total += delta;
        _steps++;
      });
    })..start();

    _events = _capture.onStateChanged.listen((CaptureState state) {
      setState(() => _lastEvent = state.name);
    });
  }

  @override
  void dispose() {
    unawaited(_events.cancel());
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _capture.isSupported
                    ? 'Supported on this platform'
                    : 'Not supported on this platform',
              ),
              const SizedBox(height: 24),
              _Row('captured', '${_capture.isCaptured}'),
              _Row('last state event', _lastEvent),
              _Row(
                'delta this frame',
                '${_lastDelta.dx.toStringAsFixed(1)}, ${_lastDelta.dy.toStringAsFixed(1)}',
              ),
              _Row(
                'total',
                '${_total.dx.toStringAsFixed(0)}, ${_total.dy.toStringAsFixed(0)}',
              ),
              _Row('frames with motion', '$_steps'),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FilledButton(
                    onPressed: () async {
                      await _capture.capture();
                      setState(() {});
                    },
                    child: const Text('Capture'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () async {
                      await _capture.release();
                      setState(() {});
                    },
                    child: const Text('Release'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'While captured, the cursor should not move.\n'
                'Switching away with Cmd+Tab must release it and bring the '
                'cursor back.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 160, child: Text('$label:')),
          SizedBox(
            width: 140,
            child: Text(
              value,
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
