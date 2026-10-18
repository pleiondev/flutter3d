# Небольшие 3D-движки и HAL 2024–2026 рядом с flutter3d

Дата: 2026-10-17. Исходники читались через `gh api` (HEAD на дату отчёта), ничего не клонировалось и не запускалось.
Пути flutter3d даны относительно `/Users/dmitrii/flutter3d`. Звёзды и даты взяты из GitHub API.

Отбор: проект живой (push в 2026, большинство заметно развивалось в 2024–2026), меньше ~3k звёзд, в коде есть
настоящий HAL, плагинная модель или и то и другое. Из выдачи `gh search repos` отброшены шумные результаты
(LLM-движки, UI-фреймворки, «3D-движки» на CSS) и учебные проекты без абстракции над API.

Оговорка: SpartanEngine (3.2k), TypeGPU (3.3k), mach (4.9k) и zig-gamedev (2.9k, последний push в марте) не попали
в выборку из-за порога по звёздам или из-за активности.

## 1. Сводная таблица

| Движок | Репозиторий | ★ | Последний push | Создан | Язык | Бэкенды | Стиль HAL | Плагины | Лицензия |
|---|---|---|---|---|---|---|---|---|---|
| blade | https://github.com/kvark/blade | 810 | 2026-10-16 | 2022-11 | Rust | Vulkan, Metal, GLES/WebGL | тонкие трейты, bind groups *по именам полей* (`#[derive(ShaderData)]`), авто-барьер на границе прохода (или `manual_barriers`) | нет (крейты) | MIT |
| renderling | https://github.com/schell/renderling | 250 | 2026-10-11 | 2022-02 | Rust | wgpu | своего HAL нет; GPU-driven «slab» (всё в storage-буферах), шейдеры на Rust (rust-gpu) | нет | MIT/Apache-2.0 |
| myth | https://github.com/panxinmiao/myth | 222 | 2026-10-12 | 2026-01 | Rust | wgpu (native+wasm) | своего HAL нет; сильный декларативный render graph (SSA-версии, cull, алиасинг, Mermaid-дамп) | нет (closures `SceneLogic`, Python-биндинги) | Apache-2.0 |
| rivet-engine | https://github.com/wrapperup/rivet-engine | 110 | 2026-10-17 | 2025-09 | Odin | Vulkan | процедурная обёртка, полный bindless + BDA + push constants, ручные барьеры | нет; livepatch кода, AST-метапрограмма | MIT |
| delve-framework | https://github.com/Interrupt/delve-framework | 341 | 2026-08-11 | 2023-12 | Zig | sokol_gfx (GL/GLES/D3D11/Metal/WebGPU) + null + headless | immediate поверх sokol, uniform-блоки по имени через ручную таблицу | модули жизненного цикла + Lua (биндинги comptime-рефлексией) | MIT |
| slang-rhi | https://github.com/shader-slang/slang-rhi | 213 | 2026-10-16 | 2024-08 | C++ | D3D11, D3D12, Vulkan, Metal, CUDA, WGPU, CPU (compute) | WebGPU-образные encoders; биндинг через иерархический `ShaderCursor` по именам рефлексии + bindless-хэндлы; авто-трекинг состояний | нет (флаги сборки) | Apache-2.0 + LLVM exc. |
| LLGL | https://github.com/LukasBanana/LLGL | 2640 | 2026-10-17 | 2016-07 | C++ | GL/GLES/WebGL, D3D11, D3D12, Vulkan, Metal, Null | D3D11-образный; гибрид heap + индексы + именованные uniforms, DSL лэйаута | бэкенды — динамические модули с проверкой build ID | BSD-3 |
| kohi | https://github.com/travisvroman/kohi | 1517 | 2026-10-16 | 2021-02 | C | Vulkan | высокоуровневый stateful, binding sets по индексу | бэкенд рендера и аудио — `.so/.dll` по имени из конфига; hot reload игровой библиотеки | Apache-2.0 |
| lightweightvk | https://github.com/corporateshark/lightweightvk | 486 | 2026-10-17 | 2023-07 | C++ | Vulkan (MoltenVK, Android) | полный bindless, поколенческие хэндлы + `Holder`, барьеры по зависимостям, объявленным при открытии прохода | нет | MIT |
| NRI | https://github.com/NVIDIA-RTX/NRI | 487 | 2026-10-09 | 2021-09 | C++/C | D3D11, D3D12, Vulkan, Metal, WGPU, NONE | «Graphics API, not RHI»: descriptor sets + root constants + DescriptorHeap-bindless, ручные барьеры; интерфейсы-расширения по имени | нет | MIT |
| LuminaEngine | https://github.com/MrDrElliot/LuminaEngine | 550 | 2026-10-17 | 2024-11 | C++ / C# | Vulkan (Metal/DX12 — TODO) | «GPU-pointer» RHI: `Malloc` → GPU-адреса, bindless texture heap, ручные барьеры | `.lplugin` JSON (deps, фазы загрузки, платформы), DLL с ABI-подписью и BuildId, C#-скрипты с hot reload | Apache-2.0 |
| luma.gl | https://github.com/visgl/luma.gl | 2483 | 2026-10-16 | 2016-01 (v9 — переписан под WebGPU) | TypeScript | WebGL2, WebGPU, null | WebGPU-образный `Device`; биндинги по имени, bind groups строит фабрика внизу | шейдерные модули/плагины (compile-time) | MIT |
| kool | https://github.com/kool-engine/kool | 592 | 2026-10-12 | 2017-02 | Kotlin MPP | Vulkan, GL/GLES, WebGL2, WebGPU, wgpu4k | высокоуровневый `RenderBackend.renderFrame`; три bind group по частоте (VIEW/PIPELINE/MESH); шейдеры на Kotlin-DSL (KSL) | нет; hot reload игрового кода в редакторе | Apache-2.0 |
| Ada | https://github.com/AdaEngine/Ada | 228 | 2026-10-17 | 2021-08 | Swift | Metal, WebGPU (wgpu), OpenGL, Headless | Metal-образный, слоты + `RenderResourceSet`; render graph в стиле Bevy с диагностикой | `protocol Plugin` (compile-time) + AdaScript с `@access(read:,write:)` и транзакционным hot reload | MIT |
| flutter_scene | https://github.com/bdero/flutter_scene | 955 | 2026-10-15 | 2024-02 | Dart | Impeller (flutter_gpu), WebGL2, WebGPU | повтор поверхности flutter_gpu, слоты по имени; минимальный render graph с наблюдателем | пакеты + JSON-манифест компонентов из codegen; MCP для редактора | MIT |
| estella | https://github.com/esengine/estella | 693 | 2026-10-17 | 2026-01 | TS + C++/Wasm | WebGL2/GLES, WebGPU | GL-образный `GfxDevice`; реестр ресурсов с пересозданием после потери устройства; render graph с отсечением | TS-плагины Bevy-стиля с детектором неоднозначного порядка; нативные side-modules (.wasm); AOT TS→C→wasm с ABI-хэшем | Apache-2.0 |

