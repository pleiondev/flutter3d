# Ревью публичного API перед 1.0.0-rc.1 (рабочее дерево ветки 0.9.0, 2026-10-09)

Заметки агента. Источники: `packages/*/api/*.api` (57 снапшотов), барреты `lib/*.dart`, `lib/src` для контекста, `tasks/1.0-stability.md` (решения 5–7), `tasks/1.0-api-review.md` (§A, §E, решения Дмитрия 1–8). Все числа — из `rg` по рабочему дереву. Ничего не менял.

Общее впечатление: большая часть механики из `1.0-api-review.md` уже сделана (0 дублей имён между пакетами, wire-таблицы для enum'ов, `show`-списки почти везде, нет `gpu.`/`SoLoud`/`web.` в приоритетных снапшотах, 0 `dynamic`). Ниже — то, что осталось и что под strict semver потом не исправить без мажора.

---

## 1. MUST — сломается позже, править до rc.1

| # | Что | Где | Почему это мажор потом |
|---|---|---|---|
| 1.1 | **Публичные record-typedef'ы в implementable-интерфейсах.** `CharacterMoved` — 9-полевой record, который возвращает `CharacterMover` (пользователи его реализуют по решению 6). `JetDrop` — 5-полевой record в `LiquidSink.receive`. | `flutter3d_physics.api:34`, `:455`, `:463` | Добавить поле в record нельзя без смены типа: ломаются и реализации, и деструктуризация. Заменить на `final class` с именованным конструктором. |
| 1.2 | **36 публичных членов возвращают record'ы** (core 18, sim 6, game 4, physics 2, foundation 3, audio 1, net 1). Самые рискованные: `IrradianceField.toAtlas()` (5 полей, core:1791), `PhysicalSky.look()` (core:3143), `Telemetry.prepare()` (sim:2687), `Spawn.spawnIn()` (game:528), `LoopbackWire.pair()` (net:30). | см. `rg '^\s+(static )?\([^)]*\) \w+\('` по приоритетным api | То же: record нельзя расширить. Оставить record'ы только для математических пар (`sinCos`, `uvAt`, `toSrgb`), остальное — классы. |
| 1.3 | **`abstract interface class` у backend-интерфейсов аудио**: `DirectionalBackend` (`placeVoice`), `MixingBackend` (`mixBus`, `routeVoice`). Решение 5/§A.1: всё implementable — `abstract base class` с дефолтами. | `flutter3d_audio_core.api:112`, `:217` | Новый метод в миноре сломает сторонний аудио-бэкенд. Третий — `PlacedEvent` в foundation (`:89`), его тоже реализуют снаружи. |
| 1.4 | **`sealed` там, где множество будет расти.** `Recorded` — 22 подтипа, запись HAL-команд (hardware:1254): каждая новая команда HAL ломает exhaustive `switch` пользователя. `CollisionShape` — 6 подтипов (physics:186), §B обещает «custom shape via ShapePhysics». `ActionBinding` — 5 (game:15; XR/жесты добавятся). `TimelineCommand` — 8 (game:819). `MaterialExpression` — 20 (core:2210). | `rg '^sealed'` → 26 строк (core 11 с дублями двух библиотек, sim 7, game 6, hardware 1, physics 1) | §A.2: `sealed` — только где exhaustive matching и есть цель (результаты: `SaveRead`, `ServiceAnswer`, `LevelPatchResult`, `Resimulation`, `TapeBisection`, `RunStatus` — ок). Остальные → `base`/`abstract base`. |
| 1.5 | **Enum-ы в «открытых» множествах, пропущенные §A.2.** `LevelLightType` (sim:1409) и `ModelLightType` (core:2648) остались `enum`, хотя `LightType` уже `final class` (core:1957). Также `ShadowCastingMode` (core:3919), `MaterialAlphaMode` (core:2107), `AnimationBlend`, `DiffuseModel`, `SortMode`, `TangentMethod`. Всего enum'ов: hardware 28, core 42, sim 6, physics 1, game 2. | см. `rg '^enum '` | В Dart `switch` по enum обязан быть исчерпывающим → добавление значения в миноре ломает пользовательский код. Каждый публичный enum = замороженное множество. Для GPU-констант (BlendFactor, CompareFunction…) это нормально; для light/shadow/material — нет. |
| 1.6 | **Четыре формы одного глагола `open` у устройств.** `DeviceRegistry.open({width,height,onFallback}) → Future` (hardware:317); `openDevice({width,height,registry?})` — глобальная функция в app (app:681, 45 файлов в apps); `WebGlDevice.open(...) → WebGlDevice` **синхронно** (webgl:60) при решении §E.3 «open — асинхронный»; `WebGpuDevice.open → Future` (webgpu:67); `GpuRenderBackend.open({bundleAsset, extraBundles})` **без width/height** (impeller:48) при `BackendOpener = Future<GraphicsDevice> Function({required int width, required int height})` (hardware:27). | | HAL на своей версионной линии (решение 2) — потом не выровнять. |
| 1.7 | **Исключения, которые бросаются, но не экспортированы.** `MissingToolException`, `ToolFailedException` объявлены в `flutter3d_build/lib/src/convert/external.dart:125,136`, бросаются 4 раза, в `flutter3d_build.api` их нет. | | Пользователь CLI/hook не может поймать по типу; добавить в экспорт потом — ок, но тип уже «утёк» через стек. Проще добавить сейчас. |
| 1.8 | **Deprecation с до-1.0 датой: `TonemapCurve.agxFull`** — «Deprecated in 0.7.4, removed in 2.0.0». | `render_settings.dart:2527`, core.api:4394 | Решение 4 заставит держать его до 2.0. До 1.0.0 ломать можно бесплатно — удалить сейчас. Остальные 7 `@Deprecated` (plugin_api `LoopPhase.elements`, sim `Level.gravity` ×2, physics/physics_native `oil`, build `legacyPluginMarkerKey`) — формат верный («Deprecated in 1.0.0, removed in 2.0.0»), но это тоже deprecation *в самом* 1.0.0 — стоит решить, не удалить ли их до rc.1 вовсе (ничего в репо их не использует). |
| 1.9 | **`Vector3` как цвет в формате уровня.** `Level.fogColor: Vector3` (sim:1349), `LevelLight.color: Vector3` (sim:1396, 1402), `writeIrradiance(..., Vector3 color)` (core:1817), `BlackBody.color(kelvin) → Vector3` (effects:15), `outlineColorOf(Color) → Vector3` (game:889). Решение §E.11: один тип цвета, `LinearColor`. | | `Level` — самый массовый тип у пользователей; смена типа поля позже — мажор. |
| 1.10 | **`null` как ошибка у `load*`/`decode*`.** Решение 4: create/open/load бросают. Осталось: `EncodedImageUpload.decodeTexture → Future<TextureHandle?>` (hardware:341), `loadEnvironment/loadTexture → Future<…?>` (app:181,183), `ConvertCommandSettings.parse → ?` (build:28), `DeviceClass.parse → ?` (core:887). Всего нуллабельных create/open/load/decode/parse/read: 22 (было 74); остальные — честное «read → null когда нет». | | Смена `T?` → `T` + throw — поведенческий break. |

---

## 2. SHOULD — не ломает немедленно, но закрепит неудобную форму

**2.1 Фасады и re-export.**
- Единственный re-export без `show`: `flutter3d_game/lib/flutter3d_game.dart:49` → `export 'package:flutter3d/flutter3d.dart';`. Это по §E.14 («game re-exports flutter3d»), но противоречит решению 7 («барреты называют, что re-export'ят»). Нужен явный список, иначе каждая минорная добавка в `flutter3d` молча расширяет surface `flutter3d_game`.
- `flutter3d` сам — фасад: `show` над core (~540 имён), foundation (~157), hardware (~149), vector_math (5 типов). §E.14 обещал, что `flutter3d` дотягивается до sim/audio/physics — не сделано (0 таких экспортов). `flutter3d_sim` ничего не re-export'ит (120 `src/`-экспортов) — это не фасад, задача это и предполагала.
- `flutter3d_post/lib/standard.dart:32-37` экспортирует 6 своих библиотек без `show` — внутри пакета, терпимо.
- Прочие `export 'package:'` (plugin_api←foundation, audio←audio_core, flame_multiplayer←net, mcp/model←kit) — с `show`.

**2.2 HAL: две формы одного.**
- `createBuffer` и `createStorageBuffer` оба на `GraphicsDevice` (hardware:371-430).
- `SynchronousBufferReadback.readBufferSync` — всё ещё в основной библиотеке hardware (`:770`), им mixin'ятся `WebGlDevice`, `CpuDevice`, `FakeBackend`, `RecordingDevice`. §E.12 обещал перенести в testing.
- `DeviceRegistry.presenterFor(device) → Object?` и `addPresenter<T>(Object presenter)` (hardware:319, 321) — нетипизированные.
- 8 top-level `wrap*({required Object backend})` + 8 `final Object backend` полей (hardware:9-23, 146…902) — SPI бэкендов в том же снапшоте и на той же версионной линии, что и пользовательский HAL. Вынести в `backend.dart` уже сделано (library есть), но snapshot один.
- Комментарий `graphics_device.dart:525-535` утверждает, что `supportsX`-геттеры `@Deprecated` — их в коде 0. Стейл.
- `addMaterials` в двух местах — **уже нет**: только `Scene.addMaterials(ShaderLibrary)` core:3665 (plugin_runtime `addMaterial(String)` — другое). `readPixels` в core нет (есть `captureNextFrame`/`captureObjectIds`). `defaultDevices` в снапшотах нет.

**2.3 Три словаря для «выключенного шага» в core.** `RenderSettings.stepsOff` (поле, :3474) + `switchedOffSteps` (геттер, :3448) + `only()/without()` (:3445, :3447) + `FrameGraph.compile(disabled:, switchedOff:)` по строкам (:1384) + `PassSkip.disabled`/`.switchedOff` (:3043-3045). Выбрать один («off»), остальные — nit, но после 1.0 переименование = deprecation на мажор.

**2.4 `Map<String, double>` как контракт** — 27 вхождений в приоритетных api: `InputFrame.axes/tunes/values` (sim:1159-1161), `Tunables` (sim:2757-2760), `AnimationParameters.loadByName(Map<String,double>)` (core:237), `ElementsSteps.elements: Map<String,bool>` (elements:240). Физика (`concentrations`, 11 мест) — предметно оправдано. §B обещал `SettingKey<T>`.

**2.5 Точка входа.** Quickstart (`site/content/quickstart.md:125-202`) ведёт Flutter3dView → Scene3D → SceneSurface; скаффолд `flutter3d create` генерирует **Scene3D** (`project_template.dart:65`); демо используют **SceneSurface** (25 файлов в 10 apps) + `openDevice` (45 файлов); `Flutter3dView` — только в platformer (3 файла). `Flutter3dView` имеет **34 именованных параметра** (app:107), среди них пересекающиеся владельцы `device`, `renderer`, `devices`, `presenter`, `views` — §C обещал «явный owner». Три входа с разной эргономикой и ни один не «первый» во всех трёх источниках.

**2.6 Позиционные конструкторы ≥3 у растущих типов** (всего 29): `SilentVoice(id, asset, gain, pan, rate, loop)` (audio:254), `Emission(effect, origin, perSecond, direction, remaining)` (particles:115), `RoomDoor(side, offset, width, height)` (sim:2166), `Audible(key, at, loudness, rate)` (effects:8), `TraceDispatch` (hardware:1611). Для `LinearColor`, `WorldPosition`, `RgbValues`, `PluginVersion` — норма.

**2.7 Mutable-поля на объектах, которыми владеет движок.** `Collider.kind/shape/world/userData/material` — не `final` (physics:90-95); `world` должен ставить `CollisionWorld`. В audio_core мутабельные `gain/pan/rate/muffle` на `AudioEmitter`/`SilentVoice`/`SpatialResult` (:42-46, :256-261, :300-306) — это состояние, ок. В hardware 9 мутабельных примитивов — все в `Fake*` testing-типах (но они в том же снапшоте).

**2.8 Dart-core исключения на публичных путях.** 987 `throw` в приоритетных lib, 350 — Dart-core (ArgumentError 242, StateError 91, UnsupportedError 10, RangeError 7). `UnsupportedError` вместо `UnsupportedCapability`: `render_pass_descriptor.dart:545`, `morph_state.dart:135`, `navmesh.dart:573,576`, `files_web.dart:4`, `atomic_write_web.dart:9-17`. Иерархия в остальном в порядке: 72 exception-подобных класса, 64 под `Flutter3dException`; вне корня — `FrameGraphError`/`DeterminismError extends Error` (программные ошибки, допустимо) и 5 `*Refused` — sealed-варианты результатов (по §E.6). Голых `FormatException` — 0.

**2.9 `static const` лимиты, которые инлайнятся у пользователя:** `maxFramesInFlight = 3` (core:1433), `maxMorphTargets = 8` (:1776), `maxJoints = 64` (:4040), `maxResolution = 4096` (:3996), `maxGoals = 127` (sim:946), `Lightmap.maxSize = 4096` (sim:1634). `LightNode.maxLights` и `Renderer.shadowedLights` уже геттеры — хорошо; остальные лучше тоже геттерами или через `DeviceLimits`.

**2.10 Mixin'ы как capability-проверка** (`is SynchronousBufferReadback`, `is EncodedImageUpload`, `LoadedShaderLibrary`, `RenderBundleEncoder`, `CommandEncoder` — hardware:122-770; `mixin class LightEmitter` particles:156). `DeviceFeature`/`features` уже есть — два механизма для одного.

---

## 3. NIT

**3.1 Британские написания.** В идентификаторах приоритетных api — **0** (`colour/centre/metre/behaviour/initialise/…` не найдены; `ModelLoadRequest` — ложное срабатывание на «modell»). Остались в строках, которые являются частью контракта:
- `ResourceId('hdr_colour')`, `ResourceId('scene_colour')` (core:1458, 1466) — имена ресурсов frame graph, по ним пользователи обращаются в `FrameGraph.compile(disabled: {...})`;
- `RenderStep._('colour grade')`, `'scene colour copy'` (core:3534, 3552) — имена проходов, те же строки-ключи;
- `BehaviorsRead(property = 'behaviour')` (sim:293) — ключ JSON уровня при американском идентификаторе `Behaviors*`;
- `DebugView` описания (11 строк) и `@Deprecated('…catalogue…')` — документация, по решению может быть британской.

**3.2 Глаголы.** `dispose` — основной (hardware 11, app 9, game 6). `release\w*(` — hardware 19, core 10 (часть — callback-параметры `release:` в `wrap*`), game 4. `close` — только net (3), app (1), game (1) — соединения, ок. `make*/take*` — 0. Объектов с `dispose` и `close` одновременно — 0. Остаётся решить, что значит `release` на GPU-хэндлах против `dispose` на устройстве.

**3.3 Единицы.** `Degrees/Deg` — 0 в снапшотах; `fovY` (6) и `yfov` (4, glTF-модель в core) — две записи одного. `Duration` — только на границе Flutter (`FramePacing`, `RenderListener.toBus`, `frameAtVsync`, `due`) — по §E.4. Без суффикса единиц: `stepRate`, `turnRate` (sim), `lossRate` (net) — Hz или доля?

**3.4 Позиционные `bool`** — 10 строк, из них 6 — сеттеры (`set isVisible(bool value)`), 3 — поля record'ов, 1 — `onPausedChanged(bool)`. Пункт §E.5 («37 позиционных bool») фактически закрыт.

**3.5 Дубли имён между пакетами** — **0** на 2884 объявления в 57 снапшотах (типы, extension'ы, top-level функции). Пункт §A.8 закрыт.

**3.6 Enum в сериализации** — `LevelLightType` через `_wireNames` (level_light.dart:24-33), `TextureFormat/QueryType/VertexFormat.byName(String wireName)` (hardware:579, 814, 982), `.f3d` пишет коды (f3d_wire.dart:3). Единственный найденный `.name` в JSON — `animation_graph_json.dart:34` (`'type': p.type.name` для `AnimationParameterType`). Проверить.

**3.7 CLI.** `bin/` содержит 8 исполняемых файлов (`convert, create, flutter3d, init, lights, migrate, plugin_mcp, plugins`), в pubspec `executables:` — один `flutter3d` (решение §C «one executable»). Коды выхода зафиксированы (`cli.dart` api:8-12: ok/failure/usage=2/refused/wouldOverwrite), `--json` со схемой — `cli_contract.dart:77-95`, `pluginAuthorMcpSchemaVersion = '1.0.0'`. Top-level константа `usage` (build.api:587) — слишком общее имя для публичного символа.

**3.8 Plain `class` у 19 виджетов `flutter3d_app`** (`Flutter3dView`, `Scene3D`, `Spatial3D`…) — Flutter-конвенция, но `implements Flutter3dView` снаружи ничто не запрещает; `final class` для не-наследуемых ничего не стоит.

**3.9 `List<T> get`** — core 70, sim 24, game 11 против `Iterable` core 4/sim 9; `Unmodifiable*` — 1 на все приоритетные api. Документировать, что списки — снимки или живые.

---

## Сводка по приоритету

**До rc.1 (мажор потом):** 1.1 `CharacterMoved`/`JetDrop` → классы; 1.3 аудио-бэкенды и `PlacedEvent` → `abstract base`; 1.4 снять `sealed` с `Recorded`, `CollisionShape`, `ActionBinding`, `TimelineCommand`, `MaterialExpression`; 1.5 `LevelLightType`/`ModelLightType` → открытые классы как `LightType`; 1.6 одна форма `open` (async, `width/height`) во всех бэкендах; 1.7 экспортировать `MissingToolException`/`ToolFailedException`; 1.8 удалить `agxFull` (и решить судьбу 7 deprecation'ов в 1.0.0); 1.9 `Level.fogColor`/`LevelLight.color` → `LinearColor`; 1.10 пять `load/decode/parse → null` → throw.

**Желательно:** 2.1 `show` на `flutter3d_game:49`; 2.2 `createBuffer` vs `createStorageBuffer`, `readBufferSync` в testing, типизировать presenter; 2.3 один словарь для off-шагов; 2.5 единая первая точка входа в quickstart/скаффолде/демо; 2.9 лимиты геттерами.

**Косметика:** 3.1 строковые ключи `*_colour`/`'colour grade'`/`'behaviour'` (это тоже контракт — переименование потом потребует миграции файлов и настроек); 3.3 `yfov`; 3.7 лишние `bin/*.dart`.
