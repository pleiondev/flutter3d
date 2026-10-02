import 'package:vector_math/vector_math.dart';

import 'mesh_node.dart';
import 'scene.dart';
import 'scene_node.dart';

/// A flat mirror or a still pool — `P4`: the world drawn again by a camera
/// mirrored in this node's plane, and laid over the [surfaces] that lie in
/// it.
///
/// **The plane is the node's own, not the surfaces'.** It passes through the
/// node's origin with its local +Y as the normal, the side the reflection is
/// seen from; a camera behind it sees no reflection, as one below a pool
/// sees none. The surfaces are whatever stands in that plane — a quad, a
/// water mesh, the floor of a hall — and keep their own materials: the
/// reflection is drawn over each of them where it won the depth test, so a
/// surface is lit, textured and shadowed as it was, with the mirrored world
/// on top in proportion to [reflectance] and the angle.
///
/// **What it costs is a second picture of the scene per view**, at
/// [resolution] of the view's pixels, drawn before the scene with the frame's
/// lights and shadows and its sky. Nothing in it is reflected again, and
/// neither the particles nor anything else a contributor draws reaches it.
///
/// Drawn only while `RenderSettings.planarReflections` is on.
final class PlanarReflectorNode extends SceneNode {
  PlanarReflectorNode({
    Iterable<MeshNode> surfaces = const <MeshNode>[],
    this.reflectance = 1.0,
    this.strength = 1.0,
    Vector3? tint,
    this.resolution = 0.5,
    this.clipOffset = 0.01,
    this.reflectedLayers = ~0,
    super.name,
  }) : surfaces = <MeshNode>{...surfaces},
       tint = tint ?? Vector3(1.0, 1.0, 1.0),
       assert(reflectance >= 0.0 && reflectance <= 1.0, 'F0 is a fraction'),
       assert(strength >= 0.0, 'a reflection cannot take light away'),
       assert(
         resolution > 0.0 && resolution <= 1.0,
         'a fraction of the view, and not nothing',
       );

  /// The meshes the reflection is laid over. Left out of the reflection
  /// themselves: they stand in the plane, where the clip would cut them in
  /// half.
  final Set<MeshNode> surfaces;

  /// Meshes the mirrored camera leaves out, beyond [surfaces].
  final Set<MeshNode> excluded = <MeshNode>{};

  /// How much is reflected looking straight at the plane, Schlick's F0: one
  /// for a mirror, which then reflects everything at every angle, and about
  /// 0.02 for water, which reflects little looking down and nearly all at a
  /// grazing angle.
  double reflectance;

  /// What the Fresnel term is multiplied by before the reflection is laid
  /// on; one lays it on as the angle says.
  double strength;

  /// Linear light the reflection is multiplied by: a tinted glass, a dark
  /// pool.
  final Vector3 tint;

  /// The reflection's size as a fraction of its view's, each way. Half by
  /// default, which is a quarter of the pixels; a still mirror that fills the
  /// screen wants one.
  double resolution;

  /// How far below the plane the mirrored camera's near plane sits, in
  /// metres. A little, so a wall standing on the floor keeps its foot in the
  /// reflection rather than a seam of whatever the clip left.
  double clipOffset;

  /// Which layers the mirrored camera draws, intersected with each view's.
  /// Not [layerMask], which is this node's own layer like any node's.
  int reflectedLayers;

  /// The plane's normal in world space: the node's local +Y, normalised.
  Vector3 readPlaneNormal([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(m[4], m[5], m[6]);
    if (result.length2 > 0.0) result.normalize();
    return result;
  }

  @override
  void onAttachedToScene(Scene scene) => scene.registerReflector(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterReflector(this);
}
