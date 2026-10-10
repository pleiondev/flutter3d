import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A rival or a past run, drawn where a recorded track was at a moment of it.
///
/// **Not in the collision world, not stepped, and it cannot be hit.** A ghost
/// that could be collided with would be a past run blocking the one being
/// played, which is the one thing it must never do. [Playback] says the same
/// in its own words; this is the half of it that is made of geometry.
///
/// The track is a [Tape]: from a [Recorder] as the run is played, from a
/// replay played again headless, or from a run's pose record
/// (`PoseRecord.track`) when its tape cannot be replayed — see [ghostOfRun].
final class Ghost {
  Ghost(this.node, {this.floor = 0.0, this.facing = 0.0});

  final SceneNode node;

  /// The model's own lowest point, taken off the height: a track records
  /// where the feet were, and a model is not always drawn from its feet. In
  /// metres.
  final double floor;

  /// Added to the track's yaw, for a model that faces somewhere other than
  /// the way the game's yaw nought points. In radians.
  final double facing;

  final Pose _at = Pose();

  /// The default look: translucent and pale, in a colour nothing else wears.
  ///
  /// A ghost has to read as *not a thing you can hit* at the glance a player
  /// can spare, and the two ways to say that are through it and unlike
  /// everything else. `blend` puts it in the transparent half of the render
  /// list, so the world shows through; nothing writes depth through it, so
  /// two ghosts overlapping are brighter rather than a hole in the one
  /// behind; and nothing lights it.
  static RenderMaterial look({double alpha = 0.35, double roughness = 0.5}) =>
      RenderMaterial(
        baseColor: LinearColor.fromSrgb(0.65, 0.85, 1.0, alpha),
        roughness: roughness,
        alphaMode: MaterialAlphaMode.blend,
        depthWrite: false,
        lighting: LightingModel.unlit,
      );

  /// Turns every part in [meshes] into [look].
  ///
  /// **Replaces the materials rather than editing them.** The model's own are
  /// textured, opaque and lit, and a ghost is unlit, blended and writes no
  /// depth; turning one into the other means changing more than a colour.
  /// One material across every part, deliberately: nothing colours a ghost
  /// per part, and a ghost with a solid part inside it reads as solid.
  static void haunt(List<MeshNode> meshes, RenderMaterial look) {
    for (final mesh in meshes) {
      mesh.material = look;
    }
  }

  /// Puts the ghost where [track] was [seconds] into it, or hides it.
  ///
  /// Hidden rather than left where it was: a ghost that stops where the
  /// recording ran out reads as something parked in the way. [lift] raises it
  /// along the track's own up rather than the world's, which on a slope or a
  /// banked corner differ by most of a metre. Returns whether it is shown.
  bool showAt(double seconds, Tape track, {double lift = 0.0}) {
    if (!Playback(track).sampleAt(seconds, _at)) {
      node.isVisible = false;
      return false;
    }
    node
      ..isVisible = true
      ..setPosition(
        _at.position.x + _at.up.x * lift,
        _at.position.y + _at.up.y * lift - floor,
        _at.position.z + _at.up.z * lift,
      )
      ..setRotation(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _at.yaw + facing),
      );
    return true;
  }

  /// A ghost of [model] in [scene], every part in [look]; or, with no model,
  /// whatever [fallback] adds to the scene — a box the size of the thing,
  /// because a game that runs beats a game that does not.
  ///
  /// [model] is the asset the game already loaded, so the ghost costs no
  /// second load. The ghost starts hidden.
  static Ghost build(
    Scene scene, {
    required RenderMaterial look,
    required SceneNode Function() fallback,
    ModelAsset? model,
    double floor = 0.0,
    double facing = 0.0,
    String name = 'ghost',
  }) {
    if (model == null) {
      return Ghost(fallback(), floor: floor, facing: facing)
        ..node.isVisible = false;
    }
    final instance = model.instantiate(scene, name: name);
    haunt(instance.meshes, look);
    return Ghost(instance.root, floor: floor, facing: facing)
      ..node.isVisible = false;
  }
}
