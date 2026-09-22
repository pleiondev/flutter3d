# Engine gap analysis: space, slalom, open world, and the genre list

Read on 2026-09-19 against `modeler-ui` at `302be699`. Seven passes went over
the code, each told to check the documentation against the tree before
believing it. Where two passes disagreed I read the file myself; that settled
volumetric fog, what the sweep does with a moving capsule, and
`StaticMeshShape`, all below.

This document lists what is missing, and `doc/plan-status.json` has no rows for
any of it yet. The work is scheduled for the release after 0.7.0.

## Scope

Three games were the source of requirements: a space station with ships and
weapons fire; a ski slalom with mountain terrain, snow thrown by the skis,
falling snow and fog; an open world with sky, ground, rivers, sea, LOD models
and a way to construct new game objects. The owner then widened the question
to a list of genre groups (many objects, large fast worlds, characters,
procedural geometry, high-quality small scenes, horror, stylisation, XR,
educational and engineering 3D).

Decisions taken on 2026-09-19:

| Question | Decision |
|---|---|
| What gets built | Engine and physics work only, without new genre packages or demo apps. The games stay as the source of requirements. |
| Platforms | Desktop, web and mobile. |
| Genre groups in scope | Characters, many objects, quality and stylisation, engineering 3D and XR. Procedural geometry (voxels) is out. |
| Rotation in physics | Grow the existing solver: quaternion, angular velocity, inertia tensor, then joints and CCD. Plain Dart, `Portable` maths, snapshot-compatible. |
| Space scale | An arena around the station, up to about 10 km. No floating origin; reversed-Z and a 3D broadphase are enough. |
| Station content | Modular parts joined at sockets. |
| Decals | Both mechanisms: projected decals, and a trail map written through render-to-texture and read by the terrain shader. |
| Terrain heights | All four sources: noise in the engine, sculpting in the level editor, heightmap import, MCP tools. |
| Open-world size | Up to about 4×4 km, streaming terrain tiles and models by distance. |
| Water | Sea with vertex waves, plus rivers along splines. |
| Sky and weather | Atmospheric scattering with time of day, stars, a cloud layer, height fog, camera-follow weather particles. |
| Verification | New golden scenes in `packages/flutter3d/example`, headless physics tests with VM/web parity. |
| Game object | An asset format: model, LOD chain, collision, sockets, and full orientation in the level format. No behaviour, no UI. |
| Shader contract | One breaking release: `time` in the uniform block, user texture slots in the material language, source materials compiled by `flutter3d_build` for every GPU backend. Goldens are rewritten once. |
| Order | Cheap wins, then physics, then shaders, then VFX, then world scale. |

## What the three games are blocked on

### Space

`RigidBody` has no orientation at all (`rigid_body.dart:37`,
`dynamics.dart:23`). Roll exists in neither camera nor input: `FlyCamera` lives
in the editor and clamps pitch, `InputState` has two 2D axes. `EntityDef`
stores `yaw` only and brushes are axis-aligned. `SpatialGrid` is a 2D grid
over XZ with 4 m cells. A star field, a ribbon or beam primitive and additive
blend on an ordinary `Material` are all missing, and `ParticleSystem.burst()`
never assigns `particle.source`, so a muzzle flash or an explosion cannot
light anything.

### Slalom

`CollisionHeightfield` is written and tested and constructed nowhere outside
tests: `LevelCollision.addTo` (`level_collision.dart:23`) adds brushes only.
`SphereVehicle` already has the right skeleton (ground normal, gravity along
the slope, sweep with slide), but it asks the ground through `GroundField`,
whose one implementation follows a track spline. Particles blend additively
only, so white snow cannot be drawn. An emitter does not pass its velocity to
what it emits. Decals, weather and height fog are missing, a terrain takes one
cover texture, and nothing in the tree generates noise to build a mountain from.

### Open world

The only water in the tree is a swim trigger in the platformer. Terrain tiles are never released (`terrain_tiles.dart`, `_uploaded`)
and `DeviceMesh` has no `dispose()`. Far plane defaults to 1000 m with a
standard depth projection. `LodSpec` lives in `.f3dproj` and
`project_document.dart` never mentions it, so a LOD chain authored in the
modeler does not reach `.f3d` or `.glb`. `LodGroup` is built automatically only
when each level is a single surface. Nothing in the tree is a prefab.

## Nine foundations

Most gaps across the genre list reduce to these.

1. **Rotation and joints in physics.** Ships, docking, ragdoll, debris.
2. **The shader contract.** No `time`; five closed texture bindings
   (`kMaterialTextureBindings`); `emitMaterialFragment` is called from tests
   only, so a source material runs on the CPU rasteriser and nowhere else.
   `FullscreenEffect`, `LayeredShaderLibrary` and
   `LightingModel.vertexShaderName` are built and have no consumer.
3. **World scale.** Reversed-Z, tile and asset streaming, releasing GPU
   memory, index buffer updates.
4. **Terrain as a system.** Collision wiring, noise, material layers,
   geomorphing, editor and MCP tools.
5. **VFX.** Alpha blending with sorting, ribbons and beams, inherited
   velocity, stretched billboards, particle collision, decals, a serialised
   effect format.
6. **The game object.** Model, LOD, collision and sockets as one asset;
   orientation in the level format.
7. **Per-instance work.** An instanced batch is one sphere for culling, one
   LOD level, one pick id, and its whole buffer is copied for every pass of
   every frame. `BakedPoses` bakes clips into a pose texture and no shader
   reads it.
8. **Animation runtime.** `AnimationLayer`, `rootMotionDelta`, `TwoBoneIk` and
   `FabrikIk` are called from tests only. A state machine, a blend space, clip
   events and bone sockets are missing. A mesh takes 64 joints and the
   constructor throws past that; eight morph targets can be active at once.
   `FbxDecoder.decode` refuses.
