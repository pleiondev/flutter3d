import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'blocks.dart';
import 'checkpoint.dart';
import 'collectible.dart';
import 'runner.dart';

/// Where the run is.
enum RunState {
  /// Being played.
  running,

  /// The runner is dead and waiting to be put back. One step, usually.
  fallen,

  /// The exit was reached.
  finished,
}

/// A platformer's step, in the order it has to happen in.
///
/// The sibling of `GameSimulation` in `flutter3d_shooter`, and the reason that
/// one had to leave the engine: its step reads a weapon, an arsenal, a use key
/// and an exit, and four of those five mean nothing here. What the two share is
/// the *order* — mechanisms move, the broadphase catches up, dynamics run, the
/// body sweeps, overlaps dispatch — and the order is documented in both because
/// it is the part that is easy to get wrong and impossible to see.
final class PlatformerSimulation {
  PlatformerSimulation({
    required this.runner,
    required this.collision,
    required this.input,
    required Vector3 startAt,
    this.mechanisms,
    this.dynamics,
    this.actors,
    this.levelNext,
    GameRandom? random,
    this.killPlane = -20.0,
  })  : random = random ?? GameRandom(1),
        _respawn = startAt.clone();

  final Runner runner;
  final CollisionWorld collision;
  final InputState input;
  final MechanismWorld? mechanisms;
  final Dynamics? dynamics;

  /// The things that move on their own, or null for a level with none.
  ///
  /// Built by the application since this package existed and **never stepped**,
  /// which is why there were no enemies: the system was there, the brains were
  /// there, and nothing called them.
  final ActorSystem? actors;
  final GameRandom random;

  /// What the application says the level goes on to, passed through unread.
  final String? levelNext;

  /// The height below which there is no level left.
  ///
  /// A platformer needs this and a shooter does not, because a shooter's floor
  /// is continuous and a platformer's is the interesting part. Without it a
  /// player who misses a jump falls at terminal velocity forever and the game
  /// looks hung rather than lost.
  final double killPlane;

  /// Where the camera is looking, written by the application before each step.
  ///
  /// Zero in a headless test, which then gets world axes — see [Runner.step].
  double cameraYaw = 0.0;

  RunState state = RunState.running;
  String? nextLevel;

  final Vector3 _respawn;

  /// Where a death puts the runner back: **the feet**, as a level authors it.
  ///
  /// Every point that crosses this seam — the player spawn, a checkpoint's
  /// `respawn`, this — is a place on the floor rather than the middle of a
  /// body. [Runner.reviveAt] is the one place that converts.
  Vector3 get respawnPoint => _respawn;

  /// How many times the runner has died. A score, and a test's favourite number.
  int deaths = 0;

  /// Collectibles taken on this step, for a sound and a counter.
  final List<Collectible> takenThisStep = <Collectible>[];

  /// True on the step a checkpoint was reached for the first time.
  bool reachedCheckpointThisStep = false;

  /// True on the step the runner landed on something and killed it.
  bool stompedThisStep = false;

  /// Damage a second from standing against an enemy.
  ///
  /// A rate rather than a lump, exactly as a hazard's is, and for the same
  /// reason: what matters is how long you are in the wrong place.
  double actorDamage = 60.0;

  void step(double dt) {
    takenThisStep.clear();
    reachedCheckpointThisStep = false;
    stompedThisStep = false;

    if (state == RunState.finished) return;

    if (state == RunState.fallen) {
      _revive();
      return;
    }

    // Doors and lifts move, and the broadphase learns where they are, before
    // the runner sweeps against them. The same order and the same reason as
    // the shooter's; a mover that has not been reindexed is a mover the sweep
    // finds in last step's place.
    mechanisms?.step(dt);

    // Actors after the movers and **before the broadphase catches up**, for the
    // same reason and with the same consequence: an actor that has moved and
    // not been reindexed is an actor the runner's sweep finds in last step's
    // place, which is a patrol you can walk through half the time.
    actors?.step(dt, focus: runner.position, focusBody: runner.body.collider);

    collision.reindex();
    dynamics?.step(dt);

    runner.step(dt, input, cameraYaw: cameraYaw);

    // Intent, not residual velocity — see [Runner.shove].
    dynamics?.push(runner.body.collider, runner.shove);

    _readFloor();
    _readActors(dt);

    // Overlaps dispatch here: collectibles are taken, hazards bite, checkpoints
    // light up. All three run from inside this call, which is why each of them
    // reports through a flag rather than returning anything.
    collision.update();
    collision.clearKinematicDeltas();

    // What the machinery did this step, asked for rather than assumed. Without
    // this the events are the empty lists they were initialised with, and every
    // consequence read out of them — the coin sound, a trigger's message —
    // silently never happens, while the purse fills up and the door opens. The
    // shooter's step ends with the same call for the same reason.
    mechanisms?.publish();

    _readCheckpoints();
    _readCollectibles();
    _readExits();

    if (state == RunState.finished) return;

    if (runner.position.y < killPlane || runner.health.isDead) {
      state = RunState.fallen;
    }
  }

  void _revive() {
    deaths += 1;
    runner.reviveAt(_respawn);
    // The broadphase is holding the runner where they died.
    collision.reindex();
    state = RunState.running;
  }

  /// What the runner's weight and its landing do to the floor.
  ///
  /// Read from `body.ground` rather than from an overlap, and that is the
  /// distinction the two mechanisms are built around: brushing the side of a
  /// crumbling platform is not standing on it, and a ground pound that broke a
  /// block beside the one it hit would be a pound nobody could aim.
  void _readFloor() {
    final under = runner.body.ground?.userData;
    if (under is Crumbling) under.takeWeight();
    if (runner.poundedThisStep && under is Breakable) under.shatter();
  }

