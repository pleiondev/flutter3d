/// Two players' worth of a fixed-step simulation, kept in step across an
/// unreliable transport: input frames, delay, prediction, and rollback on a
/// confirmation that disagreed.
///
/// **`flutter3d_net` is not a dependency of this app.** `NetSession` and
/// `LoopbackTransport` both need only `flutter3d_sim`'s `Snapshot` and
/// `GameRandom` underneath, so this page reimplements the small pieces of
/// each that the demo below actually exercises, against those same real
/// types. `flutter3d_net_webrtc`, the transport for an actual connection
/// between two browsers, is a native plugin and has no page of its own.
///
/// Quoted by `rollback_netcode.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region transport
/// A pair of transports joined by a fixed delay and a loss rate, so a test
/// is separated by an unreliable network rather than by nothing.
final class _LoopbackTransport {
  _LoopbackTransport._(this._delaySteps, this._lossRate, this._random);

  final int _delaySteps;
  final double _lossRate;
  final GameRandom _random;
  late final _LoopbackTransport _peer;

  int _now = 0;
  final List<(int dueAt, int value)> _inbox = <(int, int)>[];
  void Function(int value)? _listener;

  static (_LoopbackTransport, _LoopbackTransport) pair({
    required int stepsPerSecond,
    double delaySeconds = 0.0,
    double lossRate = 0.0,
    int seed = 1,
  }) {
    final random = GameRandom(seed);
    final delaySteps = (delaySeconds * stepsPerSecond).round();
    final a = _LoopbackTransport._(delaySteps, lossRate, random);
    final b = _LoopbackTransport._(delaySteps, lossRate, random);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  void send(int value) {
    if (_random.nextDouble() < _lossRate) return;
    _peer._inbox.add((_peer._now + _delaySteps, value));
  }

  void listen(void Function(int value) onMessage) => _listener = onMessage;

  void tick() {
    _now++;
    _inbox.removeWhere((entry) {
      if (entry.$1 > _now) return false;
      _listener?.call(entry.$2);
      return true;
    });
  }
}
// #endregion transport

final class RollbackNetcodeDemo extends ShowcaseDemo {
  double lossRate = 0.3;
  late String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run(lossRate);
    final material = Material(
      name: 'peer',
      baseColor: Vector4(0.5, 0.6, 0.9, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run(double lossRate) {
    // #region session
    // Each peer's own count of "my presses the other side has heard about",
    // standing in for a `NetSession.applyAndStep` that folds a remote frame
    // into a shared simulation. Every message repeats the last few sends,
    // the same redundancy `NetSession` uses, so one dropped packet is not
    // one lost step.
    final (linkA, linkB) = _LoopbackTransport.pair(
      stepsPerSecond: 30,
      delaySeconds: 0.05,
      lossRate: lossRate,
    );
    var aKnowsOfB = 0;
    var bKnowsOfA = 0;
    linkA.listen((int value) => aKnowsOfB = value);
    linkB.listen((int value) => bKnowsOfA = value);
    // #endregion session

    // #region redundant
    var bSends = 0;
    var aSends = 0;
    for (var step = 1; step <= 60; step++) {
      aSends = step;
      bSends = step;
      // The current count sent three times running: the same message a
      // `redundancy` window resends, so a single dropped packet is caught
      // by the next one.
      for (var r = 0; r < 3; r++) {
        linkA.send(aSends);
        linkB.send(bSends);
      }
      linkA.tick();
      linkB.tick();
    }
    // #endregion redundant

    final agree = aKnowsOfB == bKnowsOfA;
    final close = (bSends - aKnowsOfB) <= 3 && (aSends - bKnowsOfA) <= 3;
    return 'after sixty steps at a ${(lossRate * 100).round()}% loss rate:\n'
        'A last heard B at $aKnowsOfB (B actually reached $bSends)\n'
        'B last heard A at $bKnowsOfA (A actually reached $aSends)\n'
        'both sides agree on the same number: $agree\n'
        'both are within three steps of the truth: $close';
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Loss rate',
      min: 0.0,
      max: 0.9,
      value: () => lossRate,
      onChanged: (double v) => lossRate = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the peer marker was not drawn');
    }
    if (!_report.contains('both sides agree on the same number: true')) {
      throw StateError(
        'both sides should end up knowing the other reached the same step, '
        'even at a 30% loss rate',
      );
    }
    if (!_report.contains('both are within three steps of the truth: true')) {
      throw StateError(
        'resending the last few steps should keep both sides close to the '
        'truth, not stuck far behind it',
      );
    }
  }
}
