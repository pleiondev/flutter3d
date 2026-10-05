## Unreleased

- **A lint for cues told apart by hue alone.** `ColorVision.confusions`
  takes a palette by name and answers the pairs normal eyes tell apart
  and a protan, deutan or tritan does not, with who and how near, in CIE
  1976 ΔE (`ColorVision.difference`); a pair nobody tells apart is not
  its business. The fix for a pair it answers is a second cue, not a
  third colour.

- **Colour vision, as a colour table.** `ColorVision.simulate` shows the
  picture as someone missing a cone sees it — protan, deutan or tritan,
  Machado, Oliveira and Fernandes's matrices, blended by severity — and
  `ColorVision.correct` moves what they run together to where they can
  tell it apart, Fidaner's shift of the error. Both are a matrix in linear
  light; `toStrip` bakes one into the strip `LookSettings.lut` reads after
  the tone map, with a game's own `CubeLut` grade applied first when it
  has one, and `upload` puts it on a device. No shader of its own: the
  table pass every backend has draws it, and the software renderer's frame
  through it is the frame `ColorVision` predicts to within the table's
  interpolation. At no severity the table is the neutral one, byte for
  byte.

- **Root motion through the root's parent, and snapshots that pose again.**
  `rootDelta` and holding the root over rest are in the pose's space,
  through the root's parent at rest: a Z-up armature in centimetres walks
  and bobs as it should. A graph's snapshot keeps each goal's inputs (what
  it reaches, looks at, stands on) and the parameters by name, so
  `restore` makes the pose as it was. `Pose.setFrom`;
  `AnimationGoal.save`/`restore`; `AnimationParameters.loadByName`.

- **Goals ask for the joints they need, not the whole pose.**
  `Pose.worldMatrixOf` composes one joint's world matrix down its own
  chain. `TwoBoneIk`, the look, the foot plant and the dungeon's foot rays
  use it: a step's goals on the hero's rig take a quarter of the time the
  full walks did. A look turns by `Portable.atan2`, since goals run in a
  game's step now.
- **`AnimationGoal.fadingTo`** says where a goal's weight is going, so a
  caller decides whether to fade again from the goal, which a snapshot
  keeps, rather than from a flag of its own.
- **Feet put on the ground under them.** `FootPlantGoal` takes a
  `FootLeg` per leg: hip, knee and ankle bent by `TwoBoneIk` towards a
  pole joint or direction. Each has a `ground` height the game writes from
  a ray down. A foot on a step is lifted onto it. A foot below the clip's
  floor lowers the hips by as much, so the other knee bends rather than
  one leg hanging. A rig whose foot is a bone of its own on the root, as
  the Quaternius characters export their IK targets, names it as `foot`,
  and it moves with its ankle. On flat ground nothing moves.

- **`.f3d` keeps `extras`.** A new section, 28, holds every `extras`
  block a document carries: the document's own, and those of nodes,
  materials, skins and clips. Each is JSON tagged with its owner's kind
  and index. A clip's markers now survive conversion, which they did not
  before; the writer warned that extras were dropped and dropped them. A
  document with none writes the bytes it did. A reader that predates the
  section skips it, as unknown sections are skipped.
- **Animation graphs as JSON, kept in a model file.**
  `AnimationGraphJson.encode`/`decode` turn an `AnimationStateMachine`
  into plain JSON and back. Every field is named, states, clips and
  parameters by name, defaults left out. A wrong shape throws a
  `FormatException` saying where, such as `states[1].blend.points[0].at is
  "fast", not a number`. `keep` puts graphs by name into a document's root
  `extras` under `animationGraphs`, and `graphsIn` reads them back, so a
  model carries its characters' graphs through `.f3d` and glTF alike.

- **An animation graph saves and restores.** `AnimationGraph.save()` is
  everything a step changes, as JSON: the state by name and its playhead,
  the crossfade, the parameters, each layer's graph and weight, and each
  goal's weight. `restore` puts it back and makes the pose again without
  a step, since a step would take a transition the saved graph had not. A
  state the machine no longer has leaves the graph in its entry. Restored
  mid-fade, mid-blend, with a layer and a look still fading in, a graph
  steps on to the same pose, root travel and markers as the one it was
  saved from. `AnimationParameters.load` puts every value back at once.

- **Blend spaces across a plane.** `AnimationBlendSpace(across:)` names a
  second parameter, and each `BlendPoint` gets a `y`. This gives a walk
  forward, back and to each side by the two speeds along and across the
  body. Every point plays by the inverse square of its distance: all of
  one clip standing on its point, smoothly between. One phase, root
  motion and markers work as along a line. `problems` checks the second
  parameter and that no two points share a place.

- **Root motion from the animation graph.** With `rootNode` set, the
  graph takes that node's travel along the floor out of the pose and
  hands it over as `rootDelta`. The node's x and z are held at rest and
  its height stays the clip's. The travel is the clip's own, unwound
  across the loop's turns, through a blend by its weights and through a
  crossfade by the fade's. `rootDeltaIn` carries it into the world by the
  model's matrix, turned, scaled and laid flat. The turns are read off the
  playhead, elapsed time minus where it stands. Floored from elapsed time
  alone, a sum of sixtieths a hair under a turn counted one turn fewer
  than the playhead had wrapped, and the body leapt a stride back.

- **Goals in the animation graph: IK after the pose.**
  `AnimationGraph.goals` is laid on the posed frame, in the pose's own
  space. `ReachGoal` bends a two-bone chain to a target through
  `TwoBoneIk`. `LookGoal` turns a joint so that what faced `forward` at
  rest faces the target, at most `limit` radians. Each has a weight that
  `fadeTo` moves on the steps. The look undoes the joint's rest frame to
  find its face. Written with vector_math's `Quaternion.rotated`, which
  turns by the inverse, it faced the wrong way only once the animation had
  turned the joint off its rest, so the test turns it.

- **Markers in the animation graph.** An `AnimationMarker` names a moment,
  such as a foot down or a blow landing. A state carries them as shares of
  its cycle, a blend's cycle included. A clip reads its own from its glTF
  `extras` as `{"markers": [{"time": 0.3, "name": "step"}]}`, in seconds.
  `.f3d` does not keep extras, so only a model read from glTF has them
  until `.f3d` does. `AnimationGraph.passed` lists those the last step went
  through, each once a cycle, one at nought on entering the state, once in
  all for a clip played once, and only from the state being entered during
  a crossfade.

- **Layers in the animation graph.** `AnimationGraph.layers` holds
  `AnimationGraphLayer`s. Each is a graph of its own, with its own states
  and parameters, evaluated on the same steps and laid on the base pose
  where its `AnimationMask` covers. Override replaces the base by
  `weight`. Additive lays its distance from the skeleton's rest on top: a
  translation added, a turn applied after the base's in the node's own
  frame, a scale multiplied. `fadeTo` moves the weight over seconds of
  steps, so a layer comes in without a pop. `AnimationMask.below` masks a
  node and everything under it, such as an upper body from its spine. A
  layer of another skeleton is refused.

- **Blend spaces in the animation graph.** An `AnimationState` can blend
  instead of playing one clip. `AnimationBlendSpace` names a float or
  integer parameter and two or more `BlendPoint`s, a clip at each value,
  and between two points the state plays some of each. The clips share one
  phase, which moves at the speed of the length the mix would have, so a
  walk of a second and a run of half a second go round together at three
  quarters of a second when half and half, with the feet down at once. An
  exit time out of a blend counts in cycles of the mix. `problems` names a
  blend with too few points, points that do not rise, a missing clip or
  parameter, a parameter that is not a number, and a clip named beside a
  blend.

- **`Skeleton.bindPoseOf`**: a joint's bind pose in the skinned mesh's
  space, the inverse of its inverse bind matrix. A ragdoll takes its
  joints' limits from it.

- **Nothing in the browser's build imports `dart:io` or `dart:isolate`.**
  Decoding and encoding models and transcoding KTX2 off the main isolate go
  through `src/engine/platform/background.dart`: `Isolate.run` natively,
  in place in the browser. The model decoder's sibling-file ports are in
  `model_isolate.dart`. `FileAssetSource` and `fileUriResolver` read
  through `platform/files.dart`, which is `dart:io` natively and refuses
  with a reason in the browser. Each is chosen by `if
  (dart.library.js_interop)` at compile time, as pub.dev reads it. Native
  behaviour is unchanged: the same `FileSystemException`, the same
  isolates. `isMissingFile` tells a missing file on either. The pubspec
  declares all six platforms, and a structure rule now holds every package
  that says it runs on the web to imports the browser can have.

- **Instance attributes.** `InstancedMeshNode.setInstanceData` (and `data`
  on `addInstance` and `acquire`, `InstanceHandle.setData`) gives each copy
  of a batch four numbers of the game's own, after its colour in a record
  now twenty floats long. The instanced vertex stage hands them on as
  `v_instance`, the other mesh stages as nought, and a material written in
  the language reads them as `instance` — a colour, a team, a phase only the
  game knows. The emitted stage declares the varying only when it reads it.
  `material-instance-data` is in all four golden sets.

- **Lighting hooks in the material language.** A `light { … }` block runs
  once per light inside the engine's light loop and returns how the surface
  answers it — a toon ramp, a BRDF of the author's — which the engine
  multiplies by the light's radiance, `n·l` and shadow, as it does
  `ShadeLight` of every lit model. It reads `lightDir`, `halfDir`, `nDotL`,
  `nDotH` and `vDotH`; the fragment body reads `lit`, the surface lit
  through the block with the ambient, the lightmap and the emissive added
  as Lambert adds them. A material with a block binds as a lit model — the
  maps, the shadows, the light list — and the parser refuses a block the
  fragment body never reads, since the compiled shader would drop it and
  everything bound for it. `evaluateMaterialLight` runs the block on the
  software backend. `material-light-hook` is in all four golden sets.

- **`Renderer.addMaterials` and `removeMaterials`**: more than one bundle of
  materials, added after the renderer was made — `P8`. Each `.f3dmat` the
  build hook compiles is a bundle of its own. Added later is consulted
  earlier, so a bundle naming a stage another has replaces it; what the
  renderer resolved by name is forgotten and linked again at the next draw.

- **Caustics.** `ShadowSettings.caustics` (with `translucentCasters`, off by
  default) follows the sun's light through every caster with a volume — a
  transmission and a thickness. Each is drawn from the sun into two small
  maps of its own, near faces and far faces; one photon per texel is bent in
  and out by Snell's law, dimmed by Fresnel and by its volume's absorption
  over the path, followed to the first opaque surface below, and added into
  the atlas there, sized by where its neighbours land so that light is
  neither made nor lost. The caster itself stops the light, so what lands
  under it is what its photons bring: the bright focal line and dark rim a
  glass of water throws, in the colour of what is in it. Thin-walled casters
  keep the shading they had. Static meshes only; `causticPhotons` sets the
  grid.
