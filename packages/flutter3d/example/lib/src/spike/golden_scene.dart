import 'package:flutter3d/flutter3d.dart';

/// Builds a scene's own content — see [GoldenScene.stage].
typedef GoldenStaging = Future<GoldenStaged> Function(GoldenStage stage);

/// What a [GoldenStaging] is given: the demo's device, renderer, scene and
/// the two nodes a staged scene most often has to move.
final class GoldenStage {
  const GoldenStage({
    required this.device,
    required this.renderer,
    required this.scene,
    required this.camera,
    required this.orbit,
    required this.sun,
  });

  final GraphicsDevice device;

  /// The orbit that framed the loaded model, for the one scene that keeps
  /// the model and places something beside it at the model's own scale.
  final OrbitController orbit;

  /// For the scenes whose content is a contributor rather than a node:
  /// particles and splats.
  final Renderer renderer;
  final Scene scene;
  final CameraNode camera;

  /// The demo's directional light, which casts. A staged scene turns it off
  /// or aims it; the three lamps are switched by [GoldenScene.lights].
  final LightNode sun;
}

/// What a [GoldenStaging] built.
final class GoldenStaged {
  const GoldenStaged({
    this.nodes = const <SceneNode>[],
    this.keepModel = false,
    this.everyFrame,
  });

  /// Added under the demo's model pivot, in place of the model unless
  /// [keepModel] says otherwise.
  final List<SceneNode> nodes;

  /// Whether the loaded model stays, for the one scene that needs a rigged
  /// and morphing mesh beside what it builds.
  final bool keepModel;

  /// Called before every frame with the renderer's index of the frame about
  /// to be drawn, and the loaded model.
  ///
  /// **The frame index, not a count of builds or the clock**, because it is
  /// the number the jitter, the noise and the history are functions of: a
  /// motion keyed to it is the same motion on every backend and every run,
  /// and the capture lands on the same step of it. A staged scene also places
  /// its camera here when it needs a pose the orbit cannot give.
  final void Function(int frame, ModelInstance model)? everyFrame;
}

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
    this.morphWeights = const <double>[],
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
    this.cameraAt,
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
    this.stage,
    this.configure,
  });

  /// Builds what the scene draws in place of the loaded model, or null to
  /// draw the model.
  ///
  /// **One hook rather than a flag per scene**, because the scenes 0.8 added are
  /// thirty arrangements and not thirty variations of a model: a floor under
  /// sixty-four lights, glass in front of a wall, a wheel turning. A flag each
  /// would have put thirty `if`s into the demo's staging, where the rooms
  /// above already take five. Each builder lives in `GoldenStages` and is
  /// the same construction as the software test that carries the scene's
  /// name.
  ///
  /// Asynchronous because two of them read a file or bake one first — the
  /// splat asset and the impostor atlas — and the frame counted as the first
  /// must already have them.
  final GoldenStaging? stage;

  /// The settings this scene changes beyond the ones named above, applied to
  /// what the demo would otherwise draw with. Null changes nothing, which is
  /// what keeps every scene recorded before it byte for byte where it was.
  final RenderSettings Function(RenderSettings settings)? configure;

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

  /// Where the orbit camera is on each frame, counted from the first frame of
  /// the staged scene — `G0`. Null holds [yaw] and [pitch] for the whole run.
  ///
  /// A golden is always many frames: the runner captures frame
  /// `GoldenRunner.captureFrame` of one renderer, so anything temporal (a
  /// jitter, a history, a velocity) has settled or accumulated by the time it
  /// is compared. What a still scene could not do was move its camera, and
  /// that is what a temporal resolve has to be tested against. A function of
  /// the frame and nothing else, so the capture is the same every run.
  final ({double yaw, double pitch}) Function(int frame)? cameraAt;

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

  /// Morph weights written onto every morphing mesh after the clip is frozen,
  /// or empty to leave whatever the clip and the file set.
  ///
  /// **Set by hand because the useful models set them by hand.** The one model
  /// in this repository that is both rigged and morphing carries weights
  /// channels that are all zeros — its author drives those expressions from
  /// code — so a scene that only froze a clip would record a face at rest and
  /// call it a morph test. Written after the seek, so the clip moves the bones
  /// and this decides the shape they carry.
  final List<double> morphWeights;

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
