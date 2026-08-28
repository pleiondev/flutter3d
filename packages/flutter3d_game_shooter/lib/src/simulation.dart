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

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'actions.dart';
import 'combat/hit_zones.dart';
import 'combat/hitscan.dart';
import 'combat/projectile.dart';
import 'combat/weapon.dart';
import 'combat/weapon_behaviour.dart';
import 'player.dart';
import 'secret.dart';
import 'step_phases.dart';

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
  complete;

  /// The same answer in the words every game shares.
  RunOutcome get outcome => switch (this) {
    GameState.playing => RunOutcome.playing,
    GameState.dead => RunOutcome.lost,
    GameState.complete => RunOutcome.won,
  };
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
    this.dynamics,
    this.levelNext,
    required this.random,
    this.zones = const HitZones(),
  });

  /// What a shot is worth depending on where it lands.
  ///
  /// **Only what the player fires.** A monster's claw and a rocket's blast are
  /// deliberately even: a blast has no single point of contact worth talking
  /// about, and a game where a monster can headshot the player is a game where
  /// the damage a player takes depends on something they cannot see and did not
  /// choose. Aiming is the player's skill; being aimed at is not.
  final HitZones zones;

  final Player player;
  final CollisionWorld collision;

  /// The order the world is stepped in — see [WorldStep]. This game is where
  /// the order was argued out; the argument moved and the calls stayed.
  late final WorldStep _world = WorldStep(
    collision: collision,
    mechanisms: mechanisms,
    dynamics: dynamics,
  );
  final InputState input;

  /// All nullable: a game may have no doors, no monsters, no rockets and no
  /// weapons, and a simulation with none of them still runs. That is the same
  /// rule the entity registry follows — the package offers parts and the game
  /// says which of them it has.
  final MechanismWorld? mechanisms;
  final ActorSystem? actors;
  final ProjectileSystem? projectiles;
  final WeaponShot? shot;

  /// Crates, barrels and anything else with mass, or null for a game with
  /// none.
  final Dynamics? dynamics;

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

  /// What this level has been worth so far.
  ///
  /// **A shooter with nothing to show at the end of a level**, which is half of
  /// what the genre is: the walk to the exit is the game, and the three numbers
  /// on the way out are what say whether it was played or merely survived.
  ///
  /// Counted here rather than by the application, because the events it counts
  /// are this step's and are gone by the time a widget is asked to draw. Names
  /// rather than fields — see [Tally] — so a game that counts something else
  /// adds a line rather than a class.
  final Tally tally = Tally();

  /// Names this simulation counts under. Constants because a typo in one place
  /// and not the other is a counter that reads nought for ever.
  static const String kills = 'kills';
  static const String secrets = 'secrets';

  /// How many monsters this level started with, and how many secrets it holds.
  ///
  /// The other half of a count: three of five is a sentence and three is not.
  /// Read from the world at the first step rather than passed in, because the
  /// only thing that knows is what was actually spawned — a level that says it
  /// has four monsters and spawns three would otherwise be reported as
  /// unfinishable for ever.
  int get monsterCount => _monsterCount;
  int _monsterCount = 0;

  int get secretCount => _secretCount;
  int _secretCount = 0;

  bool _counted = false;

  /// Counts what the level holds, once, on the first step.
  void _countTheLevel() {
    if (_counted) return;
    _counted = true;
    _monsterCount = actors?.actors.length ?? 0;
    final doors = mechanisms;
    if (doors != null) {
      for (final mechanism in doors.all) {
        if (mechanism is Secret) _secretCount++;
      }
    }
  }

  /// Adds up the secrets entered this step.
  ///
  /// Read off the mechanisms rather than pushed by them, because a secret is a
  /// trigger and triggers report through a flag — the same shape everything
  /// else in the world uses, and the reason `publish` exists.
  void _countSecrets(MechanismWorld doors) {
    for (final mechanism in doors.all) {
      if (mechanism is Secret && mechanism.justFound) {
        tally.add(secrets);
        foundThisStep = mechanism;
      }
    }
  }

  /// The secret entered this step, for a message and a sound. Null on every
  /// other step, which is all of them.
  Secret? foundThisStep;

  /// What came of pressing the use key, or null if it was not pressed or
  /// reached nothing.
  ///
  /// Returned rather than pushed into `MechanismEvents.messages`, because
  /// `publish()` runs after the use key and would clear it.
  ActivationOutcome? usedThisStep;

  /// Where the entities live.
  ///
  /// Both systems that have moved across must share **one** world, or a save
  /// written from one of them silently leaves the other out. Passing two is a
  /// mistake with no symptom until a load, so it is a mistake with a sentence
  /// instead.
  EcsWorld? get entities {
    final mine = actors?.entities;
    final theirs = projectiles?.entities;
    if (mine != null && theirs != null && !identical(mine, theirs)) {
      throw StateError(
        'the actor system and the projectile system were given different '
        'EcsWorlds. One save cannot cover two worlds: build one and hand it '
        'to both.',
      );
    }
    return mine ?? theirs;
  }

  /// The generator every roll in this simulation comes out of.
  ///
  /// **It was optional, and the consequence was stated rather than hidden —
  /// which did not stop the shipped game from taking it.** `apps/flutter3d_demo_dungeon` built
  /// its world without one, so `save()` wrote no dice at all and every restored
  /// crypt diverged from the one that was saved at the first flinch roll. A
  /// documented trap is still a trap; what makes this one avoidable is that
  /// there is now no way to leave it out.
  ///
  /// Pass the same instance to [ActorSystem] and [Hitscan] — it is one object
  /// shared, not one each. Two generators are two sequences, and a snapshot
  /// records one of them.
  final GameRandom random;

  /// Rules this game adds to the step, which this package never heard of.
  ///
  /// **The plugin boundary for behaviour.** A game built on this genre gets a
  /// curse that ticks, a score that decays, a hazard nobody here imagined —
  /// without forking [step]. The phases it can hang them off are [ShooterPhases]
  /// plus the two every genre has; each is announced below at the point its name
  /// claims, and the order the announcements happen in is the order documented
  /// there and here, which is to say it is part of the contract.
  final StepSystems systems = StepSystems();

  final Vector3 _wish = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  /// Advances the world by one fixed step.
  void step(double dt) {
    firedThisStep = null;
    usedThisStep = null;
    damageTakenThisStep = 0.0;
    foundThisStep = null;
    hits.clear();
    // Last step's dead and hurt, forgotten here rather than inside
    // `ActorSystem.step` — which is halfway through this step, after the
    // player's own shot has already killed something. See
    // [ActorSystem.beginStep].
    this.actors?.beginStep();
    _countTheLevel();
    systems.run(StepPhase.begin, dt);

    final playing = _state == GameState.playing;

    if (playing) {
      player.look(input.lookDelta);
      player.moveWish(input.moveAxis, _wish);
      // Asked for every step rather than on an edge: standing up can be refused
      // by a ceiling, and a player who let go under a crawlspace has to keep
      // asking until there is room. See [Player.crouch].
      player.crouch(held: input.held(ShooterActions.crouch));
      _wish.scale(player.crouchThrottle);
      if (input.pressed(GameAction.jump)) player.body.requestJump();
    } else {
      // A dead player's input moves nothing. The world keeps going around
      // them, which is the difference between dying and the game freezing.
      _wish.setZero();
    }

    // The order this game worked out and the other two copied — see
    // [WorldStep], which holds the whole argument now, including which half of
    // it a test will catch and which half is reasoning said out loud.
    _world.movers(dt);
    _world.index(dt);

    player.body.step(
      dt,
      wishDirection: _wish,
      sprint: playing && !player.isCrouching && input.held(GameAction.sprint),
    );

    // After the player has moved, because what they shove depends on where
    // they ended up and how fast they got there.
    if (playing) {
      dynamics?.push(player.body.collider, player.body.velocity);
    }

    _world.settle();
    systems.run(ShooterPhases.afterPlayer, dt);

    final doors = mechanisms;
    if (doors != null) {
      if (playing && input.pressed(GameAction.use)) _use(doors);
      // Last, because the use key above can start a door: publishing before it
      // would report that door a step late, every time. It is why `WorldStep`
      // keeps this apart from `settle` instead of bundling the two.
      _world.publish();
      _readExits(doors);
      _countSecrets(doors);
    }
    // Announced whether or not this level has mechanisms: a phase that exists
    // only when the level happens to have a door is a phase nobody can rely on.
    systems.run(ShooterPhases.afterWorld, dt);

    player.inventory.step(dt);
    if (playing) _weapon(dt);

    // **A shot is a noise, and until now nothing in the level could tell.** A
    // monster noticed being seen or being hit and nothing else, so a player
    // could empty a shotgun in the next room and walk in on something still
    // asleep. Reported before the actors think, so the ones that heard it are
    // already moving on the step it happened.
    final actors = this.actors;
    final fired = firedThisStep;
    if (fired != null && actors != null) {
      if (fired.loudness > 0.0) {
        actors.hear(firedFrom, radius: fired.loudness);
      }
    }
    systems.run(ShooterPhases.afterWeapons, dt);

    if (actors != null && player.isAlive) {
      player.eye(_eye);
      actors.step(dt, focus: _eye, focusBody: player.body.collider);
      _hurtPlayer(actors.damageToFocusThisStep);
      // Counted where the news is, which is the step it happened on: `died` is
      // cleared at the top of the next one.
      if (actors.died.isNotEmpty) tally.add(kills, actors.died.length);
    }
    systems.run(ShooterPhases.afterActors, dt);

    // After the weapon, so a rocket fired this step is not moved until the
    // next one — otherwise it starts the game already a step down the corridor.
    final projectiles = this.projectiles;
    if (projectiles != null) {
      projectiles.step(dt);
      for (final blast in projectiles.detonations) {
        // Who fired it, as whatever that body is: a monster's rocket landing
        // among its own is how a crowd turns on itself, and a blast with no
        // owner — one that timed out in the open — has nobody to blame.
        final firedBy = blast.owner?.userData;
        for (final entry in blast.damage.entries) {
          final target = entry.key.userData;
          if (target is! Damageable) continue;
          target.applyDamage(entry.value, from: firedBy);
          if (identical(target, player)) damageTakenThisStep += entry.value;
        }
      }
    }

    if (_state == GameState.playing && !player.isAlive) {
      _state = GameState.dead;
    }
    // Last, after the state is resolved, so a system reading `state` reads this
    // step's answer rather than the previous one's.
    systems.run(StepPhase.end, dt);
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
    // Before the shot, not after: the kick from this shot must not move the
    // shot that is about to leave, or a single tap would fire high.
    //
    // Empty hands settle at the ordinary rate: a player who has just run out
    // still has a sight to bring back down, and `Arsenal.current` throws rather
    // than inventing a weapon to ask.
    player.settleRecoil(
      dt,
      perSecond: arsenal.isEmpty ? 7.0 : arsenal.current.recoilRecovery,
    );

    final slot = input.slotRequest;
    if (slot != null) arsenal.selectSlot(slot);

    final shot = this.shot;
    if (shot != null &&
        arsenal.wantsToFire(
          held: input.held(ShooterActions.fire),
          pressed: input.pressed(ShooterActions.fire),
        )) {
      final weapon = arsenal.fire();
      if (weapon != null) {
        _fire(shot, weapon);
        // After the shot has left. A burst climbs because this is applied ten
        // times a second and only pulled back at the weapon's own recovery.
        player.kick(weapon.recoil);
      }
    }

    // Only when the trigger is idle: switching weapons out from under a player
    // who is mid-burst because one shot emptied the magazine is worse than
    // letting them notice.
    if (!input.held(ShooterActions.fire)) arsenal.fallBackIfEmpty();
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
    for (final entry in Hitscan.damageByTarget(
      hits,
      scale: (ShotHit hit) => zones.forHitOn(hit.collider?.userData, hit.point),
    ).entries) {
      final target = entry.key.userData;
      // The player did this one, which is what stops a monster shot by them
      // from turning on the monster next to it.
      if (target is Damageable) target.applyDamage(entry.value, from: player);
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
    'random': random.state,
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
    if (seed is num) random.state = seed.toInt();

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
    // Health came back on a component; whether a body is solid is a fact about
    // the collision world, and something has to put the two together.
    actors?.syncCorpses();

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
  /// Every named mechanism, each answering for itself.
  ///
  /// This used to be a `switch` over three types, and the note beside it called
  /// that out as the remaining debt of the ECS migration: a new mechanism was
  /// silently unsaved. `Mechanism.save` is abstract now, so there is nothing to
  /// forget — and the two lamps and the trigger volumes this game already had
  /// were among the things being forgotten.
  static Map<String, Object?> _saveMechanisms(MechanismWorld world) =>
      <String, Object?>{
        for (final mechanism in world.all)
          if (mechanism.name != null) mechanism.name!: mechanism.save(),
      };

  void _restoreMechanisms(Object? from) {
    final world = mechanisms;
    if (world == null || from is! Map) return;
    for (final mechanism in world.all) {
      final name = mechanism.name;
      if (name == null) continue;
      final row = from[name];
      if (row is! Map) continue;
      mechanism.restore(row.cast<String, Object?>());
    }
    world.events.reached.clear();
  }

  void _hurtPlayer(double amount) {
    if (amount <= 0.0) return;
    player.applyDamage(amount);
    damageTakenThisStep += amount;
  }
}
