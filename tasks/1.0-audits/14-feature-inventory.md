# Инвентаризация возможностей flutter3d (ветка 1.0.0, rc.1, по состоянию на 2026-10-09)

Заметки агента. Источники: `site/content/reference/comparison.md` (**cmp**), каталог витрины `apps/flutter3d_showcase/lib/catalog/*.dart` (**SC**, у каждой записи поле `since`), `ARCHITECTURE.md` (**ARCH §N**), `site/content/reference/packages.md` (**PKG**), `material-language.md` (**ML**), `SUPPORT.md`, `packages/flutter3d_core/lib/src/engine/render/render_settings.dart` (**RS**), CHANGELOG 1.0.0-rc.1 пакетов, grep по `packages/*/lib`. Статусы: **да** / **частично** / **нет** / **не проверено**. ARCH §15 «Limits» местами устарел (там ещё «нет joints», «нет hot reload»); где он противоречит cmp/SC/CHANGELOG, верил более новому источнику.

## 1. Рендеринг: материалы и текстуры

| Возможность | Статус | Где |
|---|---|---|
| PBR metal-rough (GGX), normal/ORM/emissive, alpha mask | да | ARCH §6.2; SC shading «PBR metal and rough» 0.1.0 |
| Spec-gloss (KHR_materials_pbrSpecularGlossiness) | нет | grep `specularGlossiness` по core: 0 |
| Clearcoat, sheen, anisotropy, transmission/refraction, volume/thickness, IOR, specular, dispersion, iridescence | да | `MaterialExtensions` + `LightingModel.pbrLayered`, ARCH §6.4; SC shading 0.8.0. Не рисуются (только экспорт): текстуры specular, coat normal, anisotropy, iridescence |
| Subsurface, hair, cloth shading | нет | grep по core: 0 (есть только физическая ткань) |
| Toon, unlit, Lambert, Blinn-Phong, Normals | да | 6 lighting models, ARCH §6.1 |
| Vertex colours | да | ARCH §6.2; `MeshBuilder.addVertex(color:)` |
| Texture transform (KHR_texture_transform, per-map) | да | ARCH §6.4; SC formats «Texture transform» 0.7.0 |
| Свой материал / язык материалов `.f3dmat` v2 (surface/light/ambient/composite/vertex hooks, fullscreen stage, compute kernel только на CPU) | да | ML; SC shading «A material of your own» 1.0.0-rc.1 |
| Runtime-компиляция шейдеров | частично | `RuntimeShaders` только для WebGL2/WebGPU/CPU; Impeller — только из бандла (ML таблица, ARCH §15) |
| Energy compensation, EON diffuse | да | RS `energyCompensation`, `DiffuseModel.eon` (ARCH §6.4) |
| Triplanar, detail textures | нет | только UV-проекция в модельере `flutter3d_mesh/uv_project.dart` |
| KTX2/Basis (ETC1S), BC/ETC2/ASTC blocks | да | ARCH §15; отказ: UASTC, Zstd/zlib supercompression, arrays, cube maps, 3D |
| PNG/JPEG | да | `dart:ui` + чистый Dart `formats/image/png_decoder.dart`, `jpeg_decoder.dart` (SC formats «Image decoding without dart:ui» 0.7.0) |
| HDR (Radiance) | да | `formats/image/hdr_decoder.dart`, `EnvironmentMap.fromPanorama` |
| EXR | нет | grep: 0 |
| Процедурные текстуры | да | `ProceduralTexture`, `CheckerboardTexture` (SC scene 0.5.0) |
| Видеотекстуры | нет | grep `VideoTexture|video_player`: 0 |

## 2. Освещение, тени, GI, атмосфера