- **A see-through caster can paint what it lets through.** Its base colour
  map multiplies the transmittance, and neither is held to one, so a card
  marked `ShadowCastingMode.shadowsOnly` can carry a picture of where light
  went: darker where it was turned away, brighter where a lens gathered it.
  `MeshNode.receivesTranslucentShadows` (true by default) lets a surface that
  stands in front of a translucent caster, such as a label on a glass, opt
  out of being shaded by it.
- **See-through casters shade the sun by what they let through.**
  `ShadowSettings.translucentCasters`, off by default. A blended or
  transmissive material is drawn into the sun's atlas after the opaque
  casters, into the three channels that held nothing, as how much of red,
  green and blue it lets through: its opacity, its transmission tinted by its
  colour and by what its volume leaves after its thickness
  (`attenuationColor`, `attenuationDistance`), and the Fresnel loss of its
  index at that angle. A transmitting material's alpha is read as its look,
  not as holes in it. Clear glass casts
  a faint shadow with darker edges, a coloured liquid a shadow of its colour,
  and layers combine. A see-through surface that casts is not shaded by it,
  and it does nothing under the `evsm` filter. Off, every frame is drawn byte for byte as
  before.
- **A material in the language can declare a `uniform`**, a member of
  `MaterialParams` that a game sets in `Material.parameters` on every draw,
  where a `param` is still a constant folded into its variant. The emitter
  writes the block, `describeMaterial` reports it and its defaults, and
  `BundledMaterials.parameters` hands a material those defaults.

- **`Material.parameters` is a map of the material's own**, empty and open
  to additions. It was a shared constant, so a material made without
  parameters could not be given any.

- **`BundledMaterials`** reads the materials a bundle carries and builds
  each one's `LightingModel` from its source — `P8`. The emitted stage keeps
  no point-shadow block, and `describeMaterial` asks for the base colour map
  always, since `ReadSurface` samples it: a material that named no texture
  was drawn with the map unbound, black on Impeller and refused on WebGL2.

- **`Material.alphaToCoverage`** antialiases a masked surface's edge by the
  multisample resolve rather than cutting it at the threshold, on WebGL2 and
  WebGPU. Elsewhere the hard cutoff is drawn and
  `FrameResult.alphaToCoverageDeclined` says so. Off by default.

- **A masked surface writes an opaque alpha once it has survived its cut.**
  It wrote the texture's alpha into the frame, and anything reading the
  frame as premultiplied brightened every leaf towards its rim.

- **`MeshNode.drawOrder`** puts nodes that share a material in an order:
  it adds to the material's `drawBucket`, outranks every other sort term in
  both halves of the list, and is never merged across by the batching. Nought
  by default.

- **An orthographic camera no longer reads its eye as a point the light
  travels to.** Highlights, Fresnel and reflections are measured against
  the view axis rather than from the eye's position, so they stop sliding
  across the frame as an orthographic camera pans; fog thickens with depth
  from the eye's plane rather than in rings round it; and the sky is seen
  through a sixty-degree lens turned as the camera is, rather than as one
  colour. `isOrthographic` tells a view-projection matrix's kind. Light
  shafts march from the eye's plane, as the volumetric fog already did.
  `orthographic-metal` is in all four golden sets.

- **Shadow cascades through an orthographic camera cover what it shows.**
  The near cascades were spheres sized by distance from the eye, which
  suits a perspective view that widens as it goes; an orthographic one is
  as wide at every depth, so they covered the air in front of the camera
  and every shadow fell to the cascade fitted to the whole level. They are
  now slabs along the view axis, as wide as the frame and spanning the
  depth the casters take up inside it, and the shader picks one by depth
  along the axis, so stepping the camera back along it changes nothing.
  `orthographic-shadows` is in all four golden sets.

- **Splats through an orthographic camera fog by depth.** Both splat stages
  measured the fog from the eye's position, so a splat off the axis came out
  foggier than one on it; they now read the view axis and the lens from
  `FogInfo`, as the lit stages do, through `contributor_eye.glsl`, which the
  particle stages share. `orthographic-particles` — billboards, splats and
  mesh particles, five columns alike — is in all four golden sets.

- **An orthographic near plane can stand behind the camera.**
  `CameraNode.readViewOrigin` is where the rays begin — the camera's
  position, or its near plane where that is behind it — and the renderer
  measures depths, the fog's air and the shadow cascades from it. What
  stood between that plane and the camera used to have a depth of nought
  or less, which the surface buffer reads as sky, and took no fog.

- **Splats through an orthographic camera are sorted by depth.** Distance
  from wherever the camera was put along its axis put a splat off to the
  side behind one it covers; `SplatSorter.sort` takes an `axis`, and
  `SplatQuads` sorts along the lens's own through an orthographic one,
  re-sorting when it turns rather than when it moves.

- **`MeshOverlay.lookThrough(camera, width, height)`** works the overlay's
  pixel out from the camera's projection, which answers for every kind of
  lens. The example worked it out from a field of view and sized every
  handle through an orthographic camera as if seen in perspective.

- **A material channel in place of the light, over all or part of the
  frame.** `RenderSettings.debugView` takes a `DebugViewSettings`: a
  `DebugView` — albedo, the shading normal, roughness, metalness,
  occlusion, emission, the UV, or magenta where the light came out NaN or
  infinite — and a `split`, the share of the width left lit, so one draw
  wipes between the light and the channel. The lit models write the channel
  themselves, so it shows what the maps did; the composite leaves that side
  out of the exposure, the curve and the grade. Off by default and an exact
  no-op; `debug-view-split` is in all four golden sets.

- **`FrameResult.targetBytes`** says what the targets a frame drew into or
  read from hold, each texture once, without a capture asked for.
  `textureBytes` is how one is counted: its base level, every slice and
  sample.

- **The lens: distortion, flare, and tables from a grading tool.**
  `LookSettings.distortion` bends the frame radially, barrel above nought
  and pincushion below, held on its border, and everything laid over the
  scene bends with it while the vignette and the grain stay put.
  `BloomSettings.lensFlare` throws a bright light's ghosts and halo across
  the middle of the frame, drawn from the glow so only what blooms flares.
  `CubeLut` reads a `.cube` file, 3D or 1D with its domain, into the strip
  `LookSettings.lut` grades through, and `upload` puts it on a device.
- **SMAA 1x beside FXAA.** `AntiAliasSettings(method: EdgeSmoothing.smaa)`
  smooths the finished picture in three passes: the luma steps marked, the
  line behind each staircase rebuilt from where its run ends and which side
  of each end a crossing edge stands on, and each pixel blended by the area
  that line covers of it. Against an 8×8 supersample a tilted edge comes out
  at about a quarter of its hard error. FXAA stays the default; a bundle
  without the three stages falls back to it. Orthogonal edges only: no
  diagonal search and no corner rounding. The area table is the engine's
  `smaaArea`, written by `tool/make_tables.dart` and shared with the
  software backend byte for byte.
- **Projected box decals.** A `DecalNode` is a box, its node's unit cube,
  that paints a picture onto whatever geometry stands inside it: a texture
  (or none) times an sRGB tint with an opacity, an optional emission, a
  region of an atlas, an `order` between overlapping decals, and an angle
  limit past which a surface turned away from the box's up is left alone.
  `RenderSettings.decals` switches them on and is off by default. The pass
  reads the point under each pixel back out of the surface buffer, since a
  depth attachment cannot be sampled, and lays the decal's colour under the
  light the surface was lit by, read back through the albedo buffer, so a
  decal in a shadow is in the shadow. It runs between the opaque half of the
  scene and the transparent one, which it splits the frame for, so glass in
  front of a decal is drawn over it. It needs three colour attachments and
  turns multisampling off, as every reader of the surface buffer does.

