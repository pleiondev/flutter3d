/// What the engine asks a backend's bundle for, readable from Dart.
///
/// The engine names shaders — `MeshVertex`, `Pbr`, `Composite` — and a backend
/// must ship a bundle answering to them. That requirement is the one thing
/// `GraphicsDevice` cannot express: nothing in any signature says which names,
/// so an implementation written from the interface alone compiles and draws
/// nothing.
///
/// The list already existed as data, in this package's bundle manifest, which
/// both backends compile from. It was just not readable from Dart, so nothing
/// could check a device against it. Now the conformance suite can, and a third
/// backend finds out which entry point it is missing rather than which frame
/// came back empty.
///
/// Kept in step with the manifest by a test, not by discipline.
///
/// **Not every bundle holds every entry point** since 1.0 (D15): a project's
/// build writes the stages its [ShaderStageNeed]s bring, and a stage left out
/// is refused with a [MissingShaderStageException] when it is asked for.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderStageKind;

import 'src/stage_need.dart';

export 'src/engine_bundle.dart' show EngineBundleStamp;
export 'src/shading_constants.dart' show dielectricF0;
export 'src/stage_need.dart' show MissingShaderStageException, ShaderStageNeed;

/// One entry point the engine requires: its name and what it runs as.
///
/// **A class, so an entry point can say more in a minor** than its name and
/// kind. The list below names its kind through [fragment], which a vertex
/// or fragment entry point is enough for; a kind beyond the two goes in
/// [kind].
final class RequiredShader {
  /// An entry point of [kind]; without one, a fragment stage when
  /// [fragment] is true and a vertex stage otherwise.
  const RequiredShader({
    required this.name,
    bool fragment = false,
    ShaderStageKind? kind,
  }) : assert(
         kind == null || !fragment || identical(kind, ShaderStageKind.fragment),
         'an entry point named fragment and given another kind',
       ),
       kind =
           kind ??
           (fragment ? ShaderStageKind.fragment : ShaderStageKind.vertex);

  /// The name the engine asks a bundle for.
  final String name;

  /// What the entry point runs as.
  final ShaderStageKind kind;

  /// Whether this is a fragment stage.
  bool get fragment => identical(kind, ShaderStageKind.fragment);

  @override
  bool operator ==(Object other) =>
      other is RequiredShader && name == other.name && kind == other.kind;

  @override
  int get hashCode => Object.hash(name, kind);

  @override
  String toString() => 'RequiredShader($name, ${kind.name})';
}

/// Every compute stage, as `shaders/flutter3d.compute.json` lists them —
/// `H6`. A manifest of its own because neither impellerc nor the WebGL2
/// generator reads it; a backend that computes answers to these names, and
/// one that does not answers `supportsCompute` false instead. Checked
/// against the manifest by `test/manifest_test.dart`.
///
/// The three `SplatSort` stages are the GPU splat sort — `H11` — and a
/// computing backend may leave them out: the software rasteriser does, so
/// its clouds take the CPU sort they are held to, and a consumer asks for
/// each by name before it dispatches.
const List<String> computeShaders = <String>[
  'PrefixSum',
  'SplatSortCount',
  'SplatSortScan',
  'SplatSortScatter',
];

