import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
// `Material` exists in both flutter/material.dart and flutter3d. This file
// wants Flutter's, for the widgets; the files under `src/` that build the
// engine's do not import flutter/material.dart at all and so need no such
// dance.
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'package:flutter3d_audio/flutter3d_audio.dart';

import 'src/effects.dart';
import 'src/hud.dart';
import 'src/scene_surface.dart';
import 'src/fixture_looks.dart';
import 'src/monster_looks.dart';
import 'src/sounds.dart';
import 'src/weapon_models.dart';
import 'package:flutter3d_game/sample.dart';
import 'package:flutter3d_game/shooter.dart';

/// The game, as far as it goes: a room to stand in and a camera to look around
/// with.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// pointer capture in `mouse_capture` — and what is left here is the part that
/// is specific to this game. Right now that is a handful of boxes, because the
/// level format does not exist yet.
///
/// What this proves, which no unit test can: that the fixed step, the captured
/// mouse and the renderer agree with each other at 60 Hz on a real device.
void main() {
  runApp(const DungeonApp());
}

class DungeonApp extends StatelessWidget {
  const DungeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Dungeon',
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Radians of view movement per unit of mouse motion.
  ///
  /// A setting, and settings belong to the application. `Player` takes it as a
  /// field with a default so that a game with no preferences never has to
  /// think about it.
  static const double _lookSensitivity = 0.0022;



  final InputState _input = InputState();
  late final DesktopInput _devices;
  late final GameLoop _loop;
  late final Ticker _ticker;

  /// The level, once it has loaded. Null while it is loading or if it failed.
  LoadedLevel? _loaded;
  CharacterController? _body;

  /// Everything, loaded. Pickups arrive in a later stage and will replace
  /// this; until they do, a launcher nobody can find is a launcher nobody can
  /// test.
  /// Everything the player is carrying: health, armour, weapons, ammunition,
  /// keys and whatever power-up is running. One object rather than four fields,
  /// so a pickup has somewhere to give something to and the HUD has one thing
  /// to read — and so it can hang off the player's collider, which is how a
  /// locked door asks what the body in front of it holds.
  /// Who the player is, once there is a body to be.
  Player? _player;
  GameSimulation? _sim;
  GameState _shown = GameState.playing;

  final Inventory _inventory = Inventory(
    arsenal: Arsenal(
      slots: Weapons.all,
      owned: <WeaponDef>[...Weapons.all],
      ammo: <AmmoType, int>{
        AmmoType.bullets: 90,
        AmmoType.shells: 30,
        AmmoType.rockets: 12,
      },
      startingSlot: 1,
    ),
  );

  /// Everything a document in this game's levels may name.
  ///
  /// Built once and shared by the loader's validator and the spawner, so the
  /// two cannot disagree about what a level is allowed to contain.
  final EntityRegistry _entityKinds = sampleRegistry();

  final ParticleSystem _particles = ParticleSystem(capacity: 3000);
  /// The pistol, not the fists: the game starts with both, and a shooter that
  /// opens on empty hands looks unfinished.
  /// Assigned in `initState`, once there is a device to upload its models to.
  ///
  /// A field initializer used to do it, back when a mesh could reach the
  /// graphics context on its own. Nothing can now, which is the point.
  late final WeaponView _weaponView;
  ActorSystem? _actors;
  ActorVisuals? _actorVisuals;

  Arsenal get _arsenal => _inventory.arsenal;
  Health get _playerHealth => _inventory.health;
  int _kills = 0;

  /// Explosions from the last step, for the effects to catch up with.
  final List<Detonation> _blasts = <Detonation>[];

  /// The last shot's hits, for the impact markers the debug overlay draws.
  final List<ShotHit> _lastShot = <ShotHit>[];
  double _hitFlash = 0.0;

  /// Fades after the player is hurt. Red rather than the crosshair's white,
  /// because taking damage and dealing it must never look alike.
  double _painFlash = 0.0;

