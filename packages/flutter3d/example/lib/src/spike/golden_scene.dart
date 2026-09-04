import 'package:flutter3d/flutter3d.dart';

/// One reproducible frame.
///
/// Every input that changes a pixel is named here, and nothing is left to the
/// environment: the window size does not decide the render size, the wall clock
/// does not decide the animation time, and the light set is spelled out rather
/// than inherited from whatever the demo happens to default to. A golden whose
/// inputs are implicit fails the first time an unrelated default moves, and then
/// gets updated without anybody reading the diff.
final class GoldenScene {
  const GoldenScene({
    required this.name,
    required this.source,
    this.lighting = LightingModel.pbr,
    this.yaw = 0.7,
    this.pitch = 0.35,
    this.lights = const <String>{'sun', 'key light'},
    this.animationTime,
    this.shadows = true,
    this.bloom = true,
    this.ground = true,
    this.debug = const DebugDrawOptions(),
    this.width = 480,
    this.height = 360,
    this.particles = false,
    this.viewModel = false,
    this.surfaceBuffer = false,
    this.shadowMap = false,
    this.pointShadow = false,
    this.spotShadow = false,
    this.extraPointShadows = 0,
    this.moverFrames = 0,
    this.groundDrop = 0.0,
    this.groundScale = 3.0,
    this.sky = const SkySettings(),
    this.instances = 0,
    this.lightmapped = false,
    this.anisotropicFloor = false,
    this.shaderBundle,
    this.autoExposure = const AutoExposureSettings(),
    this.xray = const XraySettings(),
    this.reflectionProbe = false,
    this.reflections = const ReflectionSettings(),
    this.ambientOcclusion = const AmbientOcclusionSettings(),
  });

  /// Screen-space reflections, off in every scene but one.
  ///
  /// The engine has advertised this on its front page since it was written and
  /// had never compared a pixel of it on any backend, which is how the march
  /// came to be reading the surface buffer upside down and measuring its
  /// thickness in window depth at the same time. Both were found by a software
  /// check; a golden is what keeps the two GPU transcriptions honest about it.
  ///
  /// The scene that turns it on turns [ambientOcclusion] off, and the reverse,
  /// so that a frame that moves says which effect moved it.
  final ReflectionSettings reflections;

  /// Ambient occlusion, off in every scene but one.
  ///
  /// Same story and the same reason: the software rasteriser is the only place
  /// `ssao.frag` has ever been compared to a picture, and what Impeller and
  /// WebGL had was that the stage links. Two transcriptions of a twelve-tap
  /// march, neither ever looked at.
  ///
  /// **Switching it on changes more than the corners.** Reading the surface
  /// buffer turns MSAA off for the whole scene pass, so the antialiasing of the
  /// entire frame changes with it — which is why this is a scene of its own
  /// rather than a flag added to an existing one.
  final AmbientOcclusionSettings ambientOcclusion;

  /// Whether the frame's exposure is metered from the frame, and how fast.
  ///
  /// Off for every scene but one, since every other scene is recorded at the
  /// setting's exposure. The one that turns it on does so with an infinite
  /// rate, so the frame captured is at the target whatever the wall clock
  /// did between frames — a golden that adapted at a rate would be a golden
  /// recorded at whatever the run's timing happened to be.
  final AutoExposureSettings autoExposure;

  /// An asset holding a loadable shader bundle, layered under the engine's
  /// as the renderer's `materials`, so [lighting] may name a stage only that
  /// bundle has. Null draws with the engine's shaders alone.
  ///
  /// The one input here that reaches the device before the renderer exists:
  /// `GraphicsDevice.loadShaders` runs on the bytes, on whichever backend the
  /// build is, and the scene is the proof that the same file loads on all
  /// three. See `GoldenExtras.exampleShaderBundle`.
  final String? shaderBundle;

  /// Silhouettes for the nodes on a layer, and — when the mask names one —
  /// the model replaced by a wall with two cubes about it. See
  /// `GoldenExtras.xrayRoom`.
  final XraySettings xray;

  /// Replaces the model with a floor and a wall lit by a hand-built lightmap
  /// and nothing else, for the lightmapped vertex stage and the lit models'
  /// lightmap term. See `GoldenExtras.lightmappedRoom`.
  final bool lightmapped;

  /// Tiles the ground with a checkerboard sampled with as much anisotropy as
  /// the device allows, up to eight, so that a low [pitch] looks along it.
  /// See `GoldenExtras.checkerFloor`.
  ///
  /// Needs [ground]; the plane it retextures is the demo's own.
  final bool anisotropicFloor;

