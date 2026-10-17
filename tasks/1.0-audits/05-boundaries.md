# Аудит границ пакетов flutter3d (рабочее дерево, ветка 0.9.0, 2026-10-09)

Заметки агента. Прогон `dart run tool/structure.dart` на текущем дереве: **70 правил, 68.7 с, all held, exit=0**. Раздел «State when the weekly limit hit» в `tasks/1.0-boundaries.md:155-180` устарел: B1, B3 и C в дереве доделаны, все 9 правил включены и зелёные.

## 1. Статус девяти запланированных правил (`tool/structure/layers.dart`, `boundaries.dart`, `rules.dart`)

| # | Правило | Реализация | Включено | Проходит | Что НЕ покрывает |
|---|---|---|---|---|---|
| 1 | Матрица слоёв | `packageLayers` (L0–L9, 59 пакетов) + `layerForbidden`, `layerProblems` → `_layersBelow` (rules.dart:5118) | да | да | только `dependencies:` пакетов; не смотрит dev_dependencies, импорты и `apps/` |
| 2 | Нет зависимости ради реэкспорта | `reexportOnlyDependencies` → `_noReexportOnlyDependency` (rules.dart:5555) | да | да | — |
| 3 | Allowlist реэкспортов с причиной | `reexportsAllowed` (10 пар) + `reexportedWhole` (1) → `_reexportsAllowedOnly` (rules.dart:5502) | да | да | реэкспорт pub-пакетов (`vector_math` из `flutter3d.dart:669`) не проверяется |
| 4 | Declare what you name | `undeclaredNames` → `_declareWhatYouName` (rules.dart:5607), покрывает пакеты и apps (lib/, bin/) | да | да | только типы из api-снапшотов (функции, константы, pub-пакеты — нет); hook/, test/ — нет |
| 5 | plugin_api = контракт, бюджет, фазы | `unreachableContractTypes`, `pluginApiTypeBudget=57`, `phasesNamedForAPackage` → `_pluginContract` (rules.dart:5267) | да | да | — |
| 6 | Сим-стек не импортирует core/hardware/shaders/particles | `simulationImportProblems` → `_simulationDrawsNothing` (rules.dart:5166) | да | да | только lib/ (test/ не читается) |
| 7 | Runtime не зависит от editor_*/build/mcp/model_core | `runtimeToolDependencies` → `_runtimeIsNoTool` (rules.dart:5210); одно исключение `effects -> build_hooks` | да | да | только пакеты; apps не проверяются (см. ниже lesson_viewer → editor_core) |
| 8 | Одно имя — один дом | `namesWithTwoHomes`, `publicNameSharedOnPurpose = {}` → `_oneHomePerName` (rules.dart:5391) | да | да | читает api-снапшоты → приватные/скрытые дубли не видит |
| 9 | internal/builtin/testing по allowlist | `restrictedLibraryUsers` → `_restrictedLibraries` (rules.dart:5424) | да | да | — |

Плюс старое правило «no package reaches into another package's src» (rules.dart:745) — только lib/ пакетов, по замыслу.

## 2. Нарушения по убыванию серьёзности

**A. Хуки демо-игр тянут `flutter3d_build` → `flutter3d_mcp` → `dart_mcp` в игру (остаток цепочки «effects → build → mcp»).**
В пакетах цепочка разорвана: `effects` зависит от `flutter3d_build_hooks` (`packages/flutter3d_effects/pubspec.yaml:55`), а `build_hooks` зависит только от core/hardware/foundation/shaders. Но три приложения:
- `apps/flutter3d_demo_dungeon/hook/build.dart:1-2`, `apps/flutter3d_demo_platformer/hook/build.dart:1-2`, `apps/flutter3d_demo_racing/hook/build.dart:1-2` — `import 'package:flutter3d_build/flutter3d_build.dart'` и `package:hooks/hooks.dart`; при этом `flutter3d_build` у всех трёх лежит в `dev_dependencies`, а `hooks` не объявлен вовсе. Комментарий в `effects/pubspec.yaml` сам говорит, что хук может импортировать только `dependencies:`. Правила 1/4/7 этого не видят (apps + hook/ вне охвата).

