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
    this.extraPointShadows = 0,
    this.moverFrames = 0,
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

  // The point light's cube atlas: six tiles across, four down, each a
  // ninety-degree view from a light. Pinned because the layout is a decision
  // written twice — once in the renderer's face list and once in the shader's
  // face selection — and a golden is what stops the two from drifting.
  //
  // The fill light must be ON, and this is the whole reason to say so here: the
  // caster mark is set on it, but the light set switched it off, so no atlas
  // was ever allocated and the composite fell back to the directional map. The
  // golden recorded that instead and passed on it for as long as it existed.
  const GoldenScene(
    name: 'cube-shadow',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'key light', 'fill light'},
    shadowMap: true,
    pointShadow: true,
  ),

  // The lit view of a point shadow — the only scene that reads the cube atlas
  // rather than displaying it.
  //
  // Both atlas goldens show the map itself, so between them they pinned every
  // line that writes a face and not one that samples it: the slot lookup, the
  // face pick, the v flip and the tile inset were all unpinned while looking
  // thoroughly covered. One light rather than four, because four fill in each
  // other's shadows and leave nothing to read.
  const GoldenScene(
    name: 'cube-shadow-lit',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'fill light'},
    pointShadow: true,
  ),

  // Four casters, four rows. The single-caster golden above passes whether the
  // atlas holds one row or four, so it said nothing while three of the four
  // rows were being cleared away; this scene is the one that fails when they
  // are.
  //
  // The atlas rather than the lit image, because four lights around a model
  // fill in each other's shadows — the lit view of a three-row loss is a
  // slightly darker picture, which is exactly the kind of difference a person
  // talks themselves into accepting. Occupied rows are countable.
  const GoldenScene(
    name: 'cube-shadow-many',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'key light', 'fill light'},
    shadowMap: true,
    pointShadow: true,
    extraPointShadows: 3,
  ),

  // A caster that has moved, which nothing else here has.
  //
  // Every other scene freezes the turntable so the recorded frame and the
  // compared frame match, and the consequence went unnoticed: no golden could
  // show a shadow following anything. That mattered the moment the atlas
  // started skipping faces whose contents had not changed — a scheduler that
  // never refreshed anything would leave the opening pose's shadow on the
  // ground and every static golden would still pass.
  //
  // The model turns for sixty frames and then holds, so the capture at frame
  // ninety is settled, and the shadow on the floor has to be the shadow of the
  // pose it settled into.
  const GoldenScene(
    name: 'cube-shadow-mover',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'fill light'},
    pointShadow: true,
    moverFrames: 60,
  ),

  // Six casters for four rows, which is the case the allocator exists for.
  //
  // Until it existed the rows went to the first four point lights in scene
  // order, so a level with five torches had one that could not cast a shadow
  // anywhere, ever. Now the rows go to whichever four look largest from the
  // camera. This scene is only meaningful if relevance and scene order pick
  // *different* sets — check that when re-recording, because if they agree the
  // golden passes either way and pins nothing.
  const GoldenScene(
    name: 'cube-shadow-crowded',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'key light', 'fill light'},
    shadowMap: true,
    pointShadow: true,
    extraPointShadows: 5,
  ),
];

/// Looks up a scene by name.
GoldenScene? goldenSceneNamed(String name) {
  for (final scene in kGoldenScenes) {
    if (scene.name == name) return scene;
  }
  return null;
}
