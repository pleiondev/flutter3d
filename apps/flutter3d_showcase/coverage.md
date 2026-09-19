# What the showcase covers

The list of pages, read from the code of the engine (the public `lib/` API of each
package) and not from the headings of a CHANGELOG. **One row is one page.** A row
that says *fold* is shown on the page of another row and has no page of its own. The
`since` column is a hint: the version heading a CHANGELOG entry sits under, or
`unknown` when no entry names it. A page's `evidence` line has to be checked against
the record by hand before the catalog test will accept it. Paths are under
`packages/`.

Sets A to I are the units of parallel work: a worker owns one set's catalog file,
pages and tests, and nothing else. `CL` means that package's `CHANGELOG.md`; `F3D` is
`packages/flutter3d/CHANGELOG.md`, the master record for the renderer, scene,
animation and assets.

**Items that do not exist and must not get a page:** an anisotropic BRDF (the only
anisotropy is texture filtering, `RenderSettings.anisotropy`); retargeting (only a
comment in `pose.dart` mentions it); a real FBX reader (`FbxDecoder` recognises the
format and refuses it with a reason); a separate spot-shadow system (a spot light uses
one face of the point-light cube slot).

The **0.7.0 audit** at the end lists every `## 0.7.0` entry of the CHANGELOGs and the
page that shows it, or the reason none does. It is what makes "new in 0.7" a checked
statement (see `test/coverage_test.dart`).

## Set A: shading (`lib/pages/shading/`)

| id | title | main API | since |
|---|---|---|---|
| lighting-models | The six lighting models | `LightingModel.builtIn`, `Material.lighting` (`formats/lighting_model.dart`); toon and normals are two of the six | F3D 0.1.0 "Six lighting models" |
| pbr-lighting | PBR metal and rough | `Material.metallic/roughness/baseColor/emissive` (`render/material.dart`) | F3D 0.1.0 |
| normal-mapping | Normal maps | `Material.normal`, `normalScale`, `mesh_tangents.dart` | unknown |
| alpha-modes | Alpha modes | `MaterialAlphaMode` opaque/mask/blend/hashed, `alphaCutoff`, `doubleSided` | hashed: F3D 0.7.0 |
| draw-state | Draw order and depth state | `Material.depthWrite/depthCompare/drawBucket`, `RenderSettings.backfaceCulling` | unknown |
| texture-filtering | Anisotropic texture filtering | `RenderSettings.anisotropy`, `GraphicsDevice.maxAnisotropy` (needs mip maps) | F3D 0.4.3 |
| specular-scale | Specular strength | `RenderSettings.specular` | unknown |
| exposure | Manual exposure | `RenderSettings.exposure` | unknown |
| wireframe | Wireframe | `RenderSettings.wireframe`, `FrameResult.wireframeDeclined` (needs wireframe: Impeller only) | unknown |
| draw-batching | Identical-draw batching | `RenderSettings.batchIdenticalDraws`, `FrameResult.batchedDraws` | F3D 0.7.0 |
| punctual-lights | Directional, point and spot lights | `LightNode`, `LightType`, cone angles, `range` | F3D 0.1.0 |
| area-lights | Rectangle area lights | `LightType.area`, width and height | F3D 0.7.0 |
| photometric-units | Lights in lumens and lux | `Photometric.fromLux/fromCandela/fromLumens` | F3D 0.7.0 |
| light-channels | Light channels | `LightNode.channels`, `SceneNode.lightChannels` | F3D 0.7.0 |
| many-lights | Thirty-two lights and the fade band | `RenderSettings.lightFadeBand` (check the real per-draw limits in code before quoting a number) | F3D 0.7.0 |
| ambient-light | Ambient light | `Scene.ambientColor/ambientIntensity` | unknown |
| fmat-files | `.fmat` material files | `readFmat/writeFmat`, `MaterialDocument` (`formats/fmat/`) | F3D 0.3.0 |
| material-language | The material expression language | `parseMaterial`, `evaluateMaterial`, `material_glsl` (`formats/material_language/`) | F3D 0.7.0 |

## Set B: environment and shadows (`lib/pages/environment/`, `lib/pages/shadows/`)