  /// Replaces the model with four coloured walls, a floor and two metal
  /// balls reflecting them through a probe placed at the mirror one: the
  /// capture into six cube faces, the chain filtered on the device, and the
  /// physical model reading it. See `GoldenExtras.probeRoom`.
  final bool reflectionProbe;

  /// Draws the source as a batch of this many copies instead of one model.
  ///
  /// Zero draws the model as loaded. Above zero the first mesh of the loaded
  /// model becomes an `InstancedMeshNode` of this many instances laid out on
  /// a grid, each turned, scaled and tinted by its index — the picture that
  /// pins the instanced vertex stage on every backend.
  final int instances;

  /// File name, without an extension, under `test/goldens/`.
  final String name;

  /// Draws a fixed burst inside the scene pass. See [GoldenExtras].
  final bool particles;

  /// Draws a held box over the finished scene, in its own pass.
  final bool viewModel;

  /// Shows the scene pass's second attachment — world-space normal in rgb,
  /// depth in alpha — instead of the lit image.
  final bool surfaceBuffer;

  /// Shows the shadow map instead of the lit image.
  final bool shadowMap;

  /// What is behind everything. Off in every scene but one, which is what keeps
  /// the rest of this set recorded: a sky changes every pixel the scene did not
  /// otherwise draw.
  final SkySettings sky;

  /// Makes the scene's first point light a shadow caster, so the cube atlas
  /// has something in it.
  final bool pointShadow;

  /// The same for the spot light, which takes a row of the same atlas and uses
  /// one of its six columns.
  ///
  /// Separate from [pointShadow] rather than folded into it, because the two
  /// answer different questions of the same machinery: a cube writes six
  /// columns and picks between them by dominant axis, a cone writes one and
  /// must not pick at all. A scene with both on cannot tell which of them drew
  /// the shadow it is looking at.
  final bool spotShadow;

  /// How far to lower the ground below the model, in model radii.
  ///
  /// The ground moves rather than the model, because everything else in the
  /// scene is placed from the scene's bounds — lifting the model would carry
  /// the floor and the lights up with it and change nothing.
  ///
  /// A caster sitting on the floor has nowhere for a penumbra to widen, which
  /// is why every shadow scene here answered the same way however the filter
  /// was set. Contact hardening cannot be judged without a gap to harden over.
  final double groundDrop;

  /// How far the ground reaches from the model, in model radii each way.
  ///
  /// Three is the demo's: a floor wide enough for a shadow to land on and
  /// not so wide that it is the picture. A scene about the floor wants it to
  /// be the picture — [anisotropicFloor] stretches it to twelve, so that at a
  /// low [pitch] the far checks run to the horizon behind the model rather
  /// than ending a few checks past it.
  final double groundScale;

  /// Frames to turn the model for before holding it still, or zero to leave it
  /// where it is.
  ///
  /// The only motion any golden has. Every scene otherwise freezes the
  /// turntable, because a golden must render the same on the frame it is
  /// compared on as on the frame it was recorded — which also meant no golden
  /// could show a shadow tracking anything, and the atlas only refreshes faces
  /// whose contents changed. Counting frames rather than reading the clock
  /// keeps it reproducible; stopping well before the capture keeps it still.
  final int moverFrames;

  /// Extra shadow-casting point lights added around the model, so more than one
  /// row of the atlas is occupied.
  ///
  /// One caster cannot show whether the rows are drawn or read independently —
  /// with a single row every layout bug looks like a working shadow. That is
  /// exactly what hid a pass-per-light clearing the whole atlas and leaving
  /// only the last row.
  final int extraPointShadows;

  /// Matched against a model chip label by substring, as `FLUTTER3D_SOURCE` is.
  final String source;

  final LightingModel lighting;
  final double yaw;
  final double pitch;

  /// Lights switched on, by name. A subset by default, because the shadow is
  /// only readable when the caster dominates.
  final Set<String> lights;

  /// Seconds to freeze any clip at, or null for a model with no animation.
  final double? animationTime;

  final bool shadows;
  final bool bloom;
  final bool ground;
  final DebugDrawOptions debug;

  /// Render size, fixed so the result does not depend on the window.
  ///
  /// Small on purpose: a golden is compared, not admired, and 480x360 is enough
  /// to catch a lighting or geometry regression while keeping the reference
  /// images small enough to live in the repository.
  final int width;
  final int height;

  RenderSettings settingsFrom(RenderSettings base) => base.copyWith(
    debug: debug,
    shadows: base.shadows.copyWith(enabled: shadows),
    bloom: base.bloom.copyWith(enabled: bloom),
    tonemap: lighting != LightingModel.normals,
    xray: xray,
    reflections: reflections,
    ambientOcclusion: ambientOcclusion,
  );
}
