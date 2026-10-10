import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'blocks.dart';
import 'checkpoint.dart';
import 'collectible.dart';
import 'events.dart';
import 'runner.dart';
import 'spring.dart';
import 'water.dart';

/// Where the run is.
///
/// **A class with constants, not an enum** (1.0): a state this genre adds in a
/// minor release is a new constant, not a break in every exhaustive `switch`
/// over the old four. A `switch` over it keeps a default case; [outcome] is the
/// answer every game shares and is exhaustive.
final class RunState {
  const RunState._(this.name, this.outcome);

  /// Being played.
  static const RunState running = RunState._('running', RunOutcome.playing);

  /// The runner is dead and waiting to be put back. One step, usually.
  ///
  /// Still [RunOutcome.playing]: it is one step of a run that is going on,
  /// not an outcome — a runner who has just died has not lost until the
  /// lives do.
  static const RunState fallen = RunState._('fallen', RunOutcome.playing);

  /// The exit was reached.
  static const RunState finished = RunState._('finished', RunOutcome.won);

  /// The lives ran out. The run is over and the level starts again.
  ///
  /// Distinct from [finished] because they are opposite outcomes that a game
  /// has to show differently, and distinct from [fallen] because that one is
  /// one step long and this one waits for the player.
  static const RunState lost = RunState._('lost', RunOutcome.lost);

  /// Every state, in the order they were declared.
  static const List<RunState> values = <RunState>[
    running,
    fallen,
    finished,
    lost,
  ];

  /// The state called [name] in a snapshot, or null for one this build does
  /// not know.
  static RunState? byName(Object? name) =>
      values.where((RunState it) => it.name == name).firstOrNull;

  /// The word a snapshot writes for it.
  final String name;

  /// The same answer in the words every game shares.
  final RunOutcome outcome;

  @override
  String toString() => 'RunState.$name';
}

