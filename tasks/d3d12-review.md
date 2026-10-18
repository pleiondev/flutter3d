# Direct3D как стандарт для HAL flutter3d: карта, пробелы, маршруты, рекомендация

Дата: 2026-10-17. Ветка `1.0.0`. Репозиторий не менялся.

HAL живёт не в `flutter3d_core`, а в `packages/flutter3d_hardware` (структурное
правило «the engine names no backend»: core зависит только от него). Главный
документ: `packages/flutter3d_hardware/HAL.md` (1561 строка), снимок API в
`packages/flutter3d_hardware/api/flutter3d_hardware.api`. Пути ниже даны
относительно `packages/flutter3d_hardware/lib/src/`, если не сказано иное.

## 0. Состояние D3D12 на октябрь 2026 (по вебу)

- **Agility SDK**: последний retail 1.619.6 (14.09.2026; первая 1.619 вышла
  26.02.2026). В ней Shader Model 6.9 в retail: SER и Opacity Micromaps (DXR 1.2),
  длинные векторы, обязательные 16/64-битные операции и wave-операции,
  пересмотренные API создания view, CPU timeline query. Последний preview
  1.721.3 (30.07.2026): LinAlg, Partial Programs, GUID Texture Layout, UAV
  глубины. SM 6.10 (linear algebra) в preview 1.720 + DXC 1.10.2605.
- **Enhanced barriers**: retail с 1.608.0 (ноябрь 2022). Это модель Vulkan-подобных
  layouts/sync/access вместо legacy resource states. **Fence barriers**: preview
  1.719 (февраль 2026).
- **Work graphs**: retail с 1.613.0 (март 2024). **Mesh nodes** в work graphs до
  сих пор только preview (1.715, Developer Mode).
- **DXIL → SPIR-V**: Microsoft в 2024 объявила, что Shader Model 7 примет SPIR-V
  как формат обмена (плюс трансляторы DXIL↔SPIR-V). Публичных сроков SM7 на
  2026 не нашёл.
- **Flutter на Windows**: по вторичным источникам Flutter 3.47 (август 2026)
  сделал Impeller рендерером по умолчанию на десктопе, на Windows через
  **Vulkan**. Официальным release notes это не сверено. Исторически Windows-эмбеддер
  шёл через ANGLE (GLES поверх D3D11). В `SUPPORT.md:32` для Windows стоят
  «Impeller (Vulkan) Best effort, Impeller (OpenGL ES) Best effort».

## 1. Карта понятий D3D12 → HAL flutter3d

