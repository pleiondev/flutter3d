# Инвентарь публичной поверхности flutter3d (ветка `1.0.0`, снимки `packages/*/api/*.api`, 2026-10-09)

Заметки агента. Источники: api-снимки, барреллы, `docs/CONTRACTS.md`, `ARCHITECTURE.md`, `site/content/quickstart.md`, `site/content/reference/*.md`. Все пути относительно корня. `P` = `packages/flutter3d_plugin_api/api/flutter3d_plugin_api.api`, `C` = `packages/flutter3d_core/api/flutter3d_core.api`, `S` = `packages/flutter3d_sim/api/flutter3d_sim.api`, `H` = `packages/flutter3d_hardware/api/flutter3d_hardware.api`, `A` = `packages/flutter3d_app/api/flutter3d_app.api`, `M` = `packages/flutter3d_matter/api/flutter3d_matter.api`, `Ph` = `packages/flutter3d_physics/api/flutter3d_physics.api`, `R` = `packages/flutter3d_plugin_runtime/api/flutter3d_plugin_runtime.api`, `G` = `packages/flutter3d_game/api/flutter3d_game.api`, `F` = `packages/flutter3d_foundation/api/flutter3d_foundation.api`.

## 1. Модель модулей и плагинов

```dart
final class WindPlugin extends Flutter3dPlugin {                      // P:129
  @override PluginManifest get manifest => const PluginManifest(      // P:300-318
    id: 'wind', apiVersion: PluginApiVersion(1, 0), version: PluginVersion(1, 2, 0),
    simulationVersion: 1, dependsOn: <String>['elements'],
    backends: <String>{'webgpu', 'cpu'}, touches: PluginTouches.simulation,
    permissions: <PluginPermission>{PluginPermission.network});
  @override void install(PluginHost host) {                            // P:270-278
    host.loop.addSystem('wind.blow', LoopPhase.fields, (LoopContext c) {}, after: ['physics']);
    host.events.declare<Gust>('wind.gust', codec: Gust.codec);
    host.registry<MaterialCatalog>().add(gel);                        // registry by type
    host.registry<RendererSteps>().addNode(HazeNode(), at: RenderAnchor.afterTonemap);
  }
}
Flutter3dView(plugins: const [WindPlugin(), ...standardAddons], registries: [RuntimeShaders(...)]); // A:107
```

Типы: `Flutter3dPlugin` (`manifest`, синхронный `install`/`uninstall`), `PluginHost` (`events`, `loop`, `apiVersion`, `backend`, `registry<R>()`/`maybeRegistry`), `PluginManager` P:280-298 (`installAll`, `enable/disable`, `reorder`, журнал `PluginEnabled/Disabled/Reordered/Set` как `PluginChange` со `step` — включение плагина само есть событие симуляции), `PluginApiVersion.current = 1.0` с `refusalOn` P:217-227, `PluginDependency`+`VersionRange` P:236-244, 562-574, `PluginScope.rank`/`track` P:334-338, `Registration` как универсальный «откат» F:111-114. Реестры — всё наследники `PluginRegistry` с `forPlugin(scope)`: `FormatRegistry` P:140-147, `DataSectionRegistry` P:71-76, `VmExtensions` P:578-582, `ComponentRegistry` P:37-45, `EventRegistry` P:118-127, `LoopRegistry` P:193-197, `RenderStepRegistry`→`RendererSteps` C:3653-3677, `ModelDecoders` C:2583-2594, `EntityKinds` S:779-791, `MaterialCatalog` M:32-45, `SnapshotRegistry` P:553-560; `LightingModels` — статический реестр C:2014-2018. Композиция: `Flutter3dView(plugins:, registries:, formats:)` A:107 → `EngineLoop(plugins:, registries:, materials:, backend:)` S:678, `late final PluginManager plugins` S:723.

Три вида плагинов (ARCHITECTURE.md:3385-3414): **Dart-пакет** — полный хост, обнаруживается через блок `flutter3d_plugins:` в pubspec и topic `flutter3d-plugin` (site/content/reference/plugins.md:13-24); **data-плагин** `.f3dplugin` — `DataPluginDocument` R:47-64 (фазы, события, `entityKinds`, материалы на языке материалов, `renderSteps` с шейдером на бэкенд, `wasm`, `scripts`, секции), `DataPluginLoader` R:71-78 читает всё до установки, права через `PluginGrants` R:132-137 (`files`/`network`/`tools`); **Wasm** — `WasmPlugin` R:291-299, `WasmSystemSpec` R:314-325, `WasmLimits` R:265-271 (страницы, топливо на шаг, глубина), ABI 1–2 только i32, числа мира идут как Q16.16 `Fixed16` R:99-102; интерпретатор на Dart — эталон, браузерный `browserWasmRuntime()` R:356 без учёта топлива. Четвёртый шов — `ScriptRuntime` R:200-204 без поставляемой реализации. Пример документа: `packages/flutter3d_plugin_runtime/test/fixtures/v2/glow.f3dplugin`. Шаблоны: `flutter3d create plugin --kind render-step|effect|genre|element|tool` (plugins.md:36-40), конформанс `checkPluginConformance(create, harness:)` `packages/flutter3d_conformance/api/flutter3d_conformance.api:151`.