/// The moments inside a platformer's step that a game can hang its own rules
/// off, beside the two every genre has ([StepPhase.begin], [StepPhase.end]).
abstract final class PlatformerPhases {
  /// The runner has read its input, moved, swept the world and been pushed:
  /// where a rule that changes how the runner moves — a wind, a current, a
  /// replacement controller writing the body itself — belongs. The overlaps
  /// it causes are dispatched after it.
  static const StepPhase afterRunner = StepPhase('platformer.afterRunner');
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
    Difficulty difficulty = Difficulty.normal,
  }) : _respawn = startAt.clone() {
    runner.difficulty = difficulty;
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
  final RigidDynamics? dynamics;

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
  /// In metres.
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

  EventRegistry? _bus;

  /// Publishes what each step does onto [bus] from now on — see
  /// `events.dart` — until the returned registration is cancelled.
  /// `PlatformerPlugin` calls it for the run it steps; a test or a tool that
  /// steps the run by hand hands it a `DirectBus`. With no bus named, the
  /// events go nowhere, which is the normal case for a headless run.
  ///
  /// Handed down to the runner and the actors rather than collected up,
  /// which is what makes the order real: the runner's landing and the block
  /// that gave way under it are published one after the other, in the order
  /// the step produced them, on the step channel. The `…ThisStep` members
  /// below say the same things and are kept for now, because programs read
  /// them.
  Registration publishTo(EventRegistry bus) {
    _bus = bus;
    runner.events = bus;
    actors?.events = bus;
    return Registration(() {
      if (!identical(_bus, bus)) return;
      _bus = null;
      if (identical(runner.events, bus)) runner.events = null;
      if (identical(actors?.events, bus)) actors?.events = null;
    });
  }

  void _publish(GameEvent event) => _bus?.publish(event);

  /// Rules a game adds to the step, by phase: [StepPhase.begin], the runner's
  /// moment [PlatformerPhases.afterRunner], and [StepPhase.end].
  ///
  /// **Where a game replaces or extends what the runner does without editing
  /// the genre's step.** The step's order is the genre's and a tape replays
  /// it, so a rule is hung at a named moment inside it rather than wrapped
  /// round it. Run only while the world moves: a finished, lost or fallen
  /// run's step runs none of them.
  final StepSystems systems = StepSystems();

  /// What is running on the runner, and for how much longer.
  ///
  /// **The genre had none**, while the shooter has had them since it was
  /// written: a shield, a magnet, a pair of wings are the same bookkeeping the
  /// crypt does for berserk, and a platformer without any is a platformer
  /// whose collectibles are all worth the same thing. Counted down here so a
  /// level can hand one out and nothing else has to remember.
  ///
  /// What a power *does* is the game's: this counts, and a game asks
  /// [Powers.has] where it matters. See `doc/boundary-0.5.0.md` on why the
  /// names are not an enum.
  final Powers powers = Powers();

  /// What this run is worth, and the chain the runner is holding.
  ///
  /// **The purse counted and nothing scored.** Coins were a number that went
  /// up, so a level had one way to reward a player and no way to reward a
  /// player who was good — which is the whole of what a platformer's scoring
  /// is for. A chain of collectibles taken close together is worth more than
  /// the same collectibles taken slowly, and it breaks on a death.
  ///
  /// What a coin is worth is the game's; this only multiplies and counts.
  final Scoring scoring = Scoring();

  /// Damage a second from standing against an enemy.
  ///
  /// A rate rather than a lump, exactly as a hazard's is, and for the same
  /// reason: what matters is how long you are in the wrong place.
  double actorDamage = 60.0;

  /// State the run's snapshot carries beside the simulation's own, by name:
  /// a level's water and fires, which the game steps in its own phase.
  ///
  /// **A hook rather than a wrapper.** The elements used to ride inside the
  /// run's dynamics, saved and stepped as if they were bodies, which put
  /// them in the middle of [step] where nothing could see or order them.
  /// Now whatever steps beside the simulation hands its save and its restore
  /// here, and [save] writes each under `parts`, by name, in the order they
  /// were added; [restore] hands each its own back after the bodies'. A part
  /// whose name the save does not hold is handed null.
  final Map<String, PlatformerSnapshotPart> parts =
      <String, PlatformerSnapshotPart>{};

  /// Whether the last [step] moved the world: false for a step that only
  /// counted down a finished, lost or fallen run.
  ///
  /// What a game stepping its own state beside this one asks, so that state
  /// stands still exactly when the world does — a level's water does not
  /// flow on behind the summary screen, nor during the step that puts a
  /// fallen runner back.
  bool get didMoveThisStep => _moved;
  bool _moved = false;

  void step(double dt) {
    _moved = false;
    // The dead and the hurt, forgotten here with everything else this step
    // reports — see [ActorSystem.beginStep] for why it is not `step`'s job.
    actors?.beginStep();
    for (final String ended in powers.step(dt)) {
      _publish(PowerEnded(ended));
    }
    final lapsed = scoring.advance(dt);
    if (lapsed != null) _publish(ChainEnded(lapsed));

    if (state == RunState.finished || state == RunState.lost) return;

    if (state == RunState.fallen) {
      _revive();
      return;
    }

    elapsed += dt;
    _moved = true;
    systems.run(StepPhase.begin, dt);

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
    systems.run(PlatformerPhases.afterRunner, dt);

    _readFloor();
    _readActors(dt);

    // Overlaps dispatch, and then the machinery is asked what it did — see
    // `WorldStep.settle`, which carries the reason both of those are here and
    // in this order.
    _world.settle();
    _world.publish();

    _readWater();
    _readCheckpoints();
    _readCollectibles();
    _readExits();

    if (state != RunState.finished &&
        (runner.position.y < killPlane || runner.health.isDead)) {
      state = RunState.fallen;
    }
    systems.run(StepPhase.end, dt);
  }

  void _revive() {
    deaths += 1;
    _publish(const RunnerDied());
    // A death breaks the chain, whatever is left on its clock. A run that
    // survived dying would be a run nobody had to protect.
    final lost = scoring.breakChain();
    if (lost != null) _publish(ChainEnded(lost));
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
    if (under is Crumbling) under.bearWeight();
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
        _publish(EnemyStomped(actor));
        runner.bounce();
      } else {
        runner.applyDamage(actorDamage * dt);
      }
    }
  }

  /// Tells the runner which pool it is in, if any.
  ///
  /// **The chest, not the feet.** A capsule whose toes are wet is walking
  /// through a puddle and a capsule whose middle is under is swimming, and
  /// the difference is the whole of what makes a shallow stream different
  /// from a lake.
  void _readWater() {
    final all = mechanisms?.all;
    if (all == null) {
      runner.inWater = null;
      return;
    }
    final chest = runner.position;
    for (final mechanism in all) {
      if (mechanism is Water && mechanism.holds(chest)) {
        runner.inWater = mechanism;
        return;
      }
    }
    runner.inWater = null;
  }

  void _readCheckpoints() {
    final all = mechanisms?.all;
    if (all == null) return;
    Checkpoint? best;
    for (final mechanism in all) {
      if (mechanism is! Checkpoint || !mechanism.isReached) continue;
      if (mechanism.justReached) {
        _publish(CheckpointReached(mechanism));
      }
      if (best == null || mechanism.order > best.order) best = mechanism;
    }
    if (best != null) _respawn.setFrom(best.at);
  }

  void _readCollectibles() {
    final events = mechanisms?.events;
    if (events == null) return;
    for (final taken in events.taken) {
      if (taken is! Collectible) continue;
      // Worth what the collectible says, multiplied by the run in hand — so a
      // sweep through a line of coins pays more than the same coins picked up
      // one at a time, which is the only thing a chain is for.
      final scored = scoring.score(taken.worth);
      _publish(CollectibleTaken(taken, scored));
    }
    // Whatever the level said. Published here rather than in its own reader
    // because it comes off the same event object, gathered by the same
    // `publish()` two lines up — and reading it before that call is how it
    // stayed empty the first time this was written.
    for (final message in events.messages) {
      _publish(LevelSaid(message));
    }
  }

  void _readExits() {
    final all = mechanisms?.all;
    if (all == null) return;
    for (final mechanism in all) {
      // The level's furniture, reported here because this is the pass that
      // already walks it. See [FurnitureEvent] for what that costs.
      switch (mechanism) {
        case Spring() when mechanism.firedThisStep:
          _publish(SpringFired(mechanism.origin));
        case Crumbling() when mechanism.crumbledThisStep:
          _publish(BlockCrumbled(mechanism.origin));
        case Breakable() when mechanism.brokeThisStep:
          _publish(BlockBroke(mechanism.origin));
      }
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
    // What the dynamics carry beyond the bodies: nothing for the reference,
    // the core's own state for the native one, without which a rewind
    // stepped on from this snapshot would not repeat the run.
    'dynamics': ?dynamics?.saveState(),
    if (parts.isNotEmpty)
      'parts': <String, Object?>{
        for (final MapEntry(:key, :value) in parts.entries) key: value.save(),
      },
  });

  void restore(Snapshot from) {
    final data = from.data;
    final saved = data['runner'];
    if (saved is Map<String, Object?>) runner.restore(saved);
    final seed = data['random'];
    if (seed is num) random.state = seed.toInt();
    state = RunState.byName(data['state']) ?? RunState.running;
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

    // After the bodies' own restore, which it puts the core's state over.
    final savedParts = data.object('parts');
    switch (data['dynamics']) {
      // A save from before [parts]: the demo's elements rode in the
      // dynamics, saved beside the bodies under these two keys. Read as they
      // were written, the elements' half handed to the part of that name.
      case {'bodies': final Object? bodies, 'elements': final Object? e}
          when savedParts == null:
        dynamics?.restoreState(bodies);
        parts['elements']?.restore(e);
      case final Object? saved:
        dynamics?.restoreState(saved);
        for (final MapEntry(:key, :value) in parts.entries) {
          value.restore(savedParts?[key]);
        }
    }

    _world.afterRestore();
  }
}

/// One named share of a run's snapshot that is not the simulation's own:
/// how to write it, and how to put a written one back. See
/// [PlatformerSimulation.parts].
typedef PlatformerSnapshotPart = ({
  Object? Function() save,
  void Function(Object? saved) restore,
});
