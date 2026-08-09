import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// `Material` exists in both flutter/material.dart and flutter3d; the level
// loader is the only place that builds one, so it is hidden here.
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/effects.dart';
import 'src/level_scene.dart';
import 'src/fixture_visuals.dart';
import 'src/monster_visuals.dart';
import 'src/weapon_view.dart';

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
  static const double _lookSensitivity = 0.0022;

  /// How far the player can look up or down.
  ///
  /// Just short of straight up: at exactly a right angle the forward vector
  /// becomes parallel to the world up axis and the camera's orientation stops
  /// being defined.
  static const double _pitchLimit = math.pi / 2.0 - 0.01;


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
  final Arsenal _arsenal = Arsenal(
    owned: <WeaponDef>[...Weapons.all],
    ammo: <AmmoType, int>{
      AmmoType.bullets: 90,
      AmmoType.shells: 30,
      AmmoType.rockets: 12,
    },
    startingSlot: 1,
  );

  final ParticleSystem _particles = ParticleSystem(capacity: 3000);
  final WeaponView _weaponView = WeaponView();
  WeaponShot? _shot;
  ProjectileSystem? _projectiles;
  MonsterSystem? _monsters;
  MonsterVisuals? _monsterVisuals;

  /// The player's own hide. Armour arrives with the pickups.
  final Health _playerHealth = Health(100.0);
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

  /// How far the eye sits above the centre of the player's box.
  static const double _eyeOffset = 0.7;

  final InterpolatedVector3 _smoothedPosition = InterpolatedVector3();

  double _yaw = 0.0;
  double _pitch = 0.0;

  Duration _lastTick = Duration.zero;
  int _steps = 0;
  double _fps = 0.0;

  // Scratch vectors, reused every step. Allocating these per frame is the
  // easiest way to hand the collector work it does not need.
  final Vector3 _forward = Vector3.zero();
  final Vector3 _right = Vector3.zero();
  final Vector3 _wish = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  MechanismWorld? _mechanisms;
  FixtureVisuals? _fixtureVisuals;

  /// What the player is carrying. Stage 9's inventory will take this over.
  final KeyRing _keys = KeyRing();

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

    try {
      _renderer = Renderer.create(
        fallbackAlbedo: SolidColorTexture.white.upload(),
        fallbackNormal: SolidColorTexture.flatNormal.upload(),
      );
    } catch (error) {
      _initError = error;
    }

    _ticker = createTicker(_onTick)..start();
    unawaited(_loadLevel());
  }

  Future<void> _loadLevel() async {
    try {
      final loaded = await const LevelLoader().load(_levelAsset);
      final start = loaded.level.playerStart;

      final hitscan = Hitscan(world: loaded.collision);
      final projectiles = ProjectileSystem(world: loaded.collision);
      final monsters = MonsterSystem(
        world: loaded.collision,
        projectiles: projectiles,
      );
      final visuals = MonsterVisuals(loaded.scene);
      final mechanisms = MechanismWorld(loaded.collision);
      final fixtures = FixtureVisuals(loaded.scene, loaded.level.materials);

      // The level's entities become actors. Which entity becomes what is the
      // entity kind's business, in flutter3d_game; all the application supplies
      // is what they look like, which is the one thing the simulation cannot
      // know.
      loaded.level.spawnInto(
        SpawnContext(
          world: loaded.collision,
          monsters: monsters,
          mechanisms: mechanisms,
          onMonsterSpawned: visuals.add,
          onFixture: fixtures.add,
        ),
      );
      final body = CharacterController(
        world: loaded.collision,
        // Lifted by half the body height: a spawn is authored where the
        // player's feet go, which is the only place an author can see.
        position: (start?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0),
      );
      // What the player is carrying hangs off their collider, so a locked door
      // can read it without the physics knowing that keys exist.
      body.collider.userData = _keys;

      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _body = body;
        _projectiles = projectiles;
        _monsters = monsters;
        _monsterVisuals = visuals;
        _mechanisms = mechanisms;
        _fixtureVisuals = fixtures;
        _shot = WeaponShot(
          world: loaded.collision,
          hitscan: hitscan,
          projectiles: projectiles,
        );
        _yaw = start?.yaw ?? 0.0;
        _smoothedPosition.jumpTo(body.position);
        // Loading blocked the ticker for a couple of seconds, and all of that
        // time is sitting in the accumulator. None of it happened in the game,
        // so it is dropped rather than simulated — otherwise the first frame
        // spends its whole budget catching up, and the dropped-step counter
        // reads as a performance problem for the rest of the session.
        _loop.clock.reset();
      });

      for (final issue in loaded.issues) {
        debugPrint('level: $issue');
      }
    } catch (error, stack) {
      debugPrint('level failed to load: $error\n$stack');
      if (mounted) setState(() => _initError = error);
    }
  }

  @override
  void dispose() {
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

    _steps = _loop.advance(dt);
    // Once a frame, not once a step: this is display, and the simulation does
    // not care where the capsules are.
    _monsterVisuals?.sync();
    _fixtureVisuals?.sync();
    setState(() {});
  }

  /// One step of simulated time. Everything that decides where the player is
  /// happens here and nowhere else.
  void _step(double dt) {
    final body = _body;
    final loaded = _loaded;
    if (body == null || loaded == null) return;

    _yaw -= _input.lookDelta.x * _lookSensitivity;
    _pitch = (_pitch - _input.lookDelta.y * _lookSensitivity)
        .clamp(-_pitchLimit, _pitchLimit);

    // Movement follows the yaw only. Walking forward while looking at the floor
    // must not drive the player into it — that is what a fly camera does, and
    // not what a first-person one should.
    final axis = _input.moveAxis;
    final sin = math.sin(_yaw);
    final cos = math.cos(_yaw);
    _forward.setValues(-sin, 0.0, -cos);
    _right.setValues(cos, 0.0, -sin);
    _wish.setValues(
      _forward.x * axis.y + _right.x * axis.x,
      0.0,
      _forward.z * axis.y + _right.z * axis.x,
    );

    if (_input.pressed(GameAction.jump)) body.requestJump();

    // Doors and lifts move first, and the world is re-indexed before the player
    // sweeps against them: a lift indexed one step late is a lift you can walk
    // through, and one that has not moved yet cannot carry you.
    final mechanisms = _mechanisms;
    mechanisms?.step(dt);
    loaded.collision.reindex();

    body.step(
      dt,
      wishDirection: _wish,
      sprint: _input.held(GameAction.sprint),
    );

    loaded.collision.update();
    loaded.collision.clearKinematicDeltas();

    if (mechanisms != null) {
      if (_input.pressed(GameAction.use)) _use(body, mechanisms);
      _collectMessages(mechanisms);
    }
    if (_messageFor > 0.0) _messageFor = math.max(0.0, _messageFor - dt);

    _updateWeapon(dt, body);

    // After the weapon, so a rocket fired this step is not moved until the
    // next one — otherwise it starts the game already a step down the corridor.
    final monsters = _monsters;
    if (monsters != null && _playerHealth.isAlive) {
      _eye
        ..setFrom(body.position)
        ..y += _eyeOffset;
      monsters.step(dt, playerEye: _eye, playerCollider: body.collider);
      if (monsters.playerDamageThisStep > 0.0) {
        _playerHealth.damage(monsters.playerDamageThisStep);
        _painFlash = 1.0;
      }
      for (final dead in monsters.died) {
        _kills++;
        _particles.burst(Effects.impactSparks, dead.position);
      }
    }

    final projectiles = _projectiles;
    if (projectiles != null) {
      projectiles.step(dt);
      for (final blast in projectiles.detonations) {
        _particles.burst(Effects.explosionCore, blast.position);
        _particles.burst(Effects.explosionEmbers, blast.position);
        _applyBlast(blast, monsters);
      }
      if (projectiles.detonations.isNotEmpty) {
        _blasts
          ..clear()
          ..addAll(projectiles.detonations);
        _hitFlash = 1.0;
      }
    }

    _particles.step(dt);

    _smoothedPosition.push(body.position);
  }

  /// A hand on whatever the crosshair is pointing at.
  ///
  /// A ray rather than a proximity test, so two buttons on the same wall are
  /// separately pressable and so the answer matches what the player believes
  /// they are aiming at.
  void _use(CharacterController body, MechanismWorld mechanisms) {
    _eye
      ..setFrom(body.position)
      ..y += _eyeOffset;
    _aim.setValues(
      -math.sin(_yaw) * math.cos(_pitch),
      math.sin(_pitch),
      -math.cos(_yaw) * math.cos(_pitch),
    );

    final target = mechanisms.underCrosshair(
      _eye,
      _aim,
      ignore: body.collider,
    );
    if (target == null) return;
    _say(target.activate(mechanisms.activationBy(body.collider)).message);
  }

  /// Anything the level said to the player during the physics step.
  ///
  /// A trigger fires from inside the collision dispatch, where there is nobody
  /// to return an outcome to, so it parks one and this collects it.
  void _collectMessages(MechanismWorld mechanisms) {
    for (final mechanism in mechanisms.all) {
      if (mechanism is TriggerVolume) {
        _say(mechanism.takeOutcome()?.message);
      } else if (mechanism is KeyPickup && mechanism.justTaken) {
        _say('Picked up the ${mechanism.colour} key.');
      }
    }
  }

  void _say(String? message) {
    if (message == null) return;
    _message = message;
    _messageFor = 3.0;
  }

  /// Firing, and the hands that hold the weapon.
  void _updateWeapon(double dt, CharacterController body) {
    _arsenal.advanceTime(dt);
    if (_hitFlash > 0.0) _hitFlash = math.max(0.0, _hitFlash - dt * 4.0);
    if (_painFlash > 0.0) _painFlash = math.max(0.0, _painFlash - dt * 1.6);

    final slot = _input.weaponRequest;
    if (slot != null && _arsenal.selectSlot(slot)) {
      _weaponView.selectWeapon(_arsenal.current);
    }

    final wants = _arsenal.wantsToFire(
      held: _input.held(GameAction.fire),
      pressed: _input.pressed(GameAction.fire),
    );
    if (wants) _fire(body);

    // Only when the trigger is idle: switching weapons out from under a player
    // who is mid-burst because one shot emptied the magazine is worse than
    // letting them notice.
    if (!_input.held(GameAction.fire)) {
      final before = _arsenal.current.name;
      _arsenal.fallBackIfEmpty();
      if (_arsenal.current.name != before) {
        _weaponView.selectWeapon(_arsenal.current);
      }
    }

    _weaponView.step(
      dt,
      speed: math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      ),
      grounded: body.isGrounded,
    );
  }

  void _fire(CharacterController body) {
    final shot = _shot;
    if (shot == null) return;

    final weapon = _arsenal.fire();
    if (weapon == null) return;
    _weaponView.recoil();

    // From the eye, not from the muzzle. The muzzle is off to one side, and a
    // shot that starts there misses what the crosshair is on whenever the
    // player is close to a wall — the classic corner-shooting bug.
    _eye
      ..setFrom(body.position)
      ..y += _eyeOffset;
    _aim.setValues(
      -math.sin(_yaw) * math.cos(_pitch),
      math.sin(_pitch),
      -math.cos(_yaw) * math.cos(_pitch),
    );

    // No branch on the kind of weapon. Rays, swings and rockets each know how
    // they arrive; this only has to say where the shot came from.
    shot.begin(weapon, _eye, _aim, shooter: body.collider);
    weapon.behaviour.deliver(shot);

    _lastShot
      ..clear()
      ..addAll(shot.hits);
    if (_lastShot.any((ShotHit h) => h.struckSomething)) _hitFlash = 1.0;

    // Pellets landing in the same monster are summed before they are applied,
    // or eight of them are eight deaths.
    final monsters = _monsters;
    if (monsters != null) {
      for (final entry in Hitscan.damageByTarget(_lastShot).entries) {
        final monster = entry.key.userData;
        if (monster is Monster) monsters.hurt(monster, entry.value);
      }
    }

    // Where the muzzle actually is, unlike where the shot came from: the flare
    // is the one thing that should sit at the barrel rather than at the eye.
    _muzzle
      ..setFrom(_eye)
      ..x += _aim.x * 0.6 - math.cos(_yaw) * 0.18
      ..y += _aim.y * 0.6 - 0.12
      ..z += _aim.z * 0.6 + math.sin(_yaw) * 0.18;
    _particles.burst(Effects.muzzleFlash, _muzzle, direction: _aim);

    for (final hit in _lastShot) {
      if (!hit.struckSomething) continue;
      _particles.burst(Effects.impactSparks, hit.point, direction: hit.normal);
      _particles.burst(Effects.impactDust, hit.point, direction: hit.normal);
    }
  }

  /// Splits an explosion between the monsters and the player.
  void _applyBlast(Detonation blast, MonsterSystem? monsters) {
    for (final entry in blast.damage.entries) {
      final target = entry.key.userData;
      if (target is Monster) {
        monsters?.hurt(target, entry.value);
      } else if (entry.key.layer == CollisionLayers.player) {
        // Own goal included: a rocket at your own feet hurts, which is the
        // price of the launcher being the best weapon in the game up close.
        _playerHealth.damage(entry.value);
        _painFlash = 1.0;
      }
    }
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
        onKeyEvent: (_, KeyEvent event) => _devices.handleKeyEvent(event),
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
              _SceneSurface(
                renderer: renderer,
                scene: loaded.scene,
                view: _view,
                viewModel: _weaponView.pass,
                particles: _particles,
                onBeforeFrame: _placeCamera,
              ),
              _Hud(
                captured: _devices.isCaptured,
                fps: _fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
                position: body.position,
                grounded: body.isGrounded,
                weapon: _arsenal.current,
                ammo: _arsenal.currentAmmo,
                hitFlash: _hitFlash,
                painFlash: _painFlash,
                health: _playerHealth,
                kills: _kills,
                monstersLeft: _monsters?.aliveCount ?? 0,
                message: _message,
                messageOpacity: (_messageFor / 0.6).clamp(0.0, 1.0),
                keys: _keys.keys,
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
    _smoothedPosition.read(_loop.alpha, _eye);
    _eye.y += _eyeOffset;

    final cosPitch = math.cos(_pitch);
    _target
      ..setFrom(_eye)
      ..x += -math.sin(_yaw) * cosPitch
      ..y += math.sin(_pitch)
      ..z += -math.cos(_yaw) * cosPitch;

    _camera
      ..setPositionFrom(_eye)
      ..lookAt(_target);
  }
}