Примечательно: реестры запрашиваются по типу-дженерику, а не фиксированным набором полей хоста — плагин сам знает, какие реестры есть у хоста данного приложения; `touches: simulation|view` — явная метка детерминизма; манифест носит `simulationVersion`, и он входит в `SimulationVersion.plugins` P:522-541 — плагины версионируют реплей; `backends` — свободные строки (`RuntimeBackends` R:143-148), константы есть только для четырёх своих.

## 2. Расширение кадра

```dart
final class HazeNode extends RenderNode {                              // C:3432, FrameGraphNode C:1396-1404
  @override String get name => 'wind.haze';
  @override RenderAnchor get defaultAnchor => RenderAnchor.afterTonemap;
  @override List<ResourceId> get reads => const [FrameResourceIds.sceneColor];   // C:1448-1471
  @override List<ResourceId> get writes => const [ResourceId('wind.haze')];
  @override List<ResourceId> get keeps => const [ResourceId('wind.history')];    // история между кадрами
  @override void execute(RenderFrame frame) {                           // C:3365-3369
    frame.resources.declare(const ResourceDesc(id: ResourceId('wind.haze'),
        format: TextureFormat.rgba16Float, size: FrameFraction(2)));   // C:3692, C:1378
    frame.services.drawFullscreen(FullscreenDraw(target: frame.resources.texture(const ResourceId('wind.haze')),
        fragment: shader, textures: {'scene': frame.resources.texture(FrameResourceIds.sceneColor)}));
  }
}
steps.addNode(HazeNode(), at: RenderAnchor.afterTonemap, after: ['f3d.bloom']); // C:3666
steps.addAnchor(const RenderAnchor.after(RenderAnchor.afterTonemap, 'wind.haze')); // P:426
steps.provide(RenderStep.fog); steps.addContributor(Splats());         // C:3669, 3676
settings.without({RenderStep.bloom}).withExtension(hazeSlot, const HazeSettings()); // C:3446-3447
```

Типы: `RendererSteps` (addNode/addAnchor/addContributor/addMaterials/addLightingModel/addStep/addSettings/provide, `nodesAt`, `providerOf`, `withdrawn`); `FrameContext` C:1353-1371 (device, services, settings, view, width/height, frameIndex, time, origin, jitter, матрицы, `noteDraw`, `invalidatePipeline`); `FrameResources` C:1473-1495 (`texture/tryTexture/buffer/transient/declare/provide/provideBuffer/originOf`); `ResourceId` — `extension type` над строкой C:3706; `FrameGraph.compile(outputs:, disabled:, switchedOff:)` C:1384 → `CompiledFrameGraph` C:625-644 (порядок, вырезанные узлы, версии ресурсов, `lastUseOf`, `skipReason`); `FrameGraph.undisableable = {scene, composite, object ids}` C:1386; `RenderSettings` C:3441-3512 с `stepsOff`, `extensions`, `only/without/withExtension/extension<T>`; `SettingsSlot<T>` C:3874-3892 — встроенные слоты являются «линзами» на поля настроек, плагинные — сериализуются в JSON через `SettingsExtensions` C:3861-3872; `RenderStep` C:3514-3561 — 33 встроенных шага, каждый несёт `passes`, `needs` и замыкания `switchOff/isOn` над `RenderSettings`; `RenderStepAddon` C:3563-3572 (`provides`, `adds`, `settings`) — `flutter3d_post` состоит из таких (`BloomAddon`, `FogAddon`…, `packages/flutter3d_post/api/flutter3d_post.api:7-60`); `PassContributor` C:3029-3038 + `ContributorFrame` C:665-672 (encoder, lights, sceneDepth) — рисование внутри прохода сцены; `RenderServices` C:3437-3439 (`drawFullscreen`, `encodeScene`); `RenderAnchor` P:421-481 — 25 пар before/after + `beforePresent`; `PassSkip` C:3040-3050 — семь типизированных причин пропуска.