- **Planar reflections — `P4`.** A `PlanarReflectorNode` is a plane (its
  node's origin, its local +Y the side it is seen from) and the meshes that
  lie in it. Each frame, for each view that sees the plane's front, the
  scene is drawn again through the view's camera mirrored in the plane, with
  the projection's near plane moved onto the plane (`obliqueNearPlane`), so
  nothing below it is reflected up through it. The picture, at `resolution`
  of the view (half by default), is laid over the surfaces in the scene pass
  straight after the opaque half, through the new `PlanarReflection` stage:
  read by the pixel's place on screen, weighted by Schlick's Fresnel from
  `reflectance` (one for a mirror, about 0.02 for water), tinted and fogged.
  The surfaces keep their own materials and the surface buffer keeps
  describing them. `RenderSettings.planarReflections` is off by default; a
  frame without a visible reflector culls the pass either way.
- **A public camera into a texture — `P4`.** `RenderTexture.create` makes a
  texture for a camera to draw into; `Scene.addRenderTexture` has it drawn
  every frame (or once, and again after `invalidate`) before the scene, so
  a material shows the picture in the frame it was taken. The pass is the
  reflector's with an ordinary camera: meshes with the frame's lights,
  shadows and sky, and no post chain. The texture holds sRGB bytes with the
  top of the picture in its first row on every backend, as an uploaded image
  does, so it goes into an albedo or emissive slot as one.
- `mirrorAcrossPlane`, `obliqueNearPlane` and `planeInEyeSpace` are public
  in `mirror_view.dart`, and two passes join `RenderSettings.passOrder`
  before `scene`: `render textures` and `planar reflections`.
- **A physical sky, with stars, and fog that lies on the ground.**
  `SkySettings.physical` takes a `PhysicalSky`: the air's molecular and haze
  scattering, their scale heights, the planet, the sunlight entering it, the
  ground's albedo and the stars. With it set the sky is sunlight scattered
  once along each view ray, so its colours come from where `directionToSun`
  puts the sun — blue overhead at noon, red towards a setting sun, dark away
  from it — and the disc is drawn white through the air in front of it, so it
  reddens by itself. Stars come out as the sun goes down. `SkySettings.sample`
  answers from the same model without the stars, so `EnvironmentMap.fromSky`
  and the renderer's hemispheric ambient follow the sun too, and
  `PhysicalSky.sunlight` is the colour a directional light standing for the
  sun should have. A cube map still wins. Null, the default, draws the
  gradient as before.
- **Height fog.** `FogSettings.heightFalloff` and `baseHeight` thin the fog
  upwards by the law `VolumetricFogSettings` marches, integrated along the ray
  in closed form. A falloff of nought, the default, is the flat fog to the
  bit. `FogSettings.densityAt` and `copyWith` are new; `Atmosphere` carries
  `fogHeightFalloff` and `fogBaseHeight` and blends them with the rest.
  Particles and splats fog as a flat fog as thick as the air at the camera.

- **A photo of any size.** `capturePhoto` draws a picture in tiles on the
  game's own renderer and hands it out a row of tiles at a time, so memory
  holds one row however large the picture. Each tile is drawn with a margin
  of picture round it through the new `CropProjection`, which takes the
  frame's aspect itself rather than the tile's, and the margin is cropped:
  with 32 pixels a bloom's seams drop from 53 steps to a few. Exposure is held
  at what the screen showed; temporal anti-aliasing, motion blur, render scale
  and chromatic aberration are set aside, and the report says which.
  `PhotoFilter` is eight looks composed onto the game's own `LookSettings`;
  `PhotoFinish` puts the vignette and the grain back over the whole frame
  rather than once per tile.

- **A captured frame can say which draws it made.**
  `Renderer.captureNextFrame(draws: true)` writes every mesh and shadow-caster
  draw into a `DrawJournal` — pass, node, material, counts, pipeline state and
  the values bound — and `FrameCapture.draws` hands them back, with
  `undetailedDraws` counting the full-screen draws a pass made without a mesh
  to name. Off in every other frame, where a draw site pays one null check.
  `readFloats` puts a backend's own floats beside each output's bytes, which
  the software backend's `readHdrPixels` can answer, and each `CapturedPass`
  now carries its time, draws and triangles.

- **An animation graph decides which clip plays, in the fixed step.**
  `AnimationStateMachine` holds states over named clips and transitions
  between them, each with conditions on typed parameters, a crossfade
  duration, a priority and an optional exit time; `AnimationGraph` runs it,
  and `evaluate(dt)` advances by the simulation's step and returns a `Pose`.
  Parameters are float, integer, boolean or trigger, declared in an
  `AnimationParameterSchema`, and a write of the wrong type or to a name the
  schema lacks is refused with a `ParameterWrite` saying what to call
  instead. A trigger stays set until a transition uses it, so an attack
  pressed during a swing lands when the swing allows. A definition that
  cannot run lists its problems through `problems(clips)` rather than
  building a graph whose transitions are never taken. Until now the choice
  of clip was left to each game, written against `AnimationPlayer` by hand.

- **`Pose.blendFrom` crossfades whole poses the way the player does.**
  The player's shortest-arc slerp is now one shared function,
  `shortestArcSlerp`, used by both, so a graph and a player fading between
  the same two clips turn each joint the same way. `Pose.restCopy` gives a
  second pose over the same rest for the outgoing clip.

- **A reload reaches the contributors too.** `Renderer.relinkShaders` asks
  every `PassContributor` to drop what it linked, through the new
  `PassContributor.relinkShaders`, which does nothing by default.
  `SplatContributor` and `MeshOverlay` drop their pipelines; particles, whose
  contributors live in `flutter3d_particles`, do the same there. Before this a
  reloaded shader reached the scene's own pipelines and not the splats, the
  debug lines or the particles.

- **`EnvironmentMap.fromEncoded` builds an environment from a panorama
  file's bytes.** A Radiance `.hdr` is told apart by its header and read
  here; anything else goes through the `ImageDecoder` given. Then it is
  `fromPanorama` as before. `EnvironmentMap.hdrToRgba8` is the clamp to
  eight bits that `flutter3d_model_core`'s `panoramaPixels` used to keep to
  itself, so both read a `.hdr` the same way.

## 0.8.3+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.3

- **`Renderer.renderPost` gives its bloom chain back.** Its pooled targets
  were queued for release, but only `render` drained the ring and moved the
  frame counter, so a host that only post-processed allocated a fresh chain
  on every call and the pool grew without bound. `renderPost` now retires a
  slot of the ring and advances the counter itself.

- **`Renderer.releaseTextureAfterFrame`**, `releaseMeshAfterFrame`'s
  counterpart for a texture an application uploaded and is done with: given
  back to the device once no frame in flight can still sample it.

- **`Renderer.releaseMeshAfterFrame` lets go of a mesh safely.** A mesh an
  application built and is done with, a stretch of terrain behind the
  camera, goes back to the device once no frame in flight can still draw
  it, through the same ring the renderer's own textures use, and on
  `dispose` if no frame comes. Released straight away, its buffers could
  still be read by a frame the GPU had not finished; River Sortie released
  on its next update, which was one frame clear where three are in flight.

- **A vertex colour says it is linear, and a picked colour gets there.**
  `VertexLayout.color` and `MeshBuilder.addVertex` now say what the shader
  always did: a vertex colour is linear, as glTF's `COLOR_0` is, while a
  material's `baseColor` is sRGB. A game painting scenery with colours
  picked on screen wrote them straight into vertices and got pastel.
  `linearFromSrgb(r, g, b)` makes the conversion, and `srgbToLinear` and
  `linearToSrgb`, which the format readers had to themselves, are exported
  with it from `formats.dart`.
- **`MeshData.withColor` paints a whole mesh one colour.** With
  `transformed` and `merge`, several shapes in several colours become one
  mesh drawn with one white material: a tree is one draw, not a node and a
  material per part. A layout with no colour attribute gets an unchanged
  copy.
- **`Atmosphere` is the air at one moment**: the sky, the fog, the sun
  and the ambient light as one value, `lerp` blending them all by one
  amount and `applyTo` putting them on a scene, its sun and a clear colour.
  `AtmosphereCycle` is a day of them, keyed by time and going round.
  `LightGroup` dims lights together by a `level`, each keeping its own
  full brightness.
- **`Material.fogged: false` keeps a material out of the fog**: a horizon
  of hills or a moon that should stand beyond the weather, which faded
  first, being furthest, and left a wall of fog colour.
- **`CellGrid` is a grid of cells there or gone**, from a picture of `#`s,
  worn away by `clear` and `clearAround` and drawn by `mesh` as one merged
  mesh of blocks: a Space Invaders shield. `set` grows one as well, for a
  trail laid behind a cycle or a wall read from a level.
- **`LineStripNode` is a line that grows a point at a time**, written in
  place in a mesh with room for all of it, letting go of its oldest point
  when full, and bounded by its points rather than by the empty line it
  was uploaded as.
- **`OpenPath` measures a path in metres along it**: the point, the
  heading and the right at any distance, the heading turning through a
  corner rather than snapping, straight on past either end. `ribbon` lays
  a flat strip of road on it between two distances, facing up, its `v` in
  metres so a texture tiles the same on every piece, and pieces cut at the
  same distances meet edge to edge.
- **`buildPolyline(closed: true)` joins the last point to the first** with
  an elbow like every other: a ship's outline or a ring had a square notch
  where its open ends met.
- **A node can be tinted and faded on its own.** `MeshNode.tint` multiplies
  its material's colour for that node's draw alone, in linear light as a
  vertex colour is, and its alpha fades it: below one the node is drawn
  blended in the transparent pass whatever its material says. A hundred
  craft sharing a material could not flash the one that was hit or fade
  the one sinking without a material made for the moment. No shader
  changed: the tint goes into the base colour the draw already sends. A
  tinted node is left out of automatic batches; an untinted one draws
  exactly as before.
- **`Renderer.debugLines` draws an application's own lines** beside the
  ones `RenderSettings.debug` asks for, every frame, in the same pass: a
  game's hitboxes, a path an agent means to walk. The scene cannot say
  where a shape that lives in a game's own tree is, and the only way to see
  one was a mesh made for the purpose. Null costs nothing.
- **A long scene's near shadows do not stripe.** A near cascade reaches back
  to the furthest caster towards the sun, and its depth bias, kept in
  metres, shrinks in stored depth by as much. The map stores depth as a half
  float, 1/2048 apart near the far end, and in a river valley two hundred
  metres long the bias came to a seventh of that: a lit floor compared
  against its own rounded depth shadowed itself in diagonal bands, on Metal
  and not on the software backend, which keeps full floats. The bias of each
  cascade no longer goes below the step the map is stored with, unless the
  settings ask for less than that.
- **An instance batch hands out slots that stay found.**
  `InstancedMeshNode.acquire` takes a slot and returns an `InstanceHandle`;
  `release` fills the hole with the last slot, colour and morph weights
  with it, and moves that slot's handle along, so a batch of shots or
  sparks that leave in any order never points an owner at someone else's
  instance. A full batch grows. `clear` retires every handle.

## 0.8.2

- **A sunlit room's inside corners no longer leak light.** The sun recorded
  the back faces of its casters, as the lamps' cube maps do, and the floor
  at the foot of a wall sits at exactly the depth of the wall's inner face:
  the comparison called it lit, and every inside corner showed a dotted line
  of light along it, however thick the walls, whatever the resolution and
  whatever the normal offset. `ShadowSettings.directionalCasterFaces` is the
  sun's own choice now, `ShadowCasterFaces.both` by default, which records
  the nearest surface whichever way a triangle is wound. `casterFaces` stays
  the lamps', `back` by default. A one-sided caster turned away from the sun
  now casts, where it let the sun through. The sun's map draws every face,
  and a lit slope's own depth is now in it, which a PCSS tap a few texels
  up the slope would have taken for a blocker: at a 75° slope under a sun
  of 0.2 rad, 9% of the slope came out self-shadowed. Each PCSS tap now
  allows for the receiver's own slope past the normal offset's reach, and
  the same slope is fully lit. A
  scene that set `casterFaces` for the sun sets `directionalCasterFaces`
  instead. Every golden scene with a sun was recorded again on all four
  backends.
- **A correction to 0.8.0's EVSM entry.** It said a device that cannot
  filter the moments "counts in `FrameResult.shadowsDenied`". It does not:
  `shadowsDenied` counts cube-atlas rows a lamp could not have, and an EVSM
  refusal shows in `FrameResult.skipped`, as `ShadowFilter.evsm` says.

Upgrade the backend with this: it asks for `flutter3d_shaders` `^0.8.2`,
whose PCSS allows for the receiver's slope that the two-sided sun map
needs.

## 0.8.1

Upgrade `flutter3d_impeller`, `flutter3d_webgl`, `flutter3d_webgpu` and
`flutter3d_cpu` with this: with contact shadows on and the temporal resolve
off, the renderer draws the `ContactShadowResolve` stage, which only their
0.8.1 shaders have.

- **Contact shadows lose their comb when no temporal resolve runs.** The
  march starts a fixed 4×4 Bayer cell in, per pixel, and each pixel keeps
  the hard first hit its own offset finds. With TAA the offset changes every
  frame and the history averages it; without it the pattern never moves, and
  along a thin blocker just off the floor the shadow's edge carried it as a
  comb, neighbouring pixels 181 levels apart. A `contact shadow resolve`
  pass runs right after the march while the temporal resolve is off and
  averages every phase of the pattern once, weighted by depth so it stops at
  silhouettes. Frames with TAA are unchanged.
- **A fold no longer lets the sun through its upper layer.** The flat part
  of `ShadowSettings.normalOffset` is held to one texel of the cascade the
  lookup lands in; its documentation says why. Shadow edges move by about a
  pixel, and twelve golden scenes were recorded again on all four backends.

## 0.8.0

This release fixes the hardware contract for the whole 0.8 line and builds
most of the renderer's new work on it. `flutter3d_hardware` 0.8.0 declares every member
the cycle needs (compute, GPU timestamps, float filtering, independent blend,
HDR output), so a later 0.8.x only turns answers on. Every new effect below is
off by default, and a frame that asks for none of them draws what 0.7.4 drew,
apart from the corrections listed first. Upgrade `flutter3d_shaders` and the
backends with this: the renderer binds stages and blocks only their 0.8.0
bundles declare.

What changes for an existing scene:

- **glTF `baseColorFactor` is now read as linear.** The specification says it
  is; `SurfaceMaterial.baseColor` is the authored, sRGB-encoded tint the
  shaders convert. The loader now converts on the way in and the writer on the
  way out, so a factor of 0.5 draws as 0.5 where it drew as 0.21. Any glTF with a factor below one comes out lighter.
- **A rectangle light rated in lumens is twice as bright.**
  `Photometric.fromLumens` for `LightType.area` divides by pi, the flux of a
  Lambertian panel, where it divided by 2 pi and gave every panel half the light
  its lumens promised. `toLumens` answers the same way back.
- **A rectangle light's highlight covers the whole panel.** The metal-rough
  model integrates its GGX lobe over the rectangle by linearly transformed
  cosines (Heitz, Dupuy, Hill and Neubelt 2016) where it evaluated the lobe at
  one representative point. A glossy floor under a long panel now shows the
  panel's shape. It costs the metal-rough stages one sampler, the fitted
  table in `EngineTables.ltc`.
- **`ShadowSettings.directionalLightRadius` is in radians.** It was texels
  per unit of stored depth, a unit that differed per cascade and per scene. It
  is now the light's apparent radius (the sun's is about 0.0047), the penumbra
  is worked out in metres from the gap between blocker and receiver, and the
  search and filter take sixteen taps each on a Vogel disc. Nought is still
  the 3x3 kernel. A scene that set a radius has to set it again.
