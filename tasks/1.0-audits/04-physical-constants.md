# Аудит физических констант, рабочее дерево 0.9.0 → 1.0.0-rc.1 (2026-10-09)

Заметки агента. Все пути — относительно корня репозитория. Проверено: `packages/*/lib`, C-ядро `packages/flutter3d_physics_native/csrc`, шейдеры `packages/flutter3d_shaders/shaders`, `apps/*/lib`, правила `tool/structure/*`.

## Что сделано как задумано (кратко, чтобы не искать)

- **Дома констант существуют и заполнены.** `flutter3d_matter/lib/src/standard_world.dart` (9.81, 293.15, 1.204, 343.0, 101325.0 + `speedOfSoundAt`, `airDensityAt`), `physical_constants.dart` (σ = 5.670374419e-8, R, M, γ, 273.15), `materials/materials.dart` (33 материала, `id: 'f3d.*'`), `world_properties.dart` (`WorldProperties` с gravity/airTemperature/airPressure/airDensityOverride/wind/medium, `toJson/fromJson`).
- **Заголовок C генерируется.** `flutter3d_physics_native/tool/gen_materials.dart` импортирует `flutter3d_matter` и пишет `csrc/src/f3d_materials.g.h` (176 `#define`, 33 материала, `F3D_STANDARD_*`, `F3D_STEFAN_BOLTZMANN`). Скриптом сверено каждое числовое свойство каждого `f3d.*` из `materials.dart` с заголовком: **0 расхождений, 0 пропусков** (mtime заголовка 02:32 старше `materials.dart` 02:54, но содержимое совпадает). Правило `_coreReadsTheCatalogue` (`tool/structure/rules.dart:3969-4035`) запускает `--check` и ловит копии `#define` в C.
- **C-ядро чисто.** `f3d_world.c:26-28` стартует с `F3D_STANDARD_*`; `f3d_shallow.c:307-314`, `f3d_heat.c:110-320` читают `F3D_MAT_*`; `F3D_SAT_HFG = F3D_MAT_WATER_LATENT_HEAT_OF_VAPORIZATION`, `F3D_DRY_AIR_R = R/M` (`f3d_heat.c:982,1074`). Литералов 9.81/998/343/1.2/σ в `.c` нет (только в комментариях).
- **`NativeDynamics`**: вакуум убран (`native_dynamics.dart:53-56`), гравитация пишется в ядро только при изменении `_pushProperties` (`:97-107`), мир в снапшоте (`:352-356, 376-377`).
- **`WorldProperties` — единственный тип мира.** `CollisionWorld.properties`, `NativeWorld` (зеркало ядра), `CryptWorld`/`MapWorld` принимают `WorldProperties` (`flutter3d_demo_content/lib/map_world.dart:384-394`), `Level` читает (`flutter3d_sim/lib/src/level/level.dart:274,304`). `Atmosphere` в core — туман/небо, не воздух.
- **Игровые миры — по одному литералу:** `game_shooter/lib/src/shooter_world.dart:18` (24.0), `game_platformer/lib/src/runner.dart:95` (`runGravity = 24.0`, `platformerWorld` на :51), `game_racing/lib/src/racing_world.dart:19` (20.0), `demo_arcade/lib/src/arcade_game.dart:63` (ноль). Все в `worldLiteralExempt`.
- **Читают мир:** ragdoll/fire (`effects/lib/src/fire_view.dart:558-559` — g и ρ из `NativeWorld`), racing airDrag через `mediumDensity/standardAirDensity` (`sphere_vehicle.dart:731-741`), плавание platformer `buoyancyRatio * gravity` (`runner.dart:1080`), reef `reefSea.density * g` (`demo_reef/lib/src/diver.dart:29,37,422`), `JumpLinks` (`sim/lib/src/nav/jump_links.dart:65-67`), `MovementSettings.gravity` nullable → мир.
- **Эмиссия/π исправлена:** `demo_arcade/lib/src/meteors.dart:216-217`, `demo_strategy/lib/src/effects.dart:247-255`. GLSL π не делит (`material_maps.glsl:89`) — по CONTRACTS эмиссия в нитах.
- **Солнце:** одна константа `ShadowSettings.sunAngularRadius` (см. A4), её читают `sky_settings.dart:60` и `shadow_technique.dart:224`; в шейдерах радиуса нет (`v_disc` из Dart).
- **Allowlist** (`tool/structure/repository.dart:1626-1676`): определения + 3 игровых мира + 3 обоснованных не-мировых числа (erosion 4.0, DOE-HDBK 1.2, цвет 1.204). Чисто.