  final CameraNode _camera = CameraNode(name: 'player');
  late final RenderView _view;
  Renderer? _renderer;
  Object? _initError;

  /// The backend. Everything that uploads anything needs it, so it outlives
  /// `initState` as a field rather than being rebuilt where it is wanted.
  GpuRenderBackend? _device;

  /// How far the eye sits above the centre of the player's box.
  static const double _eyeOffset = 0.7;

  final InterpolatedVector3 _smoothedPosition = InterpolatedVector3();

  Duration _lastTick = Duration.zero;
  int _steps = 0;
  double _fps = 0.0;

  // Scratch vectors, reused every step. Allocating these per frame is the
  // easiest way to hand the collector work it does not need.
  final Vector3 _right = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  // Scratch for the occlusion ray, which runs once per audible source per
  // frame and must not allocate.
  final Vector3 _sound = Vector3.zero();
  final Vector3 _flameAt = Vector3.zero();

  /// Toggled by F, and also on its own every two seconds while
  /// [_fogAlternates] is set.
  ///
  /// The automatic half is there because three attempts at an A/B were spoiled
  /// by a synthetic keystroke not reaching the window. A measurement that
  /// depends on the window manager cooperating is not a measurement; one that
  /// depends only on the clock is.
  bool _fogOn = true;

  /// Off in normal play. Turned on for a measurement.
  static const bool _fogAlternates =
      bool.fromEnvironment('DUNGEON_FOG_AB');

  /// What [Effects.flame] settles at with a torch burning steadily.
  ///
  /// Measured from the running game rather than derived — 0.24 to 0.30 with
  /// forty-odd particles alive — because the number depends on the effect's
  /// sizes, alphas and lifetimes in a way that is not worth deriving and would
  /// be wrong the moment any of them changed. The spread around it is the
  /// flicker, and it is the fire's own rather than a sine's.
  static const double _flamePower = 0.34;
  final RayHit _soundRay = RayHit();

  /// Wall-clock seconds since the game started, for anything that only has to
  /// look alive — a turning pickup, a flickering torch.
  double _elapsed = 0.0;

  /// The mixer. Built with the silent backend so a build that cannot open an
  /// audio device still runs — and replaced with the real one once SoLoud is
  /// up, which is asynchronous and must not hold up the first frame.
  AudioScene _audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();
  SoLoudBackend? _soloud;

  /// Held while a mover is travelling, stopped when it arrives. A one-shot
  /// would be a stone slab that grinds for exactly as long as the sample.
  final Map<Mechanism, SoundEmitter> _moverVoices =
      <Mechanism, SoundEmitter>{};

  MechanismWorld? _mechanisms;
  FixtureVisuals? _fixtureVisuals;

  /// The last thing the level said, and how long it has left on screen.
  String _message = '';
  double _messageFor = 0.0;
  final Vector3 _muzzle = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  @override
  void initState() {
    super.initState();

    _devices = DesktopInput(state: _input);
    _loop = GameLoop(
      input: _input,
      onStep: _step,
      drainLook: _devices.drainLook,
    );

    _view = RenderView(camera: _camera);

    unawaited(_openGraphics());
  }

