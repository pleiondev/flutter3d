/// Monsters that arrive rather than being there from the start.
///
/// **What a level could not say.** Every monster in a crypt was placed by the
/// document and stood where it was placed until something woke it, so a room
/// held whatever it held and there was no way to write "three of these when the
/// door opens" or "and then two more". A fight that arrives is the difference
/// between a room a player clears and a room a player survives, and it was
/// entirely unavailable.
///
/// **A [Mechanism], because it is the same kind of thing as a door.** It is
/// named in the document, it is triggered by a signal or by walking into it,
/// and it answers what came of that. A game wires one to a switch, a secret or
/// another spawner exactly as it wires a door, and none of that machinery had
/// to grow.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'bestiary.dart';
import 'monster_def.dart';

/// One wave: what arrives, and how long after the one before.
final class Wave {
  const Wave({
    required this.monster,
    this.count = 1,
    this.after = 0.0,
    this.spread = 1.5,
  }) : assert(count > 0, 'a wave of nothing is not a wave'),
       assert(after >= 0.0, 'a wave cannot arrive before the one before it');

  /// What arrives.
  final MonsterDef monster;

  /// How many.
  final int count;

  /// How long after the previous wave finished arriving, in seconds. Zero on
  /// the first wave means the moment the spawner fires.
  final double after;

  /// How far from the spawner's own point they are placed, in metres.
  ///
  /// **Placed apart rather than on top of each other**, because several bodies
  /// spawned at one point are several bodies the solver has to push out of each
  /// other, and what a player sees is a knot of monsters shoving itself across
  /// the room before anything walks.
  final double spread;
}

/// A place monsters arrive from, once, when something asks it to.
///
/// **Fires once.** A spawner that can be triggered twice is a room a player can
/// farm, and a level that wants a second wave says so with a second [Wave]
/// rather than by asking twice. `restore` keeps that: a saved crypt does not
/// re-arm what it already spent.
final class Spawner extends Mechanism {
  Spawner({
    super.name,
    required this.at,
    required this.waves,
    required this.bestiary,
    this.yaw = 0.0,
  }) : assert(waves.isNotEmpty, 'a spawner with no waves spawns nothing');

  /// Where they arrive, in world space.
  final Vector3 at;

  /// What arrives, in order.
  final List<Wave> waves;

  /// What builds them. The same one the level's own monsters came from, so a
  /// spawned monster is indistinguishable from a placed one.
  final Bestiary bestiary;

  /// Which way they face on arrival, in radians.
  final double yaw;

  /// Whether it has been asked.
  bool get isSpent => _spent;
  bool _spent = false;

  /// Which wave is next, and how long until it is due.
  int _wave = 0;
  double _due = 0.0;

  /// Everything this spawner has put into the world, in the order it arrived.
  ///
  /// For a game that wants to say "the room is clear when these are dead" —
  /// which is the question a spawner exists to make askable, and one nothing
  /// else can answer once the monsters are loose in the world.
  final List<Actor> spawned = <Actor>[];

  /// Whether every wave has arrived. Says nothing about whether they are alive.
  bool get isDone => _spent && _wave >= waves.length;

  @override
  Vector3 get origin => at;

  @override
  ActivationOutcome activate(Activation by) {
    if (_spent) return const NothingToDo();
    _spent = true;
    _due = waves.first.after;
    // A wave due immediately arrives on this step rather than the next, so a
    // door that opens onto an ambush opens onto it.
    if (_due <= 0.0) _release();
    return const Activated();
  }

  @override
  void step(double dt) {
    if (!_spent || _wave >= waves.length) return;
    _due -= dt;
    if (_due <= 0.0) _release();
  }

  /// Puts the next wave into the world and queues the one after it.
  void _release() {
    final wave = waves[_wave];
    for (var i = 0; i < wave.count; i++) {
      // Round the point rather than along a line, so a spawner against a wall
      // still puts most of its wave in the room.
      final angle = wave.count == 1 ? 0.0 : 6.283185307179586 * i / wave.count;
      final offset = wave.count == 1
          ? Vector3.zero()
          : Vector3(
              wave.spread * math.cos(angle),
              0.0,
              wave.spread * math.sin(angle),
            );
      spawned.add(
        bestiary.spawn(
          wave.monster,
          Vector3(at.x + offset.x, at.y + offset.y, at.z + offset.z),
          yaw: yaw,
        ),
      );
    }
    _wave += 1;
    if (_wave < waves.length) _due = waves[_wave].after;
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
    'spent': _spent,
    'wave': _wave,
    'due': _due,
  };

  @override
  void restore(Map<String, Object?> from) {
    _spent = from['spent'] == true;
    _wave = (from['wave'] as num?)?.toInt() ?? 0;
    _due = (from['due'] as num?)?.toDouble() ?? 0.0;
    // **Not the monsters.** What a spawner has already put into the world is
    // saved by the world, as actors; restoring this list would double every
    // monster a saved crypt is holding.
    spawned.clear();
  }
}
