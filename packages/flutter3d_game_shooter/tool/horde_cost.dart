/// What a horde costs a step: fifty to four hundred chasers in a maze.
///
///     flutter test tool/horde_cost.dart
///
/// **The gate before a crowd game.** Nothing in this repository had run more
/// than a few dozen actors at once, and a dungeon crawler in the arcade's shape
/// wants a hundred to two hundred alive on one screen. Thinking, steering by
/// the flow field, sweeping every body against the level and against each
/// other — each of those is per actor, and which of them dominates decides
/// what has to be made cheaper first.
///
/// The maze is thirty-six rooms of eight metres, each wall with a two-metre
/// door in its middle, so every chaser routes round corners through the field.
/// The focus walks a circle through the rooms, crossing cells all the time, so
/// the field re-sweeps as often as it would with a player who never stops.
/// Every monster is woken first by being hurt for one point: a monster that
/// has not noticed anybody stands still and costs nothing, which would flatter
/// the number.
///
/// Prints rather than asserts, as `ground_cost.dart` does: the number is the
/// machine's, and what it is compared with is the frame, which is written
/// beside it.
///
/// ## What was measured, on macOS-arm64, Dart 3.12, 2026-09-30
///
/// Six hundred steps after sixty of warm-up, milliseconds per step, and how
/// many of the horde ended more than two metres from where they began:
///
///     actors   mean   p95    worst   moved
///         50   0.34   1.07   1.28       50
///        100   0.85   1.60   1.88       98
///        200   2.10   3.00   6.04      196
///        400   7.78  15.81  19.74      388
///
/// **Two hundred is an eighth of a frame, so the gate is open.** Nearly all of
/// it is `ActorSystem.step`; `world.update` is a hundredth of that.
///
/// **The growth is not linear, and where it bends is the thing to know.** Four
/// times the horde is six times the cost at two hundred, and twice that again
/// is nearly four times more. The field is one sweep whatever the count, so
/// what grows faster than the horde is bodies meeting bodies: the closer they
/// pack round the focus, the more of each other every sweep has to push
/// through. Four hundred is where a cheaper separation than exact sweeps
/// stops being optional; two hundred is not.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const double _half = 24.0;
const double _room = 8.0;
const double _door = 2.0;

Brush _box(double cx, double cz, double sx, double sz) =>
    Brush(centre: Vector3(cx, 1.5, cz), size: Vector3(sx, 3.0, sz));

/// Six rooms by six, each wall broken by a door in its middle.
List<Brush> _maze() {
  final segment = (_room - _door) / 2.0;
  return <Brush>[
    Brush(
      centre: Vector3(0.0, -0.5, 0.0),
      size: Vector3(_half * 2.0, 1.0, _half * 2.0),
    ),
    // The outer walls, whole.
    _box(0.0, -_half - 0.5, _half * 2.0 + 2.0, 1.0),
    _box(0.0, _half + 0.5, _half * 2.0 + 2.0, 1.0),
    _box(-_half - 0.5, 0.0, 1.0, _half * 2.0),
    _box(_half + 0.5, 0.0, 1.0, _half * 2.0),
    // The inner ones, two pieces to a room's side with the door between.
    for (var line = -_half + _room; line < _half; line += _room)
      for (var start = -_half; start < _half; start += _room) ...<Brush>[
        _box(line, start + segment / 2.0, 0.4, segment),
        _box(line, start + _room - segment / 2.0, 0.4, segment),
        _box(start + segment / 2.0, line, segment, 0.4),
        _box(start + _room - segment / 2.0, line, segment, 0.4),
      ],
  ];
}

/// Where the [count] monsters start: spread over every room, a metre apart.
List<Vector3> _starts(int count) {
  final rooms = (_half * 2.0 / _room).round();
  final perRoom = (count / (rooms * rooms)).ceil();
  final side = math.sqrt(perRoom).ceil();
  return <Vector3>[
    for (var i = 0; i < count; i++)
      Vector3(
        -_half +
            ((i ~/ perRoom) % rooms) * _room +
            _room / 2.0 +
            ((i % perRoom) % side - (side - 1) / 2.0) * 1.1,
        0.9,
        -_half +
            ((i ~/ perRoom) ~/ rooms) * _room +
            _room / 2.0 +
            ((i % perRoom) ~/ side - (side - 1) / 2.0) * 1.1,
      ),
  ];
}