- **Shadows reach further and stop bleeding across tiles.** A near cascade
  pulls its depth back to the furthest caster towards the light, so a tall
  caster standing outside its sphere still shades the floor it covers. Every
  PCF tap stays inside its own cascade's tile. A spot wider than 45 degrees
  is shadowed through the cube atlas like a point light, where one stretched
  tile blurred it over up to fourteen times the width.
- **Screen patterns count their rows from the top on every backend.** The
  dither, grain, march jitter and the point-shadow kernel's rotation came out
  upside down on WebGL2, whose rows count from the bottom. Full-screen passes
  get the orientation through a `FragCoordInfo` block.
- **An `IrradianceField` is read at every pixel.** The lit models take the
  eight probes around each fragment, weighted trilinearly, by facing and by
  Chebyshev's bound from the stored depth moments, in place of one sample at
  the node's centre. The old path also scaled the result by the ambient
  strength twice; that is gone, so rooms lit by a field change brightness.
  With no field nothing changes.
- **A frame with a transmissive draw renders without MSAA.** Such a frame
  splits the scene around a copy of itself (below), and a second pass cannot
  load the multisampled targets the first left in tile memory.
  `FrameResult.antiAliasing.msaaDeclined` says so. Glass in that frame shows
  the scene behind it; where no sky is drawn behind it, it shows the clear
  colour instead of the environment it showed in 0.7.4.
- **`FramePass` gains `gpuMicros`.** It is a record, so code that builds one
  has to name the new field. It holds what the GPU spent in the passes a node
  opened, or null on a device that does not measure.
- **`SplatContributor.cloud` is a getter**, and so is `SplatQuads.cloud`: a
  contributor built with `SplatContributor.lod` draws the cut it last chose.
  The constructor takes an optional `node` and a `composite`.
- **`SplatAxes` is a final class with const instances**, so a later axis
  convention does not break a caller's `switch`.
- **Uniform blocks are the compiler's.** Every block the renderer binds is a
  generated class from `flutter3d_shaders`' `typed_blocks.dart`, bound with
  `PassEncoder.bindBlock`, and what a built-in stage is bound comes from
  `stageBindings`, the compiled bundle's own table. A `LightingModel`'s flags
  are now only the fallback for a stage from an application's own bundle.
  A draw can no longer hand a stage a block the stage dropped, which is what
  crashed 0.7.0 on Metal.

The frame over time:

- **Temporal anti-aliasing.** `AntiAliasSettings.temporal`
  (`TemporalSettings`, `enabled` false by default) jitters the projection by
  a Halton(2, 3) sequence of `sequenceLength` 16 (`JitteredProjection`),
  writes a velocity buffer, and resolves each frame against a reprojected
  history clipped to its neighbourhood. The scene then draws at
  `renderScale` and everything after the resolve at the size asked for;
  `sharpen` (0.25) runs a robust contrast-adaptive sharpen after it. Material
  maps take a mip bias of log2(`renderScale`) - 0.5 while it runs. It costs
  a velocity pass, a draw per moved node into it, and two output-sized
  history targets. `Renderer.frameIndex` is public, and `FrameHistory` keeps
  what moved since the last frame.
- **The history can be clipped to a k-DOP.** `TemporalSettings.clip` is
  `TemporalClip.aabb` by default, the YCoCg box; `kdop8`, `kdop16` and
  `kdop32` bound the neighbourhood by slabs along more axes, which removes
  the trail a colour of the right brightness and wrong hue leaves.
- **Particles, splats and blended meshes are taken from the frame they are
  in.** `TemporalSettings.reactive` (nought, off) marks the pixels they cover
  so the resolve lowers the history's share there; without it a moving ember
  showed at a fraction of its brightness. Contributors take part through
  `PassContributor.encodeReactive` and `ReactiveFrame`.
- **Noisy effects use half their samples while the resolve runs.** The
  occlusion and contact shadows draw half their samples and blend into
  histories of their own; their jitter, and that of reflections and shafts,
  comes from a blue-noise table (`EngineTables`), one of 32 slices a frame.
- **Motion blur.** `RenderSettings.motionBlur` (`MotionBlurSettings`,
  `enabled` false, `shutterFraction` 0.5, `maxRadius` 20 pixels) finds the
  longest motion per tile and its neighbours and gathers fifteen samples
  along it, after depth of field and before the temporal resolve. It fills
  the velocity buffer whether or not the resolve runs.
- **Spatial upscaling.** `RenderSettings.spatialUpscale`
  (`SpatialUpscaleSettings`, `enabled` false, `sharpen` 0.2) brings a frame
  drawn below a render scale of one up to full size with an edge-directed
  twelve-tap filter and the same sharpen. It applies only while the temporal
  resolve is off.

Light:

- **Energy compensation for rough metals.** `RenderSettings.energyCompensation`
  (false) adds back the light a single GGX bounce loses, so a rough gold
  sphere is as bright as a polished one. Arithmetic only.
- **An energy-preserving diffuse lobe.** `RenderSettings.diffuseModel` is
  `DiffuseModel.lambert` by default; `DiffuseModel.eon` is the Oren-Nayar lobe
  of Portsmouth, Kutz and Hill (2024), rough by the material's roughness,
  which keeps a rough dielectric's rim bright and stops it reading as plastic.
  Arithmetic only.
- **Clustered lights.** `RenderSettings.clusteredLights` (false) cuts each view
  into 16 x 9 tiles and 24 depth slices and lists the lights reaching each
  cell, built on the CPU per view. A draw keeps its eight shadowed slots and
  reads the rest from its fragment's cell, so a floor under sixty-four lights
  is lit by all of them where it kept thirty-two.
- **A display transform in place of the tone curve.**
  `LookSettings.displayTransform` takes a baked float colour table over a
  log2 shaper, and `TonemapCurve.aces2` is the one the engine ships: the ACES
  2.0 SDR tonescale at 100 nits with the hue held. It is the tonescale alone,
  without the reference transform's gamut mapping.
- **Local exposure.** `RenderSettings.localExposure` (`LocalExposureSettings`,
  `enabled` false, `strength` 0.7, `shadowStops` and `highlightStops` 2)
  gives each part of the frame its own exposure before the tone curve, by
  exposure fusion at an eighth of the frame, so a dark room and its window
  can both be seen. Three small passes.
- **HDR output.** `RenderSettings.outputTransform` is `OutputTransform.sdr` by
  default. `OutputTransform.extendedSrgb`, on a device whose
  `hdrOutputFormats` is not empty (WebGPU on an HDR display), draws the frame
  exposed but not tone-mapped in extended sRGB, where white is one and a
  highlight goes past it. Elsewhere it draws the SDR frame byte for byte.
- **Horizon-based occlusion and indirect light.**
  `AmbientOcclusionSettings.method` is `AmbientOcclusionMethod.ssao` by
  default. `gtao` finds the horizon along two slices per pixel and integrates
  the visibility between them, with the multi-bounce fit of Jimenez et al.
  2016 where an albedo buffer exists. `ssil` adds the light the neighbouring
  surfaces bounce, through a visibility bitmask of sixteen sectors,
  `AmbientOcclusionSettings.thickness` (0.3 metres) deep each. Both need the
  new albedo buffer, a third scene attachment, for their colour; a device
  with two attachments falls back to grey.
- **The irradiance field can update on the GPU.** `IrradianceField.gpuUpdates`
  (nought) updates that many probes a frame, round robin, each keeping
  `hysteresis` (0.9) of its old value, so the field follows a room that
  changes and gains a bounce each pass. `Renderer.irradianceAtlas` is the
  texture the lit stages read. It needs cube textures and a second colour
  attachment; elsewhere the bake stands.

Shadows and air:

- **Cascades are redrawn only where something changed.** Each tile of the
  directional atlas keys on its own matrix and the casters its volume holds,
  so a camera walking past still casters redraws nothing. Casters marked
  `shadowIsStatic` go into an atlas of their own that each frame's tile
  starts from, and as the camera walks that atlas is scrolled by whole texels
  and only the strips that came into view are drawn. Over sixty static
  blocks a walk draws a dozen casters a frame where it drew sixty-eight.
- **EVSM for the sun.** `ShadowSettings.filter` chooses `ShadowFilter.pcf`,
  `pcss` or `evsm`; null follows `directionalLightRadius` as before. `evsm`
  blurs the atlas once into exponential moments and reads the shadow with one
  filtered tap. It costs an rgba32f atlas and two blur passes and needs
  `supportsFloat32Filtering`; a device without it counts in
  `FrameResult.shadowsDenied` and falls back to the 3x3 kernel.
- **Volumetric fog.** `RenderSettings.volumetricFog` (`VolumetricFogSettings`,
  `enabled` false, `density` 0.02, `steps` 24, `distance` 40) marches each
  ray at half resolution through a medium thinning with height, lit by the
  sun's cascades and, with clustered lights on, the point and spot lights of
  each cell, and upsamples by depth so the glow stays off silhouettes.

Transparency and glass:

- **Glass that sees the scene.** A frame with a transmissive draw draws the
  opaque half, copies it with five halvings into one texture
  (`SceneColourChain`), and draws the glass reading that copy where the bent
  ray leaves it, at a level its roughness picks. A frame without glass draws
  exactly what it drew.
- **Order-independent transparency.** `RenderSettings.transparency` is
  `TransparencyMode.sorted` by default; `weightedBlended` accumulates the
  transparent half into two targets and resolves them over the scene, so
  crossing panes come out the same from any side. It turns MSAA off for the
  scene pass, and draws the list twice on a device without independent blend.

