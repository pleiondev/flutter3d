# Аудит 1.0 render/plugin API (read-only, снапшот рабочего дерева, 2026-10-09)

Заметки агента. Сокращения путей: **R** = `packages/flutter3d_core/lib/src/engine/render`, **F** = `packages/flutter3d_core/lib/src/formats`, **P** = `packages/flutter3d_plugin_api/lib/src`, **PR** = `packages/flutter3d_plugin_runtime/lib/src`, **H** = `packages/flutter3d_hardware/lib/src`. «✔» — проверено чтением, «?» — предположение.

Общий механизм (✔): все движковые проходы стоят в слотах за якорями `_FrameSchedule.stage(...)` (R/renderer.dart:3028–3231); плагин вставляет `RenderNode` через `RendererSteps.addNode(at: RenderAnchor.*)` (R/renderer_steps.dart:155), свой якорь через `addAnchor` (:238), контрибьютор через `addContributor` (:277), заменяет стадию по имени через `addMaterials` (:426, «added later = consulted earlier»), выключает движковый шаг через `provide` + отключение плагина (:326) или `RenderSettings.without`. Выход движкового шага читается по `ResourceId` через `FrameResources.tryTexture/texture/originOf` (R/frame_resources.dart:269–377) при условии объявленного `reads/optionalReads` (:425, :566).

## A. Матрица покрытия

Колонки: (a) наблюдать выход, (b) вставить до/после, (c) заменить/отключить, (d) материал/шейдер внутри стадии, (e) fullscreen-пост, (f) compute.