  /// Builds the device and everything that hangs off it.
  ///
  /// Asynchronous only because loading the shader bundle is, since flutter_gpu
  /// 3.47. Nothing else here waits for anything, and the order is the order it
  /// ran in when `initState` did it directly — the ticker still starts after
  /// the renderer exists, and the level still loads after the ticker.
  ///
  /// `build` is safe in the gap: it returns the panel whenever `_renderer` is
  /// null, which is exactly the state this leaves behind until it finishes, and
  /// which is also the state a failure leaves permanently.
  Future<void> _openGraphics() async {
    // The device first, because the weapon models and the fallback textures are
    // uploaded through it. A failure here is the same failure as a missing
    // shader bundle — `_renderer` stays null and `build` shows the panel — so
    // there is nothing further to set up.
    final GpuRenderBackend device;
    try {
      device = await GpuRenderBackend.create();
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;
    _device = device;

    _weaponView = WeaponView(
      models: dungeonWeaponModels(device),
      initial: Weapons.pistol,
    );

    // Inside `setState` because `build` is reading `_renderer` to decide
    // between the panel and the game, and by this point the first frame has
    // already been built.
    setState(() {
      try {
        _renderer = Renderer.create(
          device: device,
          fallbackAlbedo: SolidColorTexture.white.upload(device),
          fallbackNormal: SolidColorTexture.flatNormal.upload(device),
        );
      } catch (error) {
        _initError = error;
      }
    });

    // What draws alongside the world is registered rather than passed in each
    // frame. Particles inside the scene pass so they are lit and bloomed and
    // hidden by walls; the weapon over the top of it, sharing no depth with a
    // world that would otherwise slice the barrel off in every doorway.
    _renderer
      ?..addContributor(ParticleContributor(_particles))
      ..addNode(_weaponView.plugin);

    _ticker = createTicker(_onTick)..start();
    unawaited(_openAudio());
    unawaited(_loadLevel());
  }

  /// Starts SoLoud and swaps it in behind the mixer.
  ///
  /// Failing is allowed and is not fatal: a machine with no audio device, or a
  /// CI runner, keeps the silent backend and plays the game.
  Future<void> _openAudio() async {
    final backend = SoLoudBackend();
    try {
      await backend.open();
    } catch (error) {
      debugPrint('audio: could not start SoLoud: $error');
      return;
    }
    if (!mounted) return;
    _soloud = backend;
    _audio = AudioScene(
      backend: backend,
      // The walls belong to the physics; the mixer must not learn about them.
      // A wall between halves the sound rather than killing it, because a
      // monster you cannot hear at all is a monster that teleports.
      occlusion: _occlusionBetween,
    );
    await _audio.preload(Sounds.all);
    _startAmbience();
  }

  /// How much of a sound survives the trip from [from] to [to].
  double _occlusionBetween(Vector3 from, Vector3 to) {
    final loaded = _loaded;
    if (loaded == null) return 1.0;
    _sound
      ..setFrom(to)
      ..sub(from);
    final distance = _sound.length;
    if (distance < 1e-3) return 1.0;
    _sound.scale(1.0 / distance);
    final blocked = loaded.collision.raycast(
      from,
      _sound,
      distance,
      _soundRay,
      mask: CollisionLayers.world,
    );
    return blocked ? 0.35 : 1.0;
  }

  /// The torches, which run for as long as the level does.
  ///
  /// Called from both ends of a race: the audio device and the level load in
  /// parallel and either can finish first. Whichever is second starts the
  /// ambience, and the flag keeps them from starting it twice — the first
  /// version only called this from the audio side, and since the level takes
  /// seconds longer, the torches never lit.
  void _startAmbience() {
    if (_ambienceStarted) return;
    final loaded = _loaded;
    if (loaded == null || _soloud == null) return;
    _ambienceStarted = true;
    for (final torch in loaded.level.ofType(SampleEntities.torch)) {
      _audio.play(Sounds.torch, torch.position);
    }
  }

  bool _ambienceStarted = false;

  Future<void> _loadLevel() async {
    try {
      final loaded =
          await const LevelLoader().load(
        _levelAsset,
        device: _device!,
        registry: _entityKinds,
        rules: sampleRules(),
      );
      final start = loaded.level.playerStart;

      final hitscan = Hitscan(world: loaded.collision);
      final projectiles = ProjectileSystem(world: loaded.collision);
      final actors = ActorSystem(world: loaded.collision);
      final bestiary = Bestiary(
        actors: actors,
        shot: WeaponShot(
          world: loaded.collision,
          hitscan: hitscan,
          projectiles: projectiles,
        ),
        catalog: Monsters.byName,
      );
      // The one registry validates the level and then spawns it, so the two
      // cannot disagree about what a document may contain. The bestiary is
      // attached here rather than at construction because it needs a world to
      // put monsters in, and there is no world until the level has loaded.
      (_entityKinds[ShooterEntities.monster] as MonsterKind?)?.bestiary =
          bestiary;
      // Baked from the level's brushes and deliberately not from
      // `loaded.collision`: the collision world holds the doors and the lift,
      // and whichever position they happen to be in at load would be frozen
      // into the grid — a closed door becoming a wall nothing ever paths
      // through again.
      //
      // Quarter-metre cells, not the default half. Measured on this level: at
      // half a metre a one-metre corridor is two cells, both of them touching
      // a wall, so every cell in it has a clearance of one — and a monster
      // 0.7 wide, which physically fits, is refused the whole passage. The
      // grid then silently falls back to walking straight at the player in
      // exactly the places a route is worth having. Four times the cells and
      // twice the bake, both of which are load-time and both of which are
      // small.
      final navIssues = <LevelIssue>[];
      actors.navigation =
          Navigation.bake(loaded.level, cellSize: 0.25, issues: navIssues);
      final visuals = ActorVisuals(
        loaded.scene,
        appearance: const DungeonMonsters(),
        device: _device!,
      );
      final mechanisms = MechanismWorld(loaded.collision);
      final fixtures = FixtureVisuals(
        loaded.scene,
        loaded,
        appearance: const DungeonFixtures(),
        device: _device!,
      )
        ..fallbackAlbedo = _renderer?.fallbackAlbedo
        // Before spawning, so a torch can find the light it drives.
        ..bindLights();

      // The level's entities become actors. Which entity becomes what is the
      // entity kind's business, in flutter3d_game; all the application supplies
      // is what they look like, which is the one thing the simulation cannot
      // know.
      loaded.level.spawnInto(
        // The vocabulary this game speaks. The package no longer ships a
        // registry of its own — it named this game's monsters, its pickups and
        // its torches, so a second game inherited all of it.
        registry: _entityKinds,
        SpawnContext(
          world: loaded.collision,
          actors: actors,
          mechanisms: mechanisms,
          onActorSpawned: visuals.add,
          onFixture: fixtures.add,
        ),
      );
      final body = CharacterController(
        world: loaded.collision,
        // Lifted by half the body height: a spawn is authored where the
        // player's feet go, which is the only place an author can see.
        position: (start?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0),
      );
      // Who the collider *is*, rather than what it happens to be carrying.
      // A locked door reads the keys off the player, and a rocket asks the
      // player to take damage, without the physics knowing what either is.
      _player = Player(
        body: body,
        inventory: _inventory,
        eyeOffset: _eyeOffset,
        lookSensitivity: _lookSensitivity,
      );

      final sim = GameSimulation(
        player: _player!,
        collision: loaded.collision,
        input: _input,
        mechanisms: mechanisms,
        actors: actors,
        projectiles: projectiles,
        shot: WeaponShot(
          world: loaded.collision,
          hitscan: hitscan,
          projectiles: projectiles,
        ),
        levelNext: loaded.level.next,
      );

      if (!mounted) return;
      setState(() {
        _sim = sim;
        _loaded = loaded;
        _body = body;
        _actors = actors;
        _actorVisuals = visuals;
        _mechanisms = mechanisms;
        _fixtureVisuals = fixtures;
        _player!.yaw = start?.yaw ?? 0.0;
        _smoothedPosition.jumpTo(body.position);
        // Loading blocked the ticker for a couple of seconds, and all of that
        // time is sitting in the accumulator. None of it happened in the game,
        // so it is dropped rather than simulated — otherwise the first frame
        // spends its whole budget catching up, and the dropped-step counter
        // reads as a performance problem for the rest of the session.
        _loop.clock.reset();
      });

      _startAmbience();

      for (final issue in loaded.issues.followedBy(navIssues)) {
        debugPrint('level: $issue');
      }
    } catch (error, stack) {
      debugPrint('level failed to load: $error\n$stack');
      if (mounted) setState(() => _initError = error);
    }
  }

  @override
  void dispose() {
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    _ticker.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _levelAsset = 'assets/levels/crypt.json';

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0.0) _fps = _fps * 0.9 + (1.0 / dt) * 0.1;

    _elapsed += dt;
    if (_fogAlternates) {
      final phase = (_elapsed / 2.0).floor().isEven;
      if (phase != _fogOn) _fogOn = phase;
    }
    // Paused exactly when the pointer is not captured, which is what Escape
    // already does and what clicking back in already undoes. No menu, no second
    // key, and no state that can disagree with what the player sees: the
    // crosshair is gone and the cursor is back, so a game that kept simulating
    // would be a game running behind the player's back.
    _loop.paused = !_devices.isCaptured;
    _steps = _loop.advance(dt);
    // Once a frame, not once a step: this is display, and the simulation does
    // not care where the capsules are.
    _actorVisuals?.sync();
    _fixtureVisuals?.sync(_elapsed);
    setState(() {});
  }