Для сравнения flutter3d: Impeller (flutter_gpu), WebGL2, WebGPU, CPU-растеризатор и compute-only сайдкар на wgpu-native;
HAL с привязкой слотов по имени и рефлексией, без bind groups и bindless; frame graph с ~50 якорями; плагины
compile-time (build hook) плюс рантайм (JSON, Wasm-интерпретатор, expression systems); лицензия MIT.

## 2. По поверхностям

### 2.1 HAL

**Что у flutter3d.** `abstract base class GraphicsDevice` с телами по умолчанию, бросающими
`UnsupportedCapabilityException` (`packages/flutter3d_hardware/lib/src/graphics_device.dart:93`);
`DeviceFeature` — открытый value-класс с `name` и `FeatureStability` (stable/reserved), `byName`
(`packages/flutter3d_hardware/lib/src/capabilities.dart:39`, `:89`, `:850`); `DeviceFeatures`/`DeviceLimits` (`:864`, `:955`);
`PassEncoder` (`packages/flutter3d_hardware/lib/src/command_encoder.dart:125`) с `bindUniformBlock(shader, blockName, Map<String,Float32List>)`
(`:361`) и `bindTexture(shader, slot, …)` (`:398`), оба возвращают bool; `PassState` для Vulkan-образных бэкендов
(`packages/flutter3d_hardware/lib/src/pass_state.dart:62`); `DeviceRegistry` (`packages/flutter3d_hardware/lib/src/device_registry.dart:259`);
`RecordingDevice` + TraceEvent (`packages/flutter3d_hardware/lib/src/trace/recording_device.dart:40`);
`GraphicsDevice.lost` (`graphics_device.dart:1024`); снимок API `packages/flutter3d_hardware/api/flutter3d_hardware.api`.