| Стадия (узел) | a | b | c | d | e | f |
|---|---|---|---|---|---|---|
| Point shadows static/dynamic (`_CubeShadow*Node`, R/renderer_frame_nodes.dart:75,198) | да: `cube_shadow(_static)` (R/frame_plan.dart:46–47), `keeps` | да: before/afterShadows | откл.: `RenderStep.shadows` (R/render_step.dart:189); замены нет — `ShadowTechnique` не трогает куб-атлас (R/shadow_technique.dart:160) | частично: vertex-блок `.f3dmat` в depth/shadow через `vertexStageInDepthPasses` (R/renderer_material_stages.dart:51–92); свой fragment — нет | — | — |
| Directional cascades (`_ShadowMapNode`:297) | да: `shadow_map`, только `originOf==drawn` (R/pass_contributor.dart:151) | да | откл. шагом; замена частично: `ShadowTechnique.cascadesFor/kernelFor` (R/shadow_technique.dart:166–185), lookup зашит в lit-стадии (:150–157) | как выше | — | — |
| Shadow moments (`_ShadowMomentsNode`:363) | да: `shadow_moments` | да | **да**: `ShadowPrefilter(stage:)` ищется по имени в `addMaterials` (R/shadow_technique.dart:85–101) | n/a | своя стадия-префильтр (GLSL, не `.f3dmat` — :100) | — |
| Reflection probes / IBL (`_ReflectionProbeNode`:451) | да: `reflection_probe_N` (frame_plan.dart:125) | before/afterCaptures | откл. `reflectionProbes`; замена: нет (имена `reflection probe ` зарезервированы, renderer_steps.dart:171) | lit-модели плагина рисуются в захвате через `encodeScene` ✔ | — | — |
| Irradiance update (`_IrradianceUpdateNode`:1415) | `irradiance_atlas` (keeps) | да | откл. `irradianceUpdate`; замены нет | — | — | движковый; свой compute только отдельным узлом |
| Render textures / planar (`:581,:646`) | `render_textures`, `planar_reflections` (одно имя на все, :134–138) | да | откл.; замены нет | planar: `LightingModel.planarReflection` закрыт (F/lighting_model.dart:106) | — | — |
| Depth pre-draw (внутри `_SceneNode`, R/renderer_depth.dart) | нет отдельного ресурса; surface_buffer после сцены | **нет** якоря между pre-draw и opaque (beforeOpaque: «nothing can run between», P/render.dart:79–82) | нет | vertex-блок да (:109 в material-language.md); контрибьюторы в pre-pass **не рисуют** — только `boundsFor` (R/renderer_depth.dart:460–462), вопреки доке renderer_steps.dart:58 | — | — |
| Opaque scene + sky (`_SceneNode`:750) | `hdr_colour`, `surface_buffer`, `albedo_buffer` (frame_plan.dart:28–36) | before/afterOpaque; sky неотделим (:79–82) | нет (сцена «есть кадр», render_step.dart:52) | **да**: lit-модель через `LightingModelAddon`/`addLightingModel` (R/lighting_model_addon.dart:85–93); `.f3dmat` `light/ambient/composite/vertex/state`; `PassContributor.encode` внутри прохода (R/renderer_scene_pass.dart:487) с `ContributorLights` (R/pass_contributor.dart:568) | — | — |
| Decals (`_DecalNode`:995) | только через `hdr_colour@n` | before/afterDecals | откл. `decals`; замена: нет | **нет**: фикс. стадия `decal.frag`, 16 деколей/4 текстуры (R/renderer_decal_pass.dart:24–27); свой материал деколи невозможен | — | — |
| Scene colour copy (`:1053`) | `scene_colour` атлас (frame_plan.dart:105) | beforeTransparent | откл. `sceneColorCopy` | `.f3dmat` `sceneDepth/scenePosition` (usesSceneDepth, F/lighting_model.dart:375) | — | — |
| Transparent / transmission (`_TransparentNode`:1096, renderer_transmission_pass.dart) | `hdr_colour@n`, `surface_buffer` | before/afterTransparent | откл. `transparent` | да: blend-режимы, `effectsDepth`, контрибьюторы `readsSceneDepth` (R/renderer_transparency_pass.dart:368–382) | — | — |
| Particles / soft particles (контрибьютор, не узел) | `sceneDepth` в `ContributorFrame` (R/pass_contributor.dart:429) | n/a — внутри scene/transparent | удалить `removeContributor` | да, свои стадии (`flutter3d_particles`) | — | **нет** GPU-симуляции в движке; плагин — свой `RenderNode` с `device.beginComputePass` (H/graphics_device.dart:504) + `provideBuffer` (R/frame_resources.dart:308); только WebGPU/CPU (`DeviceFeature.compute` refuse в impeller/webgl ✔) |
| Object ids / pick (`_ObjectIdNode`:2888) | `object_ids` | afterTransparent | нет | нет (unlit-стадия движка) | — | — |
| Outline mask (`:2116`) | `outline_mask` | afterTransparent | откл. `highContrast` | нет | — | — |
| SSR (`_ReflectionsNode`:1223) | `hdr_colour@n` | before/afterReflections | откл.; замена: `provide(reflections)`+свой узел ✔ | — | да (`FullscreenEffect.overlay`) | — |
| Luminance/auto exposure (`:2775`) | `luminance` (readback движка) | before/afterAutoExposure | откл. | — | да | — |
| Hi-Z (`_DepthPyramidNode`:2827) | `depth_pyramid` | before/afterHiZ | откл. `hiZOcclusion`; свой тест — `OcclusionTest` в `Renderer.create` (R/renderer.dart:1799; H-mixin R/../scene/occlusion/occlusion_test.dart:61) | — | — | — |
| SSAO + blur (`:1279,:2228`) | `ao` | before/afterAmbientOcclusion | откл. | — | да (может писать `ao`: `provide`) | — |
| Contact shadows (`:1356,:2280`) | `contact_shadow` | да | откл. | — | да | — |
| Velocity/reactive/history (`:1485–1686`) | `velocity` — **только при TAA или motion blur** (`_wantsVelocity`, renderer_frame_nodes.dart:1982) | before/afterVelocity | нет отдельного шага; выключается через TAA+MB | `encodeReactive` для контрибьюторов (pass_contributor.dart:78) | да | — |
| Volumetric fog / light shafts (`:1741,:1834`) | `hdr_colour@n` | да | откл. | — | да | — |
| DoF / motion blur (`:1920,:1996`) | `hdr_colour@n` | да | откл. | — | да | — |
| TAA (`_TemporalResolveNode`:1686) | `temporal_history` (keeps, движка) | before/afterTemporalResolve | откл. `temporalAntiAliasing` | — | да, своя история через `keeps` + `provide` (frame_graph.dart:133) | — |
| Local exposure / bloom / lens flare (`:2671,:2339,:2373`) | `local_exposure`, `bloom` | да | откл.; bloom — `provide` аддоном (`flutter3d_post/light.dart`) | — | да | — |
| Tonemap/grade/composite (`_CompositeNode`:2436) | `frame@1` после | beforeTonemap (последняя линейная точка, P/render.dart:242) / afterTonemap | tonemap/colorGrade — «арифметика внутри прохода» (render_step.dart:430–443): отключить да, заменить кривую — только своим `present`-узлом поверх | — | да (`FullscreenEffect.present`) | — |
| Upscale / FXAA+sharpen / high contrast / viewport shading | `frame@n` | свои пары якорей | откл. | — | да | — |
| UI/overlay / present | `frame` | `beforePresent` | — | `PassContributor.isOverlay` (contributor_registry.dart:50) | да | — |
| Readback/capture | `device.readback` (H/graphics_device.dart:442) из узла ✔; `FrameCapture` (R/frame_capture.dart:344) | — | — | — | — | — |
| Splats / voxels | `SplatContributor` (R/splat_contributor.dart), GPU-сорт только WebGPU (R/splat_sort_gpu.dart) | — | — | контрибьютор | — | движковый |

