/// A place monsters keep coming from until somebody breaks it.
///
/// The difference from a wave is the whole of the genre: a room with a
/// generator in it is never cleared by killing what is in it, only by getting
/// to the generator. So it pours without end, holds back once [cap] of its
/// own are alive, and stops for good when its health runs out.
///
/// **A [Mechanism]**, for the reasons the shooter's spawner is one: a level
/// names it, a save carries it by that name, and it steps with the rest of the
/// maze's machinery — before the monsters move, so one born this step is
/// stepped this step. **[Damageable]**, so a shot and a hero's blows reach it
/// the way they reach a monster, by asking the collider who it is.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'horde.dart';
import 'monster_kind.dart';

final class Generator extends Mechanism implements Damageable {
  Generator({
    super.name,
    required this.collider,
    required this.kind,
    required this.horde,
    this.period = 2.0,
    this.cap = 12,
    double health = 60.0,
    this.score = 50,
  }) : health = Health(health) {
    collider
      ..kind = ColliderKind.kinematic
      ..layer = CollisionLayers.actor
      ..userData = this;
  }

  /// The block that stands in the maze, is shot at, and goes when it breaks.
  final Collider collider;

  /// What comes out.
  final MonsterKind kind;

  /// Where what comes out is kept.
  final Horde horde;

  /// Seconds between births.
  final double period;

  /// How many of its own may be alive at once before it waits.
  final int cap;

  final Health health;

  /// What breaking it is worth.
  final int score;

  bool get isDestroyed => health.isDead;

  double _clock = 0.0;

  /// How many it has made. Turns the side a monster is born on, so a crowd
  /// comes out of every face rather than piling up against one.
  int _births = 0;

  final List<Collider> _crowd = <Collider>[];
  final Vector3 _at = Vector3.zero();

  @override
  Vector3 get origin => collider.position;

  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  @override
  bool applyDamage(double amount, {Object? from}) {
    final broke = health.damage(amount);
    if (broke) world.collisions.removeLater(collider);
    return broke;
  }

  @override
  void step(double dt) {
    if (isDestroyed) return;
    _clock += dt;
    if (_clock < period) return;
    // Full: wait with the clock run down, so the next birth is the moment
    // there is room rather than a period after it.
    if (horde.countFrom(this) >= cap) {
      _clock = period;
      return;
    }
    if (_bear()) _clock -= period;
  }

  /// Places one beside the generator, on the first of eight sides with room,
  /// starting from the one after the last. False when all eight are blocked.
  bool _bear() {
    final shape = CollisionBox(
      Vector3(kind.radius, kind.height / 2.0, kind.radius),
    );
    final half = collider.shape.boundsHalfExtents;
    final out = (half.x > half.z ? half.x : half.z) + kind.radius + 0.3;
    for (var turn = 0; turn < 8; turn++) {
      final side = (_births + turn) % 8;
      final dx = _sides[side * 2];
      final dz = _sides[side * 2 + 1];
      _at.setValues(
        collider.position.x + dx * out,
        collider.position.y - half.y + kind.height / 2.0,
        collider.position.z + dz * out,
      );
      world.collisions.overlap(
        shape,
        _at,
        _crowd,
        mask:
            CollisionLayers.world |
            CollisionLayers.player |
            CollisionLayers.actor,
        includeTriggers: false,
      );
      if (_crowd.isNotEmpty) continue;
      horde.spawn(kind, _at, from: this);
      _births = side + 1;
      return true;
    }
    return false;
  }

  // The eight sides, as unit steps: the four faces, then the four corners.
  static const List<double> _sides = <double>[
    1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, //
    0.7071067811865476, 0.7071067811865476,
    -0.7071067811865476, 0.7071067811865476,
    -0.7071067811865476, -0.7071067811865476,
    0.7071067811865476, -0.7071067811865476,
  ];

  @override
  Map<String, Object?> save() => <String, Object?>{
    'clock': _clock,
    'births': _births,
    'health': health.save(),
  };

  @override
  void restore(Map<String, Object?> from) {
    _clock = (from['clock'] as num?)?.toDouble() ?? 0.0;
    _births = (from['births'] as num?)?.toInt() ?? 0;
    final vitals = from['health'];
    if (vitals is Map) health.restore(vitals.cast<String, Object?>());
    // Both ways, because a rollback goes both ways: to after it broke, and to
    // before, when the block it no longer has has to stand there again.
    if (isDestroyed) {
      world.collisions.removeLater(collider);
    } else if (collider.world == null) {
      world.collisions.add(collider);
    }
  }
}