**B. Приложения-вьюверы зависят от инструментов (правило 7 не распространяется на apps).**
- `apps/flutter3d_lesson_viewer/lib/main.dart:29` и `apps/flutter3d_stereo_lesson_viewer/lib/main.dart:41` — `import 'package:flutter3d_editor_core/...'`. Оба стоят на `flutter3d_app`, то есть это runtime, а не редактор.
- `apps/flutter3d_editor` (25 файлов) и `apps/flutter3d_modeler` (99 файлов) импортируют editor_*/mcp/model_core законно (это и есть инструменты).

**C. `plugin_runtime` всё ещё знает про чужие секции (move 14 сделан наполовину).**
`DataSectionRegistry` есть (`packages/flutter3d_plugin_api/lib/src/data_section.dart:122`), секции регистрируют `flutter3d_particles/lib/src/effects_section.dart` и `flutter3d_matter/lib/src/materials/material_sections.dart`. Но:
- `packages/flutter3d_plugin_runtime/lib/src/data/data_sections.dart:30-39` — `runtimeKeys` жёстко содержит `'materials'`, `'renderSteps'`, `'entityKinds'`, `'shaders'`;
- `data_plugin.dart:413` читает `entries('materials')` сам (`DataMaterial`), `:500` разбирает `entry['shaders']`, `:588` пишет `'materials'` в JSON, `:128` — `'shaders'`;
- ради этого `plugin_runtime` держит зависимости на `flutter3d_core` (3 импорта: `data_plugin.dart:4 show RendererSteps`, `runtime_shaders.dart:5`, `material_wgsl.dart:43`), `flutter3d_sim` (`data_entity_kind.dart:2`, `data_plugin.dart:6 show EntityKinds`), `flutter3d_shaders/translate.dart`, `flutter3d_physics`, `flutter3d_hardware`. Для «плоского» рантайма (он в `flatDartPackages`) это тянет рендер-ядро на сервер реплея.

**D. Sim/view: прямое чтение симуляции вьюхами (мимо `published`).**
Механика правильная: `LoopContext.world` бросает `StateError` в frame-фазе (`packages/flutter3d_sim/lib/src/loop/engine_loop.dart:1267-1278`), `LoopContext.published` есть (`:1281`), `PublishedWorlds` (`loop/published_worlds.dart`). В пакетах frame-фазы `world` не читают (0 совпадений). Но элементы живут вне ECS, и вьюхи читают их напрямую:
- `packages/flutter3d_effects/lib/src/elements.dart:283` — `NativeWorld get world => simulation.world;` — вью отдаёт наружу нативный мир симуляции; `:150`, `:278` читают `simulation.world`.
- В демо из виджетов/вью: `apps/flutter3d_demo_reef/lib/main.dart:611` (`pressureAt(run.world, …)` в `Text`), `apps/flutter3d_demo_hollow/lib/reel_main.dart:91` (`run.world.isBurning`), `apps/flutter3d_demo_platformer/lib/src/elements.dart:165` (`world.restore(run.world.snapshot())` — копирование мира в «рисующий» мир каждый кадр).
- Слияние `TrackedBody.look: SceneNode` / `WaterBody.view` устранено: в `elements` (`simulation.dart:388`, `:497`) нет SceneNode; в `effects/src/elements.dart:416` — `Map<TrackedBody, SceneNode> _looks`, `:673 final LiquidView view` (в `_DrawnWater`, это вью-пакет — нормально). `elements` импортирует только foundation/plugin_api/physics_native/vector_math.
- View-типы в sim: `CameraRig`/`PhotoCamera` переехали в `flutter3d_camera` (`camera_rig.dart:30`, `photo_camera.dart:40`). Остались `Lightmap`/`LightmapBaker` (`packages/flutter3d_sim/lib/src/level/lightmap_baker.dart:53` — трассировка света по тексели в сим-стеке; план: «LightmapBaker → build», не сделано) и `SequencePlayer` (`sim/src/cinema/sequence_player.dart:69`, степается, `with ActorDirector` — спорно, ARCHITECTURE.md:263 объявляет это сознательным).