| Возможность | Статус | Где |
|---|---|---|
| Directional / point / spot | да | ARCH §6.3 |
| Rect area lights (LTC) | да | ARCH §6.3; SC shading 0.7.0 |
| Физические единицы (lux, cd, nits), физическая камера (aperture/shutter/ISO) | да | ARCH §6.3, `PhysicalCamera`; SC «Lights in lumens and lux» |
| Light channels | да | `LightChannels`, SC shading 0.7.0 |
| Clustered lights (32+, light list texture) | да | ARCH §4.9; SC environment 0.8.0 |
| Light cookies, IES-профили | нет | grep: 0 |
| Cubemaps, IBL (prefiltered chain), панорама | да | `EnvironmentMap.prefilter/fromPanorama`, SC environment «IBL» 0.3.0 |
| Spherical harmonics | нет | только band-0 SH у сплатов (`splatShC0`) |
| Каскадные тени, кэш статики, soft (PCF/PCSS), EVSM, contact shadows | да | `ShadowTechnique.pcf/pcss/evsm`, SC shadows; cmp |
| Point/spot cube shadows (атлас) | да | SC shadows «Point and spot shadows» 0.2.0 |
| Translucent casters, caustics | да | `ShadowSettings.translucentCasters`, `caustics`; cmp «Caustics under glass and water» |
| Тени от alpha-mask листвы | да | SC shadows «Shadows of cut-out leaves» 0.7.0 |
| Дистанция теней | частично | ограничена `ShadowSettings.viewDistance` (60 м по умолчанию), ARCH §15 |
| Lightmaps (бейк) | да | `flutter3d_sim` `Lightmap`, `bake_lightmap`; SC 0.4.2 |
| Irradiance field (DDGI-подобный, с visibility, GPU-обновление) | да | ARCH §6.3; SC environment 0.7.0/0.8.0 |
| Reflection probes (prefilter на устройстве) | да | `ReflectionProbeNode`; SC 0.4.3 |
| SSR | да | `ReflectionSettings`, SC post 0.2.0 |
| SSAO / GTAO / SSIL | да | `AmbientOcclusionMethod.ssao/gtao/ssil` (RS) |
| Planar reflections (зеркала) | да | `PlanarReflectorNode`, `mirror_view.dart`; SC environment 1.0.0-rc.1 |
| Volumetric fog, distance fog, height fog, light shafts | да | `VolumetricFogSettings`, `FogSettings`, `LightShaftSettings`; cmp |
| Физическое небо (с озоном), процедурное небо, HDRI, суточный цикл | да | `PhysicalSky`, `SkyDome/SkyGradient`, `Atmosphere/AtmosphereCycle`; CHANGELOG core rc.1 |
| Процедурные облака | нет | grep `CloudLayer`: 0 (в demo_water только staging) |
| Вода / жидкости (рендер) | да | `flutter3d_effects` `LiquidView`, `WaterBody`, `SeabedLook`; `apps/flutter3d_demo_water`, `_reef` |
| Океан (Gerstner/FFT) | нет | grep: 0 |
| Terrain (heightfield, tiles, erosion) | частично | `Heightfield`, `HeightfieldTiles`, `VoxelTerrain`, эрозия (SC sim «Terrain in tiles» 0.7.0, «Terrain erosion» rc.1); clipmaps нет |
| Растительность/ветер/трава | частично | ветер только через vertex-блок материала (пример Kelp в ML) и физику; системы травы нет |
| Decals (projected) | да | `DecalNode`, `renderer_decal_pass.dart`; SC scene rc.1 |

## 3. Рендеринг: геометрия, видимость, прозрачность, пост

