/// `ux-50`'s own spike, and the answer it reached: **Play runs in process.**
///
/// ## Why not the companion command
///
/// The row named two candidates. The out-of-process one — a command in
/// `tool/` that runs a template under `flutter run --machine` and takes the
/// document over the MCP port — is a better fit for somebody who is also
/// editing the game's Dart, and it is unavailable to most of the people this
/// modeller is for. Both macOS entitlements files turn the sandbox on and
/// the Flutter SDK sits outside the container, so the sandboxed build cannot
/// start it at all; the web build cannot start a process of any kind. A Play
/// button that worked on one of three platforms, and only for a developer
/// checkout, is a button most people would press once.
///
/// In process it is the same renderer, the same device and the same uploaded
/// textures as the viewport, on every platform the modeller opens on. What
/// it gives up is the game's own code: this runs a template, not a project,
/// so a person who wants their own game loop still wants the companion
/// command. That is a second row when somebody asks for it, not a reason to
/// build the first one that way.
///
/// ## Why not `flutter3d_game`
///
/// The candidate named `flutter3d_game` and `flutter3d_bridge`, and the
/// spike does not depend on either. `flutter3d_game` brings `pointer_lock`,
/// `pad_input`, `flutter3d_audio` and `flutter3d_particles` with it — four
/// packages, two of them native plugins — into an application that has to
/// keep building for the web and inside a macOS sandbox. What Play actually
/// needs from it is a body that walks and a set of keys that move it:
/// `CharacterController` is already a dependency here through
/// `flutter3d_physics`, and the keys are [PlayInput] below. A game that
/// wants shooting, a pad and a particle system wants the companion command,
/// which can depend on whatever it likes.
///
/// ## Reload
///
/// There is nothing to reload. The scene is `SceneSync`'s, the same class
/// the viewport keeps its own picture with, so a command that changes a
/// material changes the running game on the frame the document emits — the
/// row's own acceptance, and it comes free rather than being built.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart' show Vector2, Vector3, Vector4;

import '../staging.dart';
import 'play_template.dart';

/// What the player is asking for this frame.
///
/// **A record of four booleans and a look delta, not `flutter3d_sim`'s own
/// [InputState].** That class latches presses so a tap shorter than a step
/// still fires, which matters for a shot and does not for walking; Play has
/// one verb and no fixed step, so the whole of what it needs is what is held
/// right now.
typedef PlayInput = ({
  /// Sideways, then forwards, each in `[-1, 1]`.
  Vector2 move,
  bool sprint,
  bool jump,
});

/// The floor Play stands everything on, in metres.
///
/// **Forty across, because a body walks four metres a second.** A ten-metre
/// floor is two and a half seconds from edge to edge, which is long enough
/// to notice the edge and not long enough to forget it.
const double kPlayFloor = 40.0;

/// How fast the look follows a drag, in radians per logical pixel — the same
/// number `LevelWalk` uses, and for the same reason: it is the one that
/// feels right.
const double kPlayLookSpeed = 0.0032;

/// How far the eye sits above the body's own centre.
const double kPlayEyeHeight = 0.7;

/// A document, being walked in.
final class PlaySession {
  PlaySession._(this.stage, this.template, this._world, this._body) {
    _spawn();
  }

  /// Builds the scene [project] is played in: the document as the viewport
  /// already syncs it, a floor under it, and a body standing on the floor.
  factory PlaySession.start({
    required GraphicsDevice device,
    required ModelProject project,
    PlayTemplate template = PlayTemplate.character,
  }) {
    final ModelerStage stage = ModelerStage.fromProject(
      device: device,
      project: project,
    );
    stage.scene.add(_floorNode(device));
    final world = CollisionWorld()
      ..add(
        Collider(
          shape: CollisionBox(Vector3(kPlayFloor / 2, 0.5, kPlayFloor / 2)),
          position: Vector3(0.0, -0.5, 0.0),
        ),
      );
    return PlaySession._(
      stage,
      template,
      world,
      CharacterController(world: world),
    );
  }

  /// The scene, the camera and — the part that makes Reload nothing at all —
  /// the `SceneSync` that keeps the document's own objects in it.
  final ModelerStage stage;

  final PlayTemplate template;

  final CollisionWorld _world;
  final CharacterController _body;

  /// Which way the body faces, in radians about world up.
  double yaw = 0.0;

  /// How far the eye looks up (positive) or down.
  double pitch = 0.0;

  /// Where the body is standing, for a test and for the status line.
  Vector3 get position => _body.position;

  void _spawn() {
    _body.position.setValues(0.0, 1.0, template.startsBack);
    _body.collider.position.setFrom(_body.position);
  }

  /// Turns the view by a drag of [dx] and [dy] logical pixels.
  void look(double dx, double dy) {
    yaw -= dx * kPlayLookSpeed;
    // Short of straight up, where a view has no forward left to build from
    // — `LevelWalk.pitchLimit`'s own reasoning.
    pitch = (pitch - dy * kPlayLookSpeed).clamp(-1.5, 1.5);
  }

  /// One frame: the body walks, the document follows it where the template
  /// says it should, and the camera goes where the template puts it.
  ///
  /// [dt] is clamped the same tenth of a second `LevelWalk` clamps: a frame
  /// that stalled moves the body a tenth of a second's worth rather than the
  /// whole stall's, which is the difference between a hitch and falling
  /// through the floor.
  void step(double dt, PlayInput input) {
    if (input.jump) _body.requestJump();
    _body.step(
      dt.clamp(0.0, 0.1),
      wishDirection: _wishFor(input.move),
      sprint: input.sprint,
    );
    _world.update();
    if (template.ridesTheBody) {
      final Vector3 at = _body.position;
      stage.subject
        ..setPosition(at.x, at.y - 0.9, at.z)
        ..setRotationYawPitchRoll(yaw, 0.0, 0.0);
    }
    _placeCamera();
  }

  /// Where [axis] asks to go, turned by [yaw] and kept level: looking at the
  /// floor while walking forwards does not walk into it.
  Vector3 _wishFor(Vector2 axis) {
    final double forwardX = math.sin(yaw);
    final double forwardZ = -math.cos(yaw);
    return Vector3(
      forwardX * axis.y + -forwardZ * axis.x,
      0.0,
      forwardZ * axis.y + forwardX * axis.x,
    );
  }

  void _placeCamera() {
    final Vector3 eye = _body.position + Vector3(0.0, kPlayEyeHeight, 0.0);
    final double level = math.cos(pitch);
    final Vector3 forward = Vector3(
      math.sin(yaw) * level,
      math.sin(pitch),
      -math.cos(yaw) * level,
    );
    // A third-person camera is the first-person one walked backwards along
    // its own forward, which keeps the two a single sum rather than two
    // rules that have to be kept agreeing.
    final Vector3 at = eye - forward * template.cameraBack;
    stage.camera
      ..setPosition(at.x, at.y + (template.cameraBack > 0 ? 1.0 : 0.0), at.z)
      ..lookAt(eye + forward, up: Vector3(0.0, 1.0, 0.0));
  }

  static MeshNode _floorNode(GraphicsDevice device) => MeshNode(
    DeviceMesh.upload(
      device,
      const ParametricPlane(
        width: kPlayFloor,
        depth: kPlayFloor,
      ).toEditMesh().toMeshData(),
    ),
    engine.Material(
      name: 'play-floor',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.34, 0.35, 0.37, 1.0),
      roughness: 0.9,
    ),
    name: 'floor',
  );
}
