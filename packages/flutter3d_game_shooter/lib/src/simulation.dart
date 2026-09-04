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
/// looked like, through [events] — see `events.dart`. It used to be through a
/// field for each kind of moment, one of each per step; those are gone, and
/// what replaced them can carry two of anything and says what order it was in.
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
import 'events.dart';
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
    this.difficulty = Difficulty.normal,
  }) {
    // Handed down rather than collected up, which is what makes the order real:
    // a monster killed by this step's shot lands in the buffer *after* the shot
    // that killed it, because both were written where they happened. A list
    // read off the actor system afterwards can only say that both occurred.
    actors?.events = events;
  }

  /// How hard this game is being.
  ///
  /// Read in exactly two places here — what the player deals and what the
  /// player takes — because those are the two axes this genre has a number
  /// for. `opponentReaction` reaches the monsters through [MonsterDef]; see
  /// [Bestiary].
  final Difficulty difficulty;

  /// What a shot is worth depending on where it lands.
  ///
  /// **Only what the player fires.** A monster's claw and a rocket's blast are
  /// deliberately even: a blast has no single point of contact worth talking
  /// about, and a game where a monster can headshot the player is a game where
  /// the damage a player takes depends on something they cannot see and did not
  /// choose. Aiming is the player's skill; being aimed at is not.
  final HitZones zones;

  /// What everything the player fires is worth while `berserk` is running.
  ///
  /// **The power-up was in the shipped registry, placed in no level, and
  /// `Inventory.isBerserk` was read by nothing** — thirty seconds of a HUD line
  /// counting down beside a game that behaved exactly as it had. This is the
  /// effect it never had.
  ///
  /// Two, and the number is a statement about the roster rather than a round
  /// figure. What a power-up is worth is measured in *swings*, because that is
  /// what a player feels: at two the fists — 20 — take a runner (45) in two
  /// blows instead of three and a shooter (60) in two instead of three, the
  /// pistol (14) takes a runner in two rather than four, and a shell (8 pellets
  /// at 11, so 88 close up) takes a tank (320) in two rather than four. Every
  /// one of those crosses a whole number, which is the point: a multiplier that
  /// does not change how many times you pull the trigger changes nothing a
  /// player can notice. Two and a half would take the tank in two shells as
  /// well and the fists to one blow on a runner, which is a crypt with no fight
  /// left in it; one and a half rounds back down to three swings for the fists
  /// and two for the pistol, and would be a HUD line for a power-up that still
  /// did nothing.
  ///
  /// Applied to what the player *delivers*, not to what a weapon says it does,
  /// so it reaches the melee, the rays and a rocket's splash alike. A power-up
  /// honoured by one weapon and not the other is the bug report
  /// [Inventory.damage]'s own doc was written against.
  static const double berserkDamage = 2.0;

  /// What the player's damage is multiplied by this step.
  ///
  /// The power-up and the setting, multiplied together rather than one winning:
  /// a player on a gentle setting who picks up berserk should feel both.
  double get _playerDamageScale =>
      (player.inventory.isBerserk ? berserkDamage : 1.0) *
      difficulty.damageDealt;

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

  /// The level as the player has seen it, revealed as they walk. Null for a
  /// game that draws no map; set by the staging once the navigation grid the
  /// map is drawn from exists, which is after the simulation does.
  Automap? automap;

  /// The holes blasts have made in the level. Null for a game whose walls
  /// do not crumble; set by the staging, which knows which brushes may.
  Breaches? breaches;

  GameState get state => _state;
  GameState _state = GameState.playing;

  /// Where to go once [state] is [GameState.complete], or null when nothing
  /// said. An exit's own answer wins over the level's, which is what lets a
  /// level with two doors lead to two places.
  String? get nextLevel => _exitNext ?? levelNext;
  String? _exitNext;

  /// Where that shot started — the eye, not the muzzle.
  final Vector3 firedFrom = Vector3.zero();

  /// What was fired this step, for the actors that have to hear it.
  ///
  /// **Wiring, not a report**, which is the line the public channels were
  /// removed along: the monsters are told about a shot later in the same step
  /// and need to know how loud it was. What the *game* gets is [ShotFired],
  /// which carries the same weapon and cannot be confused for state.
  WeaponDef? _firedThisStep;

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

  /// What this step did, for a game that wants to hear about it.
  ///
  /// Drain it after [step]; see `events.dart` for what this template reports
  /// and [GameEvents] for why it is a buffer rather than a stream. Ignoring it
  /// costs nothing — the buffer caps itself, and most of this repository's
  /// tests step without ever reading it.
  ///
  /// This replaced a field for each kind of moment. Those could not carry two
  /// of anything — a shotgun landing eight pellets was one `firedThisStep` and
  /// a list of hits — and nothing said which of two subsystems spoke first.
  final GameEvents events = GameEvents();

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
        events.add(SecretFound(mechanism));
      }
    }
  }

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
    _firedThisStep = null;
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
    // After the body has moved and settled, so the map reveals from where
    // the player is rather than from where they were.
    if (playing) automap?.reveal(player.body.position);
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
    final fired = _firedThisStep;
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
        // The wall it landed on, if it landed on one: a blast in the open
        // has a normal of nothing and cuts nothing.
        if (blast.normal.length2 > 0.5) {
          breaches?.blast(blast.position, blast.normal);
        }
        // A rocket the player fired counts as theirs however long it was in
        // the air: the multiplier is read when the blast lands rather than
        // when the trigger was pulled, because a power-up that expires while
        // the rocket flies has expired.
        //
        // **Never onto the player themselves.** A blast reaches whoever fired
        // it, so a rocket jump taken while berserk would cost twice as much —
        // a power-up that makes the player more fragile, which is nobody's idea
        // of one. `berserk` says what the player is worth to the crypt, not
        // what the crypt is worth to them.
        final scale = identical(firedBy, player) ? _playerDamageScale : 1.0;
        for (final entry in blast.damage.entries) {
          final target = entry.key.userData;
          if (target is! Damageable) continue;
          if (identical(target, player)) {
            target.applyDamage(entry.value, from: firedBy);
            continue;
          }
          target.applyDamage(entry.value * scale, from: firedBy);
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
    events.add(
      MechanismUsed(
        target.activate(mechanisms.activationBy(player.body.collider)),
      ),
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
    // **The main trigger first, and only one of the two fires in a step.** They
    // share a cooldown because they share a weapon, so a player holding both
    // gets the primary — which is the one they are more likely to have meant,
    // and the one a pad's two triggers make easy to press together by mistake.
    final wantsMain = arsenal.wantsToFire(
      held: input.held(ShooterActions.fire),
      pressed: input.pressed(ShooterActions.fire),
    );
    final wantsAlternate =
        !wantsMain &&
        arsenal.wantsToFireAlternate(
          held: input.held(ShooterActions.altFire),
          pressed: input.pressed(ShooterActions.altFire),
        );

    // **No early return, and that is not style.** The fall-back below runs on
    // every step the trigger is idle, including the steps nothing was fired on
    // and the steps a game has no `shot` to fire with — an arsenal left holding
    // an empty weapon is the bug it exists to prevent.
    if (shot != null && (wantsMain || wantsAlternate)) {
      final weapon = arsenal.fire(alternate: wantsAlternate);
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
    _firedThisStep = weapon;
    events.add(ShotFired(weapon: weapon, from: firedFrom));
    for (final hit in shot.hits) {
      events.add(ShotLanded(hit));
    }

    // Pellets landing in the same monster are summed before they are applied,
    // or eight of them are eight deaths.
    // Berserk multiplies the zone scale rather than the total, so a headshot
    // taken twice over is still a headshot: the two are the same kind of thing
    // — what this shot is worth — and folding them together is what keeps
    // pellets summed once rather than rounded twice.
    final scale = _playerDamageScale;
    for (final entry in Hitscan.damageByTarget(
      shot.hits,
      scale: (ShotHit hit) =>
          zones.forHitOn(hit.collider?.userData, hit.point) * scale,
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
    if (mechanisms != null) 'mechanisms': mechanisms!.save(),
    if (actors != null) 'actors': actors!.save(),
    // **Counted every step, shown at the end of the level, and not saved.**
    // The monsters stayed dead and the secrets stayed found across a load
    // while the two numbers that report them went back to zero, so the summary
    // was wrong for any run that had ever been resumed — and wrong in the
    // direction that makes a player think they missed things they did not.
    'tally': tally.save(),
    if (automap != null) 'automap': automap!.save(),
    if (breaches != null) 'breaches': breaches!.save(),
    'monsterCount': _monsterCount,
    'secretCount': _secretCount,
    'counted': _counted,
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
    mechanisms?.restore(from['mechanisms']);
    actors?.restore(from['actors']);
    final counts = from.object('tally');
    if (counts != null) tally.restore(counts);
    final seen = from['automap'];
    if (seen is Map) automap?.restore(seen.cast<String, Object?>());
    final blown = from['breaches'];
    if (blown is Map) breaches?.restore(blown.cast<String, Object?>());
    _monsterCount = from.integer('monsterCount', _monsterCount);
    _secretCount = from.integer('secretCount', _secretCount);
    _counted = from.flag('counted', _counted);

    // Whatever the step that took the snapshot reported is not news any more.
    // Health came back on a component; whether a body is solid is a fact about
    // the collision world, and something has to put the two together.
    actors?.syncCorpses();

    // The broadphase is holding every body where it was before the restore.
    _world.afterRestore();
  }

  void _hurtPlayer(double rawAmount) {
    // **Scaled here, at the one door damage reaches the player through.** Every
    // source — a claw, a blast, a fall — arrives at this method, so the setting
    // is applied once rather than at each of them, and a source added later
    // gets it without anybody remembering.
    final amount = rawAmount * difficulty.damageTaken;
    if (amount <= 0.0) return;
    // Asked before and after, so the death is reported on the step it happened
    // rather than on every step after it, which is what `player.isAlive` gives.
    final wasAlive = player.isAlive;
    player.applyDamage(amount);
    events.add(PlayerHurt(amount));
    if (wasAlive && !player.isAlive) events.add(const PlayerDied());
  }
}