  /// Landing on an enemy, and walking into one.
  ///
  /// The whole of a platformer's combat, and the asymmetry *is* the design:
  /// from above you win, from the side you lose. Everything else — a health
  /// bar, a weapon, a hit reaction — is a different genre's answer.
  ///
  /// Read from overlap rather than from a trigger volume, because an actor's
  /// body is solid: the runner never enters it, it stops against it, and a
  /// trigger would have to be a second collider kept in step with the first.
  void _readActors(double dt) {
    final system = actors;
    if (system == null) return;
    if (!runner.health.isAlive) return;

    final body = runner.body;
    final mine = body.halfExtents;

    for (final actor in system.actors) {
      if (!actor.isAlive) continue;
      final theirs = actor.body;
      if (theirs == null) continue;

      final where = actor.position;
      if (where == null) continue;
      final apart = where - body.position;
      // A skin, because two solid bodies never overlap: the controller stops
      // one against the other and they come to rest exactly touching, where the
      // overlap is zero and a strict test says they are not in contact. Without
      // it an enemy pressed against the player did nothing at all, which is
      // what the first run of these tests reported.
      const touching = 0.06;
      if (mine.x + theirs.halfExtents.x + touching - apart.x.abs() <= 0.0) {
        continue;
      }
      if (mine.z + theirs.halfExtents.z + touching - apart.z.abs() <= 0.0) {
        continue;
      }
      if (mine.y + theirs.halfExtents.y - apart.y.abs() <= -0.15) continue;

      // **Feet against the top of its head, not centre against centre.** The
      // first version compared centres with a margin, which is true whenever
      // the runner is simply the taller of the two — so walking into a
      // waist-high guard counted as landing on it and the game had no way to
      // lose. A stomp is the feet arriving at or above the crown, on the way
      // down.
      final feet = body.position.y - mine.y;
      final crown = where.y + theirs.halfExtents.y;
      final onTop = feet >= crown - 0.25 && body.velocity.y <= 0.5;

      if (onTop) {
        system.hurt(actor, double.infinity);
        stompedThisStep = true;
        runner.bounce();
      } else {
        runner.applyDamage(actorDamage * dt);
      }
    }
  }

  void _readCheckpoints() {
    final all = mechanisms?.all;
    if (all == null) return;
    Checkpoint? best;
    for (final mechanism in all) {
      if (mechanism is! Checkpoint || !mechanism.isReached) continue;
      if (mechanism.justReached) reachedCheckpointThisStep = true;
      if (best == null || mechanism.order > best.order) best = mechanism;
    }
    if (best != null) _respawn.setFrom(best.at);
  }

  void _readCollectibles() {
    final events = mechanisms?.events;
    if (events == null) return;
    for (final taken in events.taken) {
      if (taken is Collectible) takenThisStep.add(taken);
    }
  }

  void _readExits() {
    final all = mechanisms?.all;
    if (all == null) return;
    for (final mechanism in all) {
      if (mechanism is Exit && mechanism.isReached) {
        state = RunState.finished;
        nextLevel = mechanism.next ?? levelNext;
        return;
      }
    }
  }

  Snapshot save() => Snapshot(<String, Object?>{
        'runner': runner.save(),
        'random': random.state,
        'state': state.name,
        'respawn': <double>[_respawn.x, _respawn.y, _respawn.z],
        'deaths': deaths,
        'mechanisms': <String, Object?>{
          for (final mechanism in mechanisms?.all ?? const <Mechanism>[])
            if (mechanism.name != null) mechanism.name!: _saveMechanism(mechanism),
        },
      });

  void restore(Snapshot from) {
    final data = from.data;
    final saved = data['runner'];
    if (saved is Map<String, Object?>) runner.restore(saved);
    final seed = data['random'];
    if (seed is num) random.state = seed.toInt();
    state = RunState.values.firstWhere(
      (RunState s) => s.name == data['state'],
      orElse: () => RunState.running,
    );
    final at = data['respawn'];
    if (at is List && at.length >= 3) {
      _respawn.setValues(
        (at[0] as num).toDouble(),
        (at[1] as num).toDouble(),
        (at[2] as num).toDouble(),
      );
    }
    final died = data['deaths'];
    if (died is num) deaths = died.toInt();

    final saves = data['mechanisms'];
    if (saves is Map<String, Object?>) {
      for (final mechanism in mechanisms?.all ?? const <Mechanism>[]) {
        final name = mechanism.name;
        if (name == null) continue;
        final row = saves[name];
        if (row is Map<String, Object?>) _restoreMechanism(mechanism, row);
      }
    }

    collision.reindex();
    collision.update();
    collision.clearKinematicDeltas();
  }

  /// Saves what a mechanism holds, if it holds anything.
  ///
  /// A switch over types, and it is the same one `GameSimulation.save` has —
  /// which the shooter's own notes already call out as the remaining debt of
  /// the ECS migration: a new mechanism is silently unsaved. Stated here rather
  /// than repeated silently, because this package inherits the debt rather than
  /// inventing it.
  static Map<String, Object?>? _saveMechanism(Mechanism mechanism) =>
      switch (mechanism) {
        Collectible() => mechanism.save(),
        Checkpoint() => mechanism.save(),
        Crumbling() => mechanism.save(),
        Breakable() => mechanism.save(),
        Mover() => mechanism.save(),
        _ => null,
      };

  static void _restoreMechanism(Mechanism mechanism, Map<String, Object?> row) {
    switch (mechanism) {
      case Collectible():
        mechanism.restore(row);
      case Checkpoint():
        mechanism.restore(row);
      case Crumbling():
        mechanism.restore(row);
      case Breakable():
        mechanism.restore(row);
      case Mover():
        mechanism.restore(row);
      default:
        break;
    }
  }
}