**Модели привязки ресурсов у соседей.** Их пять:

1. *По именам через рефлексию* — flutter3d, flutter_scene, estella, delve; иерархический вариант у slang-rhi
   (`cursor["material"]["albedo"].setBinding(tex)`,
   https://github.com/shader-slang/slang-rhi/blob/HEAD/include/slang-rhi/shader-cursor.h#L56-L125).
2. *Bind groups, но связанные с именами*: blade выводит лэйаут из Rust-структуры через `#[derive(ShaderData)]`,
   номера `@group/@binding` в WGSL не пишутся вообще, размер хост-структуры сверяется с шейдером при создании пайплайна
   (https://github.com/kvark/blade/blob/HEAD/blade-graphics/src/shader.rs#L561-L600). luma.gl принимает
   `Record<string, Binding>` и строит bind group фабрикой с кэшем только на WebGPU
   (https://github.com/visgl/luma.gl/blob/HEAD/modules/core/src/api/factories/bind-group-factory.ts#L26-L104).
3. *Фиксированные группы по частоте*: kool — ровно `VIEW / PIPELINE / MESH`, лэйаут выводится из шейдерного DSL
   (https://github.com/kool-engine/kool/blob/HEAD/kool-core/src/commonMain/kotlin/de/fabmax/kool/pipeline/BindGroupLayout.kt#L41-L66).
4. *Descriptor sets + root constants*: NRI, kohi, LLGL (гибрид, с DSL `LLGL::Parse("heap{cbuffer(Scene@0):frag:vert}")`,
   https://github.com/LukasBanana/LLGL/blob/HEAD/include/LLGL/Utils/Parse.h#L144-L146).
5. *Полный bindless + адреса буферов*: lightweightvk, rivet, LuminaEngine (`RHI::Malloc` возвращает GPU-указатель,
   https://github.com/MrDrElliot/LuminaEngine/blob/HEAD/Engine/Source/Runtime/Source/Renderer/RHI.h#L650-L651).

Вывод для flutter3d: выбранная модель (имена + рефлексия, bool на отсутствующий слот) встречается часто и совместима
с WebGL2 и Impeller, где bind groups нет. Если когда-нибудь понадобится WebGPU-путь без накладных расходов,
blade, luma и kool показывают, как строить группы под тем же API по именам.

**Что соседи делают лучше или иначе.**

- *Типизированный, проверяемый uniform-блок.* Blade ловит несовпадение размера хост-структуры и шейдера при создании
  пайплайна; rivet генерирует общие CPU/GPU-структуры из одного описания и отдельно запрещает голые id в GPU-структурах
  (https://github.com/wrapperup/rivet-engine/blob/HEAD/meta/meta.odin#L43-L46). У flutter3d есть
  `UniformBlock` из `flutter3d_shaders` с layout из рефлексии, но `bindUniformBlock` принимает `Map<String,Float32List>`
  и узнаёт об ошибке в рантайме.
- *Маскирование фич реального устройства.* LuminaEngine: `FDeviceDesc.DisabledFeatures` выключает поддерживаемую фичу,
  чтобы прогнать fallback на сильном железе
  (https://github.com/MrDrElliot/LuminaEngine/blob/HEAD/Engine/Source/Runtime/Source/Renderer/RHI.h#L495-L527);
  luma.gl — `disabledFeatures` (https://github.com/visgl/luma.gl/blob/HEAD/modules/core/src/api/adapter/device.ts#L261-L280).
  В flutter3d такого нет (поиск по `disabledFeatures|maskFeatures|withoutFeatures` пуст): у `FakeBackend` есть `extraFeatures`
  (`packages/flutter3d_hardware/lib/src/testing_fake_backend.dart:158`), но не маска поверх живого бэкенда.
- *Адаптер против устройства.* myth хранит отдельно «поддерживает адаптер» и «включено на устройстве»
  (https://github.com/panxinmiao/myth/blob/HEAD/crates/myth_render/src/core/context.rs#L36-L75); blade даёт
  `DeviceReport` с `Rejected(reason)` по каждому адаптеру
  (https://github.com/kvark/blade/blob/HEAD/blade-graphics/src/lib.rs#L324-L380). В `DeviceRegistry` flutter3d отчёта
  об отброшенных бэкендах и адаптерах с причиной нет.
- *Восстановление после потери устройства.* estella держит реестр ресурсов HAL, где id никогда не переиспользуются, а
  описание и данные каждого объекта позволяют пересоздать его на новом устройстве
  (https://github.com/esengine/estella/blob/HEAD/src/esengine/renderer/rhi/GfxResourceRegistry.hpp#L5-L170).
  flutter3d сообщает о потере (`GraphicsDevice.lost`, `packages/flutter3d_webgl/lib/src/webgl_device.dart:331`), но
  «every handle is spent», рендерер пересобирается целиком. Половина нужного реестра уже есть в RecordingDevice.
- *Опциональные подсистемы как отдельные интерфейсы.* NRI получает расширения по имени, а размер структуры служит
  версией (https://github.com/NVIDIA-RTX/NRI/blob/HEAD/Include/NRI.h#L52-L53). flutter3d делает почти так же для
  нескольких «capabilities-as-types» (`RenderBundleEncoder`, `EncodedImageUpload`, `SynchronousBufferReadback`,
  см. `packages/flutter3d_hardware/README.md:40`), остальное растёт методами `GraphicsDevice` с телом-отказом. Для
  ray tracing или mesh shaders паттерн `device.extension<T>()` удержит базовый класс от разрастания.
- *Барьеры.* Для будущего Vulkan-образного бэкенда (то, ради чего есть `PassState`) есть три проверенные схемы:
  автотрекинг состояний (slang-rhi,
  https://github.com/shader-slang/slang-rhi/blob/HEAD/include/slang-rhi.h#L2952-L2960); зависимости, объявленные при
  открытии прохода (lightweightvk, https://github.com/corporateshark/lightweightvk/blob/HEAD/lvk/LVK.h#L1194-L1212);
  глобальный барьер на границе прохода с опцией `manual_barriers` (blade,
  https://github.com/kvark/blade/blob/HEAD/docs/synchronization.md). Вариант LVK лучше всего ложится на frame graph
  flutter3d, где узлы и так объявляют чтения.
- *Валидирующая обёртка.* LLGL (`DbgRenderSystem`), NRI (`Source/Validation`) и slang-rhi (debug layer) оборачивают
  любой бэкенд проверками протокола. У flutter3d проверки разбросаны по бэкендам (`debugCheckLive`, `debugDrainErrors`,
  `FakeBackend.bindingViolations`). Общий `ValidatingDevice` поверх `GraphicsDevice` по образцу `RecordingDevice`
  вынес бы их в одно место.
- *Негативный контроль в тестах.* LuminaEngine: `RHI_TEST_EXPECT_VALIDATION` проходит только если слой валидации
  что-то сообщил, иначе харнесс, переставший видеть ошибки, тихо зеленеет
  (https://github.com/MrDrElliot/LuminaEngine/blob/HEAD/Engine/Applications/RHITests/Source/RHITestHarness.h#L115-L128).
  У flutter3d есть `refusal_checks.dart` и отрицательная половина `capabilityChecks`, то есть идея наполовину реализована;
  не хватает проверки, что сам канал ошибок (`debugDrainErrors`) живой.
- *Тест × бэкенд как атрибут теста.* slang-rhi: `GPU_TEST_CASE(name, D3D12|Vulkan|CPU)`
  (https://github.com/shader-slang/slang-rhi/blob/HEAD/tests/testing.h#L437-L541). Сопоставимо с
  `coreChecks/shaderChecks/computeChecks` во flutter3d, только объявление ближе к тесту.
- *Пустой null-бэкенд.* LLGL, NRI, delve, luma, Ada. У flutter3d вместо этого CPU-растеризатор и `FakeBackend`, что
  сильнее; null-девайс пригодился бы разве что серверу, где даже CPU-растеризатор лишний. NRI-шный NONE при этом
  нарочно сообщает максимальные лимиты, то есть врёт; capabilityChecks такого не пропустили бы.

**Где flutter3d впереди (проверено в дереве).**

- Проверка устройства по его собственному отчёту в обе стороны и `unprobedFeatures` с причиной
  (`packages/flutter3d_conformance/lib/src/capability_checks.dart:46`) не встретились ни у одного из 16 проектов.
  Ближе всех luma.gl, у которой одни и те же спеки идут на WebGL и WebGPU, но без сверки с отчётом.
- Независимо написанный CPU-растеризатор как эталон для голденов. У остальных голдены на каждый бэкенд свои
  (LLGL, lightweightvk на lavapipe), а у slang-rhi CPU-бэкенд умеет только compute.
- Запись и воспроизведение вызовов (`RecordingDevice`) и снимок публичного API с проверкой semver есть только у
  flutter3d.
- Стабильность фич как часть типа (`FeatureStability.stable/reserved`, `capabilities.dart:39`). «Honesty tiers» в дереве так
  не называются, ближайшее — `FeatureStability`, правило «отказ, а не подмена» и `refusal_checks.dart`.
- Явный текст семантики, которую не видно по сигнатурам (ARCHITECTURE.md §7.2), подробнее, чем у любого из соседей;
  ближайший аналог — `docs/synchronization.md` в blade.

### 2.2 Публичный API (сцена, рендер-граф, цикл)

**Что у flutter3d.** Императивное ядро `Scene`/`SceneNode` (`packages/flutter3d_core/lib/src/engine/scene/scene.dart:33`,
`scene_node.dart:33`), декларативные виджеты `Scene3D`/`Node3D`
(`packages/flutter3d_app/lib/src/declarative/scene_widgets.dart:179`, `:615`), `Flutter3dView`
(`packages/flutter3d_app/lib/src/view/flutter3d_view.dart:324`); frame graph с версиями ресурсов, отсечением и
алиасингом (`packages/flutter3d_core/lib/src/engine/render/frame_graph_compile.dart:26`, `frame_graph.dart:199`),
якоря плагинов (`packages/flutter3d_plugin_api/lib/src/render.dart:38`), `FrameResult.skipped`; симуляция — ECS с
поколенческим `Entity` (`packages/flutter3d_plugin_api/lib/src/ecs.dart:34`, `SimWorld` `:437`), `EngineLoop`
(`packages/flutter3d_sim/lib/src/loop/engine_loop.dart:102`), системы `addSystem(name, phase, fn, after:, before:)`
(`packages/flutter3d_plugin_api/lib/src/loop.dart:257`); виджет Flutter как поверхность в сцене
(`packages/flutter3d_app/lib/src/widget_surface/widget_surface.dart:19`).

**Что соседи делают лучше или иначе.**

- *Дамп и наблюдение графа кадра.* myth выводит граф в Mermaid с отдельным стилем мёртвых проходов и даёт
  подробную диагностику попытки кадра
  (https://github.com/panxinmiao/myth/blob/HEAD/crates/myth_render/src/graph/core/graph.rs#L3754-L3778);
  Ada сохраняет снимки графа и записи по кадрам в Codable со списком issues по severity
  (https://github.com/AdaEngine/Ada/blob/HEAD/Sources/AdaRender/RenderGraph/RenderGraphDiagnostics.swift#L175-L227);
  flutter_scene пишет в кадре захвата каждое чтение и запись в blackboard, каждый transient и CPU-время пасса, а в
  обычном кадре ничего не стоит
  (https://github.com/bdero/flutter_scene/blob/HEAD/packages/flutter_scene/lib/src/render/render_graph.dart#L356-L468).
  У flutter3d есть `FrameResult.skipped` с причинами, но сериализации графа (Mermaid/DOT/JSON) в `frame_graph*.dart` нет.
- *Детектор неоднозначного порядка систем.* estella выводит, что система читает и пишет, из `Query(Mut(T))`/`Res(T)` и
  находит пары, где одна пишет то, что читает другая, а порядок никто не задал
  (https://github.com/esengine/estella/blob/HEAD/sdk/src/app/ambiguity.ts). Ada делает похожее через `SystemAccessSet`.
  `LoopSystem` во flutter3d — `void Function(LoopContext)` (`loop.dart:219`) без объявления доступа, порядок внутри фазы
  задают только регистрация и after/before. Для движка, который обещает бит-в-бит повторы, неявный порядок — тихий
  источник расхождения; есть рантайм-страховка (double-step check в `engine_loop.dart`), но статической нет.
- *Журнал мутаций сцены с курсором.* myth: `render_mutations()` / `acknowledge_render_mutations(cursor)` — рендер
  забирает дельты вместо обхода (https://github.com/panxinmiao/myth/blob/HEAD/crates/myth_scene/src/scene.rs#L560-L620).
  У flutter3d «versions instead of dirty flags» (ARCHITECTURE.md §5.2), что решает ту же задачу иначе; журнал полезен
  разве что для сетевой репликации и редактора.
- *Шейдерные плагины, дописывающие материал.* luma.gl: `ShaderPlugin` объявляет modules, defines, inject-хуки, varyings и
  vertexInputs, сборщик вписывает их в шейдер
  (https://github.com/visgl/luma.gl/blob/HEAD/modules/shadertools/src/lib/shader-plugin.ts#L48-L91). У flutter3d плагин
  может добавить проход у якоря и модель освещения (`LightingModels`), но вклиниться в существующий материал
  (добавить varying в меш-шейдер) нельзя.
- *Doc-тесты как контракт.* renderling запускает README-пример headless в тестах. Для flutter3d это пример `Scene3D`
  из README на CPU-бэкенде.
- *Шейдерный код на CPU в юнит-тестах.* renderling исполняет те же функции шейдера на CPU (rust-gpu). flutter3d уже
  имеет Dart-зеркала стадий для CPU-растеризатора; не хватает точечных тестов «функция BRDF/tonemap в GLSL = Dart»
  по числам, а не по картинке.

**Где flutter3d впереди.** Модель вставки проходов (≈50 якорей + after/before + `RenderStep` с переключением и отчётом)
богаче всех: у myth 2–3 `HookStage`, у flutter_scene 4 `RenderStage`, у estella плагины по типам отрисовки. Детерминизм
(`Portable` math — `packages/flutter3d_foundation/lib/src/portable_math.dart:89`, линты, повторы) не встретился ни
у кого из 16. Виджет как поверхность в сцене есть и у flutter_scene, так что это паритет, а не отставание.

### 2.3 Plugin API

**Что у flutter3d.** `Flutter3dPlugin { manifest; install(host) }`
(`packages/flutter3d_plugin_api/lib/src/manifest.dart:573`), манифест с `touches` и `permissions` (`:28`, `:86`, `:136`),
`PluginManager` с порядком зависимостей и переключением на границе шага (`packages/flutter3d_plugin_api/lib/src/manager.dart:75`,
`enable` `:309`, `disable` `:339`); discovery через pubspec и build hook (`packages/flutter3d_build/lib/src/plugin_discovery.dart`);
рантайм: `DataPluginLoader` (`packages/flutter3d_plugin_runtime/lib/src/data/data_plugin.dart:623`), `PluginGrants`
(`packages/flutter3d_plugin_runtime/lib/src/permissions.dart:20`), Wasm-интерпретатор с топливом
(`packages/flutter3d_plugin_runtime/lib/src/wasm/interpreter.dart:23`), ABI 1 (`wasm/abi.dart:19`), Q16.16
(`packages/flutter3d_plugin_runtime/lib/src/world_fields.dart:164`); конформанс плагина — 7 проверок
(`packages/flutter3d_conformance/lib/src/plugins/plugin_checks.dart:21`: manifest, switch, names, determinism, backends,
budget, materials). ARCHITECTURE.md §12.1 до сих пор говорит «runs five checks»: текст отстал от кода.

**Модели у соседей.**

- Compile-time с порядком: Ada (`protocol Plugin`, https://github.com/AdaEngine/Ada/blob/HEAD/Sources/AdaApp/AppBuilder.swift#L488-L507),
  estella (`Plugin { dependencies, before, after, build, finish, cleanup }`, при падении `build` его системы снимаются,
  https://github.com/esengine/estella/blob/HEAD/sdk/src/app/app.ts#L78-L365), delve (модули с приоритетом,
  https://github.com/Interrupt/delve-framework/blob/HEAD/src/framework/modules.zig#L25-L90).
- Динамические библиотеки: LLGL (бэкенд как модуль, отказ при несовпадении build ID,
  https://github.com/LukasBanana/LLGL/blob/HEAD/sources/Renderer/ModuleInterface.h#L13-L39); kohi (бэкенд по имени из
  конфига, ABI не проверяется,
  https://github.com/travisvroman/kohi/blob/HEAD/kohi.runtime/src/systems/plugin_system.c#L216-L297; там же
  баг — проверяется `kplugin_render`, а вызывается `kplugin_on_window_resized`, L203–L213); LuminaEngine (`.lplugin` JSON
  с Dependencies, LoadingPhase, SupportedPlatforms, EditorOnly; DLL с `LuminaModuleABISignature` и BuildId,
  https://github.com/MrDrElliot/LuminaEngine/blob/HEAD/Engine/Plugins/DLSS/DLSS.lplugin,
  https://github.com/MrDrElliot/LuminaEngine/blob/HEAD/Engine/Source/Runtime/Source/Core/Module/ModuleManager.cpp#L146-L170).
- Wasm: estella — нативные side-modules и AOT-компилятор подмножества TS → C → wasm/dll, где `Module::open` сверяет
  `es_abi_hash` и ширину адреса, в ABI-заголовке `FP_CONTRACT OFF`, а простой интерпретатор служит третьим оракулом
  (https://github.com/esengine/estella/blob/HEAD/src/esengine/aot/AotModule.hpp#L3-L66,
  https://github.com/esengine/estella/blob/HEAD/compiler/src/interp.ts). Песочницы и прав нет.
- Скрипты: delve — Lua с биндингами из comptime-рефлексии
  (https://github.com/Interrupt/delve-framework/blob/HEAD/src/framework/scripting/binder.zig#L1-L110); Ada — AdaScript,
  где система объявляет `@access(read:, write:)` и получает фасад мира, а рантайм отклоняет необъявленный доступ
  (https://github.com/AdaEngine/Ada/blob/HEAD/Documentation/ArchitectureDecisions/0004-ada-script-world-capabilities.md),
  hot reload транзакционный, по «поколениям модулей», с откатом
  (https://github.com/AdaEngine/Ada/blob/HEAD/Documentation/ArchitectureDecisions/0007-ada-script-runtime-and-hot-reload.md),
  для скачанного кода — бюджет чекпоинтов плюс дедлайн 0.05 с по часам
  (https://github.com/AdaEngine/Ada/blob/HEAD/Sources/AdaScripting/AdaScriptCommunityPolicy.swift); LuminaEngine — C# с
  hot reload; kool — пересборка игрового кода и новый `URLClassLoader` в редакторе.
- Манифест для редактора: flutter_scene генерирует `flutter_scene_components.json` со схемами компонентов, чтобы
  редактор видел типы без компиляции
  (https://github.com/bdero/flutter_scene/blob/HEAD/packages/flutter_scene_codegen/lib/src/manifest.dart).

**Что взять.**

- *Объявленный доступ системы к миру.* Wasm-модуль flutter3d и так объявляет поля, которые читает и пишет (индексы в
  декларации модуля), а expression systems — тоже. Compile-time Dart-системы не объявляют ничего. Если дать
  `addSystem` необязательные `reads:`/`writes:` (компоненты или поля), появятся и детектор неоднозначного порядка, и
  проверка в рантайме в debug-сборке, как у Ada.
- *Транзакционная перезагрузка рантайм-плагинов.* Переключение на границе шага во flutter3d уже есть и журналируется;
  не хватает «загрузи новую версию модуля, при ошибке оставь старую» и карантина упавшей системы. Трап Wasm уже
  латчит систему и пишет `WasmTrapped` в состояние, это хорошая основа.
- *Хэш ABI в Wasm-модуле.* Сейчас модуль экспортирует `f3d_abi` (номер). Хэш набора импортов и их сигнатур, как у
  estella, ловит модуль, собранный против другой ревизии того же номера ABI.
- *Фазы загрузки и платформы в манифесте* (LuminaEngine). У flutter3d есть `backends` и `touches`; `editorOnly` и
  платформы пригодятся, когда в каталоге появятся плагины редактора.
- *Третий оракул для Wasm и выражений.* У flutter3d два исполнителя Wasm — свой интерпретатор и браузерный — и
  conformance детерминизма плагина. Прогон каждой фичи ABI на обоих с побитовым сравнением (как `conformance.test.ts`
  у estella) закрепил бы обещание «один ответ везде».

**Где flutter3d впереди.** Ни у одного из 16 нет одновременно манифеста с правами, enforced в загрузчике, детерминированного
бюджета (топливо считается в инструкциях; у Ada — часы, у estella нет песочницы), журналируемого включения и выключения,
которое повтор воспроизводит на том же шаге, и конформанса плагина с бейджем. Ближе всех по манифесту LuminaEngine
(зависимости, фазы, ABI-подпись), но без прав и изоляции, и с поведением «при цикле залогировать и загрузить в
порядке обнаружения», где flutter3d называет цикл и отказывает.

## 3. Пять идей, ранжированных по пользе

1. **Объявленный доступ систем и детектор неоднозначного порядка** (estella, Ada). Необязательные `reads:`/`writes:` у
   `LoopRegistry.addSystem` (`packages/flutter3d_plugin_api/lib/src/loop.dart:257`), проверка в debug и статическая
   проверка пар «пишет — читает без порядка» при компиляции цикла. Прямо защищает главное обещание движка —
   повторы бит в бит — и добавляется без слома API (параметры с дефолтом). Кандидат в 1.x minor.
2. **Маска фич поверх живого устройства** (LuminaEngine, luma.gl). `DeviceRegistry.open(..., withoutFeatures: {...})` или
   обёртка-девайс, которая убирает фичи из `features` и отказывает в их вызовах. Позволяет гонять fallback-ветки
   рендерера (без compute, без render bundles, без float-фильтрации) и `capabilityChecks` на одной машине, на любом
   бэкенде. Дёшево, ложится на существующую модель отказов; полезно до 1.0.
3. **Сериализация и наблюдатель frame graph** (myth, Ada, flutter_scene). JSON/Mermaid-снимок скомпилированного графа
   (узлы, версии ресурсов, отсечённые и пропущенные с причинами из `FrameResult.skipped`, алиасы) плюс наблюдатель для
   кадра захвата. Нужен редактору, баг-репортам и голден-тестам структуры графа (сейчас
   `render_anchors_test.dart` держит порядок 244 кадров своими средствами).
4. **Типизированный uniform-блок с проверкой при сборке** (blade, rivet). Сверка `UniformBlock`, сгенерированного
   `flutter3d_shaders`, с рефлексией каждой стадии на этапе build hook и пункт конформанса «размер и смещения хоста =
   шейдер». Закрывает класс ошибок из ARCHITECTURE.md §7.3 («member names are the sharp edge and fail silently»).
   После 1.0, потому что затрагивает генератор и, возможно, сигнатуры.
5. **Реестр ресурсов для восстановления после потери устройства** (estella). Опираясь на трассу создания ресурсов, которую
   уже пишет `RecordingDevice`, пересоздавать текстуры, буферы и пайплайны после `DeviceLoss.restored` вместо пересборки
   рендерера. Важнее всего для WebGL2 на мобильных браузерах. Большая работа, после 1.0.

Следом в очереди: зависимости прохода, объявленные при открытии, для будущего Vulkan-образного бэкенда (lightweightvk);
`ValidatingDevice` как обёртка (LLGL/NRI); интерфейсы-расширения `device.extension<T>()` для ray tracing и mesh shaders (NRI);
отчёт об отброшенных бэкендах и адаптерах с причиной (blade); хэш ABI для Wasm-модулей (estella); шейдерные плагины,
дописывающие varyings в материал (luma.gl).

## 4. Попутно найденное в дереве flutter3d

- ARCHITECTURE.md §12.1 («`package:flutter3d_conformance/plugins.dart` runs five checks») расходится с
  `plugin_checks.dart:21`, где проверок семь (добавлены `plugin.names` и `plugin.materials`).
- В задаче HAL назван `flutter3d_core`; фактически контракт бэкенда лежит в `packages/flutter3d_hardware`.