| Понятие D3D12 | Что в HAL | Где | Как ложится |
|---|---|---|---|
| Adapter, `IDXGIFactory::EnumAdapterByGpuPreference` | Перечисления устройств в HAL нет намеренно. Есть `DeviceRegistry` и `DeviceRequest` с `powerPreference`, `requiredFeatures`, `requiredLimits` | `device_registry.dart:62`, HAL.md:62 | Хорошо: опенер D3D12 переводит `powerPreference` в `DXGI_GPU_PREFERENCE`, а `checkSatisfiedBy` отсекает адаптер, если тот не дотягивает |
| Feature levels (11_0…12_2), `CheckFeatureSupport` (OPTIONS1…OPTIONS21) | `DeviceFeatures` (одно множество), `DeviceLimits`, `textureFormatSupport` | `capabilities.dart:89`, `:864`, `:955`, `:1103`; `graphics_device.dart:615-618` | Хорошо. Feature level и tier'ы раскладываются на отдельные `DeviceFeature`. `DeviceLimits` по умолчанию берёт минимумы WebGPU, а FL 11_0 их покрывает |
| `ID3D12Device`, removal (`DXGI_ERROR_DEVICE_REMOVED/RESET`, TDR) | `GraphicsDevice`, `lost` (`DeviceLoss`), `errors` (`DeviceError`) | `graphics_device.dart:93`, `:1024`, `:1046`, `:1064`, `:1096` | Хорошо. TDR и removal дают `DeviceLoss` (невосстановимый). Сообщения debug layer через `ID3D12InfoQueue1::RegisterMessageCallback` идут в `errors` |
| Command queue (direct, compute, copy) | Одна упорядоченная очередь: «passes execute in submission order». `asyncCompute` зарезервирован | HAL.md:588-591, `capabilities.dart:727` | Direct-очередь есть всегда. Copy-очередь бэкенд может завести внутри для `TransferEncoder`. Compute-очередь появится в minor как `ComputePlacement` |
| Command list + allocator | `CommandEncoder` (render pass), `ComputeEncoder`, `TransferEncoder`, у каждого `submit()` | `command_encoder.dart:764,770`, `compute.dart:147`, `transfer.dart:57` | Хорошо. Каждый проход становится одним command list (или куском общего), allocator'ы крутятся по `beginFrame`/`onFrameComplete` (`graphics_device.dart:416,432`) |
| `BeginRenderPass` / OMSetRenderTargets + Clear | `RenderPassDescriptor`, `ColorTarget`/`DepthTarget` с `LoadAction`/`StoreAction`, resolve | `render_pass_descriptor.dart:826,545,748` | Почти 1:1 с `D3D12_RENDER_PASS_BEGINNING/ENDING_ACCESS` (clear, preserve, discard, resolve). `StorageMode.deviceTransient` (`formats.dart:121`) на D3D12 становится обычной памятью с discard |
| Root signature (64 DWORD: константы, root CBV/SRV/UAV, таблицы) | Привязка по имени на стадию: `bindUniformBlock`, `bindTexture`, `bindStorageBuffer`, `bindUniformBytes`, `bindUniformBuffer`. Рефлексия в `StageBindings` и `UniformMemberLayout` | `command_encoder.dart:361,398,579,600,618`; `shader.dart:38,76` | Корневую сигнатуру бэкенд строит сам из рефлексии пары стадий, на пайплайн. HAL.md:75 явно отдаёт «descriptor layouts» бэкенду. `immediateData` (зарезервирован, `capabilities.dart:702`, `maxImmediateDataSize`, `capabilities.dart:986`) ложится на root constants |
| Descriptor heaps (CBV_SRV_UAV до ~1M, **sampler: не больше 2048 shader-visible**) | Сэмплер это значение, а не хэндл: `SamplerDescriptor` передаётся в каждый `bindTexture`, а `releaseSampler` служит хуком | `sampler.dart:70`, HAL.md:406-422 | Терпимо: нужен кэш дескрипторов сэмплеров с дедупликацией по значению (как в WebGPU-бэкенде, `flutter3d_webgpu/lib/src/webgpu_device.dart:1246-1258` кэширует bind group'ы). Из-за лимита 2048 нужен LRU. Таблицы SRV на каждый draw требуют кольцевого аллокатора в shader-visible куче |
| Bindless (SM 6.6 `ResourceDescriptorHeap`) | `bindlessResources` зарезервирован | `capabilities.dart:694` | В minor, как и задумано |
| PSO (монолит: шейдеры, blend, raster, depth/stencil, форматы RT, sample count, topology type, **IBStripCutValue**) | `createPipeline(vertex, fragment, layout)` + `PipelineDescriptor`. Всё прочее это состояние прохода, `PassState` | `graphics_device.dart:243,840`; `pipeline_descriptor.dart:29`; `pass_state.dart:62` | Как задумано: бэкенд копит `PassState` и ищет PSO в кэше на `draw()` (HAL.md:531-546). Ключ PSO обязан включать формат RT и depth, sample count, тип топологии **и формат индексов**: strip cut value (`0xFFFF`/`0xFFFFFFFF`) живёт в PSO, а HAL обещает, что restart в strip включён всегда (HAL.md:548-552). Динамическое состояние D3D12 (viewport, scissor, blend factor, stencil ref, тип внутри topology type) совпадает с тем, что HAL держит вне `PassState` (`setBlendColor`). Depth bias требует PSO, если нет `DynamicDepthBiasSupported` |
| Pipeline library / cached PSO blob | Нет. В minor ляжет полем `PipelineDescriptor` | HAL.md:1182 | В minor |
| Resource states / legacy barriers / **enhanced barriers** | Явных барьеров нет: «the backend tracks hazards and orders by submission» | HAL.md:76, HAL.md:1206-1211, HAL.md:665-670 | Главный вопрос дизайна, но совместимый: как Vulkan, бэкенд ведёт состояние каждого subresource. Границы проходов служат естественными точками барьеров, ведь проход в HAL самодостаточен и известен целиком к `submit`. Enhanced barriers упрощают split-барьеры между проходами. Внутри одного compute-прохода HAL требует видимости записей между dispatch'ами (HAL.md:665), а это UAV-барьер между каждой парой dispatch'ей (или анализ привязок) |
| Heaps, placed/reserved (tiled) resources, aliasing | Аллокация принадлежит бэкенду. Sparse и aliasing отсутствуют | HAL.md:75, HAL.md:1178 | Внутри бэкенда (D3D12MA). Tiled resources отсутствуют, ляжет в minor |
| Upload/readback heaps, map | `writeBuffer`, `writeTexture`, `overwriteGeometry`, `readback`, `readBuffer`, `mapBuffer` (асинхронно), `BufferTextureLayout` | `graphics_device.dart:501,659`; `resources.dart:304,562,613` | Хорошо. Выравнивание pitch на 256 байт такое же, как в WebGPU |
| `ID3D12Fence` (64-битный timeline) | `GpuFence`: timeline, `signalFence`/`waitFence`, значения только растут | `sharing.dart:149`; `graphics_device.dart:982-991` | 1:1. Для внутреннего frame pacing бэкенду хватает своих fence'ов, а через HAL наружу они уходят только для sharing |
| Shared NT handles (`CreateSharedHandle`, DXGI keyed mutex) | `NativeHandle`/`NativeHandleKind`: Metal, IOSurface, AHB, Vulkan fd/Win32. **D3D-видов нет** | `sharing.dart:38-99` | Пробел, закрывается в minor: константы `d3d12Resource`, `dxgiSharedHandle`, `d3d12Fence` (открытый класс, HAL.md:95) |
| Queries (occlusion, binary occlusion, timestamp, pipeline statistics), `ResolveQueryData` | `QuerySet`, `QueryType`, `PipelineStatistic` (5 счётчиков), `readQueryResults` | `resources.dart:441,505,735` | 1:1. Все пять счётчиков (VS invocations, clipper invocations, clipper primitives, PS invocations, CS invocations) есть в `D3D12_QUERY_DATA_PIPELINE_STATISTICS` |
| Bundles | `RenderBundle`, `RenderBundleEncoder` | `resources.dart:693`; `command_encoder.dart:707` | Хорошо. Ограничения D3D12 bundle'ов (без RT, clear, queries) совпадают со `StateError` в HAL (HAL.md:639-642) |
| `ExecuteIndirect` + command signature | `drawIndirect`, `multiDrawIndirect` (с count buffer), `dispatchIndirect` | `command_encoder.dart:517,637` | Хорошо, одна сигнатура на вид. Подвох: в HLSL `SV_VertexID`/`SV_InstanceID` **не включают** BaseVertex/StartInstance. naga и wgpu решают это root constant'ой, а свой бэкенд должен сделать так же |
| Shader Model / DXIL (DXC), DXBC (FXC, SM 5.1) | `ShaderTarget.hlsl` («shader model 5.1 and later»), `compileStage`, F3SB-бандл с секцией на бэкенд, `MaterialCompiler` | `flutter3d_shaders/lib/src/shader_target.dart:25`; `shader_bundle.dart:129`; `flutter3d_shaders/lib/src/material_compiler.dart:140` | HLSL уже назван целью, но бэкенда-потребителя нет. Секция `d3d12` (DXIL) это «a backend's own section» (HAL.md:837) |
| Mesh/amplification shaders | `meshShaders` зарезервирован, новые `ShaderStageKind` | `capabilities.dart:688`; `shader_bundle.dart:42` | В minor (HAL.md:1187) |
| DXR (state objects, SBT, inline RayQuery) | Только `rayQuery` зарезервирован | `capabilities.dart:682` | Inline ray query ляжет в minor (новый хэндл ускоряющей структуры + поле `StageBindings`). Полный DXR-пайплайн с SBT в словаре HAL не описан |
| Work graphs | Нет даже резерва имени | – | Вне 1.x-плана. Похоже скорее на будущий «GPU-driven» слой, чем на HAL |
| Sampler feedback | Нет | – | Нужен только вместе с tiled resources и стримингом. Не для 1.0 |
| VRS (tier 1: per-draw; tier 2: image) | `variableRateShading` зарезервирован | `capabilities.dart:713` | В minor |
| Conservative raster, depth bounds, depth resolve, int64 | Зарезервированы | `capabilities.dart:740,747,720,733` | Все четыре есть в D3D12, их calls лягут в minor |
| Swapchain (DXGI flip) | Нет, это presenter в `DeviceRegistry` | HAL.md:62-65 | Presenter D3D12 отдаёт кадр Flutter'у. Подробнее в §3 |
| Конвенции | `framebufferOrigin` top-left, `depthRange` 0..1 | `graphics_device.dart:110,118`; `formats.dart:1276` | Совпадают с D3D без перевёрток |

### Попутные совпадения по форматам и мелочам

- BC1/3/5/7 есть. ETC2 и ASTC на D3D отсутствуют: честное «нет» в
  `textureFormatSupport`.
- `s8UInt` отдельно: в D3D нет stencil-only формата, поэтому `TextureFormatSupport.none`.
- `d24UnormS8Uint` есть (в отличие от Metal на Apple Silicon).
- `samplerBorderColor`: в D3D12 произвольный цвет в обычном (не static) сэмплере есть.
- `wireframe`: `D3D12_FILL_MODE_WIREFRAME` есть.
- `pointPrimitives`: точки в D3D всегда размером 1 px, и HAL требует того же.
- Бюджет материала: 16 текстур, 16 сэмплеров, 12 uniform-блоков на стадию
  (HAL.md:882, `flutter3d_shaders/lib/src/stage_budget.dart:20`). Это укладывается
  даже в лимиты D3D11 (128 SRV, 16 сэмплеров, **14** CB на стадию). Удачно, и
  ломать это нельзя.

## 2. Пробелы и неудобства

### Чего HAL не может выразить (а D3D12 умеет или требует)

1. **Нативные хэндлы D3D для sharing** (`sharing.dart:89-99`): нет вида для
   `HANDLE` от `ID3D12Resource`/`ID3D12Fence` и для DXGI shared handle.
   Закрывается в minor добавлением констант. Без них zero-copy между wgpu-сайдкаром
   на DX12 и рисующим устройством на Windows невозможен (сейчас там только Vulkan Win32).
2. **Несколько очередей**: async compute и copy queue (`asyncCompute` зарезервирован).
3. **Явное управление памятью**: heaps, placed и aliased ресурсы, tiled resources,
   residency (`MakeResident`/`Evict`, бюджет из `QueryVideoMemoryInfo`).
   Сознательно отдано бэкенду. Для HAL это не дефект, но под нагрузкой бэкенду
   придётся самому реагировать на бюджет памяти.
4. **Pipeline cache blob**: нет (ляжет в minor полем дескриптора).
5. **Work graphs, sampler feedback, полный DXR**: нет даже зарезервированных имён.
   `rayQuery` покрывает только inline RT.
6. **Root constants / immediate data**: зарезервированы, но не активны. Пока они
   выключены, мелкие per-draw данные идут через `bindUniformBytes`, то есть через
   upload-кольцо и root CBV, и это нормально.
7. **Специализационные константы**: в D3D их нет вообще, поэтому для D3D это
   не пробел. Наоборот, будущее поле в `PipelineDescriptor` D3D-бэкенду придётся
   эмулировать перекомпиляцией (в DXIL нет spec constants).

### Что в HAL неудобно ложится на D3D12

1. **Привязка по имени на каждый draw, а не bind groups.** HAL держит
   `bindTexture(stage, name, texture, sampler)` и `bindUniformBlock` по имени
   (`command_encoder.dart:361,398`). D3D12 хочет корневую сигнатуру и таблицы.
   Бэкенду нужна сопоставленная из рефлексии раскладка «имя → root parameter /
   слот в таблице», а на каждый draw нужно копировать дескрипторы в
   shader-visible кольцо (`CopyDescriptorsSimple`) или кэшировать таблицы по
   набору ресурсов, как WebGPU-бэкенд кэширует bind group'ы
   (`flutter3d_webgpu/lib/src/webgpu_device.dart:1246`). Это та же работа, что
   WebGPU-бэкенд уже делает, только на уровень ниже.
2. **Сэмплер как значение плюс лимит 2048 сэмплеров в shader-visible куче.**
   Нужен кэш по значению `SamplerDescriptor` с вытеснением. Engine-стадии
   используют мало комбинаций, так что на практике это не проблема.
3. **Комбинированные сэмплеры GLSL.** Исходники движка пишутся на GLSL под
   impellerc с `sampler2D`. HLSL разделяет `Texture2D` и `SamplerState`. Путь
   через naga это уже решает (разделение есть в `glsl_to_wgsl.dart:46-48` ради
   WGSL), а вывод HLSL из того же SPIR-V унаследует разделение.
4. **Неявные барьеры** (HAL.md:1207). Бэкенд обязан отслеживать состояние
   каждого subresource (mip/layer/face, потому что HAL рисует в отдельный
   `face`/`mipLevel`/`layer`, `render_pass_descriptor.dart:545`). Для enhanced
   barriers это layout на subresource. Объём работы как у Vulkan-бэкенда.
5. **Видимость записей между dispatch'ами в одном compute-проходе** (HAL.md:665):
   консервативно UAV-барьер после каждого dispatch'а. Это дорого, но корректно.
   Оптимизация требует анализа пересечения привязок.
6. **Мгновенные записи вне проходов** (`writeBuffer`/`overwriteGeometry` «видны со
   следующего прохода», HAL.md:966) требуют staging-кольца и copy до следующего
   прохода, а для ресурса в использовании ещё и версионирования (как в wgpu/Dawn).
7. **Отложенное уничтожение** (HAL.md:905-912): бэкенд над D3D12 обязан сам
   держать объекты до fence'а кадра. Это прямо написано для Vulkan/Metal и
   полностью относится к D3D12.
8. **Strip cut value в PSO**: ключ PSO зависит от формата индексного буфера,
   который в HAL биндится отдельно (`bindIndexBuffer`). Решается тем, что PSO
   ищут на `draw()`, когда формат уже известен.
9. **Agility SDK требует экспортов из exe** (`D3D12SDKVersion`,
   `D3D12SDKPath`). В Flutter-приложении это означает правку `windows/runner`
   и не делается пакетом прозрачно. Без Agility SDK остаётся системный
   D3D12 Windows 10/11 без enhanced barriers на старых сборках ОС.

## 3. Что нужно для Direct3D-бэкенда в этом дереве

### Маршрут A. D3D12 уже работает через браузер (стоимость около нуля)

`flutter3d_webgpu` в Chrome/Edge на Windows рисует через **Dawn → D3D12**
(Tint → HLSL → DXC), `flutter3d_webgl` идёт через **ANGLE → D3D11**. Значит,
D3D фактически уже стоит в матрице поддержки, просто не назван. В
Windows-сессию rc.1 (D56, `tasks/1.0-rc1-plan.md:662,789`) можно бесплатно
добавить прогон WebGPU-голденов и conformance в Chrome на Windows-машине с GPU и
WebGL2 там же. Это первая проверка D3D12 и D3D11 на реальных пикселях.

### Маршрут B. wgpu-сайдкар на DX12 (дёшево для compute, дорого для рисования)

- `flutter3d_wgpu` уже собирается под `windows-x86_64-msvc` и
  `windows-aarch64-msvc` (`flutter3d_wgpu/tool/hook/wgpu_native.dart:30,55-57,70-72`,
  wgpu-native v29.0.1.1).
- `f3d_wgpu_open` создаёт инстанс с `wgpuCreateInstance(NULL)`
  (`flutter3d_wgpu/csrc/f3d_wgpu.c:162`), то есть со всеми бэкендами. На Windows
  wgpu выберет Vulkan или DX12 сам, и какой именно, сейчас никто не фиксирует и
  не логирует. Шаг на 1.0: прочитать `WGPUAdapterInfo.backendType`, писать его в
  отчёт или лог и при желании дать выбор через `WGPUInstanceExtras.backends` и
  `dx12ShaderCompiler` (FXC или DXC).
- **WARP**: у wgpu на DX12 есть software-адаптер WARP (fallback adapter). Он
  позволяет гонять `computeChecks`/`kernelChecks` сайдкара на D3D12 прямо на
  `windows-latest` раннере GitHub без GPU. Это реальная проверка D3D12-пути
  компиляции (naga → HLSL → FXC/DXC) на ядрах conformance, и к rc.1 её реально
  успеть.
- Превратить сайдкар в рисующее устройство значит дописать render-половину в
  C-поверхность и FFI. Логика рисования уже написана в Dart для WebGPU через JS
  interop (`flutter3d_webgpu/lib/src/webgpu_device.dart`). Наиболее
  экономный путь к «нативному WebGPU на D3D12/Vulkan/Metal» такой: общий
  WebGPU-образный слой над двумя привязками, JS и `webgpu.h` через FFI. Это
  большая работа (L–XL), зато она даёт D3D12 вместе с Vulkan и без своего
  трекинга барьеров.
- Презентация: текстура wgpu → DXGI shared handle → Flutter. В wgpu-native
  есть `wgpuTextureGetNativeMetalTexture` (`f3d_wgpu.c:600-602`). Есть ли
  аналог для D3D12 в C API, надо проверить. Если нет, понадобится небольшое
  upstream-расширение, по той же логике, что в плане 2K
  (`tasks/1.0-rc1-plan.md:372`).

### Маршрут C. ANGLE / D3D11 через Impeller или WebGL

Impeller на Windows по свежим данным идёт через Vulkan, а GLES-фоллбэк через
ANGLE ложится на D3D11. Через `flutter_gpu` бэкенд `flutter3d_impeller` D3D
напрямую не видит. Выбор API здесь принадлежит Flutter, и flutter3d на него не
влияет. Практический смысл: на Windows-машинах без годного Vulkan-драйвера
(старые Intel iGPU, VM, RDP) Impeller-путь упадёт на GLES/ANGLE, и это стоит
проверить в D56-сессии отдельно. Строка плана rc.2 «on Windows through ANGLE
(5.3)» (`tasks/1.0-rc1-plan.md:753`) про это.

### Маршрут D. Нативный D3D12 через FFI (XL, после 1.0)

- Тонкая C/C++-прослойка (как `f3d_wgpu.c`) над COM-интерфейсами D3D12,
  собранная native-assets хуком под MSVC. Dart FFI по vtable'ам COM без
  прослойки неудобен: пакет `win32` D3D12 не покрывает, ffigen с COM не работает.
- Состав: D3D12MA (аллокатор), трекер состояний subresource и enhanced barriers,
  кольца дескрипторов, кэш PSO по `PassState`, кэш сэмплеров, отложенное
  уничтожение по fence, staging, presenter.
- Презентация: рендер в shared-текстуру → `FlutterDesktopGpuSurfaceDescriptor`
  с DXGI shared handle через texture registrar Windows-эмбеддера. Работает ли
  это, когда сам Flutter композитит через Impeller/Vulkan, нужно проверить.
- Agility SDK: экспорты из `windows/runner` плюс `D3D12Core.dll` рядом с exe.
  DXC: `dxcompiler.dll` + `dxil.dll` в рантайме, либо компиляция в DXIL на
  сборке, тогда в рантайме они не нужны.
- По трудоёмкости это ровно «fifth backend» из HAL.md:1222-1248, со
  скелетом из `examples/flutter3d_backend_null` и шаблоном
  `flutter3d create plugin --kind backend`.

### Путь шейдеров

Сейчас так (`flutter3d_shaders/lib/src/glsl_to_wgsl.dart:1-10`,
`wgsl_compiler.dart:55-60`): GLSL (под impellerc) → `glslangValidator -V` →
SPIR-V → `naga` → WGSL. Ядра идут из kernel language в WGSL (HAL.md:770-780).
`compileStage` уже умеет `ShaderTarget.hlsl`.

Для D3D это:

1. SPIR-V → `naga --hlsl` (SM 5.1 / 6.x) → DXC → DXIL (или FXC → DXBC для SM 5.1).
   Результат идёт в собственную секцию бандла `d3d12` (HAL.md:837) с
   рефлексией register/space ↔ имя. Альтернативы: SPIRV-Cross → HLSL, или
   Tint (WGSL → HLSL, как в Dawn).
2. Компьют: kernel → WGSL (уже есть) → naga → HLSL → DXC.
3. Перспектива: SM7 должен принимать SPIR-V. Тогда SPIR-V, который сборка уже
   делает, станет почти прямым входом. Это довод держать SPIR-V центральным
   промежуточным форматом, как сейчас.
4. Детерминизм ядер: DXC тоже может сжимать mul+add в FMA (`precise` нужен для
   побитовой точности). Это та же проблема, что README сайдкара описывает для
   Metal, и `kernelToleranceChecks` её поймают.

### Применимая conformance

- `runDeviceConformance` со всеми тирами (HAL.md:1024-1046): сначала
  `coreChecks`, затем без shader-тира, затем полный список. Дальше
  `capabilityChecks` (честность фич: ETC2/ASTC «нет», BC «да»), `computeChecks` +
  `kernelChecks` + `kernelToleranceChecks`, `featureOutputChecks`,
  `drawnOutputChecks`, `sharingChecks` (после появления D3D-видов
  `NativeHandleKind`), `multiviewChecks` (D3D12 view instancing), фаззер против
  `cpu`, собственный golden-набор.
- D3D12 debug layer + GPU-based validation как источник `errors` в тестовом
  прогоне.
- **WARP** как CI-адаптер на `windows-latest`, по аналогии с SwiftShader и
  swangle в плане rc.2 (`tasks/1.0-rc1-plan.md:752-753`).
- Пункт rc.2 «a shader lint against the strictest HLSL compiler»
  (`tasks/1.0-rc1-plan.md:758-759`) и есть первый шаг шейдерного пути: прогонять
  все стадии движка и ядра через naga → HLSL → DXC в CI. Это ловит
  несовместимости ещё до бэкенда.

## 4. Рекомендация

**Да, считать D3D12 одним из эталонных стандартов при решениях HAL**, наравне с
Vulkan, Metal и WebGPU, с оговоркой «как проверку, а не образец». HAL и так
сознательно WebGPU-образный (имена фич по WebGPU, дефолты лимитов по WebGPU). WebGPU
сам спроектирован так, чтобы ложиться на D3D12, поэтому большая часть уже
совместима. Проверка по D3D12 ценна там, где WebGPU что-то прячет: лимит 2048
сэмплеров, strip cut в PSO, root constants, отсутствие spec constants в DXIL,
`SV_InstanceID` без базы, лимит в 14 CB на стадию в D3D11. По моим проверкам ни
одно замороженное решение 1.0 этому не противоречит: всё, чего не хватает,
добавляется в minor (новые константы открытых классов, поля дескрипторов,
члены с отказывающими дефолтами).

Я бы ввёл правило: любая новая фича или поле HAL получает в описании строку «как
это на D3D12», так же как сейчас неявно есть «как это на WebGPU» и «на Metal».

**Для 1.0 (rc.1, без нового бэкенда), всё S:**

1. В D56-сессии на Windows прогнать WebGPU и WebGL2 в Chrome на реальном GPU
   (это Dawn/D3D12 и ANGLE/D3D11) и записать результат в SUPPORT рядом с
   Impeller.
2. Сайдкар: логировать и сообщать `backendType` адаптера, запускать
   `computeChecks`/`kernelChecks` сайдкара на `windows-latest` через WARP (DX12).
3. Перед заморозкой ещё раз пройтись по зарезервированным именам: стоит
   **зарезервировать** `workGraphs` и `samplerFeedback` (или явно записать, что
   они вне 1.x), и проверить, что форма `rayQuery` не мешает полному DXR позже.
4. Ничего в замороженных сигнатурах ради D3D менять не нужно.

**rc.2 / 1.x minor:**

5. HLSL-линт шейдеров (naga → HLSL → DXC) в CI, он уже в плане.
6. `NativeHandleKind`: `d3d12Resource`, `dxgiSharedHandle`, `d3d12Fence` (minor).
7. `immediateData` и `bindlessResources` из резерва в stable, с учётом root
   constants и SM 6.6.

**После 1.0 (выбор маршрута):**

8. Если нужен нативный рендер на Windows помимо Impeller, начинать с маршрута B
   (рисующий нативный WebGPU через `webgpu.h`/wgpu-native с общей логикой
   WebGPU-бэкенда). Он даёт D3D12, Vulkan и Metal одной работой, а барьеры и
   дескрипторы берёт на себя wgpu.
9. Собственный D3D12-бэкенд (маршрут D) имеет смысл, только если понадобится
   то, чего WebGPU не даст: work graphs, полный DXR, mesh shaders раньше
   WebGPU, или тонкий контроль памяти. Это XL-работа на месяцы.

## Источники

- [DirectX 12 Agility SDK Downloads](https://devblogs.microsoft.com/directx/directx12agility) (версии 1.619.6, 1.721.3-preview, даты work graphs, enhanced barriers, fence barriers)
- [igor'sLAB: Agility SDK 1.619 и Shader Model 6.9](https://www.igorslab.de/en/directx-12-agility-sdk-1-619-introduces-shader-model-6-9-microsoft-is-bringing-modern-gpu-features-out-of-preview-and-into-everyday-use/)
- [D3D12 enhanced barriers (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/enhanced-barriers)
- [Mesh nodes in work graphs, 1.715 preview](https://www.elevenforum.com/t/new-d3d12-preview-agility-sdk-v1-715-0-mesh-nodes-in-work-graphs.26921)
- [DirectX Adopting SPIR-V (DirectX blog, 2024)](https://devblogs.microsoft.com/directx/directx-adopting-spir-v/)
- [Flutter 3.47: Impeller по умолчанию на десктопе](https://startdebugging.net/2026/08/flutter-3-47-impeller-default-renderer-on-desktop/) (вторичный источник, сверить с release notes)
- [wgpu Instance docs](https://wgpu.rs/doc/wgpu/struct.Instance.html) (выбор DX12-компилятора в дескрипторе инстанса)
