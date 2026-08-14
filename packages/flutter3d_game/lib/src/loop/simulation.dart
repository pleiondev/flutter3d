/// The ordered core of a step, and the state the game is in.
///
/// ## Why this is a class and not a comment
///
/// This order lived in the application, untested, with two of its lines
/// carrying comments about bugs they prevent. Both bugs look like physics
/// faults and neither is one, both are invisible in a screenshot, and both come
/// back the moment somebody moves a line while tidying up. They are now under
/// two tests written by permuting the order first — see `simulation_test.dart`.
///
/// The second reason is that every game that drives a simulation would
/// otherwise have to get the same order right again from scratch.
///
/// ## State and presentation
///
/// **Everything here is state.** What a shot looked like, what it sounded like,
/// how much the screen flashed and where the smoke went are not; they are the
/// caller's, and this reports *that* things happened rather than what they
/// looked like — [firedThisStep], [hits], [damageTakenThisStep],
/// [usedThisStep], and the per-step lists the subsystems already keep.
///
/// That line is drawn deliberately and it is load-bearing: a save file, a
/// replay and a network packet all need exactly what is on this side of it, and
/// none of them need any of what is on the other. Drawing it now is cheaper
/// than drawing it later.
///
/// ## Why the name is not `Simulation`
///
/// Because `package:flutter/material.dart` exports one — Flutter's scroll
/// physics has a `Simulation` — and every application built on this package
/// imports material. A name that forces `hide` into every game's imports is a
/// name that was chosen for the wrong room.
///
/// ## Not a closed loop
///
/// It does not own particles, audio, the view model or the interpolated
/// camera position, and it does not advance them. A caller steps this and then
/// reads it; the alternative — a simulation that called back into the
/// application — would put the renderer's frame rate inside the fixed step,
/// which is the one thing this package exists to prevent.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../actors/damageable.dart';
import '../actors/actor_system.dart';
import '../actors/player.dart';
import '../combat/hitscan.dart';
import '../combat/projectile.dart';
import '../combat/weapon.dart';
import '../combat/weapon_behaviour.dart';
import '../input/game_action.dart';
import '../input/input_state.dart';
import '../ecs/ecs_world.dart';
import '../save/game_random.dart';
import '../save/snapshot.dart';
import '../world/exit.dart';
import '../world/mechanism.dart';
import '../world/mover.dart';
import '../world/signals.dart';

/// Whether the game is being played, lost, or finished.
///
/// Three, not two, because "the level ended" and "you ended" want different
/// screens, different music and different keys — and a caller holding a single
/// `bool over` has to keep a second flag beside it to tell them apart.
enum GameState {
  playing,

  /// The player's health reached zero. Their input no longer moves anything;
  /// the world carries on around them.
  dead,

  /// An [Exit] was reached. See [GameSimulation.nextLevel].
  complete,
}

final class GameSimulation {
  GameSimulation({
    required this.player,
    required this.collision,
    required this.input,
    this.mechanisms,
    this.actors,
    this.projectiles,
    this.shot,
    this.levelNext,
    this.random,
  });

  final Player player;
  final CollisionWorld collision;
  final InputState input;

  /// All nullable: a game may have no doors, no monsters, no rockets and no
  /// weapons, and a simulation with none of them still runs. That is the same
  /// rule the entity registry follows — the package offers parts and the game
  /// says which of them it has.
  final MechanismWorld? mechanisms;
  final ActorSystem? actors;
  final ProjectileSystem? projectiles;
  final WeaponShot? shot;

  /// What the level document says follows it.
  final String? levelNext;

  GameState get state => _state;
  GameState _state = GameState.playing;

  /// Where to go once [state] is [GameState.complete], or null when nothing
  /// said. An exit's own answer wins over the level's, which is what lets a
  /// level with two doors lead to two places.
  String? get nextLevel => _exitNext ?? levelNext;
  String? _exitNext;

  /// What the player fired this step, or null.
  WeaponDef? firedThisStep;

  /// Where that shot started — the eye, not the muzzle.
  final Vector3 firedFrom = Vector3.zero();

  /// What it struck. Empty on a step with no shot, and on a shot that missed.
  final List<ShotHit> hits = <ShotHit>[];

  /// Damage the player took this step, from every source together.
  ///
  /// One number rather than one per source: a caller wants to know whether to
  /// flash the screen, and being hit by a monster and a rocket in the same step
  /// is one flash.
  double damageTakenThisStep = 0.0;

  /// What came of pressing the use key, or null if it was not pressed or
  /// reached nothing.
  ///
  /// Returned rather than pushed into `MechanismEvents.messages`, because
  /// `publish()` runs after the use key and would clear it.
  ActivationOutcome? usedThisStep;

