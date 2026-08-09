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

  /// Explosions from the last step, for the effects to catch up with.
  final List<Detonation> _blasts = <Detonation>[];

  /// The last shot's hits, for the impact markers the debug overlay draws.
  final List<ShotHit> _lastShot = <ShotHit>[];
  double _hitFlash = 0.0;

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
      final body = CharacterController(
        world: loaded.collision,
        // Lifted by half the body height: a spawn is authored where the
        // player's feet go, which is the only place an author can see.
        position: (start?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0),
      );

      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _body = body;
        _projectiles = projectiles;
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

    body.step(
      dt,
      wishDirection: _wish,
      sprint: _input.held(GameAction.sprint),
    );

    loaded.collision.update();
    loaded.collision.clearKinematicDeltas();

    _updateWeapon(dt, body);

    // After the weapon, so a rocket fired this step is not moved until the
    // next one — otherwise it starts the game already a step down the corridor.
    final projectiles = _projectiles;
    if (projectiles != null) {
      projectiles.step(dt);
      for (final blast in projectiles.detonations) {
        _particles.burst(Effects.explosionCore, blast.position);
        _particles.burst(Effects.explosionEmbers, blast.position);
        // Damage lands here once there is anything with health to take it.
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

  /// Firing, and the hands that hold the weapon.
  void _updateWeapon(double dt, CharacterController body) {
    _arsenal.advanceTime(dt);
    if (_hitFlash > 0.0) _hitFlash = math.max(0.0, _hitFlash - dt * 4.0);

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
        if (!captured)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Click to look around  ·  WASD to move  ·  Space to jump  ·  '
                'Shift to sprint  ·  Esc to release the pointer',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
      ],
    );
  }
}