**E. Глобальное мутабельное состояние в lib/ (правило `nothing shares a mutable value as a constant` ловит только `static final Vector3/Matrix4`; остальное не ловится).**
- `packages/flutter3d_game/lib/src/run/game_events.dart:41` — `ToolEventPoster? toolEventCapture;` (бывший `postGameEvent`; переключается из `flutter3d_game/lib/testing.dart:19`).
- `packages/flutter3d_game/lib/src/run/run_timeline_extensions.dart:147,150` — `_onService`, `_timelineExtensions` (процесс-wide).
- `packages/flutter3d_physics_native/lib/src/native_physics.dart:158` — `PhysicsStart? _chosen;` — выбор бэкенда физики на весь процесс, «chosen the first time anything asks and the same every time after».
- `packages/flutter3d_app/lib/src/backend_native.dart:79-80` и `backend_web.dart:128-129` — ленивый глобальный `DeviceRegistry _presenters` (наследник `defaultDevices`); `presenterFor` теперь через `is`, а не `runtimeType` (`hardware/src/device_registry.dart:125-146`) — закрыто, но результат `Object?` и каст `as FramePresenter?` в `backend_native.dart:125-128`.
- `packages/flutter3d_mesh/lib/src/extrude.dart:155` — `List<int> _lastMoved` в чисто геометрическом пакете.
- `packages/flutter3d_plugin_api/lib/src/vm_extensions.dart:47,51` — `_registered`, `_aliases` (только растут, по замыслу VM-service).
- `packages/flutter3d_app/lib/src/diagnostics/render_extensions.dart:264 bool _registered`, `hot_swap/hot_swap.dart:98 static bool _extensionRegistered`, `flutter3d_core/src/engine/scene/scene_node.dart:39,48,50,141` — статические счётчики `_versionCounter`, `_dirtyEpoch`, `_ancestorWalks`, `_debugViewsSet` (общие для всех сцен в изоляте).
- Синглтоны платформ: `pad_input/lib/pad_input.dart:81-82`, `pointer_lock/lib/pointer_lock.dart:54-55` (ожидаемо для plugin-пакетов).
- `.runtimeType` для диспетчеризации в lib/ не найден (единственное — `hardware/src/resources.dart:152`, `==`).

**F. Дубли, которых правило 8 не видит (приватные или скрытые из barrel).**
- `Portable`: `packages/flutter3d_foundation/lib/src/portable_math.dart:89` и копия `packages/flutter3d_model_core/lib/src/rig/portable_math.dart:48`. Обоснование копии в шапке файла устарело («не зависеть от flutter3d_sim») — model_core уже зависит от foundation (`pubspec.yaml:60`).
- `UniformMemberLayout`: typedef в `flutter3d_hardware/lib/src/shader.dart:44` и структурная копия в `flutter3d_shaders/lib/src/uniform_blocks.dart:12`.
- `ClothMesh`/`ClothSettings`/`JointType`: `flutter3d_physics` (`cloth_mesh.dart:10`, `cloth_settings.dart:11`, `physics_backend.dart:87`) и `flutter3d_physics_native` (`native_cloth.dart:14,104`, `core/constants.dart:101`) — скрыты `hide` в barrel (`flutter3d_physics_native.dart:18-25`), но внутри пакета имена те же.
- `EcsWorld` (`sim/src/ecs/ecs_world.dart:47`) extends `SimWorld` (`plugin_api/src/ecs.dart:345`) — теперь наследование, а не два мира.
- Публичные дубли из плана (`Brush`, `LevelValidator`, `Particle`, `AddLight`, `MoveBy`, `Listed`, `Pose`, `Body`, `Heightfield`, `Selection`, `Tally`, `DocumentText`) — по одному дому каждый, закрыто.
- game vs game_ui: виджеты ушли в `game_ui` (credits `screens/credits.dart`, `hud/mini_map.dart`, `hud/automap_view.dart`, `touch/*`); в `flutter3d_game/lib` ни одного `StatelessWidget/StatefulWidget`, 12 файлов импортируют Flutter ради платформенных вещей (`screens/touch_platform.dart`, `input/desktop_input.dart`, `cloud/platform_cloud_saves.dart` и т.д.) — закрыто.

