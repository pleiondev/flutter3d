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
  });

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

  /// Makes the scene's first point light a shadow caster, so the cube atlas
  /// has something in it.
  final bool pointShadow;

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

/// The frames CI renders.
///
/// Chosen to cover the things that break silently rather than to be exhaustive:
/// each lighting model, because the shader bundle is tied to the Flutter version
/// and a new SDK can change one without any error; the teapot, whose normals are
/// generated; a shadow; a bloom highlight; a normal-mapped surface; and a posed
/// rig. Between them, most of what the engine does reaches a pixel here.
final List<GoldenScene> kGoldenScenes = <GoldenScene>[
  // One model, every lighting model. The cheapest way to notice that a shader
  // stopped compiling the way it used to.
  for (final model in LightingModel.values)
    GoldenScene(
      name: 'lighting-${model.shaderName.toLowerCase()}',
      source: 'Sphere',
      lighting: model,
      // No shadow or bloom here: this set is about the shading models, and a
      // change in either would show up in all six at once and say nothing about
      // which.
      shadows: false,
      bloom: false,
      ground: false,
    ),

  const GoldenScene(
    name: 'teapot-generated-normals',
    source: 'obj: Teapot',
    shadows: false,
    bloom: false,
    ground: false,
  ),

  // The shadow, with the ground it lands on.
  const GoldenScene(name: 'shadow-teapot', source: 'obj: Teapot', bloom: false),

  // Bloom, on a sphere bright enough to have something above display white.
  const GoldenScene(
    name: 'bloom-sphere',
    source: 'Sphere',
    shadows: false,
    ground: false,
  ),

  // Normal mapping and the bitangent sign, face on, where the model is designed
  // to be read.
  const GoldenScene(
    name: 'normal-mapping',
    source: 'map: Tangent gen',
    yaw: 0.0,
    pitch: 0.0,
    shadows: false,
    bloom: false,
    ground: false,
  ),

  // A posed rig at a fixed clip time, which is the only way an animated model
  // is comparable at all.
  //
  // No ground, and that is the fix for a flake rather than a preference. The
  // demo sizes its floor from the scene's bounds, and a skinned mesh has no
  // bounds until its skeleton has been posed — which happens during the first
  // draw. So the floor came out a different size depending on whether the
  // measurement landed before or after, and this golden failed about one run in
  // three on a difference that had nothing to do with skinning. Ground and
  // shadow are what shadow-teapot is for; this scene tests one thing.
  const GoldenScene(
    name: 'skinned-figure',
    source: 'skin: Figure',
    animationTime: 0.75,
    yaw: 0.6,
    pitch: 0.25,
    bloom: false,
    ground: false,
  ),

  // The debug overlay, which is otherwise never exercised by anything automatic.
  const GoldenScene(
    name: 'debug-overlay',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    debug: DebugDrawOptions(bounds: true, axes: true, lightGizmos: true),
  ),
  // The particle plugin, which the plugin seam moved out of the renderer and
  // which nothing automatic had drawn since. A fixed seed and a whole number
  // of fixed steps, so the burst is the same burst every run.
  //
  // Bloom on, because half of what particles are for is feeding it: additive
  // quads in the HDR target are what makes a burst read as light rather than
  // as orange confetti.
  const GoldenScene(
    name: 'particles-burst',
    source: 'Cube',
    shadows: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),

  // The view model plugin, in its own pass over the finished scene. The held
  // box sits where the world's depth would clip it if the stage were wrong,
  // which is the half of this that a picture can actually prove.
  const GoldenScene(
    name: 'view-model-overlay',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    viewModel: true,
  ),
  // The surface buffer, which nothing samples yet and which therefore nobody
  // had looked at. A picture of it is the only way to find out whether the
  // normals are right side up before an effect starts reflecting off them —
  // and pinning it means the next change to WriteSurface cannot quietly
  // scramble it.
  //
  // No tone map and no bloom: a normal encoded as a colour is not a light
  // value, and a curve applied to one turns a wrong answer into a plausible
  // picture. The renderer forces both off for this view.
  const GoldenScene(
    name: 'surface-buffer',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    surfaceBuffer: true,
  ),
  // The shadow map itself, which nothing had ever shown. Needed because the
  // map is about to hold a cube atlas, and an atlas nobody can look at is an
  // atlas whose layout nobody can check.
  const GoldenScene(
    name: 'shadow-map',
    source: 'Teapot',
    bloom: false,
    shadowMap: true,
  ),

  // The point light's cube atlas: three tiles across, two down, each a
  // ninety-degree view from the light. Pinned because the layout is a decision
  // written twice — once in the renderer's face list and once in the shader's
  // face selection — and a golden is what stops the two from drifting.
  const GoldenScene(
    name: 'cube-shadow',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'key light'},
    shadowMap: true,
    pointShadow: true,
  ),
];

/// Looks up a scene by name.
GoldenScene? goldenSceneNamed(String name) {
  for (final scene in kGoldenScenes) {
    if (scene.name == name) return scene;
  }
  return null;
}
