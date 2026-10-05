/// The `FlameGame` Meteor Yard is played through, and the components that
/// wire its five bridges to real `flutter3d_sim`/`flutter3d_physics` objects.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show Color, EdgeInsets, KeyEventResult, Paint;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart' show Bindings, InputSource;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'bot_brain.dart';

part 'crafts.dart';
part 'levels.dart';
part 'staging.dart';

/// Half the yard's width and depth, and how the boundary wall colliders and
/// the ground mesh both agree on the same numbers without a second constant
/// drifting from the first.
const double arenaHalfWidth = 13.0;
const double arenaHalfDepth = 9.0;

/// How high above the ground the camera sits — its own [BridgePlane], distinct
/// from the ground plane every prop and body sits on. See [ArcadeGame.cameraPlane].
const double cameraHeight = 20.0;

/// How many metres of the yard the orthographic camera shows top to bottom:
/// the whole of its 18-metre depth and a margin.
const double viewHeight = 22.0;

/// Which dynamics steps the ship: the native core, unless the build is made
/// with `--dart-define=FLUTTER3D_PHYSICS=dart`, which is the reference in
/// plain Dart.
const String physicsBackend = String.fromEnvironment(
  'FLUTTER3D_PHYSICS',
  defaultValue: 'native',
);

/// The dynamics [physicsBackend] names, for [world], with no gravity: the
/// yard is seen from straight above. In the browser the core must be loaded
/// first, with `loadPhysicsCore`.
RigidDynamics arcadeDynamics(CollisionWorld world) => physicsBackend == 'dart'
    ? Dynamics(world: world, gravity: Vector3.zero())
    : NativeDynamics(
        world: world,
        gravity: Vector3.zero(),
        // The bots walked by the core through the yard it mirrors.
        movesCharacters: true,
        castsRays: true,
      );

/// A ship over a floating meteor yard, and the bots patrolling it.
///
/// **One [FlameGame], five bridges, one shared [CollisionWorld].** The ship
/// is a [RigidBodyComponent] moved by [Dynamics]; the bots are
/// [ActorComponent]s moved by [ActorSystem]; both kinds of collider live in
/// the same [ArcadeGame.collisionWorld], so a [CollisionBridge] on the
/// ship's collider sees a bot as an ordinary solid body without either
/// side knowing the other's component type.
///
/// **Why a bot is not also a [RigidBodyComponent].** One physical collider
/// cannot be both a [CharacterController]'s and a [RigidBody]'s — the two
/// classes each register their own with [CollisionWorld.add] and neither
/// reads the other's state. Since the ECS bridge is the one that has to
/// genuinely drive a bot's movement (through [ActorSystem.step], not a
/// hand-written animation), a bot is a [CharacterController]-bodied
/// [Actor], full stop. It still meets the ship's [Dynamics] pass as an
/// ordinary kinematic obstacle, because [Dynamics.step] tests a body against
/// *everything* in [ArcadeGame.collisionWorld] it does not itself own — the
/// same "against the level" contact a crate or a wall gets.
///
/// **Why a bot never falls.** Its [MovementTuning.gravity] is zero and it
/// floats far enough above the ground plane that [CharacterController]'s own
/// ground probe never reaches it, so [CharacterController.isGrounded] stays
/// false forever and nothing ever sets its vertical velocity. A flying
/// enemy in a game built on a walking controller is exactly this: a body
/// that is airborne on purpose, for good.
final class ArcadeGame extends TransparentFlameGame with KeyboardEvents {
  ArcadeGame()
    : collisionWorld = CollisionWorld(),
      inputState = InputState(),
      bindings = Bindings(<InputSource, GameAction>{
        InputSource.key(LogicalKeyboardKey.arrowUp.keyId):
            GameAction.moveForward,
        InputSource.key(LogicalKeyboardKey.keyW.keyId): GameAction.moveForward,
        InputSource.key(LogicalKeyboardKey.arrowDown.keyId):
            GameAction.moveBack,
        InputSource.key(LogicalKeyboardKey.keyS.keyId): GameAction.moveBack,
        InputSource.key(LogicalKeyboardKey.arrowLeft.keyId):
            GameAction.moveLeft,
        InputSource.key(LogicalKeyboardKey.keyA.keyId): GameAction.moveLeft,
        InputSource.key(LogicalKeyboardKey.arrowRight.keyId):
            GameAction.moveRight,
        InputSource.key(LogicalKeyboardKey.keyD.keyId): GameAction.moveRight,
      }) {
    dynamics = arcadeDynamics(collisionWorld);
    actorSystem = ActorSystem(world: collisionWorld, random: GameRandom(7));
    inputBridge = FlameInputBridge(bindings: bindings, inputState: inputState);
  }