**G. Демо-приложения копируют движок.**
- `apps/flutter3d_lesson_viewer/lib/main.dart:69` и `apps/flutter3d_stereo_lesson_viewer/lib/main.dart:69` — своя `OpenKind extends EntityKind`, хотя `OpenKind` живёт в `flutter3d_sim/lib/src/level/entity_kind.dart:223`, а оба приложения sim импортируют; комментарий ссылается на «flutter3d_game's own OpenKind» — устарел.
- `apps/flutter3d_demo_racing/lib/src/elements.dart:30` — своя `abstract final class ElementSounds` (файл 1286 строк) при `flutter3d_game_physics/lib/src/elements/element_sounds.dart:77 class ElementSounds`.
- Одноимённые классы app↔package (разная семантика, но та же роль): `LessonPlayer` (`apps/flutter3d_lesson_viewer/lib/src/lesson_player.dart:93` ↔ `flutter3d_stereo/lib/src/lesson_player.dart:93` — одинаковая строка объявления, похоже на копию файла), `PlaySession` (modeler ↔ `flutter3d_mcp/src/editor/play_session.dart:72`), `Playback` (modeler ↔ `sim/src/save/playback.dart:14`), `HeatmapCell` (editor ↔ `sim/src/telemetry/heatmap.dart:43`), `CommandPalette`/`DockLayout`/`PaletteEntry` (modeler ↔ `editor_widgets`/`editor_core`), `RunState` (demo_river ↔ `game_platformer`), `Looks` (demo_racing ↔ `editor_core`).
- Между демо: `Reactions` (dungeon/racing/platformer, 122–180 строк каждая, все поверх `flutter3d_game_kit/reactions.dart` — это контент, не копия системы), `Effects`, `Sounds` ×4, `Staged` ×3 (+`flutter3d_demo_content/lib/shooter_staging.dart:62`).

**H. Cross-package `src/` импорты.** В `packages/*/lib`: **0** (правило держит). В тестах — **~80 строк**: `packages/flutter3d/test/*` (≈45 строк в `flutter3d_core/src/engine/...`), `flutter3d_demo_content/test/shooter/*` (≈25 в `flutter3d_sim/src/...`), `flutter3d_particles/test`, `flutter3d_cpu/test`, `flame_flutter3d/test`, `flutter3d_model_core/test`, `flutter3d_webgl/test`, `flutter3d/test/cpu_reflection_probe_test.dart:24` (`flutter3d_cpu/src/cpu_shaders_builtin.dart`). В `apps/*/lib`: только свои `src/` (showcase). Правило сознательно тесты не проверяет, но тесты `flutter3d` на `core/src` — признак, что `flutter3d_core` недоэкспортирует то, что `flutter3d` тестирует.

**I. Flutter в plain-Dart пакетах.** Во всех 22 перечисленных: lib/bin = 0 импортов `package:flutter/`, `dart:ui`, `flutter_test`; test = 0. `flatDartPackages` (`repository.dart:92`) покрывает 31 пакет, включая physics, physics_native, shaders, hardware, camera, post, editor_*, effects, net, cpu, conformance, level_scene, audio_core (пункт из arch-review «Should» закрыт). **`flutter3d_sim_mcp` не plain-Dart по замыслу** — `pubspec.yaml` объявляет `flutter: sdk` и объясняет почему (`dart:ui` через `flutter3d`/`cpu`); в его `test/fixtures/render_mcp_server.dart:16` `flutter_test`. Из списка в задаче его стоит убрать, а не чинить.

**J. Инверсии слоёв по pubspec.** Все закрыты: сим-стек (sim/physics/physics_native/elements/matter/foundation) не имеет зависимостей на core/hardware/shaders/particles/бэкенды; `core` → physics убрано (`core/pubspec.yaml` без physics, в lib/ 0 импортов; единственное упоминание — `fix_data.yaml`); `physics_native` → core запрещено явно (`layerForbidden`); `hardware` → только foundation/meta/vector_math; `plugin_api` → только foundation; backends друг друга не импортируют в lib/ (webgl/webgpu держат `flutter3d`, `flutter3d_core`, `flutter3d_cpu` только в `dev_dependencies` — паритетные тесты); `app` → `level_scene` вместо `editor_core`; `editor_core` → `level_scene`.