| Возможность | Статус | Где |
|---|---|---|
| Instancing (per-instance morph weights) | да | `InstancedMeshNode`; SC scene 0.2.0 |
| Batching одинаковых draw, per-material level batching | да | SC shading «Identical-draw batching»; `LevelBatching` |
| GPU-driven (compute culling, indirect) | нет | ARCH §15: нет compute на Impeller/WebGL2 |
| Impostors (octahedral) | да | `ImpostorNode`; cmp |
| LOD + cross-fade | да | `LodGroup.crossFade`, `MeshNode.lodFade`; `MSFT_lod` |
| HLOD | нет | только упоминание в экспорте модельера |
| Frustum culling (BVH), occlusion (Hi-Z), PVS для уровней | да | SC scene 0.7.0/0.8.0, ARCH §4.6–4.7 (occlusion выключен по умолчанию) |
| Сортировка прозрачности, OIT (weighted blended), alpha hashed, alpha-to-coverage | да | `TransparencyMode.sorted/weightedBlended`, ML `blend hashed`, SC scene rc.1 |
| Dithered LOD fade | да | см. LOD cross-fade |
| Reversed-Z, depth layers | да | ML `depthLayer`; cmp |
| Bloom/halation | да | `BloomSettings`; SC post 0.1.0 |
| Tonemapping: neutral, ACES, ACES2, AgX, AgX full, Reinhard | да | RS `TonemapCurve` |
| Colour grading, `.cube` LUT | да | `ColorGradeAddon`, `cube_lut.dart`; SC post |
| Auto exposure, local exposure, manual | да | `auto_exposure.dart`, `LocalExposureSettings` |
| DoF, motion blur | да | `DepthOfFieldSettings`, `MotionBlurSettings` |
| MSAA / FXAA / SMAA (1x) / TAA | да | `AntiAliasSettings`, `EdgeSmoothing.fxaa/smaa`, `TemporalSettings`; MSAA отключается при surface buffer (ARCH §15) |
| Upscaling | частично | `SpatialUpscaleSettings` — свой 12-tap edge-adaptive фильтр + TAAU через temporal; FSR/DLSS нет |
| Sharpen | да | SC post «FXAA, SMAA and sharpen» |
| Vignette, film grain | да | `VignetteAndGrainAddon` (`flutter3d_post`) |
| Chromatic aberration, lens distortion, lens flare | да | RS `LensFlareSettings.chromaticAberration`, `LensDistortionAddon`, `LensFlareAddon` |
| Outline / x-ray / viewport shading (normals, clay, outline, curvature) | да | `OutlinesAddon`, `XraySettings`, `ViewportShading`; SC post |
| High contrast, colour-vision simulation/correction | да | `HighContrastSettings`, `color_vision.dart`; cmp |
| Adaptive quality / resolution | да | `adaptive_quality.dart`, SC post 0.7.0 |
| Debug views, render stats по проходам | да | `DebugView`, `FramePass`; SC post rc.1 |
| Частицы: CPU-пул в один draw, soft, lit (glow + освещение сценой), flipbook, mesh-частицы, six-way lighting | да | `flutter3d_particles`: `SixWaySheet`, `MeshParticleContributor`, `ParticleGlow`; SC physics_particles |
| GPU-частицы, ribbons/trails | нет | ARCH §15 (нет compute); grep `Ribbon`: 0 (есть `NativeParticles`/`GpuParticles` в физическом ядре — симуляция, не рендер-система) |
| Gaussian splats (PLY, SPZ, paged `.f3dsplat`, GPU sort на WebGPU, octree/LOD) | да | `formats/splat/*`, `splat_sort_gpu.dart`; ARCH §4.12 |
| Воксели | да | `flutter3d_voxel` (`VoxelWorld`, `VoxelTerrain`, `VoxelNavigation`); `apps/flutter3d_demo_sandbox` |
| Линии в пикселях, wireframe, debug draw, gizmos | да | `LineStripNode`, `debug_draw.dart`, `debug_draw_gizmos.dart`, SC shading «Wireframe» (нет на WebGPU/WebGL2) |
| Текст в 3D | частично | только через `WidgetSurface` (Flutter-виджет на quad), SDF/mesh-текста нет |
| Billboards, спрайты | частично | billboard-частицы; отдельного `BillboardNode`/`SpriteNode` нет |
| UI в мире (widget surfaces) | да | `WidgetSurface`, SC widgets_misc 0.7.0 |
| Picking: id-buffer и ray | да | `renderer_pick_pass.dart`, `Raycaster` (ray бьёт bind-pose, ARCH §15) |
| Render target / camera-to-texture / экраны в уровне | да | `RenderView`, `_RenderTextureNode`, `CameraScreenKind`; SC scene «A camera into a texture» rc.1 |
| Порталы | нет | только упоминание как применение camera-to-texture |
| Stereo (side-by-side, Cardboard-профили, head tracking Android) | да | `flutter3d_stereo`; без коррекции линз и XR runtime (PKG) |
| VR/AR runtime, ARKit/ARCore | нет | grep: 0 |
| Несколько видов / split screen | да | `RenderView`, SC scene «Several views in one frame» 0.7.0 |
| HDR output | частично | `OutputTransform.extendedSrgb` только WebGPU (cmp) |
| Wide gamut / colour management | нет | только sRGB/linear (`srgb.dart`) |
| Floating origin / большие координаты | да | `WorldPosition`, `moveOriginTo` (foundation) |

## 4. Сцена и анимация