  /// One step of simulated time.
  ///
  /// The order everything happens in belongs to `GameSimulation` now, along with
  /// the two claims about it that turned out to need measuring. What is left
  /// here is presentation: this reads what the step reports and turns it into
  /// noise, sparks and flashes.
  void _step(double dt) {
    final sim = _sim;
    final player = _player;
    if (sim == null || player == null) return;

    final heldBefore = _arsenal.current;
    sim.step(dt);

    // A weapon can change hands inside the step — a slot key, or the last
    // round of the current one. The view model is told once, here, rather than
    // by the two places that could have caused it.
    if (!identical(_arsenal.current, heldBefore)) {
      _weaponView.selectWeapon(_arsenal.current);
    }

    final outcome = sim.usedThisStep;
    if (outcome != null) {
      if (outcome is Refused) _audio.play(Sounds.locked, sim.firedFrom);
      _say(outcome.message);
    }

    final mechanisms = _mechanisms;
    if (mechanisms != null) _hearMechanisms(mechanisms);

    if (_hitFlash > 0.0) _hitFlash = math.max(0.0, _hitFlash - dt * 4.0);
    if (_painFlash > 0.0) _painFlash = math.max(0.0, _painFlash - dt * 1.6);
    if (_messageFor > 0.0) _messageFor = math.max(0.0, _messageFor - dt);
    for (final power in _inventory.expired) {
      _say('$power has run out.');
    }
    _inventory.expired.clear();

    if (sim.damageTakenThisStep > 0.0) _painFlash = 1.0;

    // Said once, on the edge. There is no restart and no next level to load
    // yet, so this is exactly as much as the application can honestly do about
    // either — and it is more than the nothing it did before, when `exit`
    // spawned no mechanism and dying left you walking around at zero health.
    if (sim.state != _shown) {
      _shown = sim.state;
      switch (sim.state) {
        case GameState.playing:
          break;
        case GameState.dead:
          _say('You died.');
        case GameState.complete:
          final next = sim.nextLevel;
          _say(next == null ? 'Level complete.' : 'Level complete — $next.');
      }
    }

    _showShot(sim);
    _showActors(sim);
    _showBlasts(sim);

    final body = player.body;
    _weaponView.step(
      dt,
      speed: math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      ),
      grounded: body.isGrounded,
    );

