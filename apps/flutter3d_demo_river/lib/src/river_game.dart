/// The `FlameGame` River Sortie is played through.
///
/// **Flame owns the game; flutter3d draws it.** Every moving thing is a Flame
/// component on a flat map of the river, and the game's rules run the way
/// any Flame game's do: components update, hitboxes overlap,
/// `onCollisionStart` says what hit what. Each of those components is an
/// `Object3dComponent`, so its Flame position is written into a scene node
/// every frame, and the scene is what the player sees. Flame itself draws
/// only the instrument panel on top.
///
/// The one thing not done with hitboxes is the banks. The river's edge is a
/// curve the course can answer for any point, so the jet asks
/// [Course.rowAt] whether it is over water rather than colliding with a
/// hitbox a bank would need hundreds of.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Paint, PaintingStyle, Path, Rect;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/input.dart' show HudButtonComponent;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart'
    show EdgeInsets, FontWeight, Shadow, TextStyle;
import 'package:flutter/services.dart' show KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show Bindings, InputSource;
import 'package:flutter3d_sim/flutter3d_sim.dart' show GameAction, InputState;

import 'course.dart';
import 'levels.dart';
import 'models.dart';
import 'rules.dart';

part 'craft.dart';
part 'hud.dart';
part 'pieces.dart';
part 'sounds.dart';
part 'staging.dart';

/// Where a run is.
enum Phase {
  /// On the water at the start of a stretch, waiting for the player.
  ready,
  flying,

  /// Down, and the pause before the next jet.
  crashed,

  /// No jets left.
  over,
}

/// What brought the last jet down.
enum Crash { bank, collision, fuel }

