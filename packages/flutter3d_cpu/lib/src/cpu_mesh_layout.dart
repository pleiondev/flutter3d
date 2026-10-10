/// The slots of the software rasteriser's mesh layout that a package
/// compiling onto its stages reads — `builtin.dart`'s public half of
/// `cpu_shaders_layout.dart`.
library;

/// Where the engine's vertex attributes and the mesh stage's varyings sit,
/// as float offsets, and how many of each there are. The numbers are
/// `cpu_shaders_layout.dart`'s, which `cpu_mesh_layout_test.dart` holds
/// them to.
abstract final class CpuMeshLayout {
  /// The texture coordinate in a vertex (a `vec2`).
  static const int texcoord = 6;

  /// The vertex colour in a vertex (a `vec4`).
  static const int color = 12;

  /// The world position among the varyings (a `vec3`).
  static const int varyingWorld = 0;

  /// The normal among the varyings (a `vec3`).
  static const int varyingNormal = 3;

  /// The texture coordinate among the varyings (a `vec2`).
  static const int varyingUv = 6;

  /// An instance's own four numbers among the varyings (a `vec4`).
  static const int varyingInstance = 18;

  /// How many floats the mesh stage's varyings take, a count.
  static const int varyings = 22;

  /// Lights per frame the stages read, a count.
  static const int maxLights = 8;
}