  /// Where the entities live, when anything has moved across yet.
  ///
  /// Defaults to the projectile system's, because that is the only system that
  /// has. **When a second one moves, ownership comes up here** and both are
  /// handed the same world — which is the point of the exercise, and the day
  /// `save` above loses another hand-written line.
  EcsWorld? get entities => projectiles?.entities;

  /// The generator every roll in this simulation comes out of, if the caller
  /// gave one.
  ///
  /// Optional, and the consequence of leaving it out is stated rather than
  /// hidden: a snapshot then restores everything except *where the dice were*,
  /// so two worlds loaded from it agree until the first flinch roll and then
  /// drift. Pass the same instance to `MonsterSystem` and `Hitscan` — it is one
  /// object shared, not one each.
  final GameRandom? random;

  final Vector3 _wish = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  /// Advances the world by one fixed step.
  void step(double dt) {
    firedThisStep = null;
    usedThisStep = null;
    damageTakenThisStep = 0.0;
    hits.clear();

    final playing = _state == GameState.playing;

    if (playing) {
      player.look(input.lookDelta);
      player.moveWish(input.moveAxis, _wish);
      if (input.pressed(GameAction.jump)) player.body.requestJump();
    } else {
      // A dead player's input moves nothing. The world keeps going around
      // them, which is the difference between dying and the game freezing.
      _wish.setZero();
    }

    // Doors and lifts move first, and the world is re-indexed before the player
    // sweeps against them.
    //
    // **One of these two orderings is under test and one is not, and it is
    // worth saying which.**
    //
    // `clearKinematicDeltas` after `body.step` is tested: a platform moving
    // *sideways* carries its passenger only through the delta, and clearing it
    // early leaves the player standing while the floor departs. Note sideways.
    // The comment this replaces claimed a rising lift could not carry you, and
    // that is measurably false — a lift penetrates the capsule on it and the
    // controller pushes it out, upwards, delta or no delta.
    //
    // `reindex` before `body.step` is **not** under test, and no test here
    // pretends otherwise. It keeps the broadphase consistent with geometry
    // that already moved this step, which is right; but the narrow phase reads
    // live positions, a broadphase cell is four metres, and `update` at the end
    // of the previous step already rebuilt the grid. So a stale index loses a
    // mover only if it left its cell within one step, which nothing that calls
    // itself a door does. Ordering by argument rather than by test, said out
    // loud rather than dressed up as a caught bug.
    final doors = mechanisms;
    doors?.step(dt);
    collision.reindex();

    player.body.step(
      dt,
      wishDirection: _wish,
      sprint: playing && input.held(GameAction.sprint),
    );

    collision.update();
    collision.clearKinematicDeltas();

    if (doors != null) {
      if (playing && input.pressed(GameAction.use)) _use(doors);
      // Last, because the use key above can start a door: publishing before it
      // would report that door a step late, every time.
      doors.publish();
      _readExits(doors);
    }

    player.inventory.step(dt);
    if (playing) _weapon(dt);

    final actors = this.actors;
    if (actors != null && player.isAlive) {
      player.eye(_eye);
      actors.step(dt, focus: _eye, focusBody: player.body.collider);
      _hurtPlayer(actors.damageToFocusThisStep);
    }

    // After the weapon, so a rocket fired this step is not moved until the
    // next one — otherwise it starts the game already a step down the corridor.
    final projectiles = this.projectiles;
    if (projectiles != null) {
      projectiles.step(dt);
      for (final blast in projectiles.detonations) {
        for (final entry in blast.damage.entries) {
          final target = entry.key.userData;
          if (target is! Damageable) continue;
          target.applyDamage(entry.value);
          if (identical(target, player)) damageTakenThisStep += entry.value;
        }
      }
    }

    if (_state == GameState.playing && !player.isAlive) {
      _state = GameState.dead;
    }
  }

  void _use(MechanismWorld mechanisms) {
    player
      ..eye(_eye)
      ..aim(_aim);
    final target = mechanisms.underCrosshair(
      _eye,
      _aim,
      ignore: player.body.collider,
    );
    if (target == null) return;
    usedThisStep = target.activate(
      mechanisms.activationBy(player.body.collider),
    );
  }

  /// An exit reached ends the level, whichever way it was reached.
  ///
  /// Read out of the published events rather than watched for directly, so a
  /// door opened by a button that relays to an exit finishes the level exactly
  /// as walking into it does.
  void _readExits(MechanismWorld mechanisms) {
    if (_state != GameState.playing) return;
    for (final reached in mechanisms.events.reached) {
      if (reached is! Exit) continue;
      _exitNext = reached.next;
      _state = GameState.complete;
      return;
    }
  }