**Бэкенд (run vs build)** ✔ по `site/content/reference/material-language.md:191–205` и PR/data/material_wgsl.dart:67–90: Impeller — только build (bundle `extraBundles`/`device.loadShaders`, `gpu_device.dart:154,264`; `RuntimeShaders` отказывает: runtime_shaders.dart:260); WebGL2 — всё в runtime (GLSL, включая `light`, `vertex`, fullscreen); WebGPU — runtime только Unlit-splice (без `light`, `vertex`, `sceneDepth`), fullscreen да, compute нет; CPU — всё, включая `compute`. Для (d) на Impeller плагин **может** привезти готовый бандл и загрузить его в runtime (`LightingModelAddon.stagesFor`, R/lighting_model_addon.dart:72; `GpuLoadedShaderLibrary.load(..., running: runningSdk)` gpu_device.dart:264) — но бандл должен совпадать по SDK; build-hook пользователя не нужен (?: не проверял, что `impellerc`-бандл стороннего пакета принимается без доступа к `assets_src/`).

## B. Стабильность точек расширения

| Тип | Модификатор | в `.api` | Новые члены ломают? | Имена/коллизии | Версия | Conformance |
|---|---|---|---|---|---|---|
| `RenderNode`/`FrameGraphNode` (R/render_node.dart:217, frame_graph.dart:72) | `abstract base` с дефолтами | core.api ✔ | нет | `name` — строка; namespacing **не** проверяется, только дубликаты и `passOrder` (renderer_steps.dart:171–188) | нет | **нет** (plugin_checks.dart:22–27: manifest/switch/determinism/backends/budget/materials) |
| `PassContributor` (R/contributor_registry.dart:19) | `abstract base` | ✔ | нет | без имени; `order` int | нет | нет |
| `RenderStep` (render_step.dart:85) | `final` + public ctor | ✔ | — | `name` строка, без префикса; `switchOff/isOn` — замыкания над `RenderSettings` | нет | нет |
| `RenderAnchor` (P/render.dart:38) | `final`, `after` ctor | plugin_api.api ✔ | — | док обещает `<pluginId>.<name>` (:43), `addAnchor` **не проверяет** (renderer_steps.dart:238–267) | `PluginApiVersion` 1.0 (P/version.dart:28; major-match :52) | manifest only |
| `RenderStepAddon`/`LightingModelAddon` (R/render_step_addon.dart:33, lighting_model_addon.dart:48) | `abstract base` | ✔ | нет | `id` строка | manifest 1.0 | switch ✔ |
| `LightingModel`/`LightingModels` (F/lighting_model.dart:46,467) | `final` + `abstract final` | ✔ | — | `shaderName` глобальный, case-insensitive (:488–497), **процесс-глобальный** реестр, не namespaced; built-in защищены (:506) | нет | нет |
| `MaterialExpression`/`MaterialStatement` (F/material_language/material_ast.dart:631,736) | **`sealed`** | ✔ | плагин не может добавить выражение; новый узел ломает внешние `switch` | — | `materialLanguageVersion` 2 | — |
| `SettingsSlot` (R/settings_slots.dart:51) | `final` | ✔ | — | `id` строка, только дубликат (renderer_steps.dart:392) | JSON-кодек без версии | нет |
| `ResourceId` (frame_graph.dart:23) | extension type на String | ✔ | — | без namespace; `FrameResourceIds` фикс. | нет | нет |
| `ResourceDesc`/`ResourceSize` (R/resource_desc.dart:6,65) | `sealed` ResourceSize | ✔ | внешний `switch` сломается | — | — | — |
| `TextureFormat` (H/formats.dart:91) `final class`; `StorageMode/LoadAction/CullMode/…` — `enum` (H/formats.dart:71–739) | enum закрыты | ✔ | да для enum | — | — | — |
| `UniformBlock` (flutter3d_shaders) | abstract | ✔ | ? | имена блоков строки | — | — |
| `LightType` (…/scene/light_node.dart:27) | `final`, `custom(base:)` | ✔ | — | `name` строка; custom рисуется как base | — | — |
| `VertexLayoutDescriptor` (H/vertex_layout_spec.dart:236) | `final` | ✔ | — | — | — | — |
| `ShadowTechnique` (R/shadow_technique.dart:166) | `abstract base` | ✔ | нет | `name` | — | нет |
| `RenderServices`, `ContributorLights` (pass_contributor.dart:286,568) | `abstract base mixin` | ✔ | нет | — | — | — |
| `FormatRegistry` (P/formats.dart:32) | `base` | ✔ | — | **namespace enforced** `<pluginId>.` (:161) — единственный реестр, где это так | `FormatSpec.version` | manifest |