Форма: гибрид. Граф с объявленными `reads/writes/keeps/optionalReads`, версиями и переиспользованием ресурсов (`aliasTargets`, `ResourceOrigin drawn|kept`) — как у render graph; но размещение узла — по именованному якорю плюс `after/before` по именам узлов, а не выводится из зависимостей. Transient-ресурс объявляется внутри `execute` (`FrameResources.declare`), а не в отдельной фазе setup с builder-лямбдой, как в Unity RenderGraph/Unreal RDG. Отдельный от узлов словарь переключения — `RenderStep`, и плагин может заменить движковый шаг (`provide`). `keeps` — единственный механизм истории; `FrameContext` несёт `RenderSettings` целиком.

## 3. Материалы и шейдеры

```text
f3dmat 2                                       // material-language.md:61-67, 98-107
material Hatch {
  uniform vec3 ink = vec3(0.1);                // член MaterialParams
  state { blend mask; cutoff 0.5; environment off; }
  light { return albedo * step(0.5, nDotL) / max(nDotL, 0.001); }
  composite { return floor(direct * 4.0) / 4.0 + emissive; }
  vertex { out world = world + normal * 0.01; }
  fragment { return vec4(lit, alpha); }
}
```
```dart
final lib = await loadShaderBundleAsset(device, 'assets/shaders/hatch.f3dshaders'); // flutter3d.api:129
renderer.renderSteps.addMaterials(lib);                                 // C:3665
final bundled = BundledMaterials.read(bytes);                           // C:489-496
final m = RenderMaterial(lighting: bundled['Hatch'], parameters: bundled.parameters('Hatch')); // C:3392
HatchParameters(m.parameters).ink = Vector3(0.2, 0.1, 0.0);             // materials.g.dart, extension type
scene.add(MeshNode(mesh, m));                                            // C:2502
final class HatchModels extends LightingModelAddon {                    // C:2004-2012
  const HatchModels() : super(id: 'hatch', models: const [LightingModel('Hatch', 'Hatch')]);
  @override ShaderLibrary? stagesFor(GraphicsDevice device) => …; }
```

Типы: `SurfaceMaterial` C:4304-4326 — неизменяемое описание из документа (glTF/MTL/`.fmat`), `RenderMaterial` C:3382-3430 — изменяемое, с текстурами устройства, `lighting`, `parameters: Map<String, Float32List>`, `extraTextures`, `blendMode`, `depthLayer`; переход `bindSurfaceMaterial/bindMaterial/loadMaterial` `packages/flutter3d/api/flutter3d.api:105-117`, `MaterialDecoder` :29-32; `LightingModel` C:1970-2002 — имя стадии + набор флагов `uses*`/`vertexShaderName`, 12 встроенных; `LightingModels.register` C:2018 и `RendererSteps.addLightingModel` C:3664 — два входа; `MaterialProgram` C:2324; бандл F3SB `ShaderBundle` H:674-691 с секциями `impeller|webgl|webgpu|material`; `RuntimeShaders` R:161-169 компилирует источник во время работы для webgl/webgpu/cpu, Impeller — только из бандла, построенного хуком `compileMaterial` (`packages/flutter3d_build_hooks/api/flutter3d_build_hooks.api:25`); типизированные акцессоры генерирует `generateMaterialAccessors` :29 (пример `packages/flutter3d_effects/lib/src/materials.g.dart:17-40`); `Material3D` A:292-312 принимает `parameters: Map<String, List<double>>`; `HotSwap.loadMaterial/setMaterial` A:176, 191. Матрица «что умеет каждый бэкенд» — material-language.md:191-203.

Примечательно: один источник на собственном DSL (не GLSL/WGSL/HLSL, не графе узлов) → четыре трансляции; «модель освещения» = `.f3dmat` с блоком `light`, а `LightingModel` в Dart — лишь дескриптор возможностей; параметры — строковая карта с генерируемым типизированным видом сверху, оставленная ради data-плагинов (material-language.md:185); пара Surface/Render разделяет «документ» и «устройство».

## 4. Сцена и симуляция

```dart
final class Heat { Heat(this.kelvin); double kelvin; }
final heatCodec = ComponentCodec<Heat>.of(id: 'lab.heat',                // P:25
    encode: (h) => h.kelvin, decode: (d, v) => Heat(d as double));
void install(PluginHost host) {
  host.registry<ComponentRegistry>().register(heatCodec, published: true); // P:43
  host.loop.addSystem('lab.cool', LoopPhase.fields, (LoopContext c) {     // P:196, 155-165
    for (final e in c.world.query().having<Heat>().entities) {           // P:496-501
      c.world.set(e, Heat(c.world.get<Heat>(e)!.kelvin - 0.1 * c.dt));
    }
    c.publish(const Cooled());
  }, after: ['physics']);
}
final PublishedState s = loop.published;                                 // S:686, P:403-419
final heat = s.read<Heat>(heatCodec, entity);                            // вид читает только это
```