  /// The core's world, let go with the game rather than whenever the
  /// collector gets to it.
  @override
  void onRemove() {
    if (dynamics case final NativeDynamics native) native.dispose();
    super.onRemove();
  }

  /// Metres per second the ship flies at full stick deflection.
  static const double shipSpeed = 5.5;

  /// Where the ship starts every level: the bottom of the yard, flying up.
  /// A fresh vector every read, so nobody moving a copy moves the start.
  static Vector3 get shipStart => Vector3(0.0, 1.2, arenaHalfDepth - 2.0);

  /// Seconds between clearing a level and the next one starting.
  static const double levelPause = 2.0;

  /// A contact is a ram when the ship is flying at least this fast...
  static const double ramSpeed = 1.0;

  /// ...and the bot lies within 60 degrees of where it is flying.
  static const double ramCosine = 0.5;

  /// Whether a contact with a bot at [toBot] from the ship, while the
  /// ship flies along [heading], is the ship ramming it rather than the
  /// bot running into the ship.
  static bool isRam(Vector3 heading, Vector3 toBot) {
    final flat = Vector3(toBot.x, 0.0, toBot.z);
    return heading.length >= ramSpeed &&
        flat.length2 > 1e-9 &&
        heading.normalized().dot(flat.normalized()) >= ramCosine;
  }

  /// The 2D↔3D axis mapping every ground-level body shares.
  static final BridgePlane groundPlane = BridgePlane.ground();

  /// The mapping the camera alone uses — same axes, a different height, so
  /// the camera can sit above the yard instead of on it. See
  /// [CameraSyncController]'s own doc for why a camera is not an
  /// [Object3dComponent].
  static final BridgePlane cameraPlane = BridgePlane.ground(
    height: cameraHeight,
  );

  /// Every collider the player's or a bot's body owns, one world for both
  /// bridges — see this class's own doc comment.
  final CollisionWorld collisionWorld;
  late final RigidDynamics dynamics;
  late final ActorSystem actorSystem;

  /// What every input device — here, just [inputBridge] — writes into, and
  /// what the ship's own movement reads.
  final InputState inputState;
  final Bindings bindings;
  late final FlameInputBridge inputBridge;

  /// Bridged onto the ship's collider once [spawnWorld] builds it, so a
  /// contact with a bot reaches [_onShipHitBot].
  late final ShipComponent ship;
  late final RigidBody _shipBody;

  /// A trigger a little larger than the ship, kept on it every step, that
  /// the collision bridge listens on instead of the ship's own collider.
  ///
  /// **The ship's own collider never reports a bot.** Both are solid: the
  /// ship's [Dynamics] pass stops it at a bot's surface, and a bot's
  /// [CharacterController] sweep stops the bot at the ship's, never
  /// inside. The world reports overlaps, and two solids that only ever
  /// touch never overlap, so a hunter could chase the ship down and sit on
  /// it without a hit. A trigger is not solid, so neither solver stops at
  /// it, and a bot within a few centimetres of the hull overlaps it.
  late final Collider shipSensor;

  /// Every collider this game knows a Flame component for, so a contact's
  /// other side can be handed over: a wall has no entry and is silently not
  /// reported, exactly as [CollisionBridge]'s own doc says a bridge with
  /// nothing to hand over should behave.
  final ColliderRegistry _colliderComponents = ColliderRegistry();

  /// The bots still in play. Shrinks as the ship rams them.
  final List<ActorComponent> bots = <ActorComponent>[];

  /// Seconds flown, over every level of the run.
  double elapsed = 0.0;

  /// Hits the ship has taken on this level.
  int hits = 0;

  /// Bots the ship has rammed, over the whole run.
  int rammed = 0;

  /// Which of [arcadeLevels] is being played.
  int levelIndex = 0;

  ArcadeLevel get level => arcadeLevels[levelIndex];
  int get maxHits => level.maxHits;