## C. Пробелы, блокирующие реальные плагины (по тяжести)

1. **Impeller без build-hook пользователя.** Lit-модель, `vertex`, `sceneDepth` плагина — только в бандле; `RuntimeShaders` отказывает (runtime_shaders.dart:260). Путь «плагин шлёт свой `.shaderbundle` и `device.loadShaders`» существует (lighting_model_addon.dart:72), но привязан к SDK (`running: runningSdk`, gpu_device.dart:264) и нигде в `site/content/reference/plugins.md` не описан; data-плагины на Impeller рендер не получают вовсе. Нет: публикуемого контракта «prebuilt bundle per plugin».
2. **Новая lit-модель с BRDF (hair/cloth/SSS).** Возможно через `.f3dmat light/ambient/composite` + `LightingModelAddon` (lighting_model_addon.dart:85). Не возможно: свои uniform-блоки/текстуры сверх 5 слотов (`texture` в surface — только слоты движка, material-language.md:45), свой G-buffer-канал, своя теневая выборка (shadow_technique.dart:150–157); WebGPU-runtime отказывает `light` (material_wgsl.dart:67). Нет: доп. сэмплеров/блоков в surface.
3. **Новый тип света (area/own falloff).** `LightType.custom` рисуется «как base» (light_node.dart:20–27); light-loop и список светов упакованы движком (`ContributorLights`, pass_contributor.dart:550–576). Нет: хука в light-loop/кластеризацию.
4. **Своя теневая техника.** Только каскады/параметры/префильтр-стадия (shadow_technique.dart:140–157); куб-атлас вне техники (:160); отключить `shadows` и нарисовать своё — нельзя подменить `shadow_map` «внутри» lit-стадий (они читают движковый сэмплер). Нет: подмены producer'а `shadow_map`.
5. **Пост-эффект с depth+velocity+history (TAA-like).** depth ✔ (`surface_buffer`), history ✔ (`keeps`+`provide`, frame_graph.dart:133; своя текстура через `device`), **velocity только при TAA/MB** (renderer_frame_nodes.dart:1982) — без них ресурс не производится и узел голодает (`starved`). `FrameContext` даёт jitter/текущие матрицы (render_node.dart:121–147), но **нет предыдущей view-projection** (`FrameHistory` — internal, frame_history.dart:316). Нет: `RenderStep.velocity` и prev-VP в контексте.
6. **Decal projector со своим материалом.** Нет: деcальная стадия фиксирована (renderer_decal_pass.dart:24–27), `DecalNode` без `LightingModel`.
7. **GPU-частицы (compute).** Возможно своим `RenderNode` (compute → `provideBuffer` → контрибьютор), только WebGPU/CPU; на Impeller/WebGL2 `refuse(DeviceFeature.compute)` (graphics_device.dart:498–504). `.f3dmat compute` — только CPU (material-language.md:172). Нет: bundle-раздел с compute для WebGPU.
8. **Новый vertex-атрибут/layout (wind weights).** Свой vertex-стейдж допустим (`vertexShaderName`, lighting_model.dart:287), но layout фиксирован «как объявляет стадия» (device_mesh.dart:61), instanced/lightmapped — только движковые стадии (:277–281, «gfx-84n» отложен). Нет: описания layout в `.f3dmat`/`LightingModel`.
9. **MRT/новый формат таргета.** Свой узел открывает свой pass (до `maxColorAttachments`, H/render_pass_descriptor.dart:503); движковый scene-pass MRT (3 attachments, frame_plan.dart:33–36) расширить нельзя. `ResourceDesc` плагин может `declare` только изнутри `execute` (frame_resources.dart:205 публичен, декларации движка в renderer.dart:5004–5104) — работает, но недокументировано (?).
10. **Per-view (стерео).** `FrameContext.view` — только первый view (render_node.dart:82–84); сцена рисует все views в одном проходе (renderer_frame_nodes.dart:736); планар/пробы «picture per view» внутри движка. Нет: view-index/список views в контексте, per-view ресурсы.
11. **Свой culling/sort.** `OcclusionTest` подключается (renderer.dart:1799); frustum/`RenderList`/`key_sort` закрыты; контрибьютор сортирует себя сам внутри `encode`. Нет: хука в построение `RenderList`.
12. **CPU readback прохода.** ✔ `device.readback` из узла (graphics_device.dart:442) + `declare reads`; `frame outputs` для внешнего чтения — только движковые.