Граф сцены: `Scene` C:3733-3766 (`add<T>`, списки `meshes/lights/cameras/probes/decals/reflectors/textureViews`, `origin/toScene/toWorld/shiftOrigin/rebaseAround`, `ambientColor/ambientIntensity`, `environment`), `SceneNode` C:3783-3831 (сеттеры локального трансформа, `worldMatrix`, `layerMask`, `lightChannels`, `traverse`), `MeshNode` C:2492-2517, `LightNode` C:1924-1945, `CameraNode` C:498-506, `RenderView` C:3574-3597 (камера, `viewportFraction`, `layerMask`, `priority`, texture-views), `Renderer.render(width:, height:, scene:, views:, settings:)` C:3611. ECS: `SimWorld` P:504-520 ← `EcsWorld` S:645-671, `SimQuery/SimCommands` P:487-502, `Entity` — `extension type` над int P:87-93, `ComponentCodec/InPlaceCodec` P:19-26, 149-153. Цикл: `EngineLoop` S:677-733 — фиксированный шаг `WorldTiming` S:2802-2808, фазы шага `input/movers/physics/fields/rules/publish` и кадра `animate/audio/camera/render/ui` P:178-191, `frame(dt)`, `runSteps`, `rewindTo`, `capture/restore`, `keep(window:)`, `timeScale`, `determinismCheck`; `LoopContext` P:155-165 (`phase, step, dt, alpha, isResimulated, world, published, publish`). Рядом — более старый `StepSystems`/`StepContext` с фазами `begin/end` S:2551-2557, 2519-2521. Граница публикации: `PublishedState` (компоненты по id кодека, позиции `WorldPosition`, события, `origin`, `SimulationVersion`, `toWire/fromWire`); `SimulationHandle` S:2433-2442 (`query`, `published`, `onPublished`, `submit`, `rewindTo`, `ask`) с `LocalSimulation` S:1640-1651 и `IsolateSimulation` S:1253; `GenrePlugin<S>` S:1004-1024 (`stepSimulation/captureSimulation/restoreSimulation`, `kinds`, `headless`); `EntityKind`/`EntityDef`/`SpawnContext` S:763-774, 744-761, 2498-2506 — спавн из данных уровня. Единственный потребитель: `packages/flutter3d_game/lib/src/visuals/actor_visuals.dart:34-46, 103-106` — `published: () => loop.published`, строки читаются через `PublishedActor.read(state, entity)` S:2044.

Примечательно: граф сцены ничего не знает об `Entity`; мост рисуется руками на каждый вид; два API систем сосуществуют; компоненты типизированы Dart-типом, а на проводе — строковым id кодека; шаг считается, не измеряется (CONTRACTS.md:82-83).

## 5. HAL

```dart
final registry = platformDevices()                                        // A:685
  ..addBackend('vulkan', ({required int width, required int height}) => VulkanDevice.open(width: width, height: height)) // H:320, BackendOpener H:27
  ..addPresenter<VulkanDevice>(presenter);                                 // H:321
final device = await registry.open(width: 1280, height: 720, onFallback: print); // H:317
device.features.require(DeviceFeature.compute, backend: device.backendName);     // H:260, 196
final n = device.limits.maxColorAttachments;                               // H:262-298
device.lost.listen((DeviceLoss loss) {});                                  // H:386, 300-306
final class VulkanDevice extends GraphicsDevice { … wrapTexture(backend: image, width: w, height: h, format: f) … } // H:371, backend.dart H:23
Flutter3dView(devices: registry);  Flutter3dView(device: device);         // A:107 — занятое устройство не освобождается
SceneSurface(renderer: r, scene: s, view: v, settings: () => rs, onBeforeFrame: tick, presentFrame: presentFrame); // A:503-515
```

Типы: `GraphicsDevice` `abstract base` H:371-424 (19 абстрактных членов, остальные с телами через `refuse()`), `DeviceFeature` H:181-247 — 61 имя в стиле WebGPU со `stability stable|reserved` (`bindless-resources`, `mesh-shaders`, `ray-query` зарезервированы), `DeviceFeatures` H:249-260, `DeviceLimits` H:262-298 (`webgpuDefaults`), `DeviceRegistry` H:315-321, `DeviceUnavailableException.refusals` H:332-338, `backend.dart` H:5-23 — публичные `wrap*` для авторов бэкендов, `ShaderBundle` H:674-691. Выбор бэкенда: условный экспорт web/native на этапе компиляции, затем `try/catch` Impeller→CPU и WebGPU→WebGL2 (site/content/reference/packages.md:157). `Flutter3dView` A:105-140 владеет устройством, рендерером и циклом, если их не передали (`Flutter3dEngine.ownsDevice/ownsRenderer` A:101-102); `SceneSurface` — нижний слой, настройки тянет функцией на каждый кадр, показывает `TextureHandle` через `FramePresenter` A:155.