| id | title | main API | since |
|---|---|---|---|
| procedural-sky | Procedural sky | `SkySettings`, `sky_gradient.dart`, `SkyDome` (fold the dome) | F3D 0.2.0 |
| distance-fog | Distance fog | `FogSettings` | at most F3D 0.5.1 (`approximate`) |
| image-based-lighting | Image-based lighting | `EnvironmentMap.prefilter/fromSky/fromPanorama`, `Scene.environment` (needs cube textures, mip maps, render to mip) | prefilter F3D 0.3.0; panorama F3D 0.7.0 |
| reflection-probes | Reflection probes | `ReflectionProbeNode`, `renderer_probe_pass.dart` (cube textures, render to mip) | F3D 0.4.3 |
| irradiance-field | One bounce of diffuse light | `IrradianceField`, `irradiance_gather.dart` | F3D 0.7.0 |
| lightmaps | Baked lightmaps | `MeshNode.lightmapped`, `Material.lightmap`, `mesh_lightmapped.vert` | F3D 0.4.2 |
| shadow-settings | Shadow quality | `ShadowSettings` resolution, bias, strength, view distance | unknown |
| cascaded-shadows | Cascaded directional shadows | `ShadowSettings.cascades/cascadeSplit/viewDistance` | F3D 0.2.0 "Cascaded directional shadows" |
| point-light-shadows | Point and spot shadows | `pointBias/pointSoftness/pointLightRadius/cubeResolution/casterFaces` (cube textures) | F3D 0.2.0 |
| soft-shadows | Penumbra that widens with distance | `directionalLightRadius`, `pointLightRadius` | F3D 0.7.0 |
| contact-shadows | Contact shadows | `ContactShadowSettings` | F3D 0.7.0 |
| static-shadow-cache | The cached shadow map | `static_bake_key.dart`, `showStaticShadowMap`, `MeshNode.castShadow` | F3D 0.7.0 |
| masked-shadow-casters | Shadows of cut-out leaves | `shadow_depth_masked.frag` | F3D 0.7.0 |

## Set C: post-processing (`lib/pages/post/`)

| id | title | main API | since |
|---|---|---|---|
| bloom | Bloom and halation | `BloomSettings` | F3D 0.1.0; halation F3D 0.7.0 |
| tone-mapping | Tone-map curves | `TonemapCurve` neutral/aces/agx/reinhard/agxFull | F3D 0.7.0 |
| color-grading | Colour grade | `LookSettings` contrast, saturation, temperature, lift/gamma/gain, vignette, grain, chromatic aberration | F3D 0.3.0; more F3D 0.7.0 |
| lut-grading | Grade through a LUT | `LookSettings.lut/lutStrength` | F3D 0.7.0 |
| auto-exposure | Auto exposure | `AutoExposureSettings` | F3D 0.4.3; `perView` F3D 0.7.0 |
| screen-space-reflections | Screen-space reflections | `ReflectionSettings` | F3D 0.2.0 |
| ambient-occlusion | Ambient occlusion | `AmbientOcclusionSettings` | F3D 0.2.0; blur F3D 0.7.0 |
| light-shafts | Light shafts | `LightShaftSettings` | F3D 0.7.0 |
| anti-aliasing | FXAA and sharpen | `AntiAliasSettings`, `FrameResult.antiAliasing` | F3D 0.7.0 |
| msaa | Automatic multisampling | `device.preferredSampleCount`, `msaaDeclined` (needs offscreen MSAA) | unknown |
| depth-of-field | Depth of field | `DepthOfFieldSettings` | F3D 0.7.0 |
| user-post-effect | Your own post effect | `FullscreenEffect.overlay/present` | F3D 0.7.0 |
| viewport-shading | Viewport shading | `ViewportShadingSettings` normals/clay/outline/curvature | F3D 0.7.0 |
| surface-buffer | The surface buffer | `RenderSettings.surfaceBuffer`, `showSurfaceBuffer` | unknown |
| adaptive-resolution | Adaptive resolution | `RenderSettings.renderScale`, `AdaptiveScale` (the caller feeds it frame time) | F3D 0.7.0 |
| xray | X-ray silhouettes | `XraySettings`, `renderer_xray_pass.dart` (needs stencil) | F3D 0.4.3 |
| disabled-passes | Switching passes off | `RenderSettings.disabledPasses`, `passOrder` | F3D 0.7.0 |
| render-post | Post effects on your own image | `Renderer.renderPost` | F3D 0.7.0 |