    _burnTorches();
    _particles.advance(dt);

    // Last, so every source has already moved this step. The listener is the
    // simulated eye rather than the interpolated one: the mix should follow
    // the game's idea of where the player is, not the renderer's.
    player.eye(_eye);
    _ears.aimAt(_eye, player.yaw);
    _audio.update(_ears);

    _smoothedPosition.push(body.position);
  }

  /// The noise and the sparks a shot makes. The shot itself already happened.
  void _showShot(GameSimulation sim) {
    final weapon = sim.firedThisStep;
    if (weapon == null) return;
    _weaponView.recoil();

    // At the eye rather than at the muzzle, for the same reason the shot
    // starts there: a sound half a metre to one side pans audibly wrong when
    // the player is against a wall.
    _audio.play(
      weapon.ammo == AmmoType.shells ? Sounds.shotgun : Sounds.pistol,
      sim.firedFrom,
    );

    _lastShot
      ..clear()
      ..addAll(sim.hits);
    if (_lastShot.any((ShotHit h) => h.struckSomething)) _hitFlash = 1.0;

    // Where the muzzle actually is, unlike where the shot came from: the flare
    // is the one thing that should sit at the barrel rather than at the eye.
    _player!
      ..aim(_aim)
      ..right(_right);
    _muzzle
      ..setFrom(sim.firedFrom)
      ..x += _aim.x * 0.6 - _right.x * 0.18
      ..y += _aim.y * 0.6 - 0.12
      ..z += _aim.z * 0.6 - _right.z * 0.18;
    _particles.burst(Effects.muzzleFlash, _muzzle, direction: _aim);

    for (final hit in _lastShot) {
      if (!hit.struckSomething) continue;
      _particles.burst(Effects.impactSparks, hit.point, direction: hit.normal);
      _particles.burst(Effects.impactDust, hit.point, direction: hit.normal);
    }
  }

  void _showActors(GameSimulation sim) {
    final monsters = sim.actors;
    if (monsters == null) return;
    for (final dead in monsters.died) {
      _kills++;
      _particles.burst(Effects.impactSparks, dead.position);
      _audio.play(Sounds.monsterDie, dead.position);
    }
    // `Sounds.monsterPain` was declared, preloaded and never played: nothing
    // anywhere could tell that a monster had been hit and survived. Only the
    // ones that flinched make a noise — a hit that did not stagger reads as a
    // hit that did not land, and every hit screaming is worse than none.
    for (final hurt in monsters.hurtThisStep) {
      if (hurt.staggered) {
        _audio.play(Sounds.monsterPain, hurt.actor.position);
      }
    }
  }

  void _showBlasts(GameSimulation sim) {
    final projectiles = sim.projectiles;
    if (projectiles == null || projectiles.detonations.isEmpty) return;
    for (final blast in projectiles.detonations) {
      _particles.burst(Effects.explosionCore, blast.position);
      _particles.burst(Effects.explosionEmbers, blast.position);
      // And smoke for a second after the fire is out, from a key that belongs
      // to this blast alone. A fresh object rather than the position: two
      // rockets landing in the same doorway are two plumes, and a key they
      // shared would mean the second restarted the first. The system drops the
      // emission when it runs out, so a key per blast does not accumulate.
      _particles.emitTimed(
        Object(),
        Effects.explosionSmoke,
        blast.position,
        perSecond: 34.0,
        seconds: 0.85,
      );
    }
    _blasts
      ..clear()
      ..addAll(projectiles.detonations);
    _hitFlash = 1.0;
  }

  /// Every torch, every step. The rate is per second and the system keeps each
  /// source's fractional remainder, so the fire looks the same on a 60 Hz
  /// display and a 120 Hz one.
  void _burnTorches() {
    final fixtures = _fixtureVisuals;
    if (fixtures == null) return;
    for (final entry in fixtures.flames.entries) {
      final fixture = entry.key;
      final fire = entry.value;
      if (!fixture.enabled) continue;
      // A steady rate, not one modulated by brightness. The flicker is
      // supposed to come out of the fire, and feeding brightness back into the
      // emission rate would make it come out of itself.
      _particles.emit(
        fire,
        Effects.flame,
        fire.originInto(_flameAt),
        perSecond: 150.0,
      );

      // And the light is what the fire measures, not a sine running alongside
      // it. Divided by the power a healthy flame settles at, so the fixture
      // sees a fraction and the level's own intensity stays the thing that
      // decides how bright a torch is.
      fixture.measure(
        fire.glow.power / _flamePower,
        // Only once the glow has seen a particle. Before that its centre is
        // the world origin, and a torch whose light spends its first frames
        // inside a wall is worse than one that never moved at all.
        at: fire.glow.located ? fire.glow.centre : null,
      );
    }
  }

  void _hearMechanisms(MechanismWorld mechanisms) {
    for (final started in mechanisms.events.started) {
      _moverVoices[started] =
          _audio.play(Sounds.stoneMove, started.origin ?? _eye);
    }
    for (final stopped in mechanisms.events.stopped) {
      _moverVoices.remove(stopped)?.stop();
      _audio.play(Sounds.stoneStop, stopped.origin ?? _eye);
    }
    for (final entry in _moverVoices.entries) {
      final at = entry.key.origin;
      if (at != null) entry.value.position.setFrom(at);
    }

    for (final taken in mechanisms.events.taken) {
      _audio.play(Sounds.pickup, taken.origin ?? _eye);
    }
    for (final said in mechanisms.events.messages) {
      _say(said);
    }
  }

  void _say(String? message) {
    if (message == null) return;
    _message = message;
    _messageFor = 3.0;
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final loaded = _loaded;
    final body = _body;
    if (renderer == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'The renderer did not start.\n\n$_initError\n\n'
              'The shader bundle is built by '
              'packages/flutter3d/tool/build_shaders.sh, and has to be rebuilt '
              'after every Flutter SDK change.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (loaded == null || body == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Loading the crypt…',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) {
          // F toggles the fog in place. A before-and-after has to come from
          // one process at one camera position, which is exactly what the
          // measurement I threw away did not have.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyF) {
            setState(() => _fogOn = !_fogOn);
          }
          return _devices.handleKeyEvent(event);
        },
        child: Listener(
          onPointerDown: (_) {
            if (_devices.isCaptured) {
              _devices.pressPointer();
            } else {
              _devices.enterFirstPerson();
            }
          },
          onPointerUp: (_) => _devices.releasePointer(),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: renderer,
                scene: loaded.scene,
                view: _view,
                fog: FogSettings(
                  color: loaded.level.fogColor,
                  density: _fogOn ? loaded.level.fogDensity : 0.0,
                ),
                onBeforeFrame: _placeCamera,
              ),
              Hud(
                captured: _devices.isCaptured,
                fps: _fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
                voices: _audio.voiceCount,
                particles: _particles.aliveCount,
                position: body.position,
                grounded: body.isGrounded,
                weapon: _arsenal.current,

                hitFlash: _hitFlash,
                painFlash: _painFlash,
                health: _playerHealth,
                kills: _kills,
                monstersLeft: _actors?.aliveCount ?? 0,
                message: _message,
                messageOpacity: (_messageFor / 0.6).clamp(0.0, 1.0),
                keys: _inventory.keys,
                armour: _playerHealth.armour,
                ammo: _arsenal.currentAmmo,
                pouches: <AmmoType, int>{
                  for (final type in AmmoType.values)
                    if (type != AmmoType.none)
                      type: _arsenal.ammoOf(type),
                },
                powers: _inventory.powers,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Places the camera for the frame about to be drawn.
  ///
  /// Reads the interpolated position rather than the simulated one: on a
  /// display faster than the step rate, several frames in a row would otherwise
  /// show the same place and then jump.
  void _placeCamera() {
    final player = _player;
    if (player == null) return;

    _smoothedPosition.read(_loop.alpha, _eye);
    player
      // The interpolated position, not the simulated one — hence `eyeFrom`,
      // which takes the place rather than reading the body.
      ..eyeFrom(_eye, _eye)
      ..aim(_aim);
    _target
      ..setFrom(_eye)
      ..add(_aim);

    _camera
      ..setPositionFrom(_eye)
      ..lookAt(_target);
  }
}