9. **Render-to-texture, clip planes, billboards and world-space text.**
   `Renderer.render` has no target parameter. `edu_clip_plane` and
   `edu_step.offsets` are authored and no host draws them.

## Milestones

Row ids are not assigned. Each line is sized to become one row.

### M0. Connect what is already written

- `LevelCollision.addTo` adds `level.heightfield` as a `CollisionHeightfield`.
- `ParticleSystem.burst()` assigns `source`, so `LightEmitter` works for bursts.
- `rootMotionDelta` drives `CharacterController`; refuse or support cubic tracks.
- A bridge from `Pose` to the scene skeleton, so both IK solvers run at runtime.
- A default for `AnimationClip.referenceTime`, so additive layers work on imported clips.
- LOD chain survives export: `project_document.dart` builds `ModelLod`.
- `LodGroup` for models with more than one surface per level.
- `lod_screen.dart`, `uv_screen.dart`, `retopo_overlay.dart` reachable from the app.
- `KHR_texture_transform` applied, not only decoded.
- `TerrainTiles` invalidates its cache when heights change.
- `AdaptiveScale` offered by `SceneSurface`; a note on `lightFadeBand`.
- A stored performance baseline on a phone: draw calls, triangles, frame time.
- Stale statements fixed: `ARCHITECTURE.md:2535` (FXAA exists),
  `doc/postprocessing-parity.md:54` (DoF, light shafts, dither, sharpen and
  render scale exist), `doc/model-editor-functions.md:537-567`,
  `doc/package-merge-plan.md`. Empty package directories removed.

### M1. Physics

- Orientation, angular velocity, inertia tensor, angular friction in `RigidBody` and `Dynamics`.
- `Portable.acos` and slerp, since `dart:math` transcendentals are banned in the step.
- Joints: fixed, hinge, ball, distance. Then CCD.
- A capsule and a sphere swept as themselves. Today the mover is its bounding
  box (`collision_world.dart:381`); wedges and heightfields already return
  real planes.
- Slope limit as tuning, not the constant at `character_controller.dart:346`.
- A triangle-mesh shape with internal edge filtering. `StaticMeshShape` in
  `flutter3d_mesh` is triangle soup and nothing in physics reads it.
- A 3D broadphase beside the XZ grid.
- `GroundField` moved out of the racing package, with an implementation over
  `Heightfield`, and anisotropic lateral friction for an edge.
- Water volumes in the level format; buoyancy and current on bodies.
- A 6DOF camera rig without gimbal lock; a third analogue axis in `InputState`.

### M2. Shader contract, then what it unlocks

- The breaking release described above; additive blend selectable on `Material`.
- Reversed-Z depth.
- Water: Gerstner vertex stage, depth-based refraction, shore foam, spline rivers with flow.
- Sky: scattering LUT, sun and time of day in core, stars, cloud layer. Sky per view.
- Height fog. There is no volumetric fog either; the only code that uses the
  word is `light_shafts.frag`.
- Terrain: splat or triplanar layers, geomorphing between tile levels, a snow material.
- `LodGroup` hysteresis and a hashed cross-fade.
- Public render-to-texture: a camera that renders into a texture. Planar reflection on it.
- Clip planes with a cap, on all four backends.
- Inverted-hull outline, ramp texture for toon, matcap, quantised toon shadow.
- MSAA and the surface buffer stop being mutually exclusive
  (`renderer_scene_pass.dart:49`), or TAA replaces MSAA.
- Glass: transmission, IOR. `KHR_materials_variants`.

### M3. VFX

- Alpha and premultiplied particles with sorting; soft particles; lit particles.
- Inherited emitter velocity and local space.
- Velocity-stretched billboards. Ribbons and beams.
- Particle collision with the world; sub-emitters; rotation on mesh particles.
- A camera-follow emission volume for snow and rain.
- An effect format with `toJson`/`fromJson`. No editor in this round.
- Projected decals. A trail map through render-to-texture.
- Doppler in `flutter3d_audio`. A velocity buffer and motion blur.

### M4. World scale and instances

- `DeviceMesh.dispose()`, index overwrite, mesh resize.
- Terrain tile streaming and model streaming by distance, with a VRAM budget.
- Per-instance culling, LOD and pick id; dirty ranges for the instance buffer;
  rectangle readback for box selection.
- Skinned instancing through `BakedPoses`.
- A scene node for `ImpostorCard`, tied to `LodGroup`.
- A noise package on `Portable` maths. Heightmap import in `flutter3d_build`.
- A spline type, used by rivers, routes and sweep geometry.
- The asset format: LOD, collision and sockets in `.f3d`; a quaternion on `EntityDef`.
- Terrain tools in the level editor and in `flutter3d_editor_mcp` (17 tools
  today against 147 in `flutter3d_model_mcp`, none touching a heightfield).

### M5. Characters, engineering 3D, XR

- Animation state machine, 1D and 2D blend space, clip events, bone sockets.
- More than 64 joints (a joint texture or palette splitting); more than 8 morph targets.
- FBX decoding. Ragdoll on top of M1. Cloth pinned to joints.
- `offsets`, `edu_annotation` and `edu_clip_plane` drawn by the lesson hosts.
- Billboard nodes, world-space text, leader lines, measurements, units on import.
- XR: lens distortion, multiview, then a real runtime (WebXR or OpenXR). The
  current package is a side-by-side pair for a Cardboard holder with 3-DOF
  tracking on Android only.

## Out of scope for now

New genre packages and demo apps. Voxels, greedy meshing, fracture, dungeon
generators. Floating origin and double-precision positions. A particle effect
editor. Behaviour or scripting on a game object. Multiplayer beyond the
two-peer rollback that exists.