| Возможность | Статус | Где |
|---|---|---|
| Scene graph, flat registries, versions | да | ARCH §5 |
| Декларативный виджет-API (`Scene3D`, `Node3D`, `Mesh3D`, `Model3D`, `Light3D`, `Decal3D`, `Mirror3D`, `ReflectionProbe3D`, `Particles3D`) | да | `flutter3d_app`; SC «A scene written as widgets» rc.1 |
| Prefabs | да | `flutter3d_sim/lib/src/level/prefab.dart` (на уровне документа уровня) |
| Слои/маски | да | `LightChannels`, physics `Layers`, `AnimationMask` |
| Skeletal animation, clips, crossfade, step/linear/cubic | да | SC animation 0.1.0/0.7.0 |
| Morph targets (GPU, per-instance) | да | ARCH §15 |
| Animation graph: state machine, blend space, layers, параметры, JSON | да | `AnimationGraph`, `AnimationStateMachine`, `AnimationBlendSpace`; SC rc.1 |
| Additive layers, root motion | да | SC animation 0.7.0 |
| IK: two-bone, FABRIK, foot plant, look/reach goals | да | `TwoBoneIk`, `FabrikIk`, `FootPlantGoal`, `LookGoal`, `ReachGoal` (`engine/animation`) |
| Retargeting | да | cmp; `flutter3d_model_core/rig/retarget.dart` |
| Animation events/markers | да | `AnimationMarkerPassed` (`flutter3d_game`) |
| Timeline/sequencer | частично | таймлайн в модельере (`timeline_panel.dart`); в рантайме — `Cutscene` в fixed step |
| Cutscenes | да | `CutsceneKind`, SC sim rc.1 |
| Virtual cameras / rigs (orbit, chase, follow, first-person, overhead, group, look-at, impulses/shake, director blends) | да | `flutter3d_camera` (`VirtualCamera`, `CameraDirector`, `CameraBlend`) |
| Procedural animation | частично | через IK goals; отдельной системы нет |
| Ragdoll | да | `NativeRagdoll`, `SkeletonRagdoll` (`flutter3d_game_physics`) |
| Cloth | да | `ClothSimulation` (Dart), `NativeCloth`, `GpuCloth` |
| Hair | нет | grep: 0 |
| Crowd из запечённого клипа | да | SC animation «A crowd from a baked clip» 0.7.0 |

## 5. Физика и симуляция

| Возможность | Статус | Где |
|---|---|---|
| Формы (Dart): box, sphere, capsule, wedge, heightfield, `CustomShape` (GJK support) | да | ARCH §10, `flutter3d_physics` |
| Формы (native C core): point, sphere, box, capsule, cylinder, cone, hull, mesh, compound | да | `physics_native/core/constants.dart` `ShapeKind`; SC «Convex shapes and mesh floors», «Several shapes on one body» rc.1 |
| Rigid bodies с вращением | частично | в C-ядре да; Dart-fallback без вращения (ARCH §10, cmp) |
| Joints: fixed, spherical, revolute, prismatic, distance; моторы, лимиты, ломающиеся; multibody | да | `JointType`, `NativeMultibody`, `NativeSpring.isBroken`; SC rc.1 |
| Character controller (capsule, kinematic, coyote time) | да | ARCH §10; `NativeCharacterMover` |
| Vehicles | да | `NativeWheelSettings` (SC «A car on four springs»), `SphereVehicle`/`TireModel` в racing |
| Soft bodies | нет | только cloth |
| Fluids: частицы (CPU/GPU), shallow water, жидкости в сосудах/трубах | да | `ParticleFluid`, `NativeFluid`, `GpuFluid`, `NativeShallowLiquid`, `LiquidBody`, `Pipe` |
| Плавучесть, ветер, тепло/огонь, взрывы/обломки | да | `FloatingBody`, `WindSettings`, `NativeFire`/`NativeBurner`, `NativeExplosion`/`NativeDebris`; `flutter3d_elements` |
| Разрушение уровня | да | `Breaches` (sim), `BurningWrecks`, ломающиеся joints |
| Raycast/sweep/overlap, CCD | да | SC physics 0.5.0, «Fast bodies and thin walls» rc.1 |
| Детерминизм, `Portable`, lints | да | ARCH §9.3, `flutter3d_lints` |
| Rollback, replays (`.f3drun`, digests), rewind/time-travel | да | `flutter3d_net`, `Demo`, `RewindBuffer`, `RunTimeline` |
| Navmesh (rebake), nav grid, flow fields, crowds, jump links | да | `NavMesh`, `NavGrid`, SC sim rc.1 |
| Behaviour trees (в редакторе и по MCP) | да | `BehaviorTree`, `tree_brain.dart` |
| Триггеры/объёмы | да | `TriggerVolume`, `TriggerKind` |
| Симуляция в изоляте | да | `IsolateSimulation` (CHANGELOG sim rc.1) |
| Многопоточность шага | нет | ARCH §15 |
| Сторонний движок (Rapier/Jolt) | нет | cmp |
| Генерация уровней (WFC, эрозия) | да | `WfcTile`, SC «Levels from a seed» rc.1 |