Примечательно: словарь HAL — WebGPU-образный, а первичный бэкенд — flutter_gpu/Impeller; четыре бэкенда в репозитории плюс публичный конформанс `runDeviceConformance` (`flutter3d_conformance.api:115`); имя бэкенда — строка.

## 6. Ассеты и форматы

```dart
final doc = await loadModelAsset('assets/models/robot.glb', deviceClass: DeviceClass.phone); // flutter3d.api:121
final asset = await ModelAsset.fromDocument(doc, device: engine.device);        // :53
final robot = asset.instantiateFitted(engine.scene, length: 1.8, onGround: true); // :58
robot.player?.play('Walk');
void install(PluginHost host) {
  host.registry<FormatRegistry>().add(const FormatSpec(id: 'wind.map', version: 1,   // F:42, P:147
      suffixes: ['.windmap.json'], fixture: 'test/fixtures/v<N>/map.windmap.json'));
  host.registry<ModelDecoders>().addModelDecoder(const PlyDecoder());           // C:2591, 2578-2581
  host.registry<DataSectionRegistry>().register(const WindSection());           // P:75
}
final cache = ResourceCache<String, ModelAsset>(load: fetch, dispose: (a) => a.dispose()); // C:3679-3690
final handle = await cache.acquire('robot'); handle.release();
```

Типы: `FormatSpec` F:36-56 (id, version, suffixes, fixture, since, migrations, aliases, understands, enveloped, magic; `open/lift/claims`), `FormatDocument` F:24-30, конверт из четырёх ключей CONTRACTS.md:240-303; `ModelDecoders` с `addSource(scheme)` C:2592; `Decoders` фасада с `MaterialDecoder` flutter3d.api:17-32; `ModelAsset` :34-54 (parts, skins, clips, variants, impostors), `ModelInstance` :60-73, `ModelWardrobe` :90-101; `.f3d` — `F3dDecoder/F3dWriter/F3dDocument/F3dExtraSection` (экспорт C через flutter3d.api:133), декодирование в изоляте `decodeModelInIsolate`; CLI `cliCommands = [convert, create, init, plugins, migrate, lights, doctor, help]` `packages/flutter3d_build/api/flutter3d_build.api:86`, `convertFiles(files, to: ConversionTarget, models: ModelSettings(textures:, mips:, lods:, impostor:, chunks:))` :223, 197-204, коды выхода `CliExit` :7-13; хук `flutter3d_build` собирает бандл при `flutter build` (quickstart.md:43); `LevelScene.build(level, device:)` → `LevelSceneParts` `packages/flutter3d_level_scene/api/flutter3d_level_scene.api:16-39`, `LevelLoader.load/build` A:231-239 → `LoadedLevel` A:261-285 (сцена + `CollisionWorld`); префабы — `Level.prefabs` S:1328, `applyPrefabOverride` S:2810, инструменты `prefab.*` в `packages/flutter3d_mcp/api/flutter3d_mcp.mcp:254-304`.

Примечательно: формат — значение с миграциями и фикстурой, которую считает структурное правило; «документ» (чистый Dart, изолят) отделён от «ассета» (устройство); `DeviceClass` входит в ключ загрузки (семейство текстур); glTF не требует смены осей (CONTRACTS.md:19-22).

## 7. Физика и мир

```dart
final world = CollisionWorld(                                             // Ph:251
  backend: NativePhysics(),                                               // physics_native.api:458; DartPhysics Ph:320 — эталон
  properties: WorldProperties(gravity: Vector3(0, -24, 0), wind: Vector3(3, 0, 0), medium: 'f3d.air'), // M:220
  materials: MaterialCatalog.builtIn()..add(const PhysicalMaterial(      // M:44, 155
      id: 'lab.gel', name: 'Gel', phase: MaterialPhase.liquid,
      mechanical: MechanicalProperties(density: 1050, kineticFriction: 0.2, restitution: 0.1, source: 'lab 2026'),
      fluid: FluidProperties(viscosity: 0.8, source: 'lab 2026'))));
final body = RigidBody(world: world, shape: CollisionBox.size(Vector3.all(1)), position: Vector3(0, 2, 0), mass: 2, material: Materials.oak); // Ph:729
world.backend.dynamics(world).add(body);                                  // Ph:648, 761
world.add(Collider(shape: CollisionBox.size(Vector3(10, 1, 10)), material: Materials.concrete)); // Ph:89
final effective = level.worldOver(gameWorld);                             // S:1333; Level(world: {'gravity': [0,-9.81,0]}) S:1328
final els = ElementsSimulation.open(); final water = els.addWater(ground: g, properties: p, heat: h, bed: bed); // elements.api:216, 211
water.pour(at, volume: 0.5); els.fires.ignite(tracked, by: Igniter.match);  // :346, 260, 275
```

