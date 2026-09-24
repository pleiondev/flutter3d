import 'package:vector_math/vector_math.dart';

/// How the scene pass rejects what is hidden behind something else — `C2`,
/// `C3`. `RenderSettings.occlusion` picks one; [none] is the default and the
/// frame every golden was recorded from.
enum OcclusionMode {
  /// Frustum culling only. Everything in view is drawn.
  none,

  /// The occluders this frame are rasterised on the CPU into a small depth
  /// buffer before the render list is built, and a mesh whose box lies behind
  /// it everywhere is not drawn. Only nodes marked `MeshNode.occluder` occlude.
  software,

  /// Last frame's surface buffer, reduced on the GPU and read back, is
  /// reprojected to this frame's camera and answers the same question. Needs
  /// no occluders marked; answers "visible" until a reading has arrived, on a
  /// camera cut, with several views, and on a device with no surface buffer.
  hiZ,
}

/// Whether anything inside a world-space box may be seen this frame.
///
/// The one question the render list asks of an occlusion method, so the
/// rasteriser and the readback are interchangeable behind it. An answer of
/// false is a promise: the box lies behind something opaque at every pixel it
/// covers. Anything short of certainty — a box through the near plane, a
/// pixel nothing was drawn into — answers true.
abstract interface class OcclusionTest {
  bool mayBeVisible(Aabb3 box);
}