## 6. Ассеты и форматы

| Возможность | Статус | Где |
|---|---|---|
| glTF/GLB чтение и запись | да | `formats/gltf`; SC formats |
| glTF-расширения: draco, meshopt, texture_transform, texture_basisu, lights_punctual, materials_variants, animation_pointer, mesh_quantization, emissive_strength, unlit, ior/specular/clearcoat/sheen/anisotropy/transmission/volume/dispersion/iridescence, MSFT_lod, MSFT_screencoverage, KHR_gaussian_splatting | да | grep `KHR_` по core (список выше); pbrSpecularGlossiness — нет |
| OBJ/MTL, STL | да | `formats/obj`, `formats/stl` |
| PLY | частично | mesh-PLY через конвертер `flutter3d_build` и splat-PLY; point-cloud PLY отвергается |
| FBX | нет | `fbx_decoder.dart` отказывает с причиной (PKG) |
| USD/USDZ | частично | USDZ-запись (`UsdzWriter`); чтение `.usda` только в конвертере `flutter3d_build/convert/usd_input.dart` |
| MaterialX | частично | вход конвертера `materialx_input.dart` (не рантайм) |
| Unity / Godot сцены | частично | конвертер `unity_yaml.dart`, `godot_input.dart` (`flutter3d convert`) |
| `.f3d`, `.fmat`, `.f3dmat`, level JSON v4, `.f3drun`, `.f3dsplat`, `.f3dplugin` | да | ARCH §8, PKG |
| Пайплайн текстур (BC1/BC3/ETC2 → KTX2) | да | `flutter3d_build:convert --textures` (ARCH §15); EAC-alpha не кодируется |
| Mesh compression | частично | декодирование Draco/meshopt; энкодеров нет; vertex cache ordering есть |
| Build hook (`flutter3d_assets.yaml`, hash-кэш) | да | `flutter3d_build`, `flutter3d_build_hooks` |
| Streaming/chunks | частично | только paged splats и `ChunkStreamer` в Flame-мосте; общего стриминга нет (ARCH §15) |
| Hot reload шейдеров, моделей, текстур, окружений, уровней | да | `hot_swap.dart` (`ext.flutter3d.assets.swap`), `shader_watch.dart`; cmp |
| Asset bundles / content packs / addressables | нет | только `.f3dshaders`-бандл и data-плагины |
| Per-device-class ассеты | да | ARCH §8.8 |

## 7. Аудио

| Возможность | Статус | Где |
|---|---|---|
| Позиционное (attenuation linear/inverse/exponential, panning) | да | `flutter3d_audio_core` `Attenuation`, `EqualPowerPanner` |
| Occlusion (через collision world, gain + low-pass) | да | `SoundOcclusion`, ARCH §11.2 |
| Reverb-зоны | частично | `ReverbEffect` объявлен в модели, но «fake with gain/pan» — бекенда с реверб-рендером нет (`bus_effect.dart`) |
| HRTF | нет | `spatial.dart`: только упоминание как будущего бекенда |
| Doppler | частично | `dopplerFactor` «wired and off» (`spatial.dart:112`) |
| Mixer/buses/snapshots/ducking | да | `Mixer`, `AudioBus`, `MixSnapshot`, `DuckRule` |
| Слои музыки | да | `BlendedLoop`, `LoopBand`, `SoundtrackPlugin`, `CueSheet` |
| Streaming | не проверено | `SoLoudBackend` грузит через `loadMem`; ARCH §11.2 говорит «streaming music» |
| Форматы | не проверено | определяются SoLoud (wav/ogg/mp3/flac по документации SoLoud); в коде расширения не перечислены |
| Бекенды | да | `SoLoudBackend`, `SilentBackend`; FMOD нет |

## 8. Ввод, UI, игровые сервисы