Типы: `WorldProperties` M:214-232 (гравитация, температура и давление воздуха, выведенная плотность, ветер, `medium` как id материала, `speedOfSound`, `mediumDensity(catalog)`), константы M:239-271; `PhysicalMaterial` M:149-171 с группами mechanical/fluid/thermal/acoustic/optical/electrical, у каждой `source` и `unknown`; `MaterialPhase` M:69-79; `MaterialCatalog` M:32-45 (`contact(a,b)`, `pairs`, `require`, `watch`), 33 встроенных `Materials` M:85-120, `MaterialPair` M:52-67; `CollisionWorld` Ph:247-280 (`properties` изменяемое, `raycast/sweep/overlap/depenetrate`, `moveOriginTo`), `Collider` Ph:88-108, `CollisionShape` sealed + `CustomShape` Ph:294-309, `RigidBody` Ph:726-755 (материал либо `friction/restitution`), `RigidDynamics` Ph:757-768, `PhysicsBackend` Ph:645-653 (`dynamics/cloth/fluid`); `NativeWorld` physics_native.api:537+ — второй, низкоуровневый API ядра на C (records), которым напрямую пользуются элементы; `ElementsSimulation` elements.api:197-224, `WaterBody` :338-351, `Fires` :257-261, `Igniter` :267-277 с пресетами, `ElementsSimulationPlugin` :226-231, `ElementPlugin` :139-145; `EngineLoop.shiftsPhysics(world)` S:694. Таблица свойств мира и материалов — CONTRACTS.md:101-173; правило контакта (среднее геометрическое μ, большая реституция, пара побеждает) :92-99.

Примечательно: материал — запись каталога с происхождением, с id в пространстве `f3d.`/`<plugin>.`; гравитация читается из мира, литерал — ошибка структурного правила; переопределение мира уровнем — нетипизированная JSON-карта поверх типизированного значения.

## 8. Единицы и соглашения (как их формулирует CONTRACTS.md)

```dart
final sun = LightNode(type: LightType.directional, intensity: 100000.0);     // люксы, C:1925
final bulb = LightNode.lumens(1200.0, type: LightType.point, range: 8.0);    // люмены → канделы, C:1926
final m = RenderMaterial(baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28), emissiveStrength: 300.0 /* нит */);
camera.projection = PerspectiveProjection(fovY: math.pi / 3);                // радианы
final here = WorldPosition(12500.0, 2.0, -3.0); final local = scene.toScene(here); // double → float32 относительно Scene.origin, C:3751
final c = flutterColor.toLinear();                                           // flutter3d.api:14-15
```

Метры, Y вверх, правая система, радианы, без градусов в именах (CONTRACTS.md:14-26); `WorldPosition` из трёх double и три пространства world/scene/local (:27-72); секунды как double, `Duration` только на краю платформы, шаг считается (:74-83); СИ, одна μ (:85-99); `LinearColor` линейный, если в имени нет `srgb`, `Color` Flutter только в виджетах (:175-186); люксы/канделы/ниты, люмены как конструктор, экспозиция в EV100, `Photometric.legacyUnit`≈5790.6 (:188-231); конверт файлов (:240-303); правила имён — американское написание, `dispose` vs `close`, `create` синхронный / `open` асинхронный, булевы геттеры как вопрос, `…Settings` с `copyWith` и флагами `clear…` (:317-361). Документ сам оговаривает, что не каждая сигнатура уже несёт `WorldPosition` (:35-38); умолчания `LightNode.intensity = Photometric.legacyUnit` C:1925, `Light3D` A:243 и `RenderMaterial.emissiveStrength = Photometric.legacyNits` C:3392 — в до-1.0 единице.

## 9. Эргономика входа