Content:

- **Material layers.** `MaterialExtensions` on `SurfaceMaterial` holds
  KHR_materials_ior, specular, clearcoat, sheen, anisotropy, transmission,
  volume, dispersion and iridescence, read and written by glTF, `.fmat` and
  `.f3d` (section 22). `LightingModel.pbrLayered` draws them; a loader picks it
  only when a layer changes the shading, and with every layer at its default
  it draws what `Pbr` draws. Files that require transmission now load. The
  specular textures, the coat's normal map and the anisotropy and iridescence
  textures are kept for export and not drawn, and the loader says so.
- **A texture transform per map.** `Material.textureTransforms` gives each map
  of a layered material its own KHR_texture_transform matrix, so maps that
  disagree draw right and a file requiring the extension loads. A single
  shared transform is still baked into the mesh.
- **Variants and animation pointers.** KHR_materials_variants becomes
  `ModelDocument.variants` and a per-surface `variantMaterials` map (`.f3d`
  section 23). KHR_animation_pointer channels become `AnimationPointer`
  tracks on base colour, emissive strength, roughness, metallic, texture
  offset and light colour and intensity, played into an
  `AnimationPointerSink` such as `PointerTargets` (section 24).
- **Impostors.** `ModelLod.impostor` carries a `ModelImpostor`, an octahedral
  atlas baked by the build, stored in `.f3d` section 25 only when present.
  `ImpostorNode` draws it as one card turned to the eye with
  `LightingModel.impostor`, blending the three nearest views and receiving
  shadows. Cards cast none.
- **Clustered meshes.** `MeshData.clusters` (`MeshClusters`) records runs of up
  to 4096 triangles with a box and a normal cone, written by the build into
  `.f3d` section 26. The scene pass culls each run by frustum, cone and
  occlusion and draws only the visible ones. An older reader draws the whole
  mesh.
- **Splats from glTF and SPZ.** KHR_gaussian_splatting primitives load into
  `ModelDocument.splats`, each on its node. `parseSplatSpz` reads SPZ
  versions 1 to 4 in pure Dart, and `parseSplatPly(keepHigherBands: true)`
  keeps the higher spherical-harmonic bands in `SplatCloud.shRest`, which are
  kept and not drawn.
- **Large captures by budget.** `buildSplatOctree` merges a cloud into a tree,
  `SplatLod` picks a cut under a splat budget, and `PagedSplatOctree` reads a
  `.f3dsplat` through any byte-range reader and fetches deeper pages only
  where the cut needs them. `SplatContributor.lod` draws it.
- **Splats sort less or not at all.** The sort is a two-pass counting sort on
  quantised distance (`splat_sort.dart`), run only when the eye moves past a
  fraction of the cloud's depth. With `SplatComposite.automatic`, the default,
  a cloud under a temporal resolve draws unsorted with a hashed alpha test;
  without the resolve it draws the sorted blend as before.
- **Lit particle sheets.** Contributors get the lights a mesh of their bounds
  would get through `ContributorLights`, which the six-way smoke stage in
  `flutter3d_particles` reads.

Culling, budgets and devices:

- **Occlusion culling.** `RenderSettings.occlusion` is `OcclusionMode.none` by
  default. `software` rasterises meshes marked `MeshNode.occluder` (or their
  `occluderMesh`) into a 256 x 128 depth grid on the CPU, at most two
  thousand triangles a frame. `hiZ` needs nothing marked: it reads back last
  frame's depth pyramid and reprojects it, answering "visible" until the
  first reading. `SceneBvh.queryFrustumWhere` rejects hidden branches whole.
- **One allowance for work that can wait.**
  `RenderSettings.frameWorkBudget`, in microseconds (nought, no limit), is
  shared by irradiance probe updates and dynamic point-shadow faces; what does
  not fit waits for the next frame. `Renderer.frameWorkBudget` reports what
  was spent and put off.
- **Adaptive quality.** `AdaptiveQuality` picks each frame the best-looking
  row of a `QualityTable` (render scale and effect tier, with a cost and a
  FLIP difference) that fits `AdaptiveQualitySettings.budgetMicros`. Off by
  default. The committed tables' costs are software-rasteriser stand-ins until
  each class is measured on its own GPU.
- **Device classes.** `DeviceClass.phone`, `web` and `desktop`;
  `DeviceClassSelector` picks one from whether the GPU samples BC textures
  and a short measured probe frame, and `DeviceClassPicker` remembers it through a `DeviceClassMemory`
  and takes a player's override.
- **Targets can be shared within a frame.** `RenderSettings.aliasTargets`
  (false) lends a pooled target whose last pass has run to a later pass of the
  same frame.
- **Also new:** `Renderer.warmUp` links every pipeline a scene needs on a
  loading screen; `Renderer.captureObjectIds` reads back the whole pick pass
  as an `ObjectIdFrame`; `FieldPass` steps a texture through full-screen
  kernels, the compute path every backend has; the renderer labels each pass
  with its node's name, wraps it in a `Timeline` span and fills
  `FramePass.gpuMicros` where the device measures.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.4

Every effect below was checked against the paper or engine it comes from, and
most of what was wrong was wrong the same way: a number in the right units at
one distance, one resolution or one substep count. Pictures move, and the
goldens that show them were recorded again on all four backends. Upgrade
`flutter3d_impeller`, `flutter3d_webgl`, `flutter3d_webgpu` and
`flutter3d_cpu` with this: the renderer binds uniforms (`BloomInfo.tint`,
`ShaftInfo.sun`) that only their 0.7.4 shaders declare.

- **AgX is AgX, and it is linear.** `TonemapCurve.agx` returned its sigmoid's
  display-encoded value as if it were linear, and the composite encoded it to
  sRGB a second time: 18% grey reached the screen at 187/255 rather than 128,
  and a red velvet (0.6, 0.07, 0.1) came out pastel. It is now Wrensch's
  "Minimal AgX" whole — inset, sigmoid, outset, `pow(2.2)` — without the
  `mix(luma, v, 0.84)` that took a sixth of the saturation off every frame.
  `TonemapCurve.agxFull` draws the same picture and is deprecated.
- **A double-sided material casts its shadow from both sides.**
  `MeshNode.castsShadowFromEveryFace` is new: true for
  `ShadowCastingMode.doubleSided`, as before, and now also for a node whose
  material is `doubleSided`, as Godot, Filament and Unity take the shadow
  pass's cull from the material. A sheet draped over a ball threw a detached
  crescent — the half of it facing away from the light — and every
  double-sided leaf card cast only its back. The cascade and cube caches
  notice the change without the node moving. And the back of a double-sided
  surface is now lit from its own side: `gl_FrontFacing` reverses the normal,
  as glTF asks, in the lit shaders and in the surface buffer, and the tangent
  frame of a normal map turns with it.
- **The sun's normal offset grows with the cascade's texel and the slope.**
  A flat two centimetres was enough while a closed mesh recorded only the
  faces turned away from the sun; a double-sided one records its lit faces
  too, and a cube shadowed itself in a diagonal along its triangle split. The
  offset is now that distance plus one texel of the cascade scaled by the
  slope to the light, the measure point and spot shadows already took.
- **A long shadow no longer ends in a straight line.** The last cascade's
  depth is fitted to the casters, and a floor past its far plane was treated as
  outside the map and lit: an evening shadow was cut off where the far plane
  met the ground, straight across the teapot's. Past the far plane is behind
  every caster, and the last cascade now clamps there, in the lit shaders and
  in the light shafts.
- **The sun's shadow survives a light list gathered per draw.** A node on a
  light channel, or in a scene of more than eight lights, gets its own list,
  and the shader was told the caster's index in the frame's list: the sun's
  shadow vanished from that node and a lamp at that position was tested
  against the sun's cascades.
- **Shadow caches notice what they missed.** A swapped mesh, morph weights,
  an instance moved inside a batch, and `ShadowSettings.casterFaces` changed
  at runtime redraw the cascade and the cube faces that show them, and hiding
  a static caster drops it from the static bake.
- **Screen-space reflections lose their ghosts.** A floor of roughness 0.3
  showed shifted, smeared copies of what stood on it. The march now starts at
  a jittered fraction of a stride and halves the last stride five times
  before it reads a colour (McGuire and Mara); a hit fades with the length of
  the ray; a surface turned away from the ray is not a hit; roughness removes
  the reflection by 0.25 rather than 0.45, since this pass has no blur; the
  Fresnel term is Schlick's with F0 = 0.04 rather than a 15% floor; and the
  surface buffer is read nearest. Defaults follow Filament: `steps` 32,
  `stride` 0.1, `thickness` 0.12.