## Set D: scene and geometry (`lib/pages/scene/`)

Avoid a file name that contains `camera` (structure rule); say `view` or `orbit`.

| id | title | main API | since |
|---|---|---|---|
| scene-graph | The scene graph | `SceneNode`, version counters (`scene/`) | F3D 0.1.0 |
| culling | BVH and frustum culling | `SceneBvh`, `FrameResult.culled` | F3D 0.1.0; box culling F3D 0.7.0 |
| level-of-detail | Levels of detail | `LodGroup`, `LodLevel` (**needs the layout fix of phase 0**) | F3D 0.7.0 |
| instancing | Instanced meshes | `InstancedMeshNode` `ensureCapacity/clear` | F3D 0.2.0 |
| debug-draw | Debug drawing | `DebugDrawOptions` bounds, normals, gizmos, skeletons | F3D 0.7.0 |
| mesh-overlay | Mesh overlay | `MeshOverlay`, `OverlayBatch` | F3D 0.7.0 |
| polylines | Polylines of a width in pixels | `buildPolyline`, `Material.polyline`, `PolylineShape` | F3D 0.7.0 |
| gaussian-splats | Gaussian splats | `parseSplatPly`, `SplatCloud`, `SplatContributor` | F3D 0.7.0 |
| procedural-shapes | Procedural shapes | `CuboidShape`, `SphereShape`, `TorusShape`, `CapsuleShape`, `DiscShape` | F3D 0.1.0 |
| lathe-shape | Surfaces of revolution | `LatheShape` | F3D 0.1.0 |
| mesh-builder | Building a mesh in code | `MeshBuilder`, `MeshData`, `VertexLayout` | unknown |
| tangents | Generated tangents | `MeshTangents.withTangents` | unknown |
| vertex-cache | Vertex cache ordering | `optimizeTriangleOrder`, `optimizeVertexFetch` | unknown |
| procedural-textures | Procedural textures | `SolidColorTexture`, `CheckerboardTexture` | F3D 0.5.0 |
| view-model | The held item's own pass | `ViewModelNode` | F3D 0.4.0 |
| multi-view | Several views in one frame | `RenderView`, `ViewportRect`, `layerMask` | unknown |
| frame-stats | What a frame reports | `FrameResult` counts, `FramePass` timings | F3D 0.7.0 |
| frame-graph | The frame graph | `Renderer.planFrame`, `FrameResult.skipped`, `passOrder` | F3D 0.1.0; planFrame F3D 0.7.0 |
| frame-capture | Capturing a frame | `Renderer.captureNextFrame`, `FrameCapture` | F3D 0.7.0 |

## Set E: animation (`lib/pages/animation/`)

| id | title | main API | since |
|---|---|---|---|
| skinning | Skinned meshes | `Skeleton`, `SkinBlend` (CPU mirror of the GPU stage) | F3D 0.1.0 |
| clip-playback | Clips and crossfades | `AnimationPlayer` play/crossFadeTo/speed/wrap | F3D 0.1.0 |
| interpolation | Step, linear and cubic tracks | `AnimationTrack`, `AnimationInterpolation` | F3D 0.7.0 |
| morph-targets | Morph targets | `MorphState`, `MorphTexture` | F3D 0.5.2 |
| instanced-morphs | A face per copy | `InstancedMeshNode.setMorphWeights` (vertex texture) | F3D 0.5.2 |
| animation-layers | Layers and masks | `AnimationLayer`, `AnimationMask` | F3D 0.5.2 |
| additive-blend | Additive layers | `AnimationBlend.additive`, `AnimationClip.referenceTime` | F3D 0.7.0 |
| root-motion | Root motion | `AnimationPlayer.rootMotionDelta` (a clip with the `flutter3dRootMotion` extra) | F3D 0.7.0 |
| two-bone-ik | Two-bone IK | `TwoBoneIk` | F3D 0.7.0 |
| fabrik-ik | A chain of any length | `FabrikIk` | F3D 0.7.0 |
| pose-sampling | A pose with no scene | `Pose` | F3D 0.7.0 |
| baked-crowd | A crowd from baked poses | `BakedPoses` + `InstancedMeshNode` | unknown |
| skeleton-debug | The skeleton drawn | `DebugDrawOptions.skeletons` | F3D 0.7.0 |

