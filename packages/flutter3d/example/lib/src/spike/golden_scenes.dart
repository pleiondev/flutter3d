import 'package:flutter3d/flutter3d.dart';

import 'golden_extras.dart';
import 'golden_scene.dart';

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
  for (final model in LightingModel.builtIn)
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

  // The debug overlay, which is otherwise never exercised by anything
  // automatic. All five overlays, because the point of one frame here is that
  // every kind of line the engine can draw reaches a pixel: bounds, axes, light
  // gizmos, vertex normals and a camera frustum.
  //
  // **The last two were described and not drawn.** The site's caption for this
  // frame named normals and a frustum while the scene switched on three
  // overlays out of five, so the two line kinds a reader was told about were
  // the two nothing had ever recorded. `addNormals` walks the mesh source and
  // `addFrustum` inverts a view-projection; neither had a picture anywhere.
  //
  // The frustum needs a second camera — the one being looked through is
  // excluded, since its frustum is the edge of the screen — so the demo adds
  // one for this scene alone. See `_placeGoldenCamera` in main.dart.
  const GoldenScene(
    name: 'debug-overlay',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    debug: DebugDrawOptions(
      bounds: true,
      axes: true,
      lightGizmos: true,
      normals: true,
      cameraFrustums: true,
      // Named rather than left at zero, which picks two per cent of the scene
      // diagonal — about four pixels on a unit cube at this framing, which is a
      // fuzz along the silhouette rather than twenty-four readable spikes. A
      // golden names every input that changes a pixel, and this is one.
      normalLength: 0.25,
    ),
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

  // The same burst with bloom off, and it exists to split one number in two.
  //
  // `particles-burst` is the widest disagreement between the software backend
  // and Impeller — nearly five percent — and bloom sits between the additive
  // quads and the picture, spreading any difference in what was accumulated
  // into soft blobs several times their size. So the frame cannot say whether
  // the accumulation differs or the post chain does.
  //
  // With bloom off, it can. The same split `pointShadowMap` makes for the cube
  // atlas, and for the same reason: one number could not say which half was
  // wrong.
  // The particle scene with no particles in it: the control. If this agrees at
  // the suite's usual floor then whatever `particles-plain` disagrees about is
  // the particles, and if it does not then the disagreement was never theirs.
  const GoldenScene(
    name: 'particles-none',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
  ),

  // A pool that has been round several times. See GoldenExtras.recycled: every
  // other particle fixture warms up for less than one lifetime, so none of them
  // can see how slots are reused.
  const GoldenScene(
    name: 'particles-recycled',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),

  // Four sprites at four distances, each landing on a different level of a mip
  // chain. The only scene with a chain in it at all — see
  // GoldenExtras.particleSprite.
  const GoldenScene(
    name: 'particles-textured',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),

  // Five spheres drawn as one instanced call. The only scene in the suite that
  // draws anything more than once, and therefore the only one that says whether
  // each backend's instanced path works — see GoldenExtras.meshParticles.
  const GoldenScene(
    name: 'particles-mesh',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),
  // Ordinary meshes through the instanced vertex stage: twenty-five cubes as
  // one draw, each placed, turned, scaled and tinted by its own slot-1 record,
  // casting onto the ground. Shadows on, because the instanced stage serves
  // the shadow passes too and a batch that cast nothing would pass this
  // scene while failing every level built from one.
  const GoldenScene(
    name: 'instanced-field',
    source: 'Cube',
    bloom: false,
    instances: 25,
  ),

  // A floor and a wall lit by nothing but a hand-built lightmap: the
  // lightmapped vertex stage reading the colour as a coordinate, RGBM
  // decoded, and the lit model adding it. No lights, so nothing else can
  // put light where the map does not. See GoldenExtras.lightmappedRoom.
  const GoldenScene(
    name: 'lightmapped-room',
    source: 'Cube',
    // A name no light has, which is how this set says "none": an empty set
    // means "the default", and the default is every lamp in the demo on.
    lights: <String>{'none'},
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.3,
    pitch: 0.45,
    lightmapped: true,
  ),

  // The demo's ground plane under the cube, stretched to the horizon and
  // retextured with a checkerboard that has a mip chain and a sampler asking
  // for eight-way anisotropy, seen from just above it. The floor is the
  // picture and the cube is what the camera happens to frame: at this pitch
  // the far half of the checks — a few texels tall and many wide — fills the
  // frame behind and beside it, which is the one footprint a trilinear
  // sampler cannot serve. It blurs the checks to serve the long axis, and an
  // anisotropic one keeps them. The hardware backends draw the taps and the
  // software one answers `maxAnisotropy` of one and draws without them, so
  // the cross-backend budget for this scene is the measured size of that
  // difference — see GoldenExtras.checkerFloor.
  const GoldenScene(
    name: 'anisotropic-floor',
    source: 'Cube',
    shadows: false,
    bloom: false,
    yaw: 0.35,
    pitch: 0.06,
    groundScale: 12.0,
    anisotropicFloor: true,
  ),

  // A wall, a cube behind it and a cube in front, the two cubes on the x-ray
  // layer: the hidden one is drawn as a flat silhouette through the wall, the
  // visible one is lit as any cube is, and where the near cube's lit face
  // covers the far one on screen the silhouette is notched around it — which
  // is the stencil doing the half of the job a depth test alone cannot. That
  // notch is the frame's reason for existing; see GoldenExtras.xrayRoom for
  // where the two footprints have to sit for it to be there at all.
  //
  // Bloom off so the silhouette's colour is the colour asked for and not a
  // glow of it; the camera straight on, so which cube the wall hides does not
  // depend on how the demo frames the scene.
  const GoldenScene(
    name: 'stencil-xray',
    source: 'Cube',
    bloom: false,
    yaw: 0.0,
    pitch: 0.25,
    xray: XraySettings(layerMask: GoldenExtras.xrayLayer),
  ),

  // A mirror ball and a brushed one over four coloured walls, reflecting them
  // through a probe: six views drawn into the faces of a cube, the chain
  // convolved into its levels on the device, and the physical model picking
  // the nearest probe. Nothing else in the suite renders into a cube face or
  // a mip level, so this is the picture that says whether a face is mirrored,
  // upside down or transposed — and a face wrong in any of those ways is a
  // reflection that looks plausible and shows the wrong wall.
  //
  // The brushed ball is what pins the chain: a mirror alone reads the base
  // level and would pass with the levels below it never filtered.
  //
  // No sun shadows and no bloom, so the frame is the room and its
  // reflection; the walls are lit by the sun and the key light as every
  // scene's model is.
  const GoldenScene(
    name: 'probe-car',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.7,
    pitch: 0.35,
    reflectionProbe: true,
  ),

  // Eight quads stacked at one point: addition alone. See stackedParticles.
  const GoldenScene(
    name: 'particle-stack',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),

  // One particle, so a disagreement has one cause. See GoldenExtras.oneParticle.
  const GoldenScene(
    name: 'particle-one',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.0,
    pitch: 0.0,
    particles: true,
  ),

  const GoldenScene(
    name: 'particles-plain',
    source: 'Cube',
    shadows: false,
    bloom: false,
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
  // The view model *with point shadows on*, which no scene had ever combined.
  //
  // The gap this closes is not in the picture but in the declaration model. The
  // atlas is bound deep inside the renderer's node encoder, which two graph
  // nodes reach — the scene, which declares it reads the atlas, and this one,
  // which reaches it through `RenderServices.encodeScene`. `view-model-overlay`
  // runs with shadows off, so nothing automatic drew a weapon that samples the
  // atlas at all, and passing the wrong texture down that path would have shown
  // up first in a shipped game.
  //
  // The held box is deliberately placed on the far side of the world cube from
  // the point light, so the face turned towards the light is *inside* the
  // cube's shadow. That is not decoration: it was checked by breaking it. With
  // the atlas replaced by the white fallback on this path — the exact
  // regression a previous attempt at the fix would have shipped — the box's
  // shadowed face lights up and **4335 of 172800 pixels** differ. A scene where
  // the weapon happened to stand clear of every shadow would have passed either
  // way and pinned nothing.
  const GoldenScene(
    name: 'view-model-point-shadow',
    source: 'Cube',
    bloom: false,
    ground: false,
    lights: <String>{'fill light'},
    pointShadow: true,
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

  // Four casters in an atlas with rows to spare. The single-caster golden above
  // passes whether the atlas holds one row or six, so it said nothing while
  // three of the rows were being cleared away; this scene is the one that fails
  // when they are.
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

  // A caster well clear of the floor, which no other scene has.
  //
  // Every shadow golden until now put the model on the ground, so the gap
  // between caster and receiver was near zero everywhere and the penumbra had
  // no room to open. That is why widening the filter moved about a hundred
  // pixels whatever drove it, and why contact hardening could not be told
  // apart from a fixed kernel: there was no contact to harden against.
  const GoldenScene(
    name: 'cube-shadow-gap',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'fill light'},
    pointShadow: true,
    groundDrop: 2.5,
  ),

  // A cone rather than a cube, which nothing above draws.
  //
  // A spot borrows the whole point-shadow path — the atlas, the slot pool, the
  // distance format, the contact-hardening filter — and switches five of its
  // six columns off. That reuse is the argument for building it this way and
  // also the reason it can be wrong quietly: the shader picks a cube's column
  // by dominant axis, and for a spot aimed down from above, the dominant axis
  // is the one column that is deliberately blank. On the software rasteriser
  // that mistake shows as no shadow at all; here it shows as no shadow at all
  // too, which is why the pair is worth recording rather than either alone.
  //
  // The spot alone, with the fill light off: two lights on a small model fill
  // in each other's shadows, and a scene where they do says nothing about which
  // of them drew what.
  const GoldenScene(
    name: 'spot-shadow',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'spot light'},
    spotShadow: true,
    // Held clear of the floor for the same reason `cube-shadow-gap` is: a
    // caster resting on its receiver has no gap for the penumbra to open in,
    // and a cone's filter is the place where the ninety-degree assumption used
    // to be baked in. With the model on the ground this would pass whether or
    // not `tanHalf` reached the estimate at all.
    groundDrop: 2.5,
  ),

  // Eight casters for six rows: two lights that keep lighting the model and
  // cast nothing, which is the whole of what this scene is for.
  //
  // Until the allocator existed the rows went to the first four point lights in
  // scene order, so a level with five torches had one that could not cast a
  // shadow anywhere, ever. The scene was six casters against four rows then.
  // Raising `Renderer.kShadowedLights` to six gave every one of them a row and
  // left the ranking nothing to decide — a full atlas rather than a contended
  // one, passing whether the allocator ranked anything or not — so the count
  // went to eight and the contention came back.
  //
  // **Relevance and scene order pick different sets, which is the thing to
  // check whenever this count moves.** Priority is `range / distance to the
  // camera` and every extra light here has the same range, so the ranking is
  // by distance alone; `_placeSceneLights` shrinks each extra light's radius
  // with its index, so the lights added last are the nearest. Scene order would
  // deny the last two, relevance denies two from the middle. If the two ever
  // agree the golden passes either way and pins nothing.
  //
  // The atlas rather than the lit image, for the reason `cube-shadow-many`
  // shows the atlas: occupied rows are countable, and a lit view of two missing
  // shadows among six is a slightly brighter picture.
  const GoldenScene(
    name: 'cube-shadow-crowded',
    source: 'Teapot',
    bloom: false,
    lights: <String>{'key light', 'fill light'},
    shadowMap: true,
    pointShadow: true,
    extraPointShadows: 7,
  ),

  // The sky, which is the only scene in this set that has one.
  //
  // Every other scene draws against the clear colour, and that is what keeps
  // sixty recorded images valid: `SkySettings.enabled` is false by default and
  // the disabled path emits nothing at all. Turning it on anywhere else would
  // re-baseline the lot in a commit about something else.
  //
  // What it pins: the gradient, the sun's disc — which is analytic and half a
  // degree across, so it is the part most sensitive to the ray being built
  // wrongly — and the fact that the sky lands *behind* the teapot rather than
  // over it.
  //
  // **Bloom off, and the disc kept modest.** The first recording of this scene
  // asked for intensity 40 with bloom on, and the result was a flat lilac wash:
  // the glow swallowed the gradient it was supposed to be sitting in, and the
  // golden pinned a picture in which nothing about the sky could be read. A
  // reference nobody can read is a reference that cannot fail usefully.
  //
  // The colours are the defaults, because `Vector3` has no const constructor
  // and a scene that had to be built at runtime would be the only one here.
  const GoldenScene(
    name: 'sky',
    source: 'Teapot',
    ground: false,
    bloom: false,
    sky: SkySettings(enabled: true, sunIntensity: 6.0),
  ),

  // A look the engine never shipped, drawn through a bundle loaded from
  // bytes at run time: the example's own `ExampleStripes`, compiled into
  // `assets/shaders/example.f3dshaders` by the example's build script and
  // handed to `GraphicsDevice.loadShaders` before the renderer is built. The
  // picture is bands by normal height, which nothing in the engine draws —
  // and the proof is by refusal as much as by pixel: leave the bundle out and
  // `Renderer.create` throws for want of the stage, on every backend.
  //
  // No lights, shadow or bloom: the stage reads none of them, and a scene
  // about where a shader came from should not depend on anything else.
  const GoldenScene(
    name: 'loaded-shader',
    source: 'obj: Teapot',
    lighting: GoldenExtras.stripes,
    shaderBundle: GoldenExtras.exampleShaderBundle,
    shadows: false,
    bloom: false,
    ground: false,
  ),
  // The teapot on its floor, exposed by the frame rather than by the setting:
  // the luminance pass, the readback, the meter and the composite reading the
  // meter's answer, on every backend.
  //
  // **With the ground, and that is the point of choosing this model.** The
  // meter reads the brightest fifth of the frame, and a sphere alone against
  // black is a tenth of it — the band reaches into the black, the target
  // shoots past the ceiling, and the scene pins an exposure of exactly eight
  // whatever the meter did on the way. A floor fills the frame with lit
  // stone, so the metered value lands *between* the limits and the picture
  // moves with the arithmetic that put it there. Instant adaptation, and the
  // reason is on `GoldenScene.autoExposure`: the frame captured has to be the
  // frame after any metered frame, whatever the clock said in between.
  const GoldenScene(
    name: 'auto-exposure',
    source: 'obj: Teapot',
    shadows: false,
    bloom: false,
    autoExposure: AutoExposureSettings(
      enabled: true,
      speedUp: double.infinity,
      speedDown: double.infinity,
    ),
  ),

  // Two glowing blocks standing on a polished floor, with their reflections in
  // it. The first frame in this repository to show a screen-space reflection at
  // all — the effect is on the engine's front page and no golden in any set had
  // ever switched it on, which is how the march came to be reading the surface
  // buffer upside down on two backends and measuring thickness in window depth
  // on all three. See `GoldenExtras.mirrorRoom`.
  //
  // A low pitch, because a floor seen from above reflects the sky this scene
  // does not have and the Fresnel term goes with the angle; not so low that the
  // floor is a band a few rows tall, which is what 0.12 gave. The march is
  // stepped finer and further than the defaults — forty steps of 12 cm rather
  // than twenty-four of 18 — because at this angle a mirror image is
  // foreshortened, and a stride that overshoots it leaves the reflection in
  // stripes.
  //
  // Not `debugOnly`: the reference is the picture the effect is for, a floor
  // with something in it, rather than the diagnostic view of what the march
  // found. The diagnostic view is `ReflectionSettings.debugOnly` and is a
  // switch a person reaches for, not a frame to keep.
  //
  // Shadows off and bloom off: emissive blocks and a glow would put light on
  // the floor that is not a reflection, and this frame has to be readable as
  // "what is in the floor came out of the march".
  const GoldenScene(
    name: 'screen-space-reflections',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.55,
    pitch: 0.32,
    reflections: ReflectionSettings(
      enabled: true,
      steps: 40,
      stride: 0.12,
      thickness: 0.2,
      intensity: 0.9,
    ),
  ),

  // An inside corner with ambient occlusion darkening it, which is the only
  // thing in this repository that would ever compare the two GPU
  // transcriptions of `ssao.frag` against the software one. What Impeller and
  // WebGL had until now was that the stage compiles and that
  // `('FullscreenVertex', 'Ssao')` links — nothing about what it darkens.
  //
  // The radius is 0.9 rather than the default half metre: this room is 2.8
  // metres across, and the setting has to suit the scene rather than the
  // renderer — the default reaches a third as far and darkens a third as much
  // of the frame. The strength is turned to one so the difference between a
  // corner and an open wall is as large as the effect can make it; a golden
  // recorded at a setting nobody can see is a golden that cannot fail usefully,
  // which is the mistake the first `sky` recording made.
  //
  // See `GoldenExtras.occlusionCorner` for why the room is flat grey and lit by
  // nothing but ambient.
  const GoldenScene(
    name: 'ambient-occlusion-corner',
    source: 'Cube',
    shadows: false,
    bloom: false,
    ground: false,
    yaw: 0.75,
    pitch: 0.3,
    ambientOcclusion: AmbientOcclusionSettings(
      enabled: true,
      radius: 0.9,
      strength: 1.0,
    ),
  ),
];

/// Looks up a scene by name.
GoldenScene? goldenSceneNamed(String name) {
  for (final scene in kGoldenScenes) {
    if (scene.name == name) return scene;
  }
  return null;
}
