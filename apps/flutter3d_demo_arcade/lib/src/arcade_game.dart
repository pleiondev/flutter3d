/// The `FlameGame` Meteor Yard is played through, and the components that
/// wire its five bridges to real `flutter3d_sim`/`flutter3d_physics` objects.
library;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show Bindings, InputSource;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'patrol_brain.dart';

part 'staging.dart';

/// Half the yard's width and depth, and how the boundary wall colliders and
/// the ground mesh both agree on the same numbers without a second constant
/// drifting from the first.
const double arenaHalfWidth = 13.0;
const double arenaHalfDepth = 9.0;

/// How high above the ground the camera sits — its own [BridgePlane], distinct
/// from the ground plane every prop and body sits on. See [ArcadeGame.cameraPlane].
const double cameraHeight = 20.0;

/// A ship over a floating meteor yard, and the drones patrolling it.
///
/// **One [FlameGame], five bridges, one shared [CollisionWorld].** The ship
/// is a [RigidBodyComponent] moved by [Dynamics]; the drones are
/// [ActorComponent]s moved by [ActorSystem]; both kinds of collider live in
/// the same [ArcadeGame.collisionWorld], so a [CollisionBridge] on the
/// ship's collider sees a drone as an ordinary solid body without either
/// side knowing the other's component type.
///
/// **Why a drone is not also a [RigidBodyComponent].** One physical collider
/// cannot be both a [CharacterController]'s and a [RigidBody]'s — the two
/// classes each register their own with [CollisionWorld.add] and neither
/// reads the other's state. Since the ECS bridge is the one that has to
/// genuinely drive a drone's movement (through [ActorSystem.step], not a
/// hand-written animation), a drone is a [CharacterController]-bodied
/// [Actor], full stop. It still meets the ship's [Dynamics] pass as an
/// ordinary kinematic obstacle, because [Dynamics.step] tests a body against
/// *everything* in [ArcadeGame.collisionWorld] it does not itself own — the
/// same "against the level" contact a crate or a wall gets.
///
/// **Why a drone never falls.** Its [MovementTuning.gravity] is zero and it
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
    dynamics = Dynamics(world: collisionWorld, gravity: Vector3.zero());
    actorSystem = ActorSystem(world: collisionWorld, random: GameRandom(7));
    inputBridge = FlameInputBridge(bindings: bindings, inputState: inputState);
  }

  /// Metres per second the ship flies at full stick deflection.
  static const double shipSpeed = 5.5;

  /// Hits the ship can take before the run ends.
  static const int maxHits = 3;

  /// The 2D↔3D axis mapping every ground-level body shares.
  static final BridgePlane groundPlane = BridgePlane.ground();

  /// The mapping the camera alone uses — same axes, a different height, so
  /// the camera can sit above the yard instead of on it. See
  /// [CameraSyncController]'s own doc for why a camera is not an
  /// [Object3dComponent].
  static final BridgePlane cameraPlane = BridgePlane.ground(
    height: cameraHeight,
  );

  /// Every collider the player's or a drone's body owns, one world for both
  /// bridges — see this class's own doc comment.
  final CollisionWorld collisionWorld;
  late final Dynamics dynamics;
  late final ActorSystem actorSystem;

  /// What every input device — here, just [inputBridge] — writes into, and
  /// what the ship's own movement reads.
  final InputState inputState;
  final Bindings bindings;
  late final FlameInputBridge inputBridge;

  /// Bridged onto the ship's collider once [spawnWorld] builds it, so a
  /// contact with a drone reaches [_onShipHitDrone].
  late final ShipComponent ship;
  late final RigidBody _shipBody;

  /// Every collider this game knows a Flame component for, so
  /// [CollisionBridge.resolveOther] can answer "who is the other side" for a
  /// contact — a wall has no entry and is silently not reported, exactly as
  /// [CollisionBridge]'s own doc says a bridge with nothing to hand over
  /// should behave.
  final Map<Collider, PositionComponent> _colliderComponents =
      <Collider, PositionComponent>{};

  /// The drones still in play. Shrinks as the ship clears them.
  final List<ActorComponent> drones = <ActorComponent>[];

  double elapsed = 0.0;
  int hits = 0;

  bool get gameOver => hits >= maxHits;
  bool get cleared => drones.isEmpty && !gameOver;

  bool _stoppedStepping = false;

  /// Set by [ArcadeGameStaging.spawnWorld], in `staging.dart` — this class's
  /// one place that assembles a run.
  late final Component _actorStepper;
  late final Component _physicsStepper;

  /// Drones the ship has hit this step, waiting for [_drainHits] to remove
  /// them — see that method's own doc comment for why this cannot happen
  /// right here.
  final List<ActorComponent> _pendingRemovals = <ActorComponent>[];

  void _onShipHitDrone(ActorComponent drone) {
    if (!drones.remove(drone)) return; // already handled this contact
    hits++;
    ship.flash();
    _pendingRemovals.add(drone);
  }

  /// Actually removes every drone [_onShipHitDrone] queued last step, and
  /// stops the world once the run is over — called from [update], before
  /// [super.update] starts this frame's own pass over [children].
  ///
  /// **Why none of this can happen from inside the collision callback
  /// itself.** [_onShipHitDrone] is called *from inside*
  /// [CollisionWorld.update]'s own overlap dispatch — itself called from
  /// inside [_PhysicsStepComponent.update], itself called from inside this
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
    for (final drone in _pendingRemovals) {
      final body = drone.actor.body;
      if (body != null) _colliderComponents.remove(body.collider);
      actorSystem.remove(drone.actor);
      drone.removeFromParent();
    }
    _pendingRemovals.clear();

    if (gameOver && !_stoppedStepping) {
      _stoppedStepping = true;
      _actorStepper.removeFromParent();
      _physicsStepper.removeFromParent();
    }
  }

  @override
  void update(double dt) {
    _drainHits();
    if (!gameOver) {
      final axis = inputState.moveAxis;
      if (axis.x != 0.0 || axis.y != 0.0) _shipBody.wake();
      _shipBody.velocity.setValues(axis.x * shipSpeed, 0.0, axis.y * shipSpeed);
      elapsed += dt;
    } else {
      _shipBody.velocity.setZero();
    }
    super.update(dt);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final propagate = inputBridge.onKeyEvent(event, keysPressed);
    return propagate ? KeyEventResult.ignored : KeyEventResult.handled;
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

/// Steps the shared [Dynamics] once a frame and then dispatches
/// [CollisionWorld]'s own overlap events — the one place a bridged game
/// drives the physics half of the simulation, the same way
/// [ActorSystemComponent] is the one place the ECS half is driven.
///
/// A plain [Component], not a bridge class this package's own
/// `flutter3d_flame` exports: nothing here reads or writes a Flame
/// transform, so there is nothing to bridge — only a shared simulation to
/// step once, which is this game's responsibility rather than the
/// package's.
final class _PhysicsStepComponent extends Component {
  _PhysicsStepComponent({required this.dynamics, required this.world});

  final Dynamics dynamics;
  final CollisionWorld world;

  @override
  void update(double dt) {
    super.update(dt);
    dynamics.step(dt);
    world.update();
  }
}