  /// Where the ship is flying this step, on the ground plane. Its length is
  /// the ship's speed. What a ram is judged by, and what a dodging bot
  /// watches.
  final Vector3 shipHeading = Vector3.zero();

  /// Whether [ArcadeGameStaging.spawnWorld] has run. Before it the bot
  /// list is empty because nothing is in the yard yet, not because the ship
  /// cleared it.
  bool spawned = false;

  bool get gameOver => hits >= maxHits;

  /// This level's bots are all down and the ship survived it.
  bool get levelCleared => spawned && bots.isEmpty && !gameOver;

  /// The last level is cleared: the run is won.
  bool get cleared => levelCleared && levelIndex == arcadeLevels.length - 1;

  bool _stoppedStepping = false;
  bool _retryRequested = false;
  double _nextLevelIn = levelPause;

  /// Set by [ArcadeGameStaging.spawnWorld], in `staging.dart` — this class's
  /// one place that assembles a run.
  late final Component _actorStepper;
  late final Component _physicsStepper;

  /// What a level's bots are uploaded to and added to, kept from
  /// [ArcadeGameStaging.spawnWorld] for every level after the first.
  late final GraphicsDevice _device;
  late final Scene _scene;

  /// The craft models by role, and every visual node waiting for or wearing
  /// one, so a bot made before its model loaded is dressed when it does.
  late final ModelWardrobe<CraftRole> wardrobe;

  /// Bots the ship has rammed this step, waiting for [_drainHits] to
  /// remove them — see that method's own doc comment for why this cannot
  /// happen right here.
  final List<ActorComponent> _pendingRemovals = <ActorComponent>[];

  /// A contact between the ship and [bot], relayed from the physics world.
  ///
  /// **A ram downs the bot; anything else hits the ship.** The ship has to
  /// be flying at the bot, by [isRam], for the bot to go. A bot that
  /// runs into a ship standing still, or flying past it, strikes the ship
  /// and keeps going. The ship blinks after a hit and cannot be hit again
  /// while it does, or one bot brushing past would take several hits in
  /// a row.
  void _onShipHitBot(ActorComponent bot) {
    if (gameOver || !bots.contains(bot)) return;
    final body = bot.actor.body;
    if (body == null) return;
    if (isRam(shipHeading, body.position - shipSensor.position)) {
      bots.remove(bot);
      rammed++;
      _pendingRemovals.add(bot);
      return;
    }
    if (ship.isFlashing) return;
    hits++;
    ship.flash();
  }

  /// Asks for the level just lost to be played again, from the next frame.
  void retry() => _retryRequested = true;

  /// The on-screen stick, on a device with a touch screen and no keys.
  ///
  /// **Flame's own [JoystickComponent], reaching the ship through the same
  /// [InputState] the keys do.** Flame's layer is on top and gets the
  /// touches, so the stick is an ordinary Flame component in its viewport;
  /// each frame its deflection is written with [InputState.setStickAxis],
  /// the call a gamepad's stick goes through, and [InputState.moveAxis]
  /// adds it to whatever keys are held. The ship, the ram rule and the
  /// dodging bots read that one axis and never learn where it came from.
  JoystickComponent? joystick;

  /// Puts [joystick] in the bottom-left corner of the viewport.
  void addJoystick() {
    final stick = JoystickComponent(
      knob: CircleComponent(
        radius: 28.0,
        paint: Paint()..color = const Color(0xCCFFFFFF),
      ),
      background: CircleComponent(
        radius: 72.0,
        paint: Paint()..color = const Color(0x44FFFFFF),
      ),
      margin: const EdgeInsets.only(left: 48.0, bottom: 64.0),
    );
    joystick = stick;
    camera.viewport.add(stick);
  }

  /// Clears the yard of bots and starts [index] of [arcadeLevels]: the
  /// ship back at [shipStart], no hits, this level's bots in their lanes.
  ///
  /// Called from [update], between two frames, for the reason
  /// [_drainHits] gives.
  void startLevel(int index) {
    for (final bot in <ActorComponent>[...bots, ..._pendingRemovals]) {
      _removeBot(bot);
    }
    bots.clear();
    _pendingRemovals.clear();
    levelIndex = index;
    hits = 0;
    _nextLevelIn = levelPause;
    _shipBody.position.setFrom(shipStart);
    _shipBody.velocity.setZero();
    shipHeading.setZero();
    if (_stoppedStepping) {
      _stoppedStepping = false;
      add(_actorStepper);
      add(_physicsStepper);
    }
    _spawnBots(_device, _scene);
  }