| Возможность | Статус | Где |
|---|---|---|
| Клавиатура/мышь/тач/геймпад | да | `flutter3d_game` `ActionMap`, `PadInput`, `TouchControls` |
| Action maps, ребиндинг с экраном настроек, сохранение | да | ARCH §11.1; `ActionBindingsSection` |
| Pointer lock | частично | macOS и web; Windows/Linux нет (PKG) — [уточнение другого аудита: 0.5.0 добавил Windows и Linux, PKG устарел] |
| Геймпад: платформы | частично | web, Android, macOS, iOS; Windows/Linux нет; rumble отсутствует намеренно (`pad_input.dart:37`) — [то же уточнение] |
| Haptics | частично | `Haptic` через Flutter `HapticFeedback` (телефон), не геймпад |
| UI kit: HUD, minimap/automap, touch-раскладки, меню (title/credits/ending/loss), settings panel | да | `flutter3d_game_ui` |
| Локализация | частично | `Flutter3dGameLocalizations`: en, ru |
| Accessibility: screen reader, colour vision, high contrast + role rings, reduce motion, spoken events | да | `access/*.dart`, `Accommodations`; cmp |
| Text scale | не проверено | есть только тесты HUD на textScale |
| Save slots, миграции схем, autosave | да | `SaveSlots`, `SaveSchema/SaveUpgrade`, `Autosave`; SC «Saves that survive an update» |
| Cloud saves | да | `CloudSaveStore`, `HttpCloudSaves`, `PlatformCloudSaves`, `SaveSync` |
| Achievements / leaderboards | частично | `BestRun`, `RunService`/`ShareBundle` (шаринг забегов и призраков); сервисов платформ нет |
| Telemetry (с согласием) | да | `TelemetryUploader`, `Consents`, `PrivacySection`; `Heatmap` плейтестов |
| Photo mode, capture | да | `photo_mode/`, `PhotoCamera`, `photo_capture.dart` |
| Replays/ghosts | да | `Ghost`, `GhostRecorder` (racing), `Demo` |
| Spectator | да | `PartyTapeWatcher`, cmp |
| Networking: rollback 2–32, authoritative server + predicting client, relay (`bin/relay.dart`), WebSocket, WebRTC, dashwire, turn-based `BatonStream` | да | `flutter3d_net`, `flame_multiplayer*` |
| Lockstep как режим | частично | rollback с input delay; отдельного lockstep нет |
| Matchmaking | частично | party join через relay; сервиса подбора нет |
| Voice chat | нет | grep: 0 |

## 9. Инструменты

| Возможность | Статус | Где |
|---|---|---|
| Level editor (desktop + web), Play из редактора (`flutter run --machine`) | да | `apps/flutter3d_editor`, `flutter3d_editor_play` |
| Model editor (object/mesh/material/UV/sculpt/retopo/paint/sim/animation/render) | да | `apps/flutter3d_modeler`, models.pleion.dev |
| Material editor (граф) | частично | панели материалов в редакторах; узлового графа нет (ARCH §15) |
| MCP-серверы: editor (18 tools), model (147), project, sim (играть вслепую), diagnostic, plugin | да | `flutter3d_mcp`, `flutter3d_sim_mcp`, `flutter3d_build:plugin_mcp` |
| CLI `flutter3d`: convert, doctor, create, init, plugins, migrate, lights | да | `flutter3d_build/bin/flutter3d.dart` |
| Профайлер | частично | CPU-время по проходам, `Timeline`-спаны, VM-extensions (`frameTimes`, `bugReport`), memory report; GPU-таймстемпы только WebGPU (ARCH §15) |
| Frame capture / draw journal / inspect running frame | да | `frame_capture.dart`, `draw_journal.dart`; SC rc.1 |
| Hot reload | да | см. §6 |
| Тесты: software goldens (96 сцен, tolerance 0), conformance (41/44 checks), replay-тесты, 13 267 тестов | да | `flutter3d_testing`, `flutter3d_conformance`, README «13267 tests» |
| Шаблоны проектов | да | 4 игровых шаблона + `flutter3d_build:create`, два seed-примера (PKG) |
| Плагины (`.f3dplugin`, Wasm ABI 1, script runtime) | да | `flutter3d_plugin_api/runtime` |
| Документация | да | витрина: 119 страниц с guide + source (238 файлов), туториалы для 4 жанров + модельер, `site/content/core/*` 14 разделов |
| Редактор как скачиваемый бинарник | нет | cmp |
| Поиск z-fighting | нет | cmp (только level validator) |

## 10. Платформы

