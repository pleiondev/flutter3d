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
    this.sky = const SkySettings(),
    this.instances = 0,
  });

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
  );
}