## D. Семвер-риски

- `sealed MaterialExpression/MaterialStatement/ResourceSize` (material_ast.dart:631,736; resource_desc.dart:6) — любое расширение языка/размера ломает внешние `switch`; `enum StorageMode/LoadAction/CompareFunction/…` (formats.dart) в published `flutter3d_hardware` при открытой `TextureFormat` — непоследовательно.
- Строковые id без namespace: `RenderStep.name`, `RenderNode.name`, `SettingsSlot.id`, `ResourceId`, `LightingModel.shaderName` (case-insensitive!), `RenderAnchor.after` — коллизии двух плагинов выявляются только `ArgumentError` при install; только `FormatRegistry` держит `<pluginId>.` (formats.dart:161).
- `LightingModels` — статический реестр процесса (lighting_model.dart:468): два движка/изолята, hot-reload, тесты делят состояние.
- `RenderStep` с замыканиями `switchOff/isOn` над `RenderSettings` (render_step.dart:110–111): новое поле `RenderSettings` безопасно, но слот без кодека теряется в документе (settings_slots.dart:56).
- `static const` лимиты: `_DecalBatch.maxDecals=16` (renderer_decal_pass.dart:24), `materialDepthLayerLimit`, `ExposureMeter.size`, 8 lights в `ContributorLightInfo` (pass_contributor.dart:552) — расширяемы только мажором для шейдерного ABI.
- Nullable «unsupported»: `ContributorFrame.viewProjection/sceneDepth/lights` (pass_contributor.dart:399–429), `LightingModelAddon.stagesFor → null` = «бандл уже есть» (:72) — молчаливый путь.
- Дубли: `addContributor` vs `addNode` оставлены сознательно (tasks/1.0-api-review.md:729); `addMaterials` (registry) vs `extraBundles` (device) vs `LightingModelAddon.stagesFor` — три входа для стадий; `RenderStepAddon.provides` + `RenderSettings.without` — два способа «выключить».
- **`ShaderStageNeed` не существует в коде** ✔ (`rg` по lib: только в планах). Поддерживает выбор стадий сегодня: `LightingModel.uses*`-флаги (lighting_model.dart:289–385), `BundledMaterials.lighting` (material_bundle.dart:26–76), `RenderStep.passes`; ни один тип плагина не декларирует «мне нужны стадии X».
- `PassContributor.boundsFor/ContributorFrame`: есть `viewProjection` (jittered+reversed), `reversedDepth`, `origin`, `temporal`, `lights`, `sceneDepth`; **нет** view-index, prev-frame матриц, `jitter` у контрибьютора есть через `FrameContext.jitter` (render_node.dart:142), но нет TAA-истории.