## Set F: views, picking, input and backends (`lib/pages/view_input/`, `lib/pages/backends/`)

| id | title | main API | since |
|---|---|---|---|
| projections | Perspective and orthographic | `PerspectiveProjection`, `OrthographicProjection` | unknown |
| off-axis-projection | Off-axis frustum | `OffAxisProjection` | F3D 0.7.0 |
| tiled-render | Rendering in tiles | `TiledProjection` | F3D 0.7.0 |
| orbit-controller | Orbit | `OrbitController` `frameBounds/animateTo/advance` | F3D 0.7.0 for the new parts |
| free-look | Free-look and walking | `FreeLook` | F3D 0.7.0 |
| raycast | CPU raycasting | `Raycaster`, `TriangleBvh`, `HitResult` | F3D 0.1.0; skinned hits F3D 0.7.0 |
| pixel-picking | Picking by pixel | `Renderer.pickPixel` | F3D 0.4.3 |
| screen-bounds | Screen-space bounds | `screenBoundsOfBox` | F3D 0.7.0 |
| gamepad | Gamepad | `pad_input` `PadSnapshot`, `Deadzone` (needs a gamepad) | own line 0.4.x |
| pointer-lock | Pointer lock | `pointer_lock` (desktop and web) | own line 0.4.x |
| input-bindings | Bindings and rebinding | `flutter3d_game` `Bindings`, `Rebinding`, `DragLook` | unknown |
| touch-controls | Touch controls | `TouchStick`, `TouchButton` (a touch device) | flutter3d_game 0.4.0 |
| backend-impeller | Impeller | `flutter3d_impeller` (native only) | 0.1.0 |
| backend-webgl | WebGL2 | `flutter3d_webgl` | 0.1.0 |
| backend-webgpu | WebGPU | `flutter3d_webgpu` | 0.6.0 |
| backend-cpu | The software rasteriser | `flutter3d_cpu` | 0.2.0 |
| backend-matrix | What differs between them | every `GraphicsDevice.supports*`, live for the running device | n/a |

## Set G: formats and I/O (`lib/pages/formats/`)

| id | title | main API | since |
|---|---|---|---|
| gltf-load | glTF and GLB | `GltfLoader` and the extensions it reads | F3D 0.1.0 |
| gltf-cameras-lights | Cameras and lights from a file | `ModelCamera`, `ModelLight` | 0.7.0 |
| gltf-write | Writing GLB | `GltfWriter`, `compressGeometry` | 0.7.0 |
| export-validate | Export, read back, compare | `exportChecked`, `compareModelDocuments`, `validateGltfExport` | 0.7.0 |
| obj | OBJ and MTL | `ObjLoader`, `ObjWriter`, `ObjNormals` | F3D 0.1.0 |
| stl | STL | `StlLoader`, `StlWriter` | 0.7.0 |
| usdz | USDZ export | `UsdzWriter` (geometry only) | 0.7.0 |
| f3d | The `.f3d` container | `F3dDecoder`, `F3dWriter` | F3D 0.1.0 |
| ktx2 | KTX2 and Basis textures | `Ktx2`, `basis_universal` (UASTC, ETC1S) | F3D 0.4.2; UASTC 0.7.0 |
| texture-compression | Compressing a texture | `encodeBc1/Bc3/Etc2Rgb8`, ASTC 4x4, `buildMipChain`, `writeKtx2` | 0.7.0 |
| draco | Draco meshes | `decodeDraco` | 0.7.0 |
| meshopt | Meshopt compression | `meshopt_vertex_codec.dart`, `compressGeometry` | 0.7.0 |
| fbx-refusal | An FBX, refused with a reason | `FbxDecoder` | 0.7.0 |
| image-decode | PNG, JPEG and HDR without `dart:ui` | `PngDecoder`, `JpegDecoder`, `readHdr` | 0.7.0 |
| custom-decoder | A decoder of your own | `ModelDecoder`, `ModelLoadRequest(decoders:)` | unknown |
| model-asset | Loading into a scene | `ModelAsset.fromDocument`, `loadModelAsset`, `ModelInstance` | unknown |
| texture-transform | Texture transform | `withTextureTransform` | unknown |
| build-convert | The build-time converter | `flutter3d_build` (a command line tool: a docs page, not a live demo) | 0.7.0 |

