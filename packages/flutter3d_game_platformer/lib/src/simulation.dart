import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'blocks.dart';
import 'checkpoint.dart';
import 'collectible.dart';
import 'events.dart';
import 'runner.dart';

/// Where the run is.
enum RunState {
  /// Being played.
  running,

  /// The runner is dead and waiting to be put back. One step, usually.
  fallen,

  /// The exit was reached.
  finished,

  /// The lives ran out. The run is over and the level starts again.
  ///
  /// Distinct from [finished] because they are opposite outcomes that a game
  /// has to show differently, and distinct from [fallen] because that one is
  /// one step long and this one waits for the player.
  lost;

  /// The same answer in the words every game shares. `fallen` is still
  /// [RunOutcome.playing]: it is one step of a run that is going on, not an
  /// outcome — a runner who has just died has not lost until the lives do.
  RunOutcome get outcome => switch (this) {
    RunState.running || RunState.fallen => RunOutcome.playing,
    RunState.lost => RunOutcome.lost,
    RunState.finished => RunOutcome.won,
  };
}

/// A platformer's step, in the order it has to happen in.
///
/// The sibling of `GameSimulation` in `flutter3d_game_shooter`, and the reason that
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
    this.lives = -1,
    this.deaths = 0,
    this.elapsed = 0.0,
    this.levelNext,
    required this.random,
    this.killPlane = -20.0,
  }) : _respawn = startAt.clone() {
    // One generator, or the number in the save is a decoy. The dice this
    // simulation writes down were its own while the dice that actually decide
    // what the enemies do were the actor system's, so a restored run replayed
    // with a seed nothing was rolling from. The shooter asserts the same thing
    // about its ECS world and for the same reason.
    assert(
      actors == null || identical(actors!.random, random),
      'the ActorSystem must roll the same GameRandom this simulation saves, '
      'or the seed in the snapshot describes dice nobody is using.',
    );
  }

  final Runner runner;
  final CollisionWorld collision;

  /// The order the world is stepped in, which three games had written out — see
  /// [WorldStep]. What is left in `step` below is this game's own half.
  late final WorldStep _world = WorldStep(
    collision: collision,
    mechanisms: mechanisms,
    dynamics: dynamics,
  );
  final InputState input;
  final MechanismWorld? mechanisms;
  final Dynamics? dynamics;

  /// The things that move on their own, or null for a level with none.
  ///
  /// Built by the application since this package existed and **never stepped**,
  /// which is why there were no enemies: the system was there, the brains were
  /// there, and nothing called them.
  final ActorSystem? actors;

  /// Randomness, shared so that a snapshot can carry where the dice were.
  ///
  /// **Required, and it used to default to `GameRandom(1)`.** The shooter made
  /// this required after its shipped game took the default and saved dice
  /// nobody was rolling; the same trap was still sitting here, one package
  /// over, with the added twist that nothing in this package rolled it at all —
  /// the generator that decides what the enemies do belongs to [actors], and
  /// the constructor now asserts the two are the same object. A default is how
  /// a caller takes a decision without making one.
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

  /// How many deaths this run has left. Negative means the run cannot be lost.
  ///
  /// A count rather than a flag, because "three lives" is the shortest sentence
  /// a player understands about consequence — and one that starts negative is
  /// how a teaching level says "not here".
  ///
  /// **Negative by default**, so nothing that existed before this counts down:
  /// a package whose default is three lives is a package that silently ends
  /// every test that dies three times. The game sets the number; the genre only
  /// knows how to count it.
  int lives;

  /// How many falls this **run** has cost, which is not the same as this level.
  ///
  /// Arguments rather than always starting at nought, because a run spans levels
  /// and a simulation does not: only the application knows what the level after
  /// this one is, so only the application can carry the tally across. It used to
  /// start fresh every time, which made three lives mean three lives *per level*
  /// and the clock on the summit read as the time for the last climb.
  /// How many times the runner has died. A score, and a test's favourite number.
  int deaths;

  /// How long this run has been played, in seconds.
  ///
  /// Simulated time and not wall-clock: it is the sum of the steps, so it does
  /// not run while the game is paused, does not jump when a frame is slow, and
  /// is the same number for the same play on any machine. A timer read off the
  /// clock is a timer that punishes a player whose laptop stuttered.
  ///
  /// Given at construction for the same reason [deaths] is: a run spans levels.
  double elapsed;

  /// What this step did, for a game that wants to hear about it.
  ///
  /// Drain it after [step]; see `events.dart`. The `…ThisStep` members below
  /// say the same things and are kept for now, because programs read them.
  final GameEvents events = GameEvents();






  /// Damage a second from standing against an enemy.
  ///
  /// A rate rather than a lump, exactly as a hazard's is, and for the same
  /// reason: what matters is how long you are in the wrong place.
  double actorDamage = 60.0;

  void step(double dt) {
    // The dead and the hurt, forgotten here with everything else this step
    // reports — see [ActorSystem.beginStep] for why it is not `step`'s job.
    actors?.beginStep();

    if (state == RunState.finished || state == RunState.lost) return;

    if (state == RunState.fallen) {
      _revive();
      return;
    }

    elapsed += dt;

    _world.movers(dt);

    // Actors with the movers and **before the broadphase catches up**: an actor
    // that has moved and not been reindexed is one the runner's sweep finds in
    // last step's place, which is a patrol you can walk through half the time.
    // The shooter puts them at the other end of the step, and `WorldStep` says
    // why neither is wrong.
    actors?.step(dt, focus: runner.position, focusBody: runner.body.collider);

    _world.index(dt);

    runner.step(dt, input, cameraYaw: cameraYaw);

    // Intent, not residual velocity — see [Runner.shove].
    dynamics?.push(runner.body.collider, runner.shove);

    _readFloor();
    _readActors(dt);

    // Overlaps dispatch, and then the machinery is asked what it did — see
    // `WorldStep.settle`, which carries the reason both of those are here and
    // in this order.
    _world.settle();
    _world.publish();

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
    events.add(const RunnerDied());
    if (lives > 0) {
      lives -= 1;
      if (lives == 0) {
        // Out of lives: the run is over where it stands. Reviving first and
        // *then* ending it would put the runner back at a checkpoint they are
        // never going to play from, which reads as the game ignoring the death.
        state = RunState.lost;
        return;
      }
    }
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
        events.add(EnemyStomped(actor));
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
      if (mechanism.justReached) {
        events.add(CheckpointReached(mechanism));
      }
      if (best == null || mechanism.order > best.order) best = mechanism;
    }
    if (best != null) _respawn.setFrom(best.at);
  }

  void _readCollectibles() {
    final events = mechanisms?.events;
    if (events == null) return;
    for (final taken in events.taken) {
      if (taken is Collectible) this.events.add(CollectibleTaken(taken));
    }
    // Whatever the level said. Published here rather than in its own reader
    // because it comes off the same event object, gathered by the same
    // `publish()` two lines up — and reading it before that call is how it
    // stayed empty the first time this was written.
    for (final message in events.messages) {
      this.events.add(LevelSaid(message));
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
    'lives': lives,
    'elapsed': elapsed,
    // **Keyed by name, and a mechanism without one is not saved** — see
    // `MechanismWorld.save`, which is where the rule and the paragraph
    // explaining it now live, because this game and the shooter had written
    // out the same eight lines and the racing game had written none.
    if (mechanisms != null) 'mechanisms': mechanisms!.save(),
    // **The enemies, which this save did not carry at all.** The system is
    // real and stepped, so a save taken after clearing a room came back with
    // every enemy alive again at its spawn — health, position, brain and all
    // — while the runner's own progress restored correctly. Nothing caught it:
    // the snapshot test in this package never mentioned actors.
    if (actors != null) 'entities': actors!.entities.save(),
    if (actors != null) 'actors': actors!.save(),
  });

  void restore(Snapshot from) {
    final data = from.data;
    final saved = data['runner'];
    if (saved is Map<String, Object?>) runner.restore(saved);
    final seed = data['random'];
    if (seed is num) random.state = seed.toInt();
    state = data.enumOf('state', RunState.values, RunState.running);
    // Through the reader rather than by hand: this one used to cast each
    // component with `as num`, which throws on a save holding anything else
    // where a number belongs — the same strictness the shooter's projectiles
    // had, in the one document that must never refuse to load.
    data.vectorInto('respawn', _respawn);
    final died = data['deaths'];
    if (died is num) deaths = died.toInt();
    final left = data['lives'];
    if (left is num) lives = left.toInt();
    final played = data['elapsed'];
    if (played is num) elapsed = played.toDouble();

    mechanisms?.restore(data['mechanisms']);

    final savedEntities = data.object('entities');
    if (actors != null && savedEntities != null) {
      actors!.entities.restore(savedEntities);
    }
    actors?.restore(data['actors']);
    // Health came back on a component; whether a body is solid is a fact about
    // the collision world, and something has to put the two together. Without
    // it a restored corpse is a wall the runner cannot walk through.
    actors?.syncCorpses();

    _world.afterRestore();
  }
}