## A — неверно или две копии, которые обязаны совпадать

**A1. Дефолты `NativeMaterial` в Dart ≠ пресет ядра.** `flutter3d_physics_native/lib/src/native_world.dart:716-745`: `emissivity = 0.9, conductivity = 1.0, modulus = 0.0, poissonRatio = 0.0`. C `f3d_heat.c:83-88`: `emissivity 0.9, conductivity 1.0, modulus 5e10, poisson 0.25`. Материал, собранный в Dart руками без модуля, получает 0 там, где ядро даёт 5e10. Канонический дом — заголовок (`F3D_MAT_*`), но дефолты пресета в него не входят. Две копии вручную.

**A2. Трение по умолчанию — два определения.** `flutter3d_matter/lib/src/materials/material_catalog.dart:295` `defaultFriction = 0.6` и `csrc/src/f3d_world.c:379` `s->friction = F3D_R(0.6)`. Совпадают вручную; в генерируемый заголовок не входит. Dart пишет трение в каждое тело (`native_dynamics.dart:259`), поэтому расхождение проявится только у тел, созданных прямо в ядре.

**A3. Диэлектрический F0 = 0.04 — 16 копий CPU/GPU без общей константы.** GPU: `shaders/lib/pbr.glsl:135, 161, 242, 363, 372, 678, 814, 877`, `shaders/post/reflections.frag:295`. CPU: `flutter3d_cpu/lib/src/cpu_shaders_lit.dart:216, 500, 577, 588, 721, 982`, `cpu_shaders_reflections.dart:201`. Экспорт: `flutter3d_build/lib/src/convert/materialx_input.dart:412,419`. Значения совпадают (CPU и GPU должны сходиться на goldens), константы нет ни в matter (optical group имеет `metal F0`, диэлектрика нет), ни в core. Плюс копии в генерируемых `flutter3d_webgl/lib/engine_shaders.dart`, `flutter3d_webgpu` (51 вхождение `0.04`) — производные, не считаю.

**A4. Радиус солнца: литерал и док расходятся на 0.08 %.** `flutter3d_core/lib/src/engine/render/shadow_settings.dart:170` `sunAngularRadius = 0.00465` рад = 0.2664°, а док там же и решение аудита говорят 0.2666° (= 0.004653 рад). Небо и PCSS согласны между собой, но число не то, что заявлено.

## B — захардкожено там, где должен читаться мир / каталог

**B1. Скорость звука не доходит до аудио.** `flutter3d_audio_core/lib/src/audio_scene.dart:203` и `flutter3d_audio/lib/src/speakers.dart:42`: `spatial = const EqualPowerPanner()` → `speedOfSound = speedOfSoundInAir` (= `standardSpeedOfSound`, `units.dart:38`). `EqualPowerPanner.inWorld` (`spatial.dart:128`) никто не вызывает; `spatial:` ни одно приложение не передаёт. Решение «скорость звука по температуре» реализовано в `WorldProperties.speedOfSound`, но потребителя нет.

**B2. Окклюзия звука не читает акустику каталога.** `flutter3d_game/lib/src/visuals/sound_occlusion.dart:30-32`: `perObstacle = 0.5, floor = 0.06` — коэффициент на препятствие, без материала. Поле `PhysicalMaterial.acoustic` (полосы `absorption`, `materials.dart:497,556`) читает только `flutter3d_conformance/lib/src/plugins/plugin_checks.dart:701`. Из списка «кто читает каталог» (коллайдеры, ткань, жидкости, огонь, звук) звук — не читает.

**B3. Ткань не получает мир.** `flutter3d_physics/lib/src/cloth/cloth_settings.dart:13` `gravity = standardGravity`, `:71` `inWorld(WorldProperties)` определён, но **нигде не вызывается** (`rg '\.inWorld\('` — только определения). `showcase/lib/pages/physics_particles/xpbd_cloth.dart:198` — `const ClothSettings()`. `WindSettings.drag = 0.3` (`:202`) не масштабируется плотностью воздуха мира. Нативные `NativeClothSettings`/`NativeParticleSettings`/`NativeFluidSettings`/`NativeDebrisSettings` принимают `world`, но снаружи `physics_native` не конструируются. Каталог тканью тоже не читается (в `cloth/` нет `Materials`/`MaterialCatalog`).