  void _weapon(double dt) {
    final arsenal = player.inventory.arsenal;
    arsenal.advanceTime(dt);

    final slot = input.weaponRequest;
    if (slot != null) arsenal.selectSlot(slot);

    final shot = this.shot;
    if (shot != null &&
        arsenal.wantsToFire(
          held: input.held(GameAction.fire),
          pressed: input.pressed(GameAction.fire),
        )) {
      final weapon = arsenal.fire();
      if (weapon != null) _fire(shot, weapon);
    }

    // Only when the trigger is idle: switching weapons out from under a player
    // who is mid-burst because one shot emptied the magazine is worse than
    // letting them notice.
    if (!input.held(GameAction.fire)) arsenal.fallBackIfEmpty();
  }

  void _fire(WeaponShot shot, WeaponDef weapon) {
    // From the eye, not from the muzzle. The muzzle is off to one side, and a
    // shot that starts there misses what the crosshair is on whenever the
    // player is close to a wall — the classic corner-shooting bug.
    player
      ..eye(firedFrom)
      ..aim(_aim);

    // No branch on the kind of weapon. Rays, swings and rockets each know how
    // they arrive; this only has to say where the shot came from.
    shot.begin(weapon, firedFrom, _aim, shooter: player.body.collider);
    weapon.behaviour.deliver(shot);
    firedThisStep = weapon;
    hits.addAll(shot.hits);

    // Pellets landing in the same monster are summed before they are applied,
    // or eight of them are eight deaths.
    for (final entry in Hitscan.damageByTarget(hits).entries) {
      final target = entry.key.userData;
      if (target is Damageable) target.applyDamage(entry.value);
    }
  }

  /// Everything needed to carry on, and nothing needed only to draw.
  ///
  /// See [Snapshot] for what this is and is not. The per-step lists are
  /// deliberately absent: they describe the step that has just happened, a
  /// caller has already drained them, and restoring them would replay a sound
  /// for a monster that died before the save was taken.
  Snapshot save() => Snapshot(<String, Object?>{
        'state': _state.name,
        'exitNext': _exitNext,
        'player': player.save(),
        if (random != null) 'random': random!.state,
        if (actors != null) 'actors': actors!.save(),
        // Not a line per system any more, for the one system that has moved:
        // `EcsWorld` writes every component on every entity and refuses to
        // write one nobody registered. The hand-written lines above are what
        // this replaces, one system at a time.
        if (entities != null) 'entities': entities!.save(),
        if (mechanisms != null) 'mechanisms': _saveMechanisms(mechanisms!),
      });

  void restore(Snapshot snapshot) {
    final from = snapshot.data;
    for (final value in GameState.values) {
      if (value.name == from['state']) _state = value;
    }
    _exitNext = from['exitNext'] as String?;

    final player = from['player'];
    if (player is Map) this.player.restore(player.cast<String, Object?>());

    final seed = from['random'];
    if (seed is num && random != null) random!.state = seed.toInt();

    actors?.restore(from['actors']);
    final entities = this.entities;
    final saved = from['entities'];
    if (entities != null && saved is Map) {
      entities.restore(saved.cast<String, Object?>());
    }
    _restoreMechanisms(from['mechanisms']);

    // Whatever the step that took the snapshot reported is not news any more.
    firedThisStep = null;
    usedThisStep = null;
    damageTakenThisStep = 0.0;
    hits.clear();
    // The broadphase is holding every body where it was before the restore.
    collision.reindex();
    collision.update();
    collision.clearKinematicDeltas();
  }

  /// Mechanisms by name, because that is what a level document gives them and
  /// what a door is called does not change between two runs of the same level.
  ///
  /// Anything unnamed is skipped — a relay wired between two others has no
  /// state worth carrying, and inventing a positional key for it would make the
  /// format depend on the order the spawner happened to walk the entities in.
  static Map<String, Object?> _saveMechanisms(MechanismWorld world) {
    final out = <String, Object?>{};
    for (final mechanism in world.all) {
      final name = mechanism.name;
      if (name == null) continue;
      switch (mechanism) {
        case final Mover mover:
          out[name] = mover.save();
        case final Pickup pickup:
          out[name] = pickup.save();
        case final Exit exit:
          out[name] = exit.save();
        default:
          break;
      }
    }
    return out;
  }

  void _restoreMechanisms(Object? from) {
    final world = mechanisms;
    if (world == null || from is! Map) return;
    for (final mechanism in world.all) {
      final name = mechanism.name;
      if (name == null) continue;
      final row = from[name];
      if (row is! Map) continue;
      final fields = row.cast<String, Object?>();
      switch (mechanism) {
        case final Mover mover:
          mover.restore(fields);
        case final Pickup pickup:
          pickup.restore(fields);
        case final Exit exit:
          exit.restore(fields);
        default:
          break;
      }
    }
    world.events.reached.clear();
  }

  void _hurtPlayer(double amount) {
    if (amount <= 0.0) return;
    player.applyDamage(amount);
    damageTakenThisStep += amount;
  }
}