## Set H: physics and particles (`lib/pages/physics_particles/`)

| id | title | main API | since |
|---|---|---|---|
| particle-pool | A particle pool in one draw call | `ParticleSystem`, `ParticleEffect`, seeded `ParticleRandom` (fold) | CL particles 0.2.0 |
| particle-emitters | Emitter shapes | `SphereEmitter`, `ConeEmitter`, `BoxEmitter`, `DriftEmitter` | 0.2.0 |
| particle-modifiers | Forces | `ParticleGravity`, `Drag`, `Wind`, `Turbulence`, `Spin` | 0.2.0 |
| particle-curves | Over-life curves | `ParticleCurve`, `ParticleGradient`, `KeyEase` | 0.5.0 |
| particle-lights | Particles that light | `LightEmitter`, `ParticleGlow` | 0.2.0 |
| burst-light | A burst that lights the room | `ParticleSystem.burst(source:)` | 0.7.0 |
| textured-particles | Textured billboards | `ParticleContributor` | 0.2.0 |
| flipbook | Sprite-sheet animation | `Flipbook`, `FlipbookCell` | unknown |
| mesh-particles | Mesh particles | `MeshParticleContributor` | 0.2.0 |
| collision-shapes | Collision shapes | sealed `CollisionShape` (box, sphere, capsule, wedge, heightfield) | CL physics 0.5.1, 0.6.0 |
| collision-queries | Raycast, sweep and overlap | `CollisionWorld`, `SpatialGrid` | 0.5.0 |
| collision-layers | Layers and contact callbacks | `Layers`, `Collider`, `CollisionListener` | unknown |
| character-controller | A character controller | `CharacterController`, `MovementTuning` | 0.5.0 |
| rigid-bodies | Rigid bodies | `RigidBody`, `Dynamics`, snapshot (fold) | unknown |
| heightfield-collision | Walking on terrain | `CollisionHeightfield` | 0.5.1 |
| xpbd-cloth | Cloth | `ClothMesh.grid`, `stepCloth`, `ClothObstacle`, `WindSettings` | 0.7.0 |

## Set I: simulation, audio, XR, widgets and the rest (`lib/pages/sim_audio_xr/`, `lib/pages/widgets_misc/`)