**B4. Платформер: частицы живут в стандартном мире 9.81, а игра — в 24.** `apps/flutter3d_demo_platformer/lib/main.dart:357` `ParticleSystem(capacity: 2000)`, `.world =` в приложении не присваивается (ср. racing `main.dart:1015` и dungeon `main.dart:1159`, где присвоено). Сейчас не стреляет только потому, что все эффекты платформера задают `ParticleGravity(-2.2…-7.0)` явно (`src/effects.dart:32-171`); первый `ParticleGravity()` упадёт на 9.81. `-7.0` (`effects.dart:154`) — на грани порога «баллистики» 8 в правиле.

**B5. River: то же, плюс `ParticleGravity()` уже используется.** `demo_river/lib/src/staging.dart:26,30` системы без мира; `src/river_game.dart:618,681,699` `ParticleGravity()`. Совпадает с 9.81 случайно — river не задаёт `WorldProperties`.

**B6. Ящик платформера: трение литералом, у дерева в каталоге трения нет.** `flutter3d_game_platformer/lib/src/crate.dart:31` `friction: 0.8`. В заголовке только `F3D_MAT_STEEL_{STATIC,KINETIC}_FRICTION` — у `f3d.wood`, `f3d.granite`, `f3d.rubber` механического трения нет, поэтому и `material:` не помог бы. Пробел каталога.

**B7. Гоночные покрытия — μ по имени, не по id материала.** `flutter3d_game_racing/lib/src/vehicle/tyres.dart:98-108` `GripTable {'asphalt': 1.0, 'grass': 0.82, 'ice': 0.3, …}`. Тюнинг игры, но это и есть «пара материалов», которую обещал `MaterialCatalog.contact`.

**B8. Плотности, дублирующие каталог другими цифрами** (override разрешён решением, но числа — соседние с каталожными):
- `demo_platformer/lib/src/run_elements.dart:466` `NativeMaterial.stone(), density: 2700.0` (гранит 2630); `:567` `wood(), density: 500.0` (545).
- `showcase/lib/pages/physics_particles/heat_and_fire.dart:117` wood 500.0, `:123` steel 7800.0 (7854).
- `demo_river/lib/src/river_water.dart:533` stone 1400.0; `demo_water/lib/src/staging.dart:318` 2600.0, `:351` 440.0.
- `demo_hollow/lib/src/props.dart:50,328` `mass: 2700.0 * объём`, `:170` `450.0` (бревно).

**B9. Лава — свои тепловые числа, у `f3d.basaltMelt` термогруппы нет.** `demo_platformer/lib/src/run_elements.dart:189-192` `NativeLiquidHeat(temperature: 1450, specificHeat: 1200, conductivity: 1.5)`; в заголовке у basaltMelt только density/viscosity/tension. Пробел каталога.

**B10. 683 лм/Вт вне `physical_constants`.** `flutter3d_effects/lib/src/fire_light.dart:71` `683.0 * y / radiance` — единственное место, константа природы.

**B11. Экспозиция 1.6 — канон плюс четыре копии.** Канон `flutter3d_core/lib/src/engine/render/render_settings.dart:1604` `defaultExposure = 1.6`. Копии: `flutter3d_editor_core/lib/src/light_opt/light_optimizer.dart:366` `_exposure = 1.6`; `flutter3d_model_core/lib/src/scene_lighting.dart:190` (док в `lighting_sync.dart:109` сам говорит «match RenderSettings.defaultExposure»); `flutter3d_game_racing/lib/src/sky_presets.dart:53`; `showcase/lib/pages/post/tone_mapping.dart:17`.

**B12. Малые `intensity:` у `LevelLight` проходят мимо правила люксов.** Детектор `tool/structure/detectors.dart:604-605` сканирует только `LightNode|Light3D|ModelLight`; `LevelLight` (`sim/lib/src/level/level_light.dart:49`, дефолт 1.0) — нет. Остались `showcase/lib/pages/sim_audio_xr/lightmap_bake.dart:70,215` `intensity: 6.0`, `showcase/lib/pages/widgets_misc/level_loader.dart:24` `intensity: 5.0` — похоже на недомигрированные legacy-единицы (проверить единицу `LevelLight.intensity`).

**B13. `flutter3d_plugin_api` не упоминает `WorldProperties`** (`rg WorldProperties packages/flutter3d_plugin_api/lib` — пусто), хотя решение «один тип, который читают формат уровня и plugin_api».

**B14 (мелочь).** `flutter3d_game_kit/lib/src/world/daylight.dart:54` `defaultSunIntensity = 2.6 * Photometric.legacyUnit` (≈15 055 лк) — мигрировано через legacy-множитель, а не записано в люксах.