final class RiverGame extends TransparentFlameGame
    with KeyboardEvents, HasCollisionDetection {
  RiverGame({int seed = defaultSeed}) : course = Course(seed: seed);

  /// The trigger. `flutter3d_sim` names movement and a few common verbs; a
  /// game adds its own the same way.
  static const GameAction fire = GameAction('fire');

  /// Metres per second up the river: cruising, pushed forward, held back.
  static const double cruiseSpeed = 16.0;
  static const double fastSpeed = 26.0;
  static const double slowSpeed = 9.0;

  /// Metres per second across it at full stick.
  static const double sideSpeed = 10.0;

  /// A shot's own speed, on top of the jet's.
  static const double shotSpeed = 60.0;
  static const double shotInterval = 0.2;

  /// How close the jet has to come before a tanker or a helicopter starts
  /// to move. Until then it keeps its place, so a stretch looks the same
  /// every time it is flown into.
  static const double wakeRange = 48.0;

  /// Seconds between a crash and the next jet.
  static const double crashPause = 2.2;

  /// Half the jet's wingspan and the length ahead of its centre the bank
  /// test uses: a little under the drawing, so a wingtip over the sand is a
  /// near miss rather than a crash.
  static const double wingReach = 0.75;
  static const double noseReach = 0.9;

  /// The water, which everything is placed on: what floats at its own level,
  /// what flies at an `elevation` of [flightHeight] above it.
  static final BridgePlane river = BridgePlane.ground();

  final Course course;
  RunState run = RunState();
  Phase phase = Phase.ready;

  final InputState input = InputState();
  late final FlameInputBridge inputBridge = FlameInputBridge(
    bindings: Bindings(<InputSource, GameAction>{
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.keyW,
      ])
        InputSource.key(key.keyId): GameAction.moveForward,
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.keyS,
      ])
        InputSource.key(key.keyId): GameAction.moveBack,
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.keyA,
      ])
        InputSource.key(key.keyId): GameAction.moveLeft,
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.keyD,
      ])
        InputSource.key(key.keyId): GameAction.moveRight,
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.enter,
      ])
        InputSource.key(key.keyId): fire,
    }),
    inputState: input,
  );

  late final JetComponent jet;
  late final GraphicsDevice _device;
  late final Scene _scene;
  late final _Kit _kit;

  /// Whether [build] has run. Flame loads the game before the 3D device is
  /// open, and until then there is no jet to fly.
  bool built = false;

  /// Metres per second up the river, right now.
  double speed = 0.0;

  /// How far up the river the jet is.
  double get distance => -jet.position.y;

  /// The stretches of river built around the jet, by section index.
  final Map<int, _Stretch> _stretches = <int, _Stretch>{};

  /// Every target in play, for the tests and the models that load late.
  Iterable<TargetComponent> get targets =>
      _stretches.values.expand((stretch) => stretch.targets);

  Iterable<BridgeComponent> get bridges =>
      _stretches.values.map((stretch) => stretch.bridge).nonNulls;

  /// The craft models, and every visual node waiting for or wearing one.
  late final ModelWardrobe<Craft> wardrobe;

  double _crashTimer = 0.0;
  double _shotCooldown = 0.0;

  /// The on-screen stick and trigger, on a device with no keys.
  JoystickComponent? joystick;
  bool get touch => joystick != null;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport.add(RiverHud());
  }

  /// The renderer drawing the 3D layer, once `Flutter3dFlameWidget` has one:
  /// what a stretch's meshes go back through, so no frame still in flight is
  /// drawing them when they do. Null in the tests, which render no frames.
  Renderer? renderer;

  /// Lets go of [mesh]: after the frames in flight when there is a renderer,
  /// at once when there is none and so nothing in flight.
  void _release(DeviceMesh mesh) {
    final drawing = renderer;
    if (drawing != null) {
      drawing.releaseMeshAfterFrame(mesh);
    } else {
      _device
        ..releaseGeometry(mesh.vertices)
        ..releaseGeometry(mesh.indices);
    }
  }

  /// What brought the last jet down, for the tests and for anyone asking.
  Crash? lastCrash;

  /// The jet is down: over the land, into something, or dry.
  void crash(Crash cause) {
    if (phase != Phase.flying) return;
    lastCrash = cause;
    phase = Phase.crashed;
    _crashTimer = crashPause;
    _say(Sounds.crash);
    jet.hide();
    final at = jet.scenePosition;
    fireball(at, size: 1.3);
    if (cause == Crash.bank) smoke(at);
  }

  /// How far a depot going up reaches: whatever is this close goes with
  /// it, the jet included.
  static const double depotBlast = 5.5;

  /// A shot, or a depot going up, reached [target]: it scores, it counts
  /// towards the level's task, and it goes down the way its kind does.
  void hitTarget(TargetComponent target) {
    if (!target.hit()) return;
    final kind = target.plan.kind;
    final stage = stageOf(course.sectionIndexAt(target.plan.distance));
    final wasDone = run.taskDone(stage.level);
    run
      ..award(kind.points)
      ..count(kind);
    if (!wasDone && run.taskDone(stage.level)) {
      say('TASK DONE  ·  THE LAST BRIDGE IS OPEN');
    }

    _say(kind == TargetKind.depot ? Sounds.bigBoom : Sounds.boom);
    final at = target.scenePosition;
    switch (kind) {
      case TargetKind.tanker:
        fireball(at..y = 0.9, size: 0.7);
        splash(at..y = 0.1);
      case TargetKind.helicopter:
        fireball(at, size: 0.6);
      case TargetKind.jet:
        fireball(at, size: 1.1);
      case TargetKind.depot:
        fireball(at..y = 1.2, size: 1.6);
        _detonate(target);
    }
  }

  /// A depot going up takes its neighbours with it, and a jet refuelling
  /// over it.
  void _detonate(TargetComponent depot) {
    for (final other in targets.toList()) {
      if (!other.down &&
          other.position.distanceTo(depot.position) < depotBlast) {
        hitTarget(other);
      }
    }
    if (jet.position.distanceTo(depot.position) < depotBlast * 0.5) {
      crash(Crash.collision);
    }
  }

  /// Whether [bridge] is the last of its level and the level's task is not
  /// done yet.
  bool shielded(BridgeComponent bridge) {
    final stage = stageOf(bridge.section);
    return bridge.section == stage.last && !run.taskDone(stage.level);
  }

  /// What the task still wants, as the panel and the shield say it.
  String stillWanted(Level level) => <String>[
    for (final kind in level.task.keys)
      if (run.stillWanted(level, kind) > 0)
        '${run.stillWanted(level, kind)} ${_plural(kind)}',
  ].join(', ');

  static String _plural(TargetKind kind) => switch (kind) {
    TargetKind.tanker => 'TANKERS',
    TargetKind.helicopter => 'HELICOPTERS',
    TargetKind.depot => 'DEPOTS',
    TargetKind.jet => 'JETS',
  };

  /// A shot reached [bridge] at [at]. A shielded one throws sparks and
  /// stands; any other breaks and falls, and the next jet starts past it.
  /// The last of a level finishes the level.
  void hitBridge(BridgeComponent bridge, {required Vector2 at}) {
    if (shielded(bridge)) {
      sparks(river.to3d(at, at: flightHeight));
      _say(Sounds.spark);
      say('SHIELDED  ·  ${stillWanted(stageOf(bridge.section).level)} TO GO');
      return;
    }
    if (!bridge.collapse()) return;
    _say(Sounds.bigBoom);
    run
      ..award(500)
      ..bridgeDown(bridge.section);
    for (final along in <double>[-0.3, 0.0, 0.3]) {
      final burst = bridge.scenePosition
        ..x += bridge.span * along
        ..y = deckHeight;
      fireball(burst, size: 0.8);
    }
    splash(bridge.scenePosition..y = 0.1, size: 1.4);

    final stage = stageOf(bridge.section);
    if (bridge.section == stage.last) {
      run.finishLevel(stage.level);
      _say(Sounds.level);
      say('LEVEL COMPLETE  ·  +${stage.level.bonus}', seconds: 3.5);
    }
  }

  /// A helicopter at [from] fires at where the jet is now.
  void enemyFire({required Vector2 from}) {
    final aim = (jet.position - from)..normalize();
    _say(Sounds.tracer);
    add(
      EnemyShotComponent(
        node: MeshNode(_kit.shard, _kit.tracer, name: 'tracer')
          ..setUniformScale(0.7),
        scene: _scene,
        position: from + aim * 1.4,
        velocity: aim * EnemyShotComponent.speed,
      ),
    );
  }

  /// Fire: glowing shards that fall, dimming.
  void fireball(Vector3 at, {double size = 1.0}) => add(
    BurstComponent(
      scene: _scene,
      shard: _kit.shard,
      material: _kit.fire(),
      at: at,
      count: (14 * size).round(),
      reach: 5.0 * size,
      lift: 4.0 * size,
      size: size,
      fades: true,
    ),
  );

  /// A puff of dark smoke, rising slowly and swelling.
  void smoke(Vector3 at) => add(
    BurstComponent(
      scene: _scene,
      shard: _kit.shard,
      material: _kit.smoke,
      at: at,
      count: 2,
      reach: 0.4,
      lift: 1.5,
      gravity: -0.5,
      lifetime: 1.4,
      size: 0.9,
      grows: true,
    ),
  );

  /// White water thrown up where something meets the river.
  void splash(Vector3 at, {double size = 1.0}) => add(
    BurstComponent(
      scene: _scene,
      shard: _kit.shard,
      material: _kit.spray,
      at: at,
      count: (12 * size).round(),
      reach: 2.0 * size,
      lift: 6.0 * size,
      gravity: 18.0,
      lifetime: 0.8,
      size: 0.6,
    ),
  );

  /// A shot glancing off something it cannot break.
  void sparks(Vector3 at) => add(
    BurstComponent(
      scene: _scene,
      shard: _kit.shard,
      material: _kit.glow,
      at: at,
      count: 6,
      reach: 3.0,
      lift: 2.0,
      lifetime: 0.35,
      size: 0.35,
    ),
  );

  /// What the panel says across the middle, and for how long more.
  String? banner;
  double _bannerFor = 0.0;

  void say(String text, {double seconds = 2.5}) {
    banner = text;
    _bannerFor = seconds;
  }

  /// The level the jet is on.
  Stage get stage => stageOf(course.sectionIndexAt(distance));

  /// The level last announced, so the next is announced as the jet flies
  /// into it.
  int _announced = -1;

  /// Whether a depot is filling the tank this step.
  bool refuelling = false;

  /// What the game says into: a silent scene until [RiverGameSound.hearWith]
  /// hands it the speakers, and in every test.
  AudioScene audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();
  SoundEmitter? _engineLoop;
  SoundEmitter? _refuelLoop;
  SoundEmitter? _alarmLoop;
  int _reserveHeard = RunState.startingReserve;

  /// Called once, the first time the jet takes off.
  ///
  /// **The moment to open the speakers.** Taking off is the player's first
  /// key, touch or button, and a browser lets a page make a sound only after
  /// one; a game that opened its audio at launch has its first sound refused.
  void Function()? onFirstFlight;
  bool _flown = false;

  void _fire() {
    _say(Sounds.shot);
    add(
      ShotComponent(
        node: MeshNode(_kit.shot, _kit.glow, name: 'shot'),
        scene: _scene,
        speed: shotSpeed + speed,
        position: jet.position + Vector2(0.0, -1.3),
      ),
    );
  }

  /// One step of flight: the stick, the throttle, the fuel, the trigger,
  /// and the banks.
  void _fly(double dt) {
    final axis = input.moveAxis;
    final wanted = axis.y > 0.2
        ? fastSpeed
        : axis.y < -0.2
        ? slowSpeed
        : cruiseSpeed;
    speed += (wanted - speed) * math.min(1.0, dt * 3.0);
    jet
      ..position.x += axis.x * sideSpeed * dt
      ..position.y -= speed * dt
      ..bankTowards(axis.x, dt);

    run.burn(dt);
    refuelling = jet.depotBelow != null;
    if (refuelling) run.refuel(dt);

    final current = stage;
    if (current.index != _announced) {
      _announced = current.index;
      say(
        'LEVEL ${current.index + 1}  ·  ${current.level.name.toUpperCase()}',
        seconds: 3.0,
      );
    }

    _shotCooldown -= dt;
    if (input.held(fire) && _shotCooldown <= 0.0) {
      _fire();
      _shotCooldown = shotInterval;
    }

    final x = jet.position.x;
    final overWater =
        course.rowAt(distance).isWater(x, halfWidth: wingReach) &&
        course.rowAt(distance + noseReach).isWater(x, halfWidth: 0.15);
    if (!overWater) crash(Crash.bank);
    if (run.outOfFuel) crash(Crash.fuel);
    _ensureStretches();
  }

  @override
  void update(double dt) {
    if (!built) {
      super.update(dt);
      return;
    }
    final stick = joystick;
    if (stick != null) {
      input.setStickAxis(stick.relativeDelta.x, -stick.relativeDelta.y);
    }
    if (banner != null) {
      _bannerFor -= dt;
      if (_bannerFor <= 0.0) banner = null;
    }
    switch (phase) {
      case Phase.ready:
        if (input.pressed(fire) || input.moveAxis.length2 > 0.04) {
          phase = Phase.flying;
          _shotCooldown = shotInterval;
          if (!_flown) {
            _flown = true;
            onFirstFlight?.call();
          }
        }
      case Phase.flying:
        _fly(dt);
      case Phase.crashed:
        _crashTimer -= dt;
        if (_crashTimer <= 0.0) {
          if (run.nextJet()) {
            _restart();
          } else {
            phase = Phase.over;
          }
        }
      case Phase.over:
        if (input.pressed(fire)) {
          run = RunState();
          _restart();
        }
    }
    super.update(dt);
    _listen();
    input.endStep();
  }

  /// The stick bottom left and the trigger bottom right, above the panel.
  ///
  /// **Flame's own components, feeding the same [InputState] the keys do.**
  /// The stick's deflection goes in through [InputState.setStickAxis], the
  /// call a gamepad's stick goes through; the trigger presses and releases
  /// [fire]. The jet never learns which it was.
  void addTouchControls() {
    final stick = JoystickComponent(
      knob: CircleComponent(
        radius: 26.0,
        paint: Paint()..color = const Color(0xCCFFFFFF),
      ),
      background: CircleComponent(
        radius: 66.0,
        paint: Paint()..color = const Color(0x44FFFFFF),
      ),
      margin: const EdgeInsets.only(left: 40.0, bottom: 110.0),
    );
    final trigger = HudButtonComponent(
      button: CircleComponent(
        radius: 42.0,
        paint: Paint()..color = const Color(0x88FF5A3C),
      ),
      margin: const EdgeInsets.only(right: 48.0, bottom: 120.0),
      onPressed: () => input.press(fire),
      onReleased: () => input.release(fire),
      onCancelled: () => input.release(fire),
    );
    joystick = stick;
    camera.viewport.addAll(<Component>[stick, trigger]);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => inputBridge.onGameKeyEvent(event, keysPressed);
}

/// One stretch of river as it stands in the game: its two scene nodes, the
/// buffers to release with it, and the components living on it.
final class _Stretch {
  _Stretch({
    required this.valley,
    required this.water,
    required this.geometry,
    required this.bridge,
    required this.targets,
  });

  final MeshNode valley;
  final MeshNode water;
  final List<DeviceMesh> geometry;
  final BridgeComponent? bridge;
  final List<TargetComponent> targets;
}