## 3. Реэкспорты (`export 'package:'` в `packages/*/lib/*.dart`, кроме src/)

| Файл:строка | Цель | show | В allowlist |
|---|---|---|---|
| `flutter3d_game/lib/flutter3d_game.dart:49` | flutter3d | **нет** (целиком) | да, `reexportedWhole` |
| `…:50` app, `:67` audio_core, `:69` physics, `:71` sim | — | show | да |
| `flutter3d/lib/flutter3d.dart:44` core, `:537` foundation, `:567` hardware | — | show | да |
| `flutter3d/lib/flutter3d.dart:669` | **vector_math (pub)** | show | вне правила |
| `flutter3d_plugin_api/lib/flutter3d_plugin_api.dart:37` | foundation | show | да |
| `flutter3d_audio/lib/flutter3d_audio.dart:14` | audio_core | show | да |
| `flame_multiplayer/lib/flame_multiplayer.dart:39` | flutter3d_net | show | да |
| `flutter3d_mcp/lib/model.dart:43` | свой `kit.dart` | — | свой |
| `flutter3d_post/lib/standard.dart:32-37` | свои 6 библиотек | нет | свой |

Пакетов «только ради реэкспорта» нет (`flutter3d` больше не зависит от sim/physics/audio_core — проверено, в `layerForbidden`). `flutter3d_sim` физику не реэкспортирует (31 прямой импорт physics, 0 export).

## 4. Необъявленные и неиспользуемые зависимости

**Импортируется, но не в той секции pubspec** (после отсева шаблонных строк `flutter3d_build/lib/src/{project,plugin}_template.dart`, фикстур `migrate_test.dart`, `example/`-пакетов со своими pubspec и `.dart_tool`):

| Пакет/app | Импорт | Где | В pubspec |
|---|---|---|---|
| demo_dungeon, demo_platformer, demo_racing | `hooks` | `hook/build.dart:2` | **нет** |
| demo_dungeon, demo_platformer, demo_racing | `flutter3d_build` | `hook/build.dart:1` | dev_dependencies |

**Объявлено, но нигде не импортируется** (lib/test/example/hook):

| Пакет/app | Зависимость | Секция | Примечание |
|---|---|---|---|
| flutter3d_conformance | flutter3d_physics | dependencies | план: «conformance's dependencies» |
| flutter3d_showcase | flutter3d_hardware, flutter3d_mesh, flutter3d_samples | dependencies | |
| demo_arcade | flutter3d_app | dependencies | |
| demo_reef, demo_strategy | flutter3d_physics | dependencies | возможно ради правила 4 (имена через фасад `flutter3d_game`) |
| demo_water, lab_incident, lab_pendulum, lesson_viewer, stereo_lesson_viewer, flame_flutter3d_audio | vector_math | dependencies | имена `Vector3` приходят через реэкспорт `flutter3d.dart:669` |
| flutter3d_app | flutter3d_testing | dev | |
| flutter3d_testing, lesson_viewer | flutter3d_samples | dev | |
| lab_incident | flutter3d_cpu | dev | |

Итого: 6 реальных необъявленных (все в хуках демо), 17 неиспользуемых.

## 5. Что ловит tool/structure, а что нет

Ловит: всё из таблицы §1, foreign `src/` в lib/, Flutter в 31 плоском пакете (текст + граф pubspec), `static final Vector3/Matrix4`.
Не ловит: (a) apps целиком для правил 1, 2, 3, 6, 7 — отсюда A и B; (b) `hook/` для правила 4; (c) приватные дубли кода (F); (d) мутабельные top-level/static поля кроме Vector3/Matrix4 (E); (e) реэкспорт pub-пакетов; (f) прямое чтение `simulation.world`/`run.world` из вью (D) — `LoopContext.world` защищён только внутри loop-фаз; (g) `src/` в тестах (по замыслу).