({
  double mean,
  double p95,
  double worst,
  double actors,
  double world,
  int moved,
})
_measure(int count, {int steps = 600, int warmup = 60}) {
  final brushes = _maze();
  final world = CollisionWorld();
  for (final brush in brushes) {
    world.addBox(brush.centre, brush.size);
  }
  final at = Vector3(12.0, 0.9, 0.0);
  final player = world.add(
    Collider(
      shape: CollisionBox(Vector3(0.35, 0.9, 0.35)),
      position: at.clone(),
      kind: ColliderKind.kinematic,
      layer: CollisionLayers.player,
    ),
  );
  world.update();

  final random = GameRandom(7);
  final system = ActorSystem(world: world, random: random)
    ..navigation = Navigation(NavGrid.bake(brushes));
  final bestiary = Bestiary(
    actors: system,
    shot: WeaponShot(
      world: world,
      hitscan: Hitscan(world: world, random: random),
      projectiles: ProjectileSystem(world: world),
    ),
    catalog: Monsters.byName,
  );
  final starts = _starts(count);
  final horde = <Actor>[
    for (final start in starts) bestiary.spawn(Monsters.runner, start),
  ];
  for (final monster in horde) {
    system.hurt(monster, 1.0);
  }

  final eye = Vector3.zero();
  final times = <double>[];
  final watch = Stopwatch();
  var actorTime = 0.0;
  var worldTime = 0.0;
  for (var i = 0; i < warmup + steps; i++) {
    final angle = i * _dt * 0.25;
    at.setValues(12.0 * math.cos(angle), 0.9, 12.0 * math.sin(angle));
    player.position.setFrom(at);
    eye
      ..setFrom(at)
      ..y += 0.7;

    watch
      ..reset()
      ..start();
    system
      ..beginStep()
      ..step(_dt, focus: eye, focusBody: player);
    final stepped = watch.elapsedMicroseconds;
    world.update();
    watch.stop();
    if (i < warmup) continue;
    times.add(watch.elapsedMicroseconds / 1000.0);
    actorTime += stepped / 1000.0;
    worldTime += (watch.elapsedMicroseconds - stepped) / 1000.0;
  }
  times.sort();
  return (
    mean: times.reduce((a, b) => a + b) / times.length,
    p95: times[(times.length * 0.95).floor()],
    worst: times.last,
    actors: actorTime / steps,
    world: worldTime / steps,
    // A horde that stood still would be cheap and prove nothing, so the
    // report says how much of it went anywhere.
    moved: <int>[
      for (var i = 0; i < count; i++)
        if (horde[i].position!.distanceTo(starts[i]) > 2.0) i,
    ].length,
  );
}

void main() {
  test('a horde in a maze, per step', () {
    final rows = <String>[
      '    actors   mean ms   p95 ms   worst ms   (actors / world.update)   moved',
    ];
    // Once for the compiler: the first run pays for optimising the step, and
    // it would be charged to whichever count came first.
    _measure(50, steps: 300);
    for (final count in const <int>[50, 100, 200, 400]) {
      final r = _measure(count);
      rows.add(
        '${count.toString().padLeft(10)}'
        '${r.mean.toStringAsFixed(2).padLeft(10)}'
        '${r.p95.toStringAsFixed(2).padLeft(9)}'
        '${r.worst.toStringAsFixed(2).padLeft(11)}'
        '   (${r.actors.toStringAsFixed(2)} / ${r.world.toStringAsFixed(2)})'
        '${r.moved.toString().padLeft(12)}',
      );
    }
    rows.add('    a frame at 60 Hz is 16.7 ms');
    // ignore: avoid_print
    print(rows.join('\n'));
  });
}
