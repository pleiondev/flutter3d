/// Determinism in a step: transcendental functions computed the same way on
/// every platform, and a random generator whose state can be written down and
/// restored to continue the same sequence.
///
/// Quoted by `portable_math.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class PortableMathDemo extends ShowcaseDemo {
  late final String _report;

  bool rolling = true;
  bool _rollAsked = false;

  late GameRandom _dice;
  late GameRandom _resumed;
  final List<int> _seen = List<int>.filled(6, 0);
  final List<int> _seenAgain = List<int>.filled(6, 0);
  late final List<BarGauge> _bars;
  late final List<BarGauge> _barsAgain;
  late final MeshNode _hand;
  late final MeshNode _lamp;
  double _clock = 0.0;
  double _owed = 0.0;
  bool _agree = true;

  static const int _dots = 16;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 13.0
      ..pitch = 0.6
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.5, 1.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _reseed();
    BarGauge bar(String name, Vector4 ink, double x, double z) => BarGauge(
      context,
      name,
      ink,
      Vector3(x, 0.0, z),
      height: 3.0,
      width: 0.6,
      vertical: true,
    );
    _bars = <BarGauge>[
      for (var i = 0; i < 6; i++)
        bar(
          'face ${i + 1}',
          Vector4(0.45, 0.65, 0.95, 1.0),
          -2.5 + i * 1.0,
          3.2,
        ),
    ];
    _barsAgain = <BarGauge>[
      for (var i = 0; i < 6; i++)
        bar(
          'again ${i + 1}',
          Vector4(0.95, 0.65, 0.3, 1.0),
          -2.5 + i * 1.0 + 0.35,
          3.2,
        ),
    ];
    _hand = ballNode(context, 'hand', 0.3, Vector4(0.95, 0.75, 0.3, 1.0));
    _lamp = ballNode(
      context,
      'lamp',
      0.3,
      Vector4(0.35, 0.85, 0.4, 1.0),
      at: Vector3(0.0, 0.3, 5.5),
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 12.0, depth: 12.0),
      // A ring of points placed by `Portable`, and a hand that goes round it.
      for (var i = 0; i < _dots; i++)
        ballNode(
          context,
          'dot $i',
          0.12,
          Vector4(0.6, 0.65, 0.75, 1.0),
          at: Vector3(
            2.5 * Portable.sinCos(i * 2 * math.pi / _dots).cos,
            0.12,
            -1.5 + 2.5 * Portable.sinCos(i * 2 * math.pi / _dots).sin,
          ),
        ),
      _hand,
      _lamp,
      for (final BarGauge g in _bars) ...g.nodes,
      for (final BarGauge g in _barsAgain) ...g.nodes,
    ]);
  }

  void _reseed() {
    // #region live
    // One generator, and a second that is handed the first's state: from
    // here the two must roll the same numbers for as long as anyone asks.
    _dice = GameRandom(1234);
    _resumed = GameRandom(1)..state = _dice.state;
    // #endregion live
    _seen.fillRange(0, 6, 0);
    _seenAgain.fillRange(0, 6, 0);
    _agree = true;
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (rolling) _owed += dt * 24.0;
    if (_rollAsked) {
      _rollAsked = false;
      _owed += 30.0;
    }
    while (_owed >= 1.0) {
      _owed -= 1.0;
      final int a = _dice.nextInt(6);
      final int b = _resumed.nextInt(6);
      _seen[a]++;
      _seenAgain[b]++;
      if (a != b) _agree = false;
      if (_seen.reduce(math.max) > 40) _reseed();
    }
    // The hand goes round the ring through `Portable`, not `dart:math`.
    final ({double sin, double cos}) at = Portable.sinCos(_clock);
    _hand.setPosition(2.5 * at.cos, 0.3, -1.5 + 2.5 * at.sin);
    for (var i = 0; i < 6; i++) {
      _bars[i].set(_seen[i] / 40.0);
      _barsAgain[i].set(_seenAgain[i] / 40.0);
    }
    _lamp.material.baseColor.setValues(
      _agree ? 0.35 : 0.9,
      _agree ? 0.85 : 0.3,
      _agree ? 0.4 : 0.3,
      1.0,
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Keep rolling',
      value: () => rolling,
      onChanged: (bool v) => rolling = v,
    ),
    ToggleControl(
      'Roll thirty more',
      value: () => false,
      onChanged: (bool v) {
        if (v) _rollAsked = true;
      },
    ),
  ];

  static String _run() {
    // #region trig
    // `Portable.sinCos` places a point on a circle without ever calling
    // `dart:math`, whose trig is a platform's own library and disagrees
    // between the Dart VM and a browser in the last few bits.
    final direction = Portable.sinCos(0.7853981633974483); // pi / 4
    // #endregion trig

    // #region roll
    final dice = GameRandom(1234);
    final firstRoll = dice.nextInt(6) + 1;
    final secondRoll = dice.nextInt(6) + 1;
    final savedState = dice.state;
    // #endregion roll

    // #region resume
    // A fresh generator given the saved state continues the exact same
    // sequence, which is what lets a snapshot carry a simulation's dice
    // forward across a save and a load.
    final resumed = GameRandom(1)..state = savedState;
    final thirdRoll = dice.nextInt(6) + 1;
    final resumedRoll = resumed.nextInt(6) + 1;
    // #endregion resume

    return 'sin/cos of pi/4: ${direction.sin.toStringAsFixed(4)}, '
        '${direction.cos.toStringAsFixed(4)}\n'
        'rolls: $firstRoll, $secondRoll, then $thirdRoll\n'
        'a generator resumed from the saved state rolls $resumedRoll next, '
        'matching the original\'s $thirdRoll';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the die was not drawn');
    }
    final dice = GameRandom(1234);
    final expectedThird = () {
      dice.nextInt(6);
      dice.nextInt(6);
      return dice.nextInt(6) + 1;
    }();
    if (!_report.contains('then $expectedThird')) {
      throw StateError(
        'a GameRandom seeded the same way should roll the '
        'same sequence',
      );
    }
  }
}