| Возможность | Статус | Где |
|---|---|---|
| macOS (Metal) | да (Supported) | SUPPORT.md |
| iOS (Metal) | частично (Best effort, симулятор; iOS 15+) | SUPPORT.md; `IPHONEOS_DEPLOYMENT_TARGET = 15.0` |
| Android (Vulkan) | да (Supported, Galaxy A55); GLES best effort | SUPPORT.md |
| Windows | частично (Best effort, CI-сборки, никто не играл) | SUPPORT.md |
| Linux | частично (все тесты в CI, Impeller не рисует → CPU backend) | SUPPORT.md |
| Web: WebGPU (default) → WebGL2 fallback, wasm | да | SUPPORT.md, PKG |
| Консоли | нет | — |
| Минимумы | — | Dart ≥3.12, Flutter ≥3.44 (`flutter3d/pubspec.yaml`) |
| Impeller обязателен? | нет | runtime-fallback на `flutter3d_cpu` |
| Headless / server rendering | да | `flutter3d_cpu`, `headless_run`, `SimMcpServer`, `IsolateSimulation` |

## 11. Неигровые приложения

| Возможность | Статус | Где |
|---|---|---|
| Section/clip planes | частично | `edu_clip_plane` есть в формате урока и редакторе (`lesson_authoring.dart`), но viewer их не рисует (`lesson_viewer/main.dart:16`); рендер-клиппинг только oblique near plane зеркал |
| Измерения, dimension lines | нет | в модельере `MeasurementRuns` — метрики производительности, не линейка |
| Exploded views | нет | grep: только физические взрывы |
| Selection outlines | да | `OutlinesAddon`, `OutlineMarks`, `ViewportShading.outline` |
| Ортокамера через все эффекты, off-axis, tiled render | да | SC view_input |
| Аннотации/ярлыки | частично | `edu_annotation` через `WidgetSurface` (lesson viewer рисует) |
| Слои/видимость | частично | `visible/hidden` в шагах урока; `LightChannels`; общего слоя видимости объектов нет |
| Large model streaming/LOD | частично | LOD/impostors/occlusion есть; стриминга нет |
| Bounding boxes / fit-to-view | да | `OrbitController.frameBounds`, SC «Screen-space bounds» |
| Camera presets/bookmarks | частично | шаги урока (`at`/`yaw`), пресеты жанров в `flutter3d_camera`; закладок пользователя нет |
| Screenshots/export | да | `savePhoto`, PNG writer, GLB/USDZ export, `Export, read back, compare` |
| Material variants (KHR_materials_variants) | да | SC formats 0.8.0 |
| Turntable | да | `OrbitCubit` (lesson viewer), ортографический turntable-рендер в `render_snapshot.dart` |
| Environment presets | частично | `SkyLook`, физическое небо, панорамы; именованных пресетов-библиотеки нет |
| AR Quick Look | частично | USDZ-экспорт есть; запуск AR нет |
| Инстансированные глифы | да | `InstancedMeshNode` (50k юнитов в стратегии) |
| Heatmaps | частично | `Heatmap` плейтестов (sim), не общая визуализация данных |
| 3D-графики | нет | — |
| Point clouds | частично | только как сплаты; PLY-облака отвергаются |
| GIS: 3D Tiles/Cesium, гео-привязка, DEM | нет | grep: 0; heightfield из любого `Float32List` — частично для DEM |
| Большие координаты | да | `WorldPosition`, floating origin |
| Volume rendering, isosurfaces, slices | нет | grep: 0 |
| Digital twin: привязка телеметрии к шагу | да | `EduDataSource` (`sim/level/data_source.dart`), адаптеры MQTT/WebSocket пишутся снаружи |
| Time scrubbing / history | да | `DataSourceTrace`, `RunTimeline`, `apps/flutter3d_lab_incident` |
| Alarms / annotations в twin | не проверено | — |
| Multi-user viewing | нет | ARCH §15 (один процесс, один документ) |
| Education: уроки (шаги, камера, show/hide, аннотации), стерео-плеер | да | `apps/flutter3d_lesson_viewer`, `LessonPlayer` |
| Вопросы/оценка в уроке | частично | `check` в формате, viewer не задаёт (`lesson_player.dart:18`) |
| Лаборатории (маятник, химия, incident) с divergence-проверкой | да | `flutter3d_education/lab.dart`, `PendulumLabRun`, `Bench` |
| Probes/графики | нет | grep по education: 0 |
| LTI 1.3 + AGS + xAPI | да | `flutter3d_education/lti.dart`, `cloud/lti/server` |