/// Every entry point, as the manifest lists them.
///
/// Generated from `shaders/flutter3d.shaderbundle.json` and checked against it
/// by `test/manifest_test.dart`, which fails if a shader is added to one and
/// not the other.
const List<RequiredShader> requiredShaders = <RequiredShader>[
  RequiredShader(name: 'BlinnPhong', fragment: true),
  RequiredShader(name: 'BloomDownsample', fragment: true),
  RequiredShader(name: 'BloomThreshold', fragment: true),
  RequiredShader(name: 'BloomUpsample', fragment: true),
  RequiredShader(name: 'Composite', fragment: true),
  RequiredShader(name: 'DebugLine', fragment: true),
  RequiredShader(name: 'DebugLineVertex', fragment: false),
  RequiredShader(name: 'FullscreenVertex', fragment: false),
  RequiredShader(name: 'Easu', fragment: true),
  RequiredShader(name: 'Fxaa', fragment: true),
  RequiredShader(name: 'SmaaEdges', fragment: true),
  RequiredShader(name: 'SmaaWeights', fragment: true),
  RequiredShader(name: 'SmaaBlend', fragment: true),
  RequiredShader(name: 'LensFlare', fragment: true),
  RequiredShader(name: 'LocalExposure', fragment: true),
  RequiredShader(name: 'LocalExposureBlur', fragment: true),
  RequiredShader(name: 'Lambert', fragment: true),
  RequiredShader(name: 'Luminance', fragment: true),
  RequiredShader(name: 'DepthPyramid', fragment: true),
  RequiredShader(name: 'MeshInstancedVertex', fragment: false),
  RequiredShader(name: 'MeshLightmappedVertex', fragment: false),
  RequiredShader(name: 'MeshSkinnedVertex', fragment: false),
  RequiredShader(name: 'MeshVertex', fragment: false),
  RequiredShader(name: 'MrtProbe', fragment: true),
  RequiredShader(name: 'Normals', fragment: true),
  RequiredShader(name: 'ObjectId', fragment: true),
  RequiredShader(name: 'Particle', fragment: true),
  RequiredShader(name: 'ParticleMesh', fragment: true),
  RequiredShader(name: 'ParticleMeshVertex', fragment: false),
  RequiredShader(name: 'ParticleTextured', fragment: true),
  RequiredShader(name: 'ParticleSixWay', fragment: true),
  RequiredShader(name: 'ParticleSoft', fragment: true),
  RequiredShader(name: 'ParticleTexturedSoft', fragment: true),
  RequiredShader(name: 'ParticleSixWaySoft', fragment: true),
  RequiredShader(name: 'ParticleVertex', fragment: false),
  RequiredShader(name: 'Pbr', fragment: true),
  RequiredShader(name: 'PbrLayered', fragment: true),
  RequiredShader(name: 'PolylineVertex', fragment: false),
  RequiredShader(name: 'ProbePrefilter', fragment: true),
  RequiredShader(name: 'PlanarReflection', fragment: true),
  RequiredShader(name: 'RenderTextureEncode', fragment: true),
  RequiredShader(name: 'Reflections', fragment: true),
  RequiredShader(name: 'Ssao', fragment: true),
  RequiredShader(name: 'Splat', fragment: true),
  RequiredShader(name: 'SplatHashed', fragment: true),
  RequiredShader(name: 'SsaoBlur', fragment: true),
  RequiredShader(name: 'ContactShadow', fragment: true),
  RequiredShader(name: 'ContactShadowResolve', fragment: true),
  RequiredShader(name: 'CameraVelocity', fragment: true),
  RequiredShader(name: 'Velocity', fragment: true),
  RequiredShader(name: 'Reactive', fragment: true),
  RequiredShader(name: 'ReactiveSprite', fragment: true),
  RequiredShader(name: 'TemporalResolve', fragment: true),
  RequiredShader(name: 'TemporalAccumulate', fragment: true),
  RequiredShader(name: 'IrradianceConvolve', fragment: true),
  RequiredShader(name: 'VelocityVertex', fragment: false),
  RequiredShader(name: 'VelocitySkinnedVertex', fragment: false),
  RequiredShader(name: 'VelocityInstancedVertex', fragment: false),
  RequiredShader(name: 'LightShafts', fragment: true),
  RequiredShader(name: 'VolumetricFog', fragment: true),
  RequiredShader(name: 'VolumetricFogUpsample', fragment: true),
  RequiredShader(name: 'DepthOfField', fragment: true),
  RequiredShader(name: 'DofTileMax', fragment: true),
  RequiredShader(name: 'VelocityTileMax', fragment: true),
  RequiredShader(name: 'VelocityNeighborMax', fragment: true),
  RequiredShader(name: 'MotionBlur', fragment: true),
  RequiredShader(name: 'ViewportShade', fragment: true),
  RequiredShader(name: 'OutlineMask', fragment: true),
  RequiredShader(name: 'HighContrast', fragment: true),
  RequiredShader(name: 'Decal', fragment: true),
  RequiredShader(name: 'ShadowDepth', fragment: true),
  RequiredShader(name: 'ShadowDistance', fragment: true),
  RequiredShader(name: 'ShadowDepthMasked', fragment: true),
  RequiredShader(name: 'ShadowDistanceMasked', fragment: true),
  RequiredShader(name: 'ShadowTransmittance', fragment: true),
  RequiredShader(name: 'CausticSurface', fragment: true),
  RequiredShader(name: 'CausticPhotonVertex', fragment: false),
  RequiredShader(name: 'CausticPhoton', fragment: true),
  RequiredShader(name: 'ShadowCopy', fragment: true),
  RequiredShader(name: 'EvsmFilter', fragment: true),
  RequiredShader(name: 'ShadowTileReset', fragment: true),
  RequiredShader(name: 'ShadowTileResetVertex', fragment: false),
  RequiredShader(name: 'Sky', fragment: true),
  RequiredShader(name: 'SkyCube', fragment: true),
  RequiredShader(name: 'SkyVertex', fragment: false),
  RequiredShader(name: 'SkyCubeVertex', fragment: false),
  RequiredShader(name: 'SkyPhysical', fragment: true),
  RequiredShader(name: 'SkyPhysicalVertex', fragment: false),
  RequiredShader(name: 'Toon', fragment: true),
  RequiredShader(name: 'UnlitOpaque', fragment: true),
  RequiredShader(name: 'LambertOpaque', fragment: true),
  RequiredShader(name: 'BlinnPhongOpaque', fragment: true),
  RequiredShader(name: 'PbrOpaque', fragment: true),
  RequiredShader(name: 'PbrLayeredOpaque', fragment: true),
  RequiredShader(name: 'ToonOpaque', fragment: true),
  RequiredShader(name: 'DepthPredraw', fragment: true),
  RequiredShader(name: 'Unlit', fragment: true),
  RequiredShader(name: 'VertexTextureProbe', fragment: true),
  RequiredShader(name: 'VertexTextureProbeVertex', fragment: false),
  RequiredShader(name: 'FieldDecay', fragment: true),
  RequiredShader(name: 'Xray', fragment: true),
  RequiredShader(name: 'WboitResolve', fragment: true),
  RequiredShader(name: 'SceneColourCopy', fragment: true),
  RequiredShader(name: 'ImpostorVertex', fragment: false),
  RequiredShader(name: 'Impostor', fragment: true),
];