class _SceneSurface extends StatelessWidget {
  const _SceneSurface({
    required this.renderer,
    required this.scene,
    required this.view,
    required this.viewModel,
    required this.particles,
    required this.onBeforeFrame,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final ViewModelPass viewModel;
  final ParticleSystem particles;
  final VoidCallback onBeforeFrame;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        onBeforeFrame();
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[view],
          viewModel: viewModel,
          particles: particles,
        );
        return CustomPaint(
          painter: _ImagePainter(frame.image),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class _ImagePainter extends CustomPainter {
  const _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0.0, 0.0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => true;
}

/// The colours the HUD draws a carried key in.
const Map<String, Color> _keyPips = <String, Color>{
  'blue': Color(0xFF3A6BF2),
  'red': Color(0xFFE52E29),
  'yellow': Color(0xFFF2D133),
};

class _Hud extends StatelessWidget {
  const _Hud({
    required this.captured,
    required this.fps,
    required this.steps,
    required this.dropped,
    required this.position,
    required this.grounded,
    required this.weapon,
    required this.ammo,
    required this.hitFlash,
    required this.painFlash,
    required this.health,
    required this.kills,
    required this.monstersLeft,
    required this.message,
    required this.messageOpacity,
    required this.keys,
  });

  final bool captured;
  final double fps;
  final int steps;
  final int dropped;
  final Vector3 position;
  final bool grounded;
  final WeaponDef weapon;

  /// Negative when the weapon needs none.
  final int ammo;

  /// Fades from one to zero after a shot connected.
  final double hitFlash;

  final double painFlash;
  final Health health;
  final int kills;
  final int monstersLeft;

  /// The last thing the level said — a locked door, a key collected.
  final String message;

  /// Fades over the last part of the message's life rather than vanishing.
  final double messageOpacity;

  /// What the player is carrying, drawn as coloured pips.
  final Set<String> keys;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The crosshair, which turns red the moment a shot connects. A hit
        // marker is the cheapest feedback in a shooter and the one players
        // notice the absence of.
        Center(
          child: SizedBox(
            width: 5.0 + hitFlash * 4.0,
            height: 5.0 + hitFlash * 4.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.white70,
                  const Color(0xFFFF5B4A),
                  hitFlash,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12.0,
          top: 12.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('fps ${fps.toStringAsFixed(0)}   '
                    'steps this frame $steps   dropped $dropped'),
                Text('x ${position.x.toStringAsFixed(1)}  '
                    'y ${position.y.toStringAsFixed(1)}  '
                    'z ${position.z.toStringAsFixed(1)}  '
                    '${grounded ? 'grounded' : 'airborne'}'),
              ],
            ),
          ),
        ),
        // A red wash on being hurt. Drawn under everything else so the numbers
        // stay legible exactly when they matter most.
        if (painFlash > 0.0)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: <Color>[
                    const Color(0x00FF2A18),
                    Color.lerp(
                      const Color(0x00FF2A18),
                      const Color(0xAAFF2A18),
                      painFlash,
                    )!,
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          left: 20.0,
          bottom: 18.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('HEALTH',
                    style: TextStyle(color: Colors.white54, fontSize: 12.0)),
                Text(
                  health.isAlive ? '${health.current.round()}' : 'DEAD',
                  style: TextStyle(
                    color: health.current > 30.0
                        ? Colors.white
                        : const Color(0xFFFF6B5A),
                    fontSize: 22.0,
                  ),
                ),
                Text('kills $kills   left $monstersLeft',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11.0)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 20.0,
          bottom: 18.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(weapon.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.0,
                    )),
                Text(ammo < 0 ? '∞' : '$ammo'),
              ],
            ),
          ),
        ),
        // Above the crosshair rather than at the bottom of the screen: it
        // answers something the player just did, and their eyes are here.
        if (messageOpacity > 0.0 && message.isNotEmpty)
          Align(
            alignment: const Alignment(0.0, -0.35),
            child: Opacity(
              opacity: messageOpacity,
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFF2E4C8),
                  fontSize: 17.0,
                  shadows: <Shadow>[Shadow(blurRadius: 6.0)],
                ),
              ),
            ),
          ),

        if (keys.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 84.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final key in keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: SizedBox(
                        width: 14.0,
                        height: 22.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _keyPips[key] ?? Colors.white70,
                            borderRadius: BorderRadius.circular(3.0),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        if (!captured)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Click to look around  ·  WASD to move  ·  Space to jump  ·  '
                'E to use  ·  Esc to release the pointer',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
      ],
    );
  }
}
