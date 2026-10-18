/// The vertex layout every stage in `cpu_shaders_*.dart` agrees on.
///
/// From `mesh.vert`'s `in` declarations, which are what define the layout —
/// repeated here rather than imported because this package does not depend on
/// the engine, and a backend that needed the engine to compile would not be a
/// backend. `VertexLayout.standard` is the Dart side of the same list.
library;

/// Where each attribute sits in the sixteen floats the engine lays out.
const int kPosition = 0; // vec3
/// Float offset of the normal, three floats.
const int kNormal = 3; // vec3
/// Float offset of the texture coordinate, two floats.
const int kTexcoord = 6; // vec2
/// Float offset of the tangent, four floats: xyz and the bitangent sign.
const int kTangent = 8; // vec4
/// Float offset of the vertex colour, four floats; the lightmapped stage reads
/// its lightmap coordinate here instead.
const int kColour = 12; // vec4

/// The varyings this backend's mesh stage carries.
///
/// `mesh.vert` also passes the tangent, which only the normal-mapped models
/// use and none of the ones written here do.
const int kVWorld = 0; // vec3
/// Varying offset of the world-space normal, three floats.
const int kVNormal = 3; // vec3
/// Varying offset of the texture coordinate, two floats.
const int kVUv = 6; // vec2
/// Varying offset of the vertex colour, four floats; white from the lightmapped
/// stage.
const int kVColour = 8; // vec4
/// Varying offset of the world-space tangent and its bitangent sign, four
/// floats.
const int kVTangent = 12; // vec4
/// Where the fragment is in the level's lightmap; zero from every stage but
/// the lightmapped one, which reads it out of the colour attribute.
const int kVLightmap = 16; // vec2
/// An instance's own four numbers — `P8`; nought from every stage but the
/// instanced one, which reads them out of slot 1.
const int kVInstance = 18; // vec4
/// How many floats of varyings the mesh stages write, the last slot included:
/// the `varyingCount` each of them answers.
const int kMeshVaryings = 22;

/// Lights per frame, from `kMaxLights` in `surface.glsl`.
const int kMaxLights = 8;