| id | title | main API | since |
|---|---|---|---|
| fixed-step | Fixed step and interpolation | `FixedStep`, `GameLoop`, `Interpolated*`, `PauseGate` | unknown |
| ecs-world | The ECS world | `EcsWorld`, `remapEntitySave` | remap 0.7.0 |
| step-systems | Systems and events | `StepSystems`, `GameEvents` | 0.5.0 |
| replay-digest | Replays and digests | `Demo`, `Recorder`, `Playback`, `StateDigest`, `Divergence` | 0.7.0 |
| portable-math | Portable determinism | `Portable`, `GameRandom` | 0.5.1 |
| rewind | Rewinding | `RewindBuffer`, `Snapshot`, `StepTimeTrace` | 0.7.0 |
| headless-run | Running without a screen | `HeadlessGame`, `HeadlessRun` (library only; the `bin/` tool is native) | 0.7.0 |
| nav-grid | Path-finding | `NavGrid`, `JumpLink` | 0.4.1 |
| flow-field | A flow field | `FlowField` | unknown |
| automap | An automap | `Automap` | unknown |
| lightmap-bake | Baking a lightmap | `LightmapLayout`, `LightmapBaker`, `Breaches` | 0.4.1, 0.4.2 |
| baked-visibility | Baked visibility | `LevelVisibility`, `VisibilityCuller` | unknown |
| terrain-tiles | Terrain in tiles | `Heightfield`, `HeightfieldTiles`, `TerrainTiles` | 0.5.2, 0.7.0 |
| level-format | The level format | `Level`, `Brush`, `LevelValidator` | 0.4.2 |
| level-mechanisms | Doors, lifts and buttons | `Door`, `Lift`, `Button`, `TriggerVolume` | unknown |
| light-fixtures | Flickering lights | `LightFixture`, `FlameFlicker`, `PulseLight` | unknown |
| actors | Actors, brains and health | `Actor`, `Brain`, `Health` | unknown |
| camera-shake | The shared camera rig | `CameraRig`, `RigTuning` (the file must not be named `camera`) | unknown |
| splines | A Catmull-Rom path | `CatmullRom` | unknown |
| difficulty | Difficulty axes | `Difficulty` | 0.5.0 |
| pendulum-lab | The virtual pendulum lab | `flutter3d_lab` `PendulumSimulation`, `divergenceFrom` | 0.7.0 |
| positional-audio | Positional audio | `AudioScene`, `SoundEmitter`, `AudioListener` (web needs the script tags and COOP/COEP) | 0.1.0 |
| audio-rolloff | Distance rolloff | `InverseRolloff`, `LinearRolloff`, `ExponentialRolloff` | 0.1.0 |
| audio-buses | Mixer buses | `AudioBus`, `Mixer` | 0.2.0 |
| voice-limit | Voice limiting | `AudioScene(maxVoices:)` | 0.1.0 |
| audio-occlusion | Occlusion | `AudioScene.occlusion` | unknown |
| blended-engine-loop | A blended engine loop | `LoopBand`, `BlendedLoop` | unknown |
| stereo-rig | The stereo rig | `StereoRig`, `Eye`, `StereoSurface` | stereo 0.1.0 (published at 0.7.0) |
| viewer-profiles | Cardboard viewer profiles | `StereoViewer` | stereo 0.1.0 |
| stereo-lesson | A lesson through the rig | `LessonPlayer`, `LessonStereoView` | 0.7.0 |
| head-tracking | Head tracking (a mouse-driven pose on the web) | `HeadTracker`, `SensorHeadTracker` (native plugin) | stereo 0.1.0 |
| widget-surface | Widgets in the scene | `WidgetSurface`, `WidgetTexture` | 0.7.0 |
| scene-semantics | Describing the scene to a screen reader | `SceneSemantics` | 0.7.0 |
| scene-surface | The scene surface and its status screens | `SceneSurface`, `presentFrame`, `DidNotStart` | 0.7.0 |
| level-loader | Loading a level | `LevelLoader`, `SharedMeshes` | 0.7.0 |
| storage | Storage on every platform | `Storage`, `BinaryStorage`, `IndexedDbBinaryStorage` | 0.7.0 |
| diagnostics | Frame timing and memory pressure | `FrameClock`, `FrameTimingLog`, `MemoryPressureRelease` | 0.7.0 |
| game-settings | Settings, config and saves | `SettingsPanel`, `GameConfig`, `SaveFile` | unknown |
| run-timeline | Pausing and stepping a running game | `RunTimeline`, `RunSession` | 0.7.0 |
| accommodations | Reduce motion | `Accommodations.reduceMotion` | unknown |
| rollback-netcode | Rollback netcode over a loopback | `flutter3d_net` `NetSession`, `LoopbackTransport` (delay and loss sliders) | unknown |

`flutter3d_net_webrtc` has no page (a native plugin and a signalling relay); it is named
on the netcode page.

## The 0.7.0 audit

To be filled in before set work starts: every `## 0.7.0` entry of the CHANGELOGs of
`flutter3d`, `flutter3d_shaders`, `flutter3d_particles`, `flutter3d_physics`,
`flutter3d_sim`, `flutter3d_stereo`, `flutter3d_webgpu`, `flutter3d_app`, each with the
id of the page that shows it or the reason no page can (for example, "an internal
optimisation"). `test/coverage_test.dart` fails on an entry with neither.