## C — допустимые определения (сводка)

- Определения в matter (стандартный мир, константы природы, каталог); `Photometric.legacyUnit/legacyNits` (`light_node.dart:316,323`); `MaterialCatalog.defaultFriction` как определение.
- Законы со своими числами: `sphereDrag` (`physics/lib/src/fluid/buoyancy.dart:103`, задокументировано против C `shape_drag_of` 0.47/1.05/0.82/0.5 в `f3d_motion.c:257-275`); `liquid_view.dart:121` (DOE-HDBK); пожарная модель в `f3d_heat.c` (1673.15, soot 0.04, absorption 0.51/0.8, INERT c = 1000 — «только модель огня»); `Igniter` (`flutter3d_elements/lib/src/simulation.dart:435-470`, с источниками); `f3d_heat.c:1003` `F3D_STANDARD_ATMOSPHERE/(R·T)/ρ_world` — масштаб ν, корректно при ρ мира.
- `ior = 1.5` (`core/lib/src/formats/material_extensions.dart:34`, showcase `transmission.dart:15`) — дефолт glTF.
- Маятник (`education/lib/src/lab/pendulum.dart:24`, `pendulum_lab_run.dart:77`) — лаборатория без мира.
- Шейдеры: кроме F0 (A3) мировых чисел нет; `kPi` дважды (`color.glsl:23`, `sky_physical.frag:51`); exposure приходит uniform'ом (`surface.glsl:363`); ACES/SSAO — свои.
- Стилистика: заголовок `f3d_materials.g.h:1`, `f3d_heat.c:92`, `rules.dart:3955` пишут «flutter3d_physics' catalogue», а каталог в `flutter3d_matter`.
- Воздух в C: `air_pressure` в ядре нет (Dart-only, `native_world.dart:1440-1447`), в снапшот идёт через `toJson` — согласовано.

## Кто читает каталог (файлы в lib, вхождений `MaterialCatalog|PhysicalMaterial|Materials.*`)

matter 98 · physics 27 (`collider.dart`, `rigid_body.dart:56-67`, `collision_world.dart`, `dynamics.dart`, `fluid/fluid_medium.dart` — `FluidMedium.of(Materials.*)`) · physics_native 18 (`native_world.dart`: `NativeLiquidProperties.of`, `NativeLiquidHeat.of`, `NativeMaterial.of(PhysicalMaterial)`) · core 11 · sim 9 · conformance 7 · app 6 · modeler 5 · effects 4 · showcase/editor/flutter3d по 2 · build/build_hooks по 1 · **cloth 0 · audio 0 · game_* 0**.

## Итог по пакетам

| Пакет / приложение | A | B |
|---|---|---|
| flutter3d_core | 1 (A4) | — |
| flutter3d_physics_native | 2 (A1, A2) | — |
| flutter3d_shaders | 1 (A3) | — |
| flutter3d_cpu | 1 (A3) | — |
| flutter3d_build | 1 (A3) | — |
| flutter3d_audio_core / flutter3d_audio | — | 1 (B1) |
| flutter3d_game | — | 1 (B2) |
| flutter3d_physics (cloth) | — | 1 (B3) |
| flutter3d_game_platformer | — | 1 (B6) |
| flutter3d_game_racing | — | 2 (B7, B11) |
| flutter3d_effects | — | 1 (B10) |
| flutter3d_editor_core | — | 1 (B11) |
| flutter3d_model_core | — | 1 (B11) |
| flutter3d_plugin_api | — | 1 (B13) |
| flutter3d_game_kit | — | 1 (B14) |
| tool/structure | — | 1 (B12) |
| apps/flutter3d_demo_platformer | — | 3 (B4, B8, B9) |
| apps/flutter3d_demo_river | — | 2 (B5, B8) |
| apps/flutter3d_demo_water | — | 1 (B8) |
| apps/flutter3d_demo_hollow | — | 1 (B8) |
| apps/flutter3d_showcase | — | 4 (B3, B8, B11, B12) |
| flutter3d_matter, C-ядро, sim, particles, game_shooter, demo_racing, demo_dungeon, demo_reef, demo_arcade | 0 | 0 |

Самое весомое для rc.1: A1 (дефолты материала расходятся с ядром), B1–B3 (три из пяти обещанных читателей каталога/мира — звук, окклюзия, ткань — не подключены), B4/B5 (частицы без мира), B6/B9 (пробелы каталога: трение дерева/камня, термогруппа лавы).