## E. Полнота относительно ожиданий 1.0

- Mesh/model-форматы: ✔ `ModelDecoders`/`DecoderRegistry` (F/model_decoders.dart:97) + `FormatRegistry` (спеки, не декодеры).
- Texture-кодеки: **нет** реестра (grep `Codec|Decoder Registry` — только model_decoders); KTX2/Basis зашиты.
- Culling: только `OcclusionTest`; LOD: `LodGroup`/`LodLevel` данные (scene/lod_group.dart:14,55), политики выбора нет; skinning: `SkinBlend` закрыт (animation/skin_blend.dart:26), кастомного скиннинга нет (только свой vertex-стейдж, без instanced).
- Frame pacing: `FramePacing` `final` (frame_pacing.dart:32), события `FramePipelineStall` (:158) — наблюдать да, хука нет; `AdaptiveQuality` `final` (:134).
- **Wasm-плагины рендера не достигают**: ABI — `f3d_abi`, `f3d_step` + `field_len/get/set/publish/field_frac` (PR/wasm/abi.dart:57–61, module.dart:470) — только данные/симуляция. Data-плагины (`.f3dplugin`) дают `materials` и `renderSteps` = fullscreen по якорю (PR/data/data_plugin.dart:96–130; runtime_shaders.dart:473–521), ничего больше (ни контрибьюторов, ни compute, ни lit на WebGPU/Impeller).
- Conformance не проверяет ничего рендерного (plugin_checks.dart:22–27); шаблон `create plugin --kind render-step|effect` (plugin_template.dart:32,39) существует.

Итог: каркас кадра (якоря/узлы/ресурсы/версии) ✔ зрелый и единообразный; реальные дыры 1.0 — Impeller-runtime, surface-материалы без своих слотов, velocity-зависимость от TAA, per-view контекст, отсутствие namespace-дисциплины и `ShaderStageNeed`, рендер недоступен Wasm.
