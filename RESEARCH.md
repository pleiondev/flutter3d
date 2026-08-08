# 3D-движок на Flutter GPU: исследование и список необходимых функций

Дата: 2026-08-08, статус пунктов обновлён 2026-08-09. Отмеченные `[x]` реализованы;
неотмеченные — открыты. Разбор архитектуры сцены — в `docs/ARCHITECTURE-scene-camera.md`,
замеры и вывод про FFI — в `docs/FFI-analysis.md`.
неотмеченные — открыты. Разбор архитектуры сцены — в docs/ARCHITECTURE-scene-camera.md,
замеры и вывод про FFI — в docs/FFI-analysis.md.

---

## 0. Главный вывод, который меняет постановку задачи

**Полноценный 3D-движок на `flutter_gpu` уже существует и он далеко не прототип** —
[`flutter_scene`](https://pub.dev/packages/flutter_scene) 0.20.0 от Brandon DeRosier (bdero),
автора Impeller и самого Flutter GPU. Flutter GPU изначально был сделан именно для того,
чтобы вынести Scene из движка в обычный Dart-пакет.

Что там уже есть на сегодня:

| Подсистема | Состояние в flutter_scene 0.20.0 |
|---|---|
| PBR + IBL | есть, включая процедурное studio-окружение, sky-материалы, live IBL rebake, HDR/EXR |
| Свет и тени | directional / point / spot, shadow casting с кэшированием |
| Post-processing | tonemap, exposure, bloom, fog, god rays, SSR, DOF, AA |
| Материалы | свой формат `.fmat`, vertex+fragment стадии, **hot reload шейдеров** |
| Геометрия | инстансинг, автоматические LOD, procedural builders, geometry readback |
| Ассеты | glTF `.glb` в рантайме + прекомпиляция в `.fsceneb` (flatbuffers), KTX2 + mip, `.fstex` |
| Анимация | скиннинг, blended animation system, KHR_materials_variants |
| Экзотика | 3D Gaussian splatting (`.ply`, `.splat`) |
| Интеграция | `SceneView` (императивный + декларативный API), **интерактивные Flutter-виджеты на 3D-поверхностях** с pointer raycasting, semantics/screen reader, split-screen, multi-view, захват кадра в `ui.Image` |
| Экосистема | физика (Rapier, box3d), звук (SoLoud, FMOD), Scene Editor с MCP-сервером |
| Платформы | iOS, Android, macOS, Windows, Linux + **web через собственный WebGL2-бэкенд** |

Поэтому первое решение — не техническое, а стратегическое:

1. **Использовать `flutter_scene`** — если цель «сделать 3D в приложении».
2. **Форкнуть / расширять `flutter_scene`** — если нужны свои материалы, свой пайплайн, свой формат сцены,
   но не хочется писать RHI, glTF-импорт и IBL-пребейк с нуля.
3. **Писать свой движок с нуля** — если цель обучение, специфичная предметная область
   (CAD, геоданные, научная визуализация, voxel, 2.5D-стилизация), или принципиально другая
   архитектура (ECS, data-oriented, GPU-driven).

Дальше в документе — материал для варианта 3 (и он же карта того, что придётся
дописывать в варианте 2).

---

## 1. Что дают web-движки: сравнение подсистем

### 1.1 Three.js
Библиотека, не движок: даёт scene graph, математику, рендерер и загрузчики,
всё остальное — из `examples/jsm` и экосистемы.

- Ядро: `Object3D`-иерархия, `BufferGeometry`, математика (векторы, матрицы, кватернионы, кривые).
- Два рендерера: классический `WebGLRenderer` (императивный, GLSL, `WebGLPrograms`/`WebGLState`)
  и `WebGPURenderer` — на **node-материалах и TSL** (Three Shading Language): шейдеры пишутся
  на JS как граф узлов и транспилируются в WGSL или GLSL. Compute-шейдеры тоже через TSL.
- Post-processing на WebGPU — новый стек, эффекты как композиция узлов.
- Тени: `BasicShadowMap`, `PCFShadowMap`, `PCFSoftShadowMap`, VSM.
- Raycasting, GLTF/множество загрузчиков, сериализация, контроллеры камеры, аудио, хелперы,
  редактор, TSL-транспайлер, расширение для Chrome DevTools.

**Что забирать:** структуру математической библиотеки, `BufferGeometry`-модель атрибутов,
API загрузчиков, `Raycaster`, набор контроллеров камеры.

### 1.2 Babylon.js 8.x
Полноценный движок с редакторами и «всё включено».

- Многоуровневый RHI: `AbstractEngine` → `ThinEngine` → `Engine` / `WebGPUEngine` /
  `NativeEngine` (iOS/Android/Windows) / `NullEngine` (headless, тесты, серверный рендер).
  **Это ровно та абстракция, которая нужна нам** для «flutter_gpu + web-fallback + headless-тесты».
- Все ядровые шейдеры существуют и в GLSL, и в WGSL — без слоя конверсии.
- **Node Render Graph / FrameGraph** (8.0, alpha): рендер-пайплайн как граф узлов
  с визуальным редактором. Полный контроль над кадром без ручного кода проходов.
- `PrePassRenderer` + MRT для deferred-эффектов; DefaultRenderingPipeline (bloom, DOF, SSR, SSAO2, ...).
- IBL-тени (вклад Adobe): свет **и** тени аппроксимируются из environment-картинки. GI.
- Материалы: `StandardMaterial` (Blinn-Phong), `PBRMaterial`, `NodeMaterial` (граф → GLSL/WGSL), `ShaderMaterial`.
- Анимация: клипы, группы, скелетная, morph targets.
- Отдельные крупные подсистемы: частицы (CPU/GPU/node-based), физика (плагины), GUI (2D + 3D + редактор),
  WebXR, аудио (AudioV2), Inspector, Playground, Sandbox, Gaussian splatting,
  загрузчики glTF/OBJ/STL/SPLAT, экспорт glTF/USDZ.

**Что забирать:** тиеринг RHI, идею FrameGraph, разделение Standard/PBR/Custom материалов,
`PickingInfo`, `NullEngine` для golden-тестов.

### 1.3 PlayCanvas
Самый «мобильно-ориентированный» из трёх — полезнее всех для Flutter-таргета.

- **Clustered lighting по умолчанию** (с 1.56): сцена делится на кластеры в 3D,
  свет привязывается только к нужным. До 254 omni/spot ламп, включение/выключение
  света **без рекомпиляции шейдеров** — критично там, где рантайм-компиляции нет вообще.
- Shadow maps и cookie-текстуры рендерятся **в атлас**, а не в отдельные текстуры,
  чтобы все были доступны шейдеру одновременно.
- FrameGraph: рендер описывается набором проходов, их зависимостей и целей.
  На нём же построен пост-процесс: TAA, Bloom, DOF, SSAO, Vignette.
- WebGL2 + WebGPU (beta), unified GSplat.

**Что забирать:** clustered forward как основную схему освещения, атлас теней,
идею «менять свет без пересборки шейдера» — она прямо вытекает из ограничений flutter_gpu.

### 1.4 Сводка: чего ждут от современного движка

| Ось | Three.js | Babylon.js 8 | PlayCanvas |
|---|---|---|---|
| Абстракция бэкендов | 2 рендерера | 5 движков, включая headless | 2 бэкенда |
| Авторинг шейдеров | TSL (граф → WGSL/GLSL) | NodeMaterial (граф → GLSL/WGSL) | шейдер-чанки + defines |
| Граф кадра | нет (ручной composer) | FrameGraph + визуальный редактор | FrameGraph |
| Схема освещения | forward, per-object лимиты | forward + prepass/deferred | **clustered forward** |
| GI | нет (только IBL) | IBL shadows, GI | lightmaps, volumetric |
| Редактор | сторонние | Inspector + 4 node-редактора | полноценный веб-редактор |
| Compute | через TSL/WebGPU | WebGPU | WebGPU |

---

## 2. Что реально даёт `flutter_gpu` (и чего не даёт)

Проверено по [`api.flutter.dev/flutter/flutter_gpu`](https://api.flutter.dev/flutter/flutter_gpu/)
и [engine docs](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md).

### 2.1 Публичная поверхность API

Всего ~20 классов. Это тонкая обёртка над Impeller HAL, уровень «Metal/Vulkan-lite»:

- Ресурсы: `GpuContext`, `DeviceBuffer`, `HostBuffer` (bump-аллокатор поверх списка блоков
  `DeviceBuffer` — готовый per-frame ring buffer), `BufferView`, `Texture`, `ShaderLibrary`, `Shader`.
- Пайплайн: `RenderPipeline`, `RenderTarget`, `ColorAttachment`, `DepthStencilAttachment`,
  `ColorBlendEquation`, `StencilConfig`, `SamplerOptions`, `UniformSlot`, `Viewport`, `Scissor`, `DepthRange`.
- Исполнение: `CommandBuffer`, `RenderPass`.

`RenderPass` умеет: `bindPipeline`, `bindUniform`, `bindTexture`, `bindVertexBuffer`,
`bindIndexBuffer`, `clearBindings`, `setPrimitiveType`, `setCullMode`, `setWindingOrder`,
`setPolygonMode` (в т.ч. wireframe), `setViewport`, `setScissor`, `setStencilConfig`,
`setStencilReference`, `setDepthWriteEnable`, `setDepthCompareOperation`,
`setColorBlendEnable`, `setColorBlendEquation`, `draw()`.

`GpuContext.createTexture(storageMode, width, height, {format, sampleCount, coordinateSystem,
textureType, enableRenderTargetUsage, enableShaderReadUsage, enableShaderWriteUsage})`,
`createDeviceBuffer`, `createHostBuffer`, `createCommandBuffer`,
`doesSupportOffscreenMSAA`, `minimumUniformByteAlignment`.

### 2.2 Возможности, на которые можно опираться

| Есть | Значение для движка |
|---|---|
| `sampleCount` + `doesSupportOffscreenMSAA` | MSAA для offscreen-таргетов доступна |
| `TextureType.textureCube` | IBL, cube shadow maps возможны |
| `r16g16b16a16Float`, `r32g32b32a32Float` | полноценный HDR-пайплайн и tonemapping |
| `d24UnormS8Uint`, `d32FloatS8UInt`, `s8UInt` | depth + stencil, значит portáls, outline, decals, reversed-Z |
| Полный stencil API (per-face) | outline, маски, CSG-эффекты |
| `setPolygonMode` | wireframe-отладка бесплатно |
| `HostBuffer` | per-frame uniform-аллокации без своего аллокатора |
| `enableShaderWriteUsage` | признак того, что storage-текстуры на горизонте |
| `PolygonMode`/`WindingOrder`/`CullMode` | базовый state полностью управляем |

### 2.3 Ограничения — это и есть архитектурные развилки

**(1) Шейдеры компилируются AOT в shader bundle. Рантайм-компиляции нет.**
`.vert`/`.frag` на GLSL → манифест `.shaderbundle.json` → build hook пакета
`flutter_gpu_shaders` (через экспериментальные Dart **Native Assets**) → `.shaderbundle`.

Следствие: **node-material-граф в стиле Babylon NodeMaterial или Three TSL невозможен
в рантайме.** Варианты:
- **Uber-shader** с ветвлениями по uniform-флагам (путь PlayCanvas clustered lighting:
  «включить свет без рекомпиляции»). Стоимость — регистры и динамические ветвления.
- **Предгенерация перестановок** на этапе сборки: кодогенератор Dart раскладывает
  граф/набор фич в N вариантов `.frag` и складывает в бандл. Дизайнерский граф
  возможен, но только в редакторе, не в приложении.
- Гибрид: uber-shader для «динамики» (число ламп, наличие карт) + перестановки
  для того, что реально меняет структуру (skinning, instancing, alpha mode).

**(2) Формат shader bundle привязан к версии Flutter и может меняться.**
Движок придётся пересобирать/перепроверять под каждый апдейт master. Нужен CI,
который собирает бандлы на нескольких ревизиях, и golden-тесты рендера.

**(3) Только master channel.** Плюс `flutter config --enable-native-assets`
(и `--enable-dart-data-assets`, если повторять подход `.fmat` из flutter_scene).
Desktop требует `--enable-impeller`.

**(4) Web не поддерживается.** flutter_scene не случайно везёт **собственный WebGL2-бэкенд**.
Если web в требованиях — нужна абстракция RHI (уровень `AbstractEngine` из Babylon) и
второй бэкенд через `dart:js_interop`. Это удваивает работу по рендереру.

**(5) Compute-проходы в публичном `flutter_gpu` не выставлены.** В Impeller compute
существует, но через Dart-API его в документированном срезе нет. Значит недоступны:
GPU-частицы на compute, GPU-скиннинг, GPU-culling, indirect draw, IBL-префильтрация
в compute, GPU-сортировка прозрачных. Всё это придётся делать на CPU или эмулировать
через render-проходы (IBL prefilter — через рендер в mip-уровни; именно поэтому
flutter_scene требует master ≥ 2026-06-09 с поддержкой render-to-mip-level).

**(6) Нет compressed pixel formats** (ASTC/BC/ETC2) в публичном `PixelFormat`,
и нет `texture2DArray`/`texture3D`. Следствия:
- KTX2/Basis придётся **транскодить в несжатый** формат на CPU (память и загрузка!),
  либо ждать/проверять расширение enum на master — flutter_scene заявляет KTX2 с mip,
  значит на master что-то уже есть. ⚠️ Проверить первым делом.
- Тени и cookies — **в атлас**, а не в texture array (как в PlayCanvas).
- Color grading LUT — 2D-тайловый, не 3D-текстура.
- Кластеры света — упаковка в 2D-текстуру/буфер, не в 3D.

**(7) `draw()` без `instanceCount` в документированном API.** flutter_scene инстансинг
заявляет — либо через per-instance vertex-атрибуты, либо API появился позже. ⚠️ Проверить.

**(8) Dart GC.** Каждый `Vector3` — объект в куче. В горячих циклах (culling, обновление
трансформов, частицы) нужны пулы, `Float32List`-хранение (SoA) и `Matrix4` in-place
операции. Это отличает Dart-движок от JS-движка сильнее, чем кажется:
джанк от GC съест бюджет кадра быстрее, чем draw calls.

---

## 3. Список необходимых функций

Приоритеты: **P0** — без этого нельзя показать вращающийся куб с текстурой;
**P1** — без этого нельзя показать нормальную glTF-сцену; **P2** — то, что делает
это движком; **P3** — то, ради чего люди выбирают движок.

### Слой 0. RHI / обёртка над flutter_gpu

- [ ] **P0** `GraphicsDevice`: враппер `GpuContext`, запрос и кэш capabilities
      (`doesSupportOffscreenMSAA`, `minimumUniformByteAlignment`, поддерживаемые форматы).
- [x] **P0** Загрузка `ShaderLibrary` из бандла, реестр шейдеров по имени, типизированные
      описания uniform-блоков (кодоген из GLSL, чтобы не писать offset'ы руками).
- [x] **P0** **Кэш `RenderPipeline`** по ключу (shader × vertex layout × blend × depth × stencil × sample count).
      Создание пайплайна дорого — обязателен, с прогревом на старте.
- [x] **P0** Аллокаторы буферов: статический `DeviceBuffer` для геометрии,
      per-frame `HostBuffer` для uniform, suballocation для мелочи. Кольцо из 3 `HostBuffer` по числу кадров в полёте.
- [ ] **P0** Управление временем жизни ресурсов: явный `dispose`, ref counting,
      отложенное освобождение на N кадров (GPU ещё читает).
- [ ] **P1** Пул render-таргетов и текстур с переиспользованием по (size, format, usage) —
      на мобильных память кадра критична.
- [ ] **P1** Абстракция `CommandEncoder` над `CommandBuffer`/`RenderPass`,
      чтобы верхние слои не знали про flutter_gpu.
- [ ] **P2** Второй бэкенд (WebGL2 через `dart:js_interop`) если нужен web,
      либо `NullDevice` для headless-тестов.
- [ ] **P2** Валидационный слой в debug: проверка биндингов, форматов, отсутствующих uniform.

### Слой 1. Математика

- [x] **P0** Взять `vector_math` (`Vector2/3/4`, `Matrix3/4`, `Quaternion`, `Aabb3`, `Sphere`,
      `Plane`, `Frustum`, `Ray`, `Obb3`) — переписывать не нужно.
- [x] **P0** In-place / allocation-free обёртки для горячих путей + пул временных векторов. `readPosition(out)` и подобные.
- [x] **P0** `Transform`: TRS с ленивым пересчётом матрицы, dirty-флаг, local↔world. Реализовано через счётчики версий: отдельного прохода обновления нет.
- [ ] **P1** Euler с порядками осей, декомпозиция матрицы, `slerp`/`nlerp`, сферические координаты.
- [ ] **P1** Кривые и сплайны (Catmull-Rom, Bezier, path), easing-функции.
- [ ] **P2** Пересечения: ray×AABB/sphere/triangle/OBB/plane, sphere×frustum, sweep-тесты.
- [ ] **P2** SoA-хранилище трансформов (`Float32List`) вместо массива объектов.

### Слой 2. Граф сцены

- [x] **P0** `Node` с parent/children, локальным и мировым трансформом,
      распространением dirty-флага вверх/вниз.
- [x] **P0** `Scene` как корень + обход, `MeshNode`, `CameraNode`, `LightNode`.
- [x] **P1** Видимость, layers/culling masks, теги, поиск по имени/пути. Теги не сделаны.
- [x] **P1** **Frustum culling** + иерархические bounding volumes (AABB снизу вверх). Мировые границы кэшируются по `worldVersion`; иерархических AABB нет.
- [ ] **P2** Пространственный индекс (BVH или loose octree) для culling и raycast.
- [ ] **P2** LOD-группы с автопереключением по экранному размеру.
- [ ] **P2** Решить: классическое дерево объектов или **ECS с архетипами**.
      Для Dart аргумент за ECS сильнее обычного из-за GC и линейного обхода.
- [ ] **P3** Occlusion culling (без compute — только CPU software или hi-z через depth-даунсемплинг).
- [ ] **P3** Стриминг сцены, prefab/инстанцирование поддеревьев.

### Слой 3. Геометрия

- [x] **P0** `VertexLayout` / attribute descriptors, `Mesh` = vertex buffer + index buffer + submeshes.
- [x] **P0** Примитивы: box, plane, sphere (UV + ico), cylinder, cone, torus, capsule, quad, grid. Через абстракцию `Shape`, плюс `LatheShape`.
- [ ] **P1** Утилиты: пересчёт нормалей, генерация тангенсов (для normal maps — обязательно),
      welding/дедупликация вершин, merge, flip, вычисление AABB/sphere.
- [ ] **P1** Скиннинг: bone matrices в uniform-буфер (лимит по размеру!) или в текстуру.
- [ ] **P1** Инстансинг: per-instance атрибуты в отдельном vertex buffer
      (⚠️ проверить наличие `instanceCount` в `draw()` на master).
- [ ] **P2** Morph targets (позиции/нормали, веса).
- [ ] **P2** Батчинг статики (merge по материалу), `BatchedMesh`-аналог.
- [ ] **P2** Процедурные билдеры (extrude, revolve, tube, text-geometry), CSG.
- [ ] **P2** Geometry readback (нужно физике и raycast'у по актуальной геометрии).
- [ ] **P3** Автоматическая генерация LOD (упрощение меша), meshopt-совместимая оптимизация порядка вершин.

### Слой 4. Камеры и ввод

- [x] **P0** `PerspectiveCamera`, `OrthographicCamera`, view/projection, извлечение frustum.
- [ ] **P0** **Reversed-Z** и (опц.) infinite far plane — на мобильных с d24 иначе z-fighting.
- [x] **P1** Контроллеры: orbit, first-person, fly, trackball. Только orbit.
- [x] **P1** **Мост жестов Flutter → камера**: `Listener`/`GestureDetector`, pinch-zoom,
      два пальца = pan, инерция. На мобильных это половина воспринимаемого качества.
- [ ] **P2** Множественные вьюпорты, split-screen, mini-map, render-to-widget.
- [ ] **P2** Camera jitter для TAA, физически-корректная экспозиция (aperture/shutter/ISO).

### Слой 5. Материалы и шейдинг

- [x] **P0** Определиться со стратегией: **uber-shader vs предгенерация перестановок vs гибрид** (см. §2.3).
      Это самое дорогое решение в проекте — переделывать потом больно. Выбраны AOT-перестановки, по шейдеру на модель освещения.
- [x] **P0** `Material` с типизированными uniform'ами и слотами текстур, `UnlitMaterial`.
- [x] **P1** **PBR metal-roughness**, glTF-совместимый: baseColor, metallic, roughness, normal,
      occlusion, emissive, ORM-упаковка, per-map UV-set и `KHR_texture_transform`. Пока только baseColor, metallic, roughness; карт нормалей, AO и emissive нет.
- [x] **P1** Alpha modes: opaque / mask (cutoff) / blend, double-sided, vertex colors. Blend и double-sided есть; cutoff в шейдере нет, vertex colors декодируются но не шейдятся.
- [ ] **P1** Кодоген «GLSL uniform block → Dart-класс», чтобы биндинги были типобезопасны.
- [ ] **P2** Дополнительные модели: toon/cel, matcap, gradient, wireframe, unlit-emissive.
- [ ] **P2** glTF-расширения: clearcoat, sheen, transmission, volume, iridescence,
      anisotropy, emissive_strength, specular.
- [ ] **P2** **Hot reload шейдеров** в debug (flutter_scene это умеет — планка задана).
- [ ] **P3** Визуальный граф материалов **в редакторе** с кодогенерацией в бандл.
- [ ] **P3** Order-independent transparency (weighted blended), refraction.

### Слой 6. Освещение и тени

- [x] **P1** Directional, point, spot; attenuation, cone falloff, интенсивности в физических единицах. В шейдере только directional; point и spot есть в сцене, но не шейдятся.
- [ ] **P1** **Схема освещения**: forward с лимитом ламп → потом **clustered forward**.
      На tile-based мобильных GPU deferred проигрывает; clustered — правильный целевой выбор.
- [ ] **P1** **IBL**: irradiance (SH9 или маленький cubemap) + prefiltered specular cubemap
      (GGX по mip-уровням) + BRDF LUT. Префильтрация — рендер-проходами в mip-уровни,
      т.к. compute нет. ⚠️ Требует render-to-mip-level на master.
- [ ] **P1** Shadow maps для directional (одна карта → потом CSM), PCF-фильтрация, bias/normal offset.
- [ ] **P2** **Атлас теней** (все источники в одну текстуру — нет texture arrays).
- [ ] **P2** Cascaded shadow maps, cube shadows для point, spot shadows.
- [ ] **P2** SSAO/GTAO, contact shadows, ambient occlusion из карт.
- [ ] **P3** Light probes, lightmaps, IBL shadows (как в Babylon 8), volumetric light/god rays.
- [ ] **P3** Area lights (LTC), light cookies.

### Слой 7. Рендер-пайплайн / граф кадра

- [x] **P0** `Renderer`: собрать список отрисовки, отсортировать, выполнить проходы, представить кадр.
- [x] **P0** Интеграция с Flutter: рендер в текстуру → `ui.Image` → виджет,
      корректный `devicePixelRatio`, ресайз, `Ticker`/`SchedulerBinding` как источник времени.
- [x] **P1** Сортировка: opaque по (pipeline, material, mesh) + front-to-back;
      transparent — back-to-front по глубине. Радиксная сортировка по упакованным ключам, пайплайн — старший ключ.
- [x] **P1** Tonemapping (Khronos PBR Neutral) + exposure. Сделано.
- [ ] **P1** HDR-таргет (`r16g16b16a16Float`). Сейчас тонмаппинг применяется в шейдере
      прямо перед записью в 8-битный таргет, то есть промежуточного HDR-буфера нет —
      он понадобится для bloom и всего, что читает яркость выше 1.
- [x] **P1** Корректный color management: линейное пространство внутри, sRGB на выходе.
- [x] **P1** MSAA + resolve, depth prepass (опционально), очистка/сохранение attachment'ов
      с правильными `LoadAction`/`StoreAction` (на мобильных это прямая экономия пропускной способности). Depth prepass не делали.
- [ ] **P2** **Frame graph**: проходы как узлы с объявленными входами/выходами,
      автоматическое переиспользование таргетов и порядок. Путь Babylon 8 / PlayCanvas.
      Дорого, но иначе пост-процесс превращается в спагетти.
- [ ] **P2** Post-processing стек: bloom, FXAA/SMAA, vignette, grain, chromatic aberration,
      color grading (2D-тайловый LUT), fog (linear/exp/height).
- [ ] **P3** TAA (нужен motion vector pass + jitter), DOF, SSR, motion blur, god rays.
- [ ] **P3** MRT / prepass для screen-space эффектов (⚠️ проверить поддержку нескольких
      `ColorAttachment` в одном `RenderTarget`).

### Слой 8. Анимация

- [ ] **P1** `AnimationClip` + треки (translation / rotation / scale / weights / произвольное свойство),
      интерполяции step / linear / cubicspline (полный набор glTF).
- [ ] **P1** `AnimationPlayer`: play/pause/seek/loop/speed, привязка ко времени кадра.
- [ ] **P1** `Skeleton` + joint-иерархия, inverse bind matrices, применение к скиннингу.
- [ ] **P2** Смешивание: слои, crossfade, additive, маски по костям.
- [ ] **P2** Morph target weights в анимации.
- [ ] **P3** IK (two-bone, FABRIK, look-at), state machine / blend tree, retargeting.
- [x] **P3** Процедурная анимация, твины, spring/physics-based (можно опереться на Flutter-подход).

### Слой 9. Ассеты

- [x] **P1** **glTF 2.0 / GLB loader** — сделано для geometry-части: контейнер, буферы
      (BIN-chunk / base64 / внешние файлы), аксессоры со stride, normalized и sparse,
      граф узлов с TRS и матрицами, материалы metal-rough, изображения, конвертация
      strip/fan в треугольники, генерация плоских нормалей по спеке, определение
      зеркальных трансформов. Осталось: animations, skins, cameras, морф-таргеты.
- [ ] **P1** Загрузка в **`Isolate`**: парсинг JSON, декодирование изображений, распаковка —
      всё вне UI-потока, передача через `TransferableTypedData`. Иначе джанк при загрузке.
- [ ] **P1** Кэш ассетов с ref counting, отмена загрузки, прогресс.
- [ ] **P2** **Свой бинарный формат сцены** (flatbuffers, как `.fsceneb`) + офлайн-конвертер:
      zero-parse загрузка вместо разбора glTF в рантайме.
- [ ] **P2** Текстуры: mip-цепочки, sRGB-флаги, KTX2 → ⚠️ выяснить, есть ли на master
      compressed `PixelFormat`; если нет — транскодинг в RGBA8 и честный учёт памяти.
- [ ] **P2** HDR/EXR для environment maps, equirect → cubemap конверсия.
- [ ] **P2** Meshopt-декомпрессия (реалистично на Dart), Draco (нужен native/FFI — дороже).
- [ ] **P2** Hot reload моделей/текстур/окружений в debug.
- [ ] **P3** Экспорт (glTF/USDZ), стриминг, виртуальные текстуры.

### Слой 10. Взаимодействие

- [ ] **P1** CPU raycast по сцене (через BVH), `HitResult` с точкой, нормалью, UV, submesh.
- [ ] **P2** Raycast по скиннированной геометрии, GPU-picking через id-буфер.
- [ ] **P2** **Flutter-виджеты в 3D-пространстве** с проброшенными указателями —
      уникальное преимущество Flutter перед web-движками, flutter_scene это уже делает.
- [ ] **P2** Гизмо: перемещение/вращение/масштаб для редактора.
- [ ] **P3** Accessibility: semantics-узлы для 3D-объектов (тоже есть у flutter_scene).

### Слой 11. Частицы и VFX

- [ ] **P2** CPU-система частиц (compute нет): эмиттеры, модификаторы, кривые,
      billboard/stretched/mesh-рендер, инстансинг.
- [ ] **P2** Sprites/billboards, wide lines (геометрией — нативных толстых линий нет),
      trails, decals (через stencil/projected).
- [ ] **P3** Sky/atmosphere (procedural, Hillaire), водная поверхность, terrain.
- [ ] **P3** GPU-частицы через vertex shader + ping-pong state-текстуры (обход отсутствия compute).

### Слой 12. Текст в 3D

- [ ] **P2** SDF/MSDF-атлас шрифтов + рендер, либо растеризация Flutter-текста в атлас.
- [ ] **P2** Screen-space надписи и метки через обычные Flutter-виджеты поверх сцены
      (проще и качественнее, чем в web-движках).

### Слой 13. Физика (интеграция, не своя реализация)

- [ ] **P3** Абстракция физического мира + бэкенды. Реалистичные пути:
      Rapier через FFI, Jolt через FFI, или чистый Dart для простых случаев.
      В экосистеме уже есть `flutter_scene_rapier` и `flutter_scene_box3d` — смотреть на них.
- [ ] **P3** Collision shapes из геометрии, character controller, raycast-запросы к физике.

### Слой 14. Инструменты и DX

- [x] **P1** Debug-оверлей: FPS, время UI/raster, draw calls, треугольники, память ресурсов. Есть vtx/tri/draws/переключения пайплайна/MSAA; времени и памяти нет.
- [x] **P1** Отладочная отрисовка: wireframe (`setPolygonMode` бесплатно), нормали,
      bounding boxes, гизмо света, оси, сетка. Только wireframe.
- [ ] **P1** Профилирование через `dart:developer` Timeline (`startSync`/`finishSync`)
      с разметкой фаз кадра; профилировать **только profile/release**.
- [ ] **P2** **Golden-image тесты рендера** в CI — единственная защита от того,
      что новый master-ревизия молча испортит картинку.
- [ ] **P2** CI, собирающий shader bundles на нескольких ревизиях master.
- [ ] **P3** Редактор сцены (отдельный проект по объёму).

---

## 4. Проверено по исходникам (Flutter 3.44.6, stable)

Оказалось, что `flutter_gpu` лежит в SDK даже на stable — `bin/cache/pkg/flutter_gpu`,
всего 1757 строк Dart. Это позволило закрыть все четыре вопроса чтением кода,
а не гаданием по докам. Ниже — факты, а не предположения.

| Вопрос | Ответ на stable 3.44.6 | Где смотреть |
|---|---|---|
| Сжатые форматы (ASTC/BC/ETC2) | **Нет.** Ровно 16 значений `PixelFormat`, все несжатые | `lib/src/formats.dart:36` |
| `instanceCount` в `draw()` | **Нет.** `void draw()` вообще без параметров | `lib/src/render_pass.dart:450` |
| MRT | **Структурно есть**: `RenderTarget.colorAttachments` — это `List`, и `_setColorAttachment(ctx, index, …)` вызывается в цикле по `indexed`. `setColorBlendEnable` принимает `colorAttachmentIndex` | `lib/src/render_pass.dart:222,240,354` |
| Render-to-mip-level | **Мипов нет вообще.** У `Texture` нет `mipCount`, `overwrite()` пишет только базовый уровень, есть только `getBaseMipLevelSizeInBytes()` | `lib/src/texture.dart:82,96` |

Дополнительно выяснилось (важное, чего не было в доках):

- **Мипмапов нет как понятия.** Это жёстче, чем «нет сжатых форматов»: без mip-цепочки
  нет трилинейной фильтрации (минификация алиасится), нет префильтрованного specular
  для IBL, нет bloom по mip-пирамиде. `MipFilter` в `SamplerOptions` присутствует, но
  при одном уровне бессмысленен. Именно поэтому `flutter_scene` требует master
  с 2026-06-09 — там render-to-mip-level уже завезли.
- **`sampleCount` только 1 или 4** — проверка явная, всё остальное бросает исключение
  (`texture.dart:30`).
- **`StorageMode.deviceTransient` = tile memory.** Для MSAA- и depth-вложений это
  прямая экономия памяти и пропускной способности на мобильных; в спайке используется.
  Такие текстуры нельзя биндить в шейдер и нельзя `LoadAction.load`.
- **`Texture.asImage()`** — прямой путь из GPU-текстуры в `ui.Image` без копирования
  через CPU. Это и есть мост в дерево виджетов.
- **`UniformSlot` даёт рефлексию**: `sizeInBytes` и `getMemberOffsetInBytes(name)`.
  Смещения uniform-блока не надо хардкодить — и не надо, потому что правила
  выравнивания GLSL их и определяют.
- **Uniform-блоки рефлексируются по имени ТИПА структуры, текстуры — по имени
  переменной.** Для `uniform FrameInfo { … } frame_info;` ключ рефлексии — `FrameInfo`,
  а для `uniform sampler2D base_color_texture;` — `base_color_texture`. Несоответствие
  не ловится на этапе биндинга: `getUniformSlot` вернёт объект, и только
  `sizeInBytes == null` покажет, что блока нет.
- **Неиспользуемые члены uniform-блока исчезают из рефлексии.** Шейдер, который не
  читает `light_direction`, вернёт `null` на его смещение. Код записи uniform'ов
  обязан быть терпимым к отсутствующим членам, иначе unlit-модель падает.
- **`#include <...>` в GLSL работает** (проверено на impellerc с `--include=shaders`).
  Это единственный способ гарантировать, что все перестановки шейдеров объявляют
  одинаковый uniform-блок.
- **Цена перестановок измерима**: бандл с одним фрагментным шейдером — 12.5 КБ,
  с шестью моделями освещения + вершинным — 80 КБ.
- **`impellerc` умеет `--input-type=comp`**, то есть compute в оффлайн-компиляторе есть,
  а в Dart-API его не выставили. Ограничение на стороне биндингов, не бэкенда.

### Что выяснилось только при запуске

Читать исходники недостаточно — три вещи проявились лишь на живом GPU, и все три
дают «тихий» отказ без единой ошибки в логе:

1. **Flutter GPU включается на уровне приложения.** Ключ `FLTEnableFlutterGPU` в
   `Info.plist` или флаг `--enable-flutter-gpu`. Без него `ShaderLibrary.fromAsset`
   бросает исключение на старте — единственный случай из трёх, который хотя бы виден.
   Отдельно нужен `FLTEnableImpeller`: на macOS Impeller пока не рендерер по
   умолчанию, и без этого ключа собранное приложение запускается только через
   `flutter run --enable-impeller`, а двойным кликом падает.
2. **`Viewport` и `Scissor` по умолчанию нулевого размера,** и API на отрисовку в
   такой прямоугольник не жалуется. Выставлять явно каждый кадр.
3. **Рефлексии нельзя доверять в вопросе «биндить или нет».** Если шейдер
   *объявил* uniform-блок (например, притащил его через общий `#include`), но
   ничего из него не читает, рефлексия всё равно отдаёт блок с **ненулевым
   размером**, тогда как в скомпилированной Metal-функции соответствующего
   буфера нет вовсе: сигнатура вырождается в `normals_fragment_main(in [[stage_in]])`.
   Биндинг такого «фантомного» блока даёт `SIGSEGV` внутри
   `setFragmentBuffer:offset:atIndex:` — нативный креш без Dart-стектрейса.
   Проверка `sizeInBytes == null || == 0` **не спасает**. Движок обязан знать из
   своих метаданных перестановки, какие блоки шейдер реально использует, а
   шейдеру, которому материальные входы не нужны, не следует их объявлять.
   У нас на это наступила отладочная модель `Normals`; лечится разделением
   общего заголовка (`lib/color.glsl` без uniform'ов, `lib/surface.glsl` с ними)
   плюс явным флагом `LightingModel.usesFragInfo`.
4. **`CommandBuffer.submit()` асинхронный.** `HostBuffer.reset()` сразу после него
   отматывает bump-аллокатор, из которого GPU ещё читает. Симптом — не падение, а
   мерцание геометрии и освещения под нагрузкой, что диагностируется гораздо хуже.
   Лечение — кольцо host-буферов по числу кадров в полёте (у нас 3).

Отдельно стоит отметить, что самая дорогая по времени ошибка оказалась не в
flutter_gpu, а в собственной матрице проекции: `Matrix4.setEntry` принимает
`(row, column)`, и два элемента строки глубины легко поменять местами. Результат —
чёрный вьюпорт при полном отсутствии ошибок. Такое ловится юнит-тестом без GPU
(`test/projection_test.dart`), и это аргумент за то, чтобы камера и математика
жили в слое, не зависящем от flutter_gpu.

Что осталось непроверенным: MRT только по структуре кода, рантайм-поведение не проверялось;
бенчмарк draw calls и GC-пауз при 10k трансформов не делался.

---

## 5. Рекомендуемая последовательность

1. **Спайк**: треугольник → текстурированный куб с трансформом и depth-тестом.
   Заодно проверить 4 вопроса из §4.
2. **Слой 0 + 1 + 2 (P0)**: RHI-обёртка, кэш пайплайнов, аллокаторы, граф сцены, камера, ввод.
3. **Первая веха**: glTF-модель с PBR-материалом и IBL, MSAA, tonemapping, orbit-камера.
   На этом этапе становится ясно, выдерживает ли выбранная стратегия шейдеров.
4. **Слои 6–7 (P1)**: тени, HDR-пайплайн, сортировка, bloom.
5. **Слои 8–9 (P1)**: анимация, скиннинг, асинхронная загрузка в Isolate, свой бинарный формат.
6. **Frame graph** — до того, как пост-обработка станет неуправляемой.
7. Дальше по приоритетам P2/P3 в зависимости от предметной области.

---

## Источники

- [flutter_gpu library — Dart API](https://api.flutter.dev/flutter/flutter_gpu/)
- [Flutter-GPU.md — engine docs](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md)
- [Getting started with Flutter GPU — Flutter Blog](https://flutter.dev/blog/getting-started-with-flutter-gpu)
- [What Is Flutter GPU: How It Works, When to Use It, Limitations — LeanCode](https://leancode.co/glossary/flutter-gpu)
- [flutter_scene — pub.dev](https://pub.dev/packages/flutter_scene)
- [bdero/flutter_scene — GitHub](https://github.com/bdero/flutter_scene)
- [Introducing Babylon.js 8.0](https://babylonjs.medium.com/introducing-babylon-js-8-0-77644b31e2f9)
- [Announcing Babylon.js 8.0 — Windows Developer Blog](https://blogs.windows.com/windowsdeveloper/2025/03/27/announcing-babylon-js-8-0/)
- [BabylonJS/Babylon.js — DeepWiki overview](https://deepwiki.com/BabylonJS/Babylon.js/1-overview)
- [mrdoob/three.js — DeepWiki](https://deepwiki.com/mrdoob/three.js)
- [Three.js — WebGPURenderer manual](https://threejs.org/manual/en/webgpurenderer.html)
- [Clustered Lighting — PlayCanvas Developer Site](https://developer.playcanvas.com/user-manual/graphics/lighting/clustered-lighting/)
- [PlayCanvas Engine](https://playcanvas.com/products/engine)
- [[Impeller] Support compute passes/shaders — flutter/flutter#109346](https://github.com/flutter/flutter/issues/109346)
