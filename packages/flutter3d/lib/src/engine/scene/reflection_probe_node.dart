import 'mesh_node.dart';
import 'scene.dart';
import 'scene_node.dart';

/// A point the scene is reflected from.
///
/// A probe is the scene seen from where this node sits, drawn into the six
/// faces of a cube and convolved down a chain of roughness levels, so that a
/// physical material near it reflects the room it is in rather than a sky it
/// cannot see. It is a node because *where* is the whole of what it says: a
/// probe parented to a car goes where the car goes, and a probe placed in a
/// room stays in it.
///
/// **One per object, the nearest, and no blending.** A lit mesh takes the
/// probe nearest its bounds' centre among those whose [radius] reaches it,
/// and falls back to the scene's environment when none does. Two probes
/// blended across a boundary would be the next thing to build once something
/// asks for it; the first iteration is the one that draws a reflection at
/// all.
///
/// Two ways of keeping one current, chosen by [refreshFaceEveryFrame]:
///
///  * **Off**, the default: the six faces are captured together on the first
///    frame the probe is seen and then kept, until [invalidate] says the scene
///    around it changed. What a dungeon wants — one per room at load.
///  * **On**: one face is re-captured every frame, so the cube is six frames
///    behind at worst and the cost per frame is one view of the scene plus
///    the filter. What a car wants — its body reflects the track going past.
///
/// The convolution runs whenever a face was drawn, on every backend that can
/// draw into a mip level — see `GraphicsDevice.supportsRenderToMip`. A device
/// that cannot is not given a probe at all, and the material reads what it
/// read before.
final class ReflectionProbeNode extends SceneNode {
  ReflectionProbeNode({
    this.radius = 0.0,
    this.faceSize = 64,
    this.levels = 4,
    this.refreshFaceEveryFrame = false,
    this.near = 0.05,
    this.far = 200.0,
    super.name,
  }) : assert(faceSize >= 4, 'a face needs room for a chain below it'),
       assert(levels >= 1, 'a probe with no levels reflects one roughness'),
       assert(near > 0.0 && far > near, 'expected 0 < near < far');

  /// How far a mesh may be from this probe and still reflect it, measured to
  /// the mesh's bounds centre. Zero reaches everything.
  double radius;

  /// The edge of each face in pixels; the sharpest reflection this can hold.
  ///
  /// Sixty-four is enough for a car body and a mirror ball at the sizes the
  /// games draw them, and keeps a runtime probe at a fraction of a frame:
  /// six faces of sixty-four at four levels is under a megabyte of HDR.
  final int faceSize;

  /// How many convolved levels follow the base; the last is the roughest and
  /// doubles as the diffuse term, as `EnvironmentMap.diffuseLevel` says.
  final int levels;

  /// Whether one face is re-captured each frame, or all six once and kept.
  final bool refreshFaceEveryFrame;

  /// Where each face's view begins. Whatever is nearer than this is not in
  /// the reflection — which is one way to keep a probe's own object out of it.
  final double near;

  final double far;

  /// Meshes never drawn into this probe.
  ///
  /// A probe inside a car body would otherwise capture the inside of the car,
  /// and a mirror ball would reflect itself. Named per probe rather than as a
  /// flag on the mesh, because the same mesh is rightly in every *other*
  /// probe's view.
  final Set<MeshNode> excluded = <MeshNode>{};

  /// Says a kept probe no longer shows the scene around it.
  ///
  /// For a probe that is not [refreshFaceEveryFrame]: the six faces are
  /// re-captured on the next frame. A counter rather than a flag, for the
  /// reason `Scene.staticShadowGeneration` is one — the renderer compares
  /// against what it last drew, so nothing has to be cleared at the right
  /// moment.
  void invalidate() => _generation++;

  int get generation => _generation;
  int _generation = 0;

  @override
  void onAttachedToScene(Scene scene) => scene.registerProbe(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterProbe(this);
}