- **Light shafts scatter the sun's light instead of veiling the frame.** They
  added `strength × colour` in proportion to how much of a ray was lit — a
  flat 0.15 over nearly every pixel of a daylight scene. They are now single
  scattering with transmittance and a Henyey–Greenstein phase, in the
  caster's own colour and intensity: bright towards the sun, faint with it
  behind. `LightShaftSettings.strength` is now the air's density per metre
  (default 0.005, a clear day's haze), `anisotropy` is new (default 0.6), and
  `color` tints rather than supplies the light. The cascade is chosen by
  distance from the eye, as `shadow.glsl` chooses a surface's.
- **Dithering is on by default, and centred.** `LookSettings.dither` defaults
  to one 8-bit step, which is what turns the coloured rings round a small
  bright lamp's bloom back into a gradient. The Bayer cell's mean was -1/32
  of a step; it is nought now, so a flat colour stays the colour it was.
  `LookSettings.isNeutral` no longer asks about it.
- **The grade does what its documentation says.** Contrast pivots on linear
  light's mid grey (0.18, as a power) rather than on 0.5, which in linear light
  is a bright highlight — a contrast of 1.2 also took about a stop off. Lift is
  `c · (1 − lift) + lift`, so white stays white. A LUT is indexed and answered
  in sRGB, the space a `.cube` is written in.
- **Bloom's halation warms each level once.** On the way up a level already
  holds every level below it, and warming each compounded: at 0.5 the widest
  came out red 1.78 and blue 0.63 rather than 1.25 and 0.83. Each step now
  carries the ratio between its level and the one above. `BloomSettings.scatter`
  is new — each level weighs `scatter^level`; one, the default, is the bloom
  this has always drawn. The first step down averages its four taps with
  Karis's `1 / (1 + luma)`, so a one-texel highlight no longer flickers.
- **Depth of field.** The test of whether a sample's disc reached the pixel was
  `r <= max(tapRadius, radius)`, which always held, so a sharp object bled into
  the blur behind it; it now keeps a sample only as far as its own disc reaches.
  Nothing drawn — the sky — is infinitely far, so it blurs as the far field
  does rather than staying sharp. The spiral turns per pixel.
- **Contact shadows** start each step at a jittered point, so eight steps are
  not eight flat bands across a penumbra, and accept a blocker within twice a
  step's own depth as well as within `thickness`.
- **Ambient occlusion's blur** reads the surface buffer nearest and weighs
  depth relative to the centre's own: `AmbientOcclusionSettings.blurDepthFalloff`
  is a fraction of depth now, default 0.02 (the old ten centimetres at five
  metres).
- **Contact shadows march without a shadow map.** They took their direction
  from the light that casts the map, so clearing `castsShadow` on the sun,
  the cheap setup the pass exists for, switched them off as well. They now
  follow the first directional light when no light casts one.
- **Depth of field reads depth nearest.** A filtered tap at a silhouette
  against the sky mixed the object's depth with the sky's zero, and the
  gather spread the sharp object into the blurred sky around it.
- **Bloom's `halation` is read up to 2.5 and a negative `scatter` as zero.**
  Past 2.86 the blue weight divided by zero and the pyramid filled with NaN.
- `ReflectionSettings` says what the pass cannot know: the surface buffer
  holds no metalness, so every surface reflects as a dielectric.

## 0.7.3

- **A material's own vertex stage gets the morph state when it declares it.**
  0.7.2 fixed `Material.polyline` on Impeller by binding morphs to a
  material's own stage only when the node morphed. A stage written from
  `MeshVertex` declares the morph block and texture either way, so on a plain
  mesh it went without them: another draw's weights on the software backend,
  garbage on WebGL, a native failure on Metal. The bind now follows
  `LightingModel.vertexStageMorphs`, which is new, true by default, false for
  `LightingModel.polyline`, and round-trips through `.fmat` as `vertexMorphs`.
- **`MaterialBindings.lightingModel` builds the model a material in the
  language needs.** Every flag comes off the program, `usesLightList: false`
  included. A hand-built model that samples maps defaulted the light list on,
  and the emitted stage never declares it.

## 0.7.2

- **`Material.polyline` draws on Impeller.** The renderer bound the morph
  block and texture to whichever vertex stage drew, and `PolylineVertex`
  declares neither. The missing block was skipped, but flutter_gpu refuses a
  texture bound to a slot the stage does not have, so every polyline threw
  "Failed to bind texture" at its first draw on macOS and iOS, in 0.7.0 and
  0.7.1 alike. WebGL and the software backend let the extra bind pass. A
  material's own vertex stage now gets the morph state only when the node
  morphs; the engine's four mesh stages still get it on every draw. Found by
  drawing an unlit sphere, a polyline and a lit cube one at a time on Metal.

## 0.7.1

- **A surface with no normal map is flat again, whichever way its tangent
  runs.** The fallback normal texture stores 0.5 as byte 128, which decodes
  to 0.0039 rather than 0, so every map-less material was tilted by about a
  third of a degree along its tangent and its shading depended on the
  tangent's direction. The renderer now sends a normal scale of zero with the
  fallback, which leaves exactly (0, 0, 1) on every backend. Setting
  `normalScale: 0` by hand is no longer needed for that.
- **`Scene.defaultLightWhenUnlit`, a switch for the light nobody added.** A
  scene with no live light is still lit by one directional light by default.
  A light counts as live only when it is visible and above zero intensity, so
  turning off the only lamp used to switch a bright default light on. Set the
  flag to false and an unlit scene stays unlit, with no black light parked in
  it to keep the count above zero.
- **`Material.baseColor` is documented as what it is: sRGB in rgb, linear in
  alpha.** The doc said linear, and every shader converts it with `toLinear`,
  so a colour converted by hand went through the curve twice. Nothing about
  the rendering changed.
- **An unlit draw no longer crashes Metal on the first frame.** 0.7.0 bound
  the light list, the `LightListInfo` block and `light_list_texture`, to
  every draw. The Unlit stage (and the polyline, which uses it) gathers no
  lights and keeps neither in its compiled Metal function, so the bind went to
  a slot index the driver does not have and the process died inside
  `setFragmentBuffer:offset:atIndex:` on macOS and iOS alike. Vulkan accepted
  the same bind, which is why Android drew. The list is now bound only when
  `LightingModel.usesLightList` says the stage reads it. That is new, defaults
  to `usesMaterialMaps`, round-trips through `.fmat` as `lightList`, and is
  false for anything the material language emits.

- **The rest of a full read of the engine.** A failed frame no longer keeps its
  texture out of rotation or leaves the timeline block open; a new shadow
  resolution, a resize, `dispose` and `FrameResources.provide` release what
  they replace. A flickering torch past the first eight lights keeps flickering,
  a spot light taking over a point light's atlas row clears its tiles, and a
  replaced `Sky` draws. `lookAt` and the IK solvers work under a scaled parent,
  a skinned mesh is picked in its current pose and an instanced batch against
  every instance, and morphs and skinned bounds stop culling a visible mesh.
  `Scene.clear` is linear. `Material.copy` keeps the parameter block,
  parameters and extra textures.
- **The decoders refuse a bad file instead of hanging or reading past it.**
  meshopt, sparse glTF accessors, `.f3d` record counts, zstd and HDR sizes and
  KTX2 universal levels are checked, each with its own `FormatException`.
  meshopt filters are refused by name rather than decoded as noise, OBJ keeps
  corners with different UVs apart on the web, smooth OBJ normals follow
  positions across UV seams, USDZ flips winding under a mirror, JPEG decodes
  non-interleaved and multi-scan files, and `.fmat` keeps `mipLinear` and a
  custom vertex stage.
- **`LightNode.castsShadow` is read on the sun too.** The renderer cast the
  first directional light whatever its flag said, because only the cube
  shadows read it, so "this sun does not cast" could only be said by turning
  shadows off for the frame. It now picks the first directional light that
  asks. **The default follows the type**: left out of the constructor, it is
  true for a directional light and false for the others, which is what every
  scene already drew. A sun built with `castsShadow: false` stops casting.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3, `image` ^4.10.1.

## 0.7.0

- **The first publication: the engine with no Flutter SDK behind it.** The
  0.1.0 below was a number carried inside the workspace and never reached
  pub.dev. 0.7.0 is the number the whole shelf goes out on, so one number names
  one tree and `^0.7.0` on any `flutter3d_*` package resolves against every
  other; publishing first at 0.7.0 skips numbers nobody outside ever saw, and
  `doc/boundary-0.7.0.md` lists the thirteen packages that begin here. This is
  the renderer, the scene graph, animation and the asset layer that `flutter3d`
  0.6.0 held, moved out whole (`mcp-03n`), with everything written since. It
  depends on `flutter3d_hardware` and `vector_math` and on nothing else, and
  `flutter3d` re-exports it, so an application importing
  `package:flutter3d/flutter3d.dart` keeps every name. What follows is what
  changed against the engine inside `flutter3d` 0.6.0.

- **Accepted `flutter3d_geometry`, `flutter3d_formats` and `flutter3d_fbx`.**
  They are `package:flutter3d_core/geometry.dart` and
  `package:flutter3d_core/formats.dart` now, each importable on its own and
  both exported from `flutter3d_core.dart`; `FbxDecoder` is part of the formats
  library. All three were plain Dart with `vector_math` as their only
  third-party dependency and none was published, so the package boundary gave a
  caller that wanted a mesh or a `.glb` without the renderer nothing a library
  does not. Their tests, tools and skills moved with them; the skills are
  `flutter3d-core-geometry-meshes` and `flutter3d-core-formats-reading-models`.
  `FbxDecoder` recognises an FBX file by its magic or its extension and refuses
  every one with a `FormatException` that says to export glTF; the reader is
  not written. `flutter3d_core.dart` hides the formats library's `Ktx2Texture`,
  which carries a raw `vkFormat`, behind the engine's own, which carries a
  `TextureFormat`.

- **What a file written against `flutter3d` 0.6.0 has to change.**
  `uploadEncodedImage` requires `decodeImage`, an `ImageDecoder` answering an
  `Rgba8Image`, because this package cannot call `dart:ui`. `flutter3d` has
  `defaultImageDecoder`, and `decodeImagePure` here reads PNG and baseline JPEG
  with no SDK at all. Three enums gained a value, so an exhaustive `switch`
  over one stops compiling until it answers it: `LightType.area`,
  `MaterialAlphaMode.hashed` and `ModelFormat.stl`. `GraphicsDevice.present` is
  gone from `flutter3d_hardware`, which this package re-exports; a frame is
  shown through `presentFrame` in `flutter3d_app`. `SceneNode.visible` is a
  setter over a cached value where it was a field, so hiding a branch reaches
  everything under it. `AssetSource`, `FileAssetSource` and `fileUriResolver`
  are here, and `BundleAssetSource` and `assetUriResolver`, which name
  Flutter's asset bundle, stayed in `flutter3d`.

- **The frame says what it did.** `FrameResult.passes` is one `FramePass` per
  node the compiled graph ran, in order, with `micros`, `drawCalls`,
  `triangles` and `pipelineSwitches` (`gfx-01n`). `FrameResult.triangles` and
  `instances` count the scene's meshes, an instanced batch once per instance.
  `skipped` lists each pass that did not run with a `PassSkip` reason: off by
  its own setting, disabled by name, unconsumed, starved, or `unsupported` on
  this device. `PassSkip` is a final class with constants, so a sixth reason
  will not break a `switch`. `antiAliasing` reports what smoothed the edges and
  why multisampling was declined, which is one of two things: the device, or a
  pass in this frame that reads the surface buffer. Counting per pass found
  that `drawCalls` had never included the shadow map or the bloom chain; a
  directional fixture that read 4 reads 13.

- **Passes are addressed by name.** `RenderSettings.disabledPasses` takes node
  names, and the graph refuses a name no node carries, so `'fxaa'` for the node
  called `antialias` is an error and never a silently unchanged frame.
  `RenderSettings.passOrder` publishes the names in registration order,
  `undisablePasses` the three the graph will not drop (`scene`, `composite`,
  `object ids`), and `probePassName` the name of a probe's pass.
  `Renderer.planFrame` compiles the graph for a frame without drawing it and
  answers the `CompiledFrameGraph`, with its own light buffer and shadow slots
  so that a frame drawn after a plan is the frame drawn without one.
  `RenderSettings.forMeasurement()` is the complete set for reading values off
  a debug view: tone map off, exposure 1, bloom off. It replaces three
  hand-built copies that left bloom on, which moved the `animation-weights`
  golden.

- **A frame captured pass by pass, and one pass measured.**
  `Renderer.captureNextFrame()` is a one-shot that answers a `FrameCapture`:
  each `CapturedPass` with its reads, optional reads, writes and keeps by the
  graph's own names, and an image of everything it wrote. A resource with no
  image says why: tile memory, multisampled, a cube, or a name nothing provided.
  `FrameCapture.firstBlack` finds the first pass whose output came back black.
  It is exact on the software rasteriser; on the hardware backends a readback
  may resolve after the queue moved on. `contributionBetween` differences two
  frames into a `PassContribution` of four numbers: pixels changed, their mean
  change, the largest change and the bounds of the change.

- **A caller's own post effect, and post-processing on a buffer from
  outside.** `FullscreenEffect` wraps the read-modify-write of the right
  resource, the transient target and the shared vertex stage; it has a name and
  an `enabled`, so it appears in `passes` and `skipped` and answers to
  `disabledPasses` like a pass of the engine's. Two constructors pick the
  phase. `Renderer.renderPost(hdr, settings)` runs bloom and the composite over
  an HDR buffer handed in, registered through `FrameGraph.addExternal`, and
  answers a `PostFrameResult`; with `keepHdr` it also returns the bloomed
  buffer. Reflections and ambient occlusion are not in that call, since both
  read the surface buffer.

- **A second colour attachment is refused where opening it would abort.** On
  Impeller's OpenGL ES path a second attachment reaches an `FML_CHECK` and the
  process stops, in release too. The five nodes that read the surface buffer
  are culled on a device whose `maxColorAttachments` is 1 and reported as
  `PassSkip.unsupported`, and the scene pass attaches only what the device can
  open (`gfx-50n`).

- **Culling and the work a still scene no longer does.** The render list culls
  by the mesh's world box where it used the sphere around it, which for a wall
  or a fence reached up to sqrt(3) times further (`gfx-61n`). A scene that
  moved refits `SceneBvh` and no longer rebuilds it: 23 ms to 0.85 ms on
  50 000 meshes, and `RenderList.bvhThreshold` is a field, 256 by default
  (`gfx-62n`). `SceneNode.subtreeBounds` lets a branch outside the frustum cost
  one test, with `RenderList.considered` counting them (`gfx-66n`). Each shadow
  cascade and each cube face culls its casters against its own frustum
  (`gfx-63n`). `worldMatrix` and `visibleInHierarchy` return on one integer
  comparison against `SceneNode.changeEpoch`, and `Skeleton.update` returns at
  once for a pose it already computed: 16.4 us to 4.7 us on 64 joints
  (`gfx-64n`, `gfx-65n`). The directional shadow pass is cached on the cascade
  matrices, the change epoch and the casters' materials, so a still camera over
  a still scene draws no cascade (`gfx-68n`). None of the forty-four golden
  scenes moved.

- **Identical draws batched, resolution as a setting, and memory given
  back.** `RenderSettings.batchIdenticalDraws` merges a run of four or more
  opaque nodes that share a mesh, a material, mirroring and a reflection probe
  into one instanced call, and `FrameResult.batchedDraws` counts them; it is
  off by default because it was compared byte for byte on the software
  rasteriser only. `InstancedMeshNode` gained `ensureCapacity` and `clear`.
  `RenderSettings.renderScale`, clamped to [0.1, 1], sizes every target of the
  frame, and `FrameResult.frame` is the smaller texture, which a presenter
  already stretches. `AdaptiveScale` is the policy over it, driven by
  `FrameResult.cpuMicros`: down above 1.1 times the target period, up only
  below 0.7 times it and after six clean windows.
  `Renderer.releaseTransientTargets` trims the render target pool, and
  `MemoryPressureRelease` in `flutter3d_app` calls it on a memory warning.

- **More than eight lights reach one draw.** Twenty-four more come from a
  texture holding every scene light, with a per-draw block of row numbers and
  fade scales; a draw with eight lights or fewer never reads it. The tail casts
  no shadow. `FrameResult.lightsDropped` now means light the frame could
  deliver nowhere (`gfx-74n`). `RenderSettings.lightFadeBand` turns the edge of
  a draw's light list into a smoothstep ramp, and 0, the default, is the old
  hard edge byte for byte; on the fixture built for it the change between
  neighbouring frames goes from 3.16% to 0.23%. `LightNode.channels` and
  `SceneNode.lightChannels` are bit masks compared where the lights of a draw
  are chosen, so a light off an object's channel does not take one of its slots.

- **`LightType.area`: a rectangle that lights like a rectangle.** The diffuse
  term is Lambert's polygon form factor, exact and with no table; the specular
  term is the representative point, and its known error is a lobe not widened
  by the panel's solid angle. It takes over the two per-light arrays a panel
  has no use for, so it adds no bytes to a draw. The brute-force quadrature it
  is tested against agrees to better than half a per cent across five
  arrangements (`gfx-77n`). `Photometric` converts between
  `LightNode.intensity` and lumens, candela and lux, anchored so that an
  800-lumen point lamp is intensity 1. Nothing applies it automatically.

- **Shadows.** A cut-out caster casts its cut-out: `ShadowDepthMasked` and
  `ShadowDistanceMasked` test `Material.alphaCutoff` against the map's alpha
  times the base colour's, on the directional and the point path (`gfx-60n`).
  `ShadowSettings.directionalLightRadius` above 0 searches for the blocker and
  widens the penumbra with its distance; 0 is the 3x3 kernel as before.
  `ContactShadowSettings` marches sixteen steps toward the sun against the
  depth the scene wrote, at the frame's own resolution, fades a hit with its
  distance along the march, and declines when nothing directional lights the
  scene (`gfx-76n`). The cascade atlas and the cube atlases own their depth
  buffers. They took one from the pool each frame, and Impeller's Vulkan
  backend caches a framebuffer keyed on the colour attachment alone, so the
  second pass drew into the first pass's depth or crashed; reported upstream as
  flutter/flutter#192538.

- **`IrradianceField`: one bounce of diffuse light from the room itself.** A
  grid of probes, each an octahedral tile of irradiance with a gutter and the
  two depth moments Chebyshev's inequality needs to stop light crossing a wall.
  A probe is gathered with rays through the engine's raycaster, `gather` and
  `gatherProbe`, and a probe inside geometry is found by counting rays that
  land on the inside of a surface. It reaches a draw through the ambient
  uniform that already existed, sampled facing up and facing down per object,
  so a large floor reads one point of the field. A scene with no
  `Scene.irradianceField` is byte for byte what it was (`gfx-81n`).

- **The composite: tone curves, a colour table and a three-way grade.**
  `RenderSettings.tonemapCurve` is a `TonemapCurve` of `neutral`, `aces`, `agx`,
  `reinhard` or `agxFull`, the last with its gamut rotation, and `neutral` is
  the old curve value for value. `LookSettings.lut` takes a strip of N slices
  of N by N with `lutStrength`, and `buildIdentityLut` makes the neutral one;
  an identity table was measured to change no byte of an eight-bit frame.
  `lift`, `gamma` and `gain` are colours, `whiteBalance` and `tint` sit beside
  the older `temperature`, and `dither` is a 4x4 ordered cell added after the
  sRGB encode: a 512-pixel dark ramp went from 39 flat runs to 255. Every
  default is an exact identity.

- **Anti-aliasing, occlusion, bloom, a lens, shafts and per-view exposure.**
  `AntiAliasSettings` is an FXAA pass after the composite, for the frame in
  which anything reads the surface buffer and multisampling is therefore off;
  `sharpen` rides in it and leaves a flat area untouched by construction.
  `AmbientOcclusionSettings.blurTaps` and `blurDepthFalloff` add a blur
  weighted by depth, so occlusion does not spread across a silhouette.
  `BloomSettings.referenceHeight` keeps a glow the same share of the picture at
  any resolution through `bloomLevelsFor`, and `halation` warms the wide levels
  of the chain and leaves the core. `DepthOfFieldSettings` is a thin lens:
  `focusDistance`, `focalLength`, `aperture` as an f-number and `sensorWidth`;
  it is a gather, so a foreground blur does not spread over a sharp background.
  `LightShaftSettings` marches the view ray against the directional shadow map
  sixteen steps a pixel and draws nothing when there is no caster.
  `AutoExposureSettings.perView` meters and exposes each view of a split
  screen from the one luminance readback. All of them are off by default.

- **Viewport shading read out of the surface buffer.**
  `RenderSettings.viewportShading` takes a `ViewportShadingSettings` whose mode
  is `normals`, `clay`, `outline` or `curvature`. It is drawn in the present
  phase from the normal and depth the scene pass already writes, so no node's
  material is swapped to show it (`gfx-43n` to `gfx-45n`).

- **Materials: a lighting model per surface, a vertex stage, hashed alpha and
  a source language.** `SurfaceMaterial.lightingModel` picks one of the six
  models by shader name; `.fmat` reads and writes it, glTF and OBJ have nowhere
  to carry it, and `.f3d`'s fixed material record has no room for it yet
  (`mat-04`). `LightingModel.vertexShaderName` names a vertex stage an
  application supplies through `Renderer.create(materials:)`: the name is the
  unskinned entry point and `<name>Skinned` the skinned one, and the pipeline
  cache key includes it. Instanced and lightmapped draws keep the engine's
  stages (`gfx-75n`). `MaterialAlphaMode.hashed` keeps a fraction of pixels
  equal to the opacity, hashed on world position, in the opaque half with
  depth written and nothing sorted; picking treats it as a mask at one half.
  `parseMaterial` reads a material written as typed parameters and a fragment
  body, `emitMaterialFragment` writes GLSL from the tree, `evaluateMaterial`
  runs the same tree on the CPU, and `describeMaterial` reads the bindings off
  it. The language has no uniform block, no loop, no `#define` and no vertex
  body (`gfx-84n`).

- **A route as one line.** `buildPolyline` writes each point twice with its
  neighbours, a signed half width and a colour, and `Material.polyline` pairs
  the `PolylineVertex` stage with Unlit, so a line is widened in the vertex
  stage and a camera move rebuilds nothing. Joins are mitres held at four half
  widths. `Material.parameters` now reaches a vertex stage the material
  brought as well as a fragment stage. The same commit fixed `FrameInfo` being
  bound through the engine's `MeshVertex` handle when the pipeline's vertex
  stage was the material's own (`gfx-86n`).

- **A captured cloud of Gaussians loads, sorts and draws.** `parseSplatPly`
  reads the binary PLY a capture ships as, including the three conventions its
  header does not state: `opacity` is a logit, `scale_*` are logarithms and
  `f_dc_*` are the zeroth spherical-harmonic band. `SplatCloud` holds the
  splats as flat arrays and `SplatContributor` draws them as quads blended
  back to front with no depth write. Two approximations are stated in the
  code: the projection drops the perspective Jacobian, and the higher
  harmonic bands are skipped, so a splat does not change colour with the
  viewing angle. The CPU rebuild measured 359 ns a splat per camera move
  (`gfx-80n`).

- **Cameras and projections.** `OffAxisProjection` takes four tangents, which
  is what a headset hands over per eye, and `Projection.verticalFieldOfView`
  answers null where the question does not apply; `LodGroup` and the shadow
  cascades ask it and no longer fall back to 45 degrees or 200 metres.
  `RenderSettings.forStereo()` takes out what a pair drawn side by side cannot
  have: ambient occlusion, reflections and bloom. `TiledProjection` answers
  for one tile of a frame larger than any render target, checked by a 2x2
  stitch against one whole render byte for byte. `OrbitController` has an
  `orthoHeight` kept in step with its distance, `animateTo(yaw:, pitch:)` with
  `advance(seconds)`, and a `frameBounds` that lowers `minDistance` to a tenth
  of the radius it frames, so a millimetre-scale model can be framed.
  `FreeLook` turns the head and walks over the same yaw, pitch and target.

- **An overlay that sits on the surface, and a skeleton on screen.**
  `MeshOverlay` draws edges, vertex handles and a face wash in three batches
  and three draws whatever is in them, with handles and the nudge toward the
  eye sized in pixels. Design colours are converted on the way in, because the
  overlay is encoded inside the scene pass and the composite encodes on the
  way out. `throughGeometry` writes into a second pass with no depth test at
  `throughOpacity`, for a gizmo whose pivot is inside the object.
  `DebugDrawOptions.skeletons` draws every skinned mesh's joints through
  `addSkeletonOverlay`: an octahedron per bone and a cross at each leaf.

- **Poses, skinning and IK without a scene.** `Pose` holds a hierarchy's local
  TRS in flat arrays, samples a clip, composes `worldMatrices` and
  `jointMatrices` by the formula `Skeleton.update` documents, and `writeTo`
  pushes it onto scene nodes. `SkinBlend` repeats the skinned vertex stage on
  the CPU. `TwoBoneIk` solves from the chain's current bend toward a target
  and a pole, and `FabrikIk` a chain of any length; a sign error in
  `TwoBoneIk.solve` for a chain bent at rest was fixed with a test on a chain
  bent 90 degrees. `AnimationPlayer.rootMotionDelta` reads the
  `flutter3dRootMotion` extra of a clip, across the wrap. A layer can be
  `AnimationBlend.additive` over a clip whose `AnimationClip.referenceTime`
  names its rest frame; a clip without one gets the override path.

- **Picking, screen space and vertices overwritten in place.** `Raycaster`
  tests a skinned mesh where its pose puts it, through `PosedMesh`, and
  `Raycaster.posed` turns that off; the early box rejection uses the posed box,
  and weights that do not sum to one are renormalised. `TriangleBvh` in the geometry library is new: a tree over one
  mesh's triangles, in typed arrays, with `raycast`, `refit`, and
  `forEachInAabb` and `forEachInFrustum`, which report by a triangle's box and
  so may report a few extra. `screenBoundsOfBox` projects a world box to
  a rectangle on the glass, and answers the whole viewport for a box the eye
  is inside. `DeviceMesh.overwriteVertices(device, firstVertex, vertexBytes)`
  writes into a live vertex buffer through `GraphicsDevice.overwriteGeometry`,
  grows `bounds` to cover the new positions and bumps `version`; the box only
  grows.

- **A panorama lights the scene.** `readHdr` decodes Radiance `.hdr` in both
  scanline encodings to floats and `hdrSizeOf` reads the header alone.
  `EnvironmentMap.equirectToCubeFaces` cuts six faces from a 2:1 panorama and
  `EnvironmentMap.fromPanorama` uploads and prefilters them. The cube is eight
  bits a channel, so a sun far brighter than its sky clamps to white.

- **A model is written as well as read.** `GltfWriter` writes a self-contained
  GLB: geometry, materials and samplers, skins, animation channels in all
  three interpolations, morph targets with their names, lights through
  `KHR_lights_punctual`, cameras, `extras` on five kinds of object, and a Basis
  KTX2 image through `KHR_texture_basisu`. `compressGeometry: true` adds
  `KHR_mesh_quantization`, vertex cache reordering and
  `EXT_meshopt_compression`, which the reader decodes too; with the index
  codec's edge history the measured fixture is 3.60 times smaller, and the
  output was checked against meshoptimizer 1.2.0's own decoder. `StlWriter`
  writes binary or ASCII, `ObjWriter` bakes each surface's world matrix,
  and `UsdzWriter` writes geometry only, one `Mesh` prim per surface, in an
  archive macOS identifies as USDZ. Every writer has `warnings` naming what
  its format cannot carry. `exportToGlb`, `exportToObj`, `exportToStl` and
  `exportToF3d` answer an `ExportReport` with the files, the warnings and the
  differences `compareModelDocuments` found on reading the file back, morph
  targets included. `validateGltfExport` checks each accessor's declared
  bounds against its data. `ModelWriter`, `modelWriterNamed` and
  `encodeModelInIsolate` with a `ModelWriteRequest` are the same from above.

- **STL is read, and a document holds more of its file.** `StlLoader` reads
  both dialects and tells them apart by the file's size arithmetic, since a
  binary header often begins with `solid`; its document has a node for its
  surface, which it did not at first. `ModelFormat.stl`, `sniffModelFormat`
  and `recognizedModelFormat` know it. `ModelDocument` gained `lights`,
  `cameras`, an `asset` of type `DocumentAsset` and `extras`; `ModelSurface`
  gained `meshName` and `authoredAttributes`, the attributes read from real
  data; `EncodedImage` gained `sourceUri`; `TextureSampling` gained `mipLinear`
  with `toGltfFilters()`; and `ModelNode.lods` holds `ModelLod` levels, written
  to `.f3d` as section 21 and to glTF as `MSFT_lod`, the latter checked only
  against this package's own reader. Every new `.f3d` section is optional on
  read and `kF3dVersion` is still 1. `surfaceMaterialToJson` and
  `surfaceMaterialFromJson` are the one codec for a material's fields.

- **KTX2: supercompressed files open, and textures are encoded.**
  `Ktx2Texture.parse` unwraps Zstandard and ZLIB levels through a decompressor
  written here, `zstd.dart`, since every Dart zstd binds the C library and a
  web build cannot load one. Thirty structured and sixty fuzzed streams at
  levels 1 to 19 decode byte for byte, and the four bugs found on the way are
  in the commit for `gfx-78n`. `encodeBc1`, `encodeBc3`, `encodeEtc2Rgb8` and
  `encodeAstc4x4` encode, `buildMipChain` halves with a box filter, and
  `writeKtx2` writes the container. The ASTC encoder wrote a reserved block
  mode that ARM's astcenc decoded as magenta; it writes mode 0x53 now and is
  pinned to astcenc's output, with a worst channel error of 7 over a 64x64
  gradient (`gfx-88n`). `encodeUniversalBlocks` writes a 4x4 intermediate of
  twenty bytes a block, and `transcodeUniversal` turns it into BC1, BC3, ASTC
  4x4, ETC2 or RGBA8; `uploadEncodedImage` picks the `UniversalTarget` from
  what the device samples. Against encoding directly it costs ASTC nothing,
  BC1 0.6 dB and ETC2 0.9 dB, and ETC2 takes about a second per 1024x1024
  level because that leg decodes and re-encodes (`gfx-83n`).

- **Images without `dart:ui`.** A PNG decoder and encoder, a baseline JPEG
  decoder, DEFLATE and inflate are in the formats library, `decodeImagePure`
  wraps the two decoders in the `ImageDecoder` shape, and `sniffImageMimeType`
  names PNG, JPEG, KTX2 and WebP from their first bytes.

- **A UASTC KTX2 opens (`gfx-78n`).** What `toktx --uastc`,
  `gltf-transform uastc` and `basisu -uastc` write was refused by name — and
  by guess, since any undefined `vkFormat` outside Basis-LZ was taken to be
  one. `Ktx2Texture.parse` now
  reads the data format descriptor's colour model to learn *which* Basis
  Universal a file holds instead of inferring it from the supercompression
  scheme, and unpacks UASTC LDR 4×4 — all nineteen modes — to RGBA8 in
  `uastc_decoder.dart`, through the same Zstandard and ZLIB unwrapping the plain
  formats use, since a current encoder Zstandard-compresses UASTC unless told
  not to. Unpacked rather than repacked to BC7 or ASTC: every file opens on
  every device, at four bytes a texel. A glTF that ships only a
  `KHR_texture_basisu` UASTC texture keeps it. UASTC HDR and the newer
  intermediate colour models are refused by name. Tables transcribed from the
  Basis Universal reference transcoder, and checked against it the only way
  worth having: files its own encoder wrote, chosen until every mode appears
  in them, compared **byte for byte** with its own RGBA32 output.

- **A Draco-compressed glTF opens (`gfx-82n`).** `KHR_draco_mesh_compression`
  was detected, warned about and skipped, so a compressed file opened as a
  model with holes in it — and since every such file names the extension as
  required, most were refused outright before that. `decodeDraco` now reads
  edgebreaker connectivity, which is what every encoder writes unless told
  otherwise, in both its standard and valence traversals; both attribute walks;
  and every prediction scheme a bitstream 2.2 encoder can choose — difference,
  parallelogram, constrained multi-parallelogram, portable texture coordinates
  and geometric normals. `GltfLoader` decodes the payload and puts its values
  behind the primitive's own accessors through the new
  `GltfAccessorReader.supplyDecoded`, so morph targets, skinning and the writer
  read a compressed primitive as they read any other; joints stay the integers
  they were stored as. A payload that does not decode costs that primitive, and
  the warning carries the decoder's reason. Point clouds, bitstreams before
  2.2, the predictive traversal and the two retired prediction schemes are
  refused by name. Checked against `gltf-transform draco` at its default speed
  and at speed zero — which are nearly disjoint sets of code paths — on a
  thousand-face mesh with UV seams and on a skinned one, triangle for triangle
  against the uncompressed originals. **One bug in what was already there,
  found by that comparison**: the rANS end-of-stream check compared the state
  without first pulling in the bytes the encoder shifted out before its first
  symbol, so a valid stream whose first symbol was rare was refused.
- **`KHR_texture_transform` can be honoured, in the coordinates.**
  `sharedTextureTransform` names the one transform every texture of a material
  asks for, and `withTextureTransform` gives a mesh with that transform applied
  to its texture coordinates, tangents turned and mirrored with them. That is
  the case an atlas export writes, and it needs no matrix at the sampler. The
  decoder still applies nothing, so a document written out again is the file
  that was read. Its warning changes: it no longer fires for every texture that
  names the extension, only for a material whose textures name different
  transforms, which one set of coordinates cannot satisfy. A file that lists
  the extension under `extensionsRequired` is still refused.
- **A morph-target warning names its primitive.** The three warnings the glTF
  loader adds when it drops a morph target had their interpolations escaped,
  so each said, literally, `$label has ${targets.length} morph target(s)`.
  Nothing failed because nothing reads a warning but a person.
- **What it depends on, and what the archive carries.** `flutter3d_hardware` at
  `^0.7.0` and `vector_math`. `package:flutter3d_core/geometry.dart` and
  `formats.dart` import neither the renderer nor a device. The archive carries
  `skills/flutter3d-core-geometry-meshes/` and
  `skills/flutter3d-core-formats-reading-models/` for a coding agent, installed
  with `dart run skills@ get`.

## 0.1.0

- **The rendering core leaves `flutter3d` (`mcp-03n`).** Scene graph, render
  list, passes, materials and animation move here with no Flutter SDK
  behind them; `flutter3d` re-exports this package and keeps `rootBundle`,
  `dart:ui` and the widgets for its own thin shell.