Минимум до освещённого куба — 10 строк, свет и камера выдаются видом по умолчанию (quickstart.md:167):

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(MaterialApp(home: Flutter3dView(                       // A:105
  onCreated: (Flutter3dEngine engine) => engine.scene.add(MeshNode(          // A:91-103, C:2502
    DeviceMesh.upload(engine.device, CuboidShape(size: Vector3.all(1)).build()), // C:918, 715-717
    RenderMaterial(baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28), roughness: 0.35),
  )),
)));
```

Пример quickstart (quickstart.md:127-165) — 37 строк с комментариями, с вращением через `onFrame(engine, FrameInfo)`. Декларативно (quickstart.md:173-193; виджеты A:17, 241, 292, 346, 465): `Scene3D(children: [Camera3D(position:, target:), Light3D.point(position:, range:), Material3D(baseColor:, children: [Mesh3D(shape: CuboidShape())])])` — около пяти строк тела; ключ виджета сохраняет узел; `Contributor3D` A:23 монтирует `PassContributor` из дерева. Три слоя: `Scene3D` → `Flutter3dView` → `SceneSurface` (quickstart.md:171, 200-202). В pubspec два пакета (:98-123); предусловие — Impeller включён в `Info.plist` (:83).

Лаборатория/двойник сегодня пишет на том, что есть: `Flutter3dView(timing: WorldTiming(stepRate: 240), plugins: [LabPlugin()])`, `loop.runSteps(n)` S:731, `loop.timeScale` S:725, `loop.isPaused` S:700, `loop.capture()/restore/rewindTo` S:696, 729-730, `IsolateSimulation` S:1253; измерения — опубликованные компоненты по кодеку; внешнее состояние — `InputState`/`onStepInput` S:693. `TimeSource`, `Probe`, `ExternalStateInput`, `SimulationProfile` ни в одном снимке `api/*.api` отсутствуют (проверено `rg`) — это план (readiness-review §6 D2, D3, D6, D7), не поверхность. `flutter3d_education` (`lab.dart`, LTI) — ARCHITECTURE.md:267.

## 10. Наблюдаемость и инструменты

```dart
Flutter3dView(onFrame: (engine, FrameInfo f) {                             // A:150-153
  final r = f.result!;                                                      // FrameResult C:1497-1528
  log('${r.drawCalls} draws ${r.cpuMicros}µs skipped=${r.skipped.map((s) => s.name)} ev100=${r.ev100}');
});
engine.renderer.listener = RenderListener.toBus(loop.events, frameBudget: const Duration(milliseconds: 16)); // C:3373
final capture = await engine.renderer.captureNextFrame(draws: true);        // C:3613 → FrameCapture f3d.frameCapture v2, C:1320-1337
final memory = engine.renderer.memoryReport(scene: engine.scene);           // C:3619 → MemoryReport C:2428-2435
registerRenderExtensions(() => engine.renderer, scene: () => engine.scene); // A:693 → ext.flutter3d.render.*
registerFlutter3dExtension('wind.state', (method, params) async => …, answers: {'wind'}); // P:593
```

`FrameResult` — проходы с `micros/gpuMicros`, `skipped` с `PassSkip`, `pipelineStalls`, отказы MSAA/wireframe, `targetBytes`, `held`; события шины `FrameDrawn/FrameHeld/FrameOverTime/FramePassSkipped/FramePipelineStall` C:1373-1446; `Renderer.pickPixel/captureObjectIds/probeMultipleRenderTargets` C:3614-3616; `GpuFrameTimings` H:361-369; `FrameTimingLog` по `--dart-define` A:157-165; `StepTimeTrace` S:2559-2571, `StepDivergence` S:2523-2530; `HotSwap` A:173-200. VM-расширения: 13 под `ext.flutter3d.*` (`packages/flutter3d_app/api/flutter3d_app.vm:5-77`), `vmSchemaVersion '1.0.0'` P:595. MCP-серверы: `flutter3d.editor` (`flutter3d_mcp.mcp:5`, ~60 инструментов level/prefab/selection/light/play/capture/render), `flutter3d.diagnostics` (`flutter3d_sim_mcp.mcp:5`), `flutter3d.sim` (:48 — `run.step/bisect/expect/verify`, `state.snapshot`, `view.frame`), `flutter3d.plugins` (`flutter3d_build.mcp:5` — `plugin.create/conformance/report`); библиотека `model.dart` `flutter3d_mcp.api:668`. Всё снимается в `api/*.mcp|*.vm|*.cli` как контракт (CONTRACTS.md:305-315). `doctor`: `runDoctorChecks` build.api:148, `DoctorCheck/DoctorStatus` :56-70, внешние инструменты `fbx2gltf/blender/usdcat` :120.

Примечательно: у каждого пропуска прохода типизированная причина; захват кадра — версионированный файловый формат; инструменты для агентов версионируются как API.

## 11. Настройки и качество

```dart
const rs = RenderSettings(bloom: BloomSettings(enabled: true), renderScale: 0.85, stepsOff: {RenderStep.motionBlur}); // C:3450
final cheaper = rs.without({RenderStep.volumetricFog}).withExtension(hazeSlot, const HazeSettings());
final picker = DeviceClassPicker(traits: DeviceTraits.of(device, web: kIsWeb), memory: memory); // C:899-907, 934
final cls = await picker.pick(measure: () async => micros);                  // phone | web | desktop, C:884-892
final adaptive = AdaptiveQuality(QualityTable.of(cls), const AdaptiveQualitySettings(enabled: true, budgetMicros: 16667)); // C:13-34, 3289-3294
final frameSettings = adaptive.apply(rs); adaptive.recordFrame(result.cpuMicros, motion: 0.2);
const lookKey = SettingKey<double>('mygame.look', fallback: 1.0);           // G:750-758
final gs = const GameSettings().withValue(lookKey, 1.4).withVolume(AudioBus.music, 0.6); // G:439-456
final look = gs.valueOf(GameSettingKeys.mouseLook);                          // G:427-437
```

`RenderSettings` — около 55 полей, `const`, `copyWith`, `forMeasurement/forStereo`; `RenderViewSettings` C:3599-3606 — переопределение на вид; `QualitySetting` C:3276-3287 — сетка 5 масштабов × 4 уровней; `QualityTable.of(DeviceClass)` с флагом `measured`; `AdaptiveScale` C:36-42; `FramePacing` C:1427-1433; `DeviceClass.parse` nullable; `GameSettings` формат v2 (`volumes`, `values`, `actions`), `SettingsFile` G:760-768, `GameSettingsController` G:458-478 (перепривязка, тюнинг осей); `Level.renderSettings` как карта S:1328.

Примечательно: класс устройства выводится из признаков и замера, не из имени; настройки неизменяемы и сериализуются в уровень; плагинные слоты — единственная типизированная точка расширения настроек.

## 12. Имена и топология пакетов

Фасады: `flutter3d` (L5) реэкспортирует по имени ~390 имён ядра, 11 foundation, 96 hardware и пять типов `vector_math` (`flutter3d.api:133, 622, 635, 733`); `flutter3d_game` (L7) реэкспортирует `flutter3d` целиком (G:913) и по имени из app/audio_core/physics/sim (G:1537-1560). Слои L0–L9 — десять (ARCHITECTURE.md:4659-4681): L0 foundation/lints/samples/pad_input/pointer_lock; L1 hardware, plugin_api; L2 matter, shaders; L3 core, audio_core и четыре бэкенда, physics; L4 audio, sim; L5 flutter3d, particles, post, level_scene, build_hooks…; L6 app, plugin_runtime, elements, три жанра…; L7 game, game_kit, effects, mcp…; L8 build, game_ui, game_physics, sim_mcp…; L9 flame_flutter3d_audio; `flutter3d_demo_content` не публикуется. Всего 57 пакетов (quickstart.md:28). Правило слоёв: `flutter3d_sim` не зависит ни от `flutter3d`, ни от Flutter (ARCHITECTURE.md:217-219).

Счёт по `dependencies:` в pubspec (только пакеты workspace, транзитивно): `flutter3d` — 4 прямых / 5 транзитивных (core, foundation, hardware, plugin_api, shaders); `flutter3d_app` — 13 / 14 (плюс четыре бэкенда, sim, particles, level_scene, physics, matter); `flutter3d_game` — 10 / 18 (плюс app, audio_core, pad_input, pointer_lock); `flutter3d_core` — 4; `flutter3d_plugin_api` — 1. Минимальное приложение по quickstart (`flutter3d` + `flutter3d_app`) тянет 15 пакетов движка; игра на `flutter3d_game` — 19.

Именование: `Flutter3d*` на входных типах (`Flutter3dView/Engine/Plugin/Exception`), `Render*` для стороны кадра, `Sim*` для абстракций ECS, `Native*` для ядра на C, `Published*` для границы, `*Node` для сцены, `*3D` для виджетов, `*Addon` для плагинов шага, `*Settings/*Descriptor/*Spec` по CONTRACTS.md:350-352, id форматов и материалов `f3d.<kind>` / `<pluginId>.<kind>`. Роли: `_core` — чистый Dart без Flutter; `flutter3d` — тонкая Flutter-оболочка; `_app` — виджет и выбор бэкенда; `_game` — фасад игры; `_game_<genre>` — правила; `_game_kit/_game_ui/_game_physics` разведены по цене нативного кода (ARCHITECTURE.md:259-261). Три независимые линии версий: pub-версии пакетов (`1.0.0-rc.1`), `PluginApiVersion` (1.0, P:227), Wasm ABI (2, R:376); HAL — на своей линии.
