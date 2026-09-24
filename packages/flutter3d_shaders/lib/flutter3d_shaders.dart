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
library;

/// One entry point the engine requires.
typedef RequiredShader = ({String name, bool fragment});

/// Every compute stage, as `shaders/flutter3d.compute.json` lists them —
/// `H6`. A manifest of its own because neither impellerc nor the WebGL2
/// generator reads it; a backend that computes answers to these names, and
/// one that does not answers `supportsCompute` false instead. Checked
/// against the manifest by `test/manifest_test.dart`.
const List<String> kComputeShaders = <String>['PrefixSum'];

/// Every entry point, as the manifest lists them.
///
/// Generated from `shaders/flutter3d.shaderbundle.json` and checked against it
/// by `test/manifest_test.dart`, which fails if a shader is added to one and
/// not the other.
const List<RequiredShader> kRequiredShaders = <RequiredShader>[
  (name: 'BlinnPhong', fragment: true),
  (name: 'BloomDownsample', fragment: true),
  (name: 'BloomThreshold', fragment: true),
  (name: 'BloomUpsample', fragment: true),
  (name: 'Composite', fragment: true),
  (name: 'DebugLine', fragment: true),
  (name: 'DebugLineVertex', fragment: false),
  (name: 'FullscreenVertex', fragment: false),
  (name: 'Easu', fragment: true),
  (name: 'Fxaa', fragment: true),
  (name: 'LocalExposure', fragment: true),
  (name: 'LocalExposureBlur', fragment: true),
  (name: 'Lambert', fragment: true),
  (name: 'Luminance', fragment: true),
  (name: 'MeshInstancedVertex', fragment: false),
  (name: 'MeshLightmappedVertex', fragment: false),
  (name: 'MeshSkinnedVertex', fragment: false),
  (name: 'MeshVertex', fragment: false),
  (name: 'MrtProbe', fragment: true),
  (name: 'Normals', fragment: true),
  (name: 'ObjectId', fragment: true),
  (name: 'Particle', fragment: true),
  (name: 'ParticleMesh', fragment: true),
  (name: 'ParticleMeshVertex', fragment: false),
  (name: 'ParticleTextured', fragment: true),
  (name: 'ParticleVertex', fragment: false),
  (name: 'Pbr', fragment: true),
  (name: 'PolylineVertex', fragment: false),
  (name: 'ProbePrefilter', fragment: true),
  (name: 'Reflections', fragment: true),
  (name: 'Ssao', fragment: true),
  (name: 'Splat', fragment: true),
  (name: 'SsaoBlur', fragment: true),
  (name: 'ContactShadow', fragment: true),
  (name: 'CameraVelocity', fragment: true),
  (name: 'Velocity', fragment: true),
  (name: 'TemporalResolve', fragment: true),
  (name: 'TemporalAccumulate', fragment: true),
  (name: 'IrradianceConvolve', fragment: true),
  (name: 'VelocityVertex', fragment: false),
  (name: 'VelocitySkinnedVertex', fragment: false),
  (name: 'VelocityInstancedVertex', fragment: false),
  (name: 'LightShafts', fragment: true),
  (name: 'VolumetricFog', fragment: true),
  (name: 'VolumetricFogUpsample', fragment: true),
  (name: 'DepthOfField', fragment: true),
  (name: 'VelocityTileMax', fragment: true),
  (name: 'VelocityNeighborMax', fragment: true),
  (name: 'MotionBlur', fragment: true),
  (name: 'ViewportShade', fragment: true),
  (name: 'ShadowDepth', fragment: true),
  (name: 'ShadowDistance', fragment: true),
  (name: 'ShadowDepthMasked', fragment: true),
  (name: 'ShadowDistanceMasked', fragment: true),
  (name: 'ShadowCopy', fragment: true),
  (name: 'EvsmFilter', fragment: true),
  (name: 'ShadowTileReset', fragment: true),
  (name: 'ShadowTileResetVertex', fragment: false),
  (name: 'Sky', fragment: true),
  (name: 'SkyCube', fragment: true),
  (name: 'SkyVertex', fragment: false),
  (name: 'SkyCubeVertex', fragment: false),
  (name: 'Toon', fragment: true),
  (name: 'Unlit', fragment: true),
  (name: 'VertexTextureProbe', fragment: true),
  (name: 'VertexTextureProbeVertex', fragment: false),
  (name: 'FieldDecay', fragment: true),
  (name: 'Xray', fragment: true),
];
