/// The vertex layout every stage in `cpu_shaders_*.dart` agrees on.
///
/// From `mesh.vert`'s `in` declarations, which are what define the layout —
/// repeated here rather than imported because this package does not depend on
/// the engine, and a backend that needed the engine to compile would not be a
/// backend. `VertexLayout.standard` is the Dart side of the same list.
library;

/// Where each attribute sits in the sixteen floats the engine lays out.
const int kPosition = 0; // vec3
const int kNormal = 3; // vec3
const int kTexcoord = 6; // vec2
const int kTangent = 8; // vec4
const int kColour = 12; // vec4

/// The varyings this backend's mesh stage carries.
///
/// `mesh.vert` also passes the tangent, which only the normal-mapped models
/// use and none of the ones written here do.
const int kVWorld = 0; // vec3
const int kVNormal = 3; // vec3
const int kVUv = 6; // vec2
const int kVColour = 8; // vec4
const int kVTangent = 12; // vec4
const int kMeshVaryings = 16;

/// Lights per frame, from `kMaxLights` in `surface.glsl`.
const int kMaxLights = 8;