  void _removeBot(ActorComponent bot) {
    final body = bot.actor.body;
    // At once rather than when the bot leaves the tree, which is a frame
    // later: nothing should be told it touched a bot already gone.
    if (body != null) _colliderComponents.unregister(body.collider);
    wardrobe.forget(bot.visual);
    actorSystem.remove(bot.actor);
    bot.removeFromParent();
  }

  /// Actually removes every bot [_onShipHitBot] queued last step, and
  /// stops the world once the run is over — called from [update], before
  /// [super.update] starts this frame's own pass over [children].
  ///
  /// **Why none of this can happen from inside the collision callback
  /// itself.** [_onShipHitBot] is called *from inside*
  /// [CollisionWorld.update]'s own overlap dispatch — itself called from
  /// inside [PhysicsStepComponent.update], itself called from inside this
  /// same frame's [Component.updateTree] pass over [children]. Calling
  /// [ActorSystem.remove] there would call [CollisionWorld.remove] while the
  /// world is mid-iteration over the very list that lives in — the class of
  /// bug [CollisionWorld.removeLater]'s own doc describes for a pickup that
  /// collects itself — and calling a component's own [Component.removeFromParent]
  /// there mutates [children] while [updateTree] is still iterating it.
  /// Draining the queue here, one frame later and strictly before that
  /// frame's own pass begins, means every removal in this method runs
  /// between two frames rather than inside one.
  void _drainHits() {
    _pendingRemovals
      ..forEach(_removeBot)
      ..clear();

    if (gameOver && !_stoppedStepping) {
      _stoppedStepping = true;
      _actorStepper.removeFromParent();
      _physicsStepper.removeFromParent();
    }
  }

  @override
  void update(double dt) {
    _drainHits();
    if (_retryRequested) {
      _retryRequested = false;
      if (gameOver) startLevel(levelIndex);
    }
    if (levelCleared && !cleared) {
      _nextLevelIn -= dt;
      if (_nextLevelIn <= 0.0) startLevel(levelIndex + 1);
    }
    // The stick's deflection, screen-down as positive, into the forward-up
    // convention of the axis the keys feed.
    final stick = joystick;
    if (stick != null) {
      inputState.setStickAxis(stick.relativeDelta.x, -stick.relativeDelta.y);
    }
    if (!gameOver && !levelCleared) {
      final axis = inputState.moveAxis;
      if (axis.x != 0.0 || axis.y != 0.0) _shipBody.wake();
      // Forward is up the screen, and the camera looks down with its top
      // towards -Z, so forward is -Z: `axis.y * shipSpeed` along +Z flew
      // the ship down the screen on W.
      shipHeading.setValues(axis.x * shipSpeed, 0.0, -axis.y * shipSpeed);
      _shipBody.velocity.setFrom(shipHeading);
      elapsed += dt;
    } else {
      shipHeading.setZero();
      _shipBody.velocity.setZero();
    }
    super.update(dt);
    _turnCrafts();
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent &&
        gameOver &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      retry();
      return KeyEventResult.handled;
    }
    return inputBridge.onGameKeyEvent(event, keysPressed);
  }
}

/// The player's ship: a [RigidBodyComponent] that blinks for half a second
/// after a contact, proving the physics bridge's [CollisionBridge] actually
/// reached Flame rather than only flutter3d's own [CollisionListener].
final class ShipComponent extends RigidBodyComponent {
  ShipComponent({
    required super.body,
    required super.node,
    required super.scene,
    required super.plane,
  });

  static const double _flashDuration = 0.5;
  static const double _blinkRate = 14.0;

  double _flashRemaining = 0.0;

  void flash() => _flashRemaining = _flashDuration;

  /// Still blinking from the last hit, and so not to be hit again yet.
  bool get isFlashing => _flashRemaining > 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    if (_flashRemaining > 0.0) {
      _flashRemaining = (_flashRemaining - dt).clamp(0.0, _flashDuration);
      node.visible = (_flashRemaining * _blinkRate).floor().isEven;
    } else {
      node.visible = true;
    }
  }
}
