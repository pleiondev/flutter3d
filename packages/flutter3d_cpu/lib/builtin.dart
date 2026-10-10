/// The software rasteriser's own shading helpers — the stages it runs for
/// the engine's materials, the varying slots they read and the surface they
/// fill — for a package that compiles onto them, as `flutter3d_app`'s
/// material language does.
///
/// **For engine packages; not covered by semver for applications.** These
/// follow the engine's shaders and change with them in any release. A library
/// of its own rather than a `src/` import, so what another package builds on
/// is in this package's API snapshot and a change to it is seen in review.
library;

export 'src/cpu_mesh_layout.dart';
// The layout's own constants and the engine-internal stage names stay
// inside the package; [CpuMeshLayout] is what a stage compiled onto these
// reads.
export 'src/cpu_shaders_builtin.dart'
    hide
        SceneColourCopyShader,
        debugIdentityColour,
        kColour,
        kExtraLights,
        kMapBaseColor,
        kMapEmissive,
        kMapMetallicRoughness,
        kMapNormal,
        kMapOcclusion,
        kMaxLights,
        kMeshVaryings,
        kNormal,
        kPosition,
        kSmaaMaxSearch,
        kTangent,
        kTexcoord,
        kUnimplementedCpuFragmentShaders,
        kUnimplementedCpuVertexShaders,
        kVColour,
        kVInstance,
        kVLightmap,
        kVNormal,
        kVTangent,
        kVUv,
        kVWorld;
