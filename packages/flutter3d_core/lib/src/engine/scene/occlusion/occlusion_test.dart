import 'package:vector_math/vector_math.dart';

/// How the scene pass rejects what is hidden behind something else — `C2`,
/// `C3`. `RenderSettings.occlusion` picks one; [none] is the default and the
/// frame every golden was recorded from.
final class OcclusionMode {
  const OcclusionMode._(this.index, this.name);

  /// Frustum culling only. Everything in view is drawn.
  static const OcclusionMode none = OcclusionMode._(0, 'none');

  /// The occluders this frame are rasterised on the CPU into a small depth
  /// buffer before the render list is built, and a mesh whose box lies behind
  /// it everywhere is not drawn. Only nodes marked `MeshNode.occluder` occlude.
  static const OcclusionMode software = OcclusionMode._(1, 'software');

  /// Last frame's surface buffer, reduced on the GPU and read back, is
  /// reprojected to this frame's camera and answers the same question. Needs
  /// no occluders marked; answers "visible" until a reading has arrived, on a
  /// camera cut, with several views, and on a device with no surface buffer.
  static const OcclusionMode hiZ = OcclusionMode._(2, 'hiZ');

  /// Every value this version names, in the order of [index].
  static const List<OcclusionMode> values = <OcclusionMode>[
    none,
    software,
    hiZ,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static OcclusionMode? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position in [values]: stable within a major, appended only.
  final int index;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'OcclusionMode.$name';
}

/// Whether anything inside a world-space box may be seen this frame.
///
/// The one question the render list asks of an occlusion method, so the
/// rasteriser and the readback are interchangeable behind it. An answer of
/// false is a promise: the box lies behind something opaque at every pixel it
/// covers. Anything short of certainty — a box through the near plane, a
/// pixel nothing was drawn into — answers true.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class OcclusionTest {
  bool mayBeVisible(Aabb3 box);
}
