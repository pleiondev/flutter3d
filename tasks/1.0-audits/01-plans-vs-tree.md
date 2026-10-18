# Аудит «планы vs рабочее дерево» (flutter3d, ветка 0.9.0, 2026-10-09)

Заметки агента. Состояние дерева на 2026-10-09, до перестройки плана. Субагенты были недоступны (лимит), всё проверено вручную через `rg`/`fd`/Read и `dart run tool/structure.dart --list` (70 правил). Тесты/analyze не запускались. «Догадка» помечено явно.

## 1. tasks/1.0-scope-additions.md

| # | Состояние | Свидетельство |
|---|---|---|
| 1 | DONE | `flutter3d_core/lib/src/engine/render/render_settings.dart:1481`, 25 полей `final …Settings` |
| 2 | DONE | `apps/flutter3d_editor/lib/src/editor_plugins.dart`; `flutter3d_mcp/lib/src/editor/editor_stdio.dart`; Reactions/Soundtrack в dungeon, platformer, racing, strategy; SpokenEvents — `demo_dungeon/lib/src/spoken.dart` |
| 3 | PARTIAL | `DemoRecording` есть в 8 демо (dungeon, hollow, platformer, racing, reef, sandbox, strategy, water); нет в arcade, crawler, river. `HeadlessGame` — `flutter3d_game_strategy/lib/src/headless.dart` |
| 4 | DONE | `flutter3d_particles/lib/src/effect_document.dart:62` (`.f3dfx`), фикстура `test/fixtures/v1/blast.f3dfx`; `demo_dungeon/effects/blast.f3dfx`, `crypt.f3dfx` (flame/splash/splinters/impactSparks); WebGPU `webgpu/lib/src/runtime_material_host.dart` |
| 5 | DONE | `render_settings.dart:1534 reversedDepth = true`; `hardware/lib/src/capabilities.dart:478`; EXT_clip_control/depth32float в webgl/webgpu |
| 6 | DONE | `scene/lod_group.dart`, `mesh_node.dart`; `F3D_MEDIUMP` в 17 файлах shaders; `shaders/shaders/PRECISION.md`; `webgl_device.dart:222 highpMaterials` |
| 7 | DONE | `render/physical_camera.dart:48`; `render_settings.dart:1537,1978`; `physical_sky.dart:327 illuminanceLux`; `ev100` в `material.dart:159` |
| 8 | DONE | `render_settings.dart:1518 clusteredLights = true` |
| 9 | DONE | `core/lib/src/formats/material_language/material_parser.dart:125 materialLanguageVersion = 2`; тесты лежат в `flutter3d_core/test/formats/material_language_v2_test.dart` и `flutter3d_build_hooks/test/material_accessors_test.dart` (план называет другие места) |
| 10 | DONE | `core/lib/src/formats/lighting_model.dart:467 LightingModels`; toon — `flutter3d_post/lib/src/style/style_addon.dart`, `shaders/lib/toon.glsl` |
| 11 | DONE | `flutter3d_camera/lib/src/virtual_camera.dart:29`; `reframe:` в platformer/racing; flame зависит от camera |
| 12 | DONE | `sim/lib/src/level/level.dart:69 prefabs`, `brush.dart:177 depthLayer`, `props` |
| 13 | DONE | `render/frame_pacing.dart:32,118`; `sim/loop/frame_cadence.dart:27`; `scene_surface.dart:90 cadence` |
| 14 | DONE (ревалидация кэша не проверена) | `webgl/lib/src/webgl_image_decode.dart:73 cappedImageSize` |
| 15 | PARTIAL | `render/memory_report.dart`, `FrameCapture.toJson/parse`, `wipeSides` в `app/diagnostics/render_inspection.dart:392`; «debug channels» как сущность не найдены |
| 16 | DONE, но не «меньше» | `packages/` = 57 каталогов (56 публикуемых + demo_content); api-review решил «около 40», boundaries добавил 4 новых |
| 17 | DONE | `foundation/lib/src/world_position.dart:24`; `vector_math_64` нет ни в одном pubspec; 214 употреблений |
| 18 | PARTIAL | `scene.dart:152 shiftOrigin`, `OriginShifted` (`plugin_api/simulation.dart:320`), particles/collision/frame_history подключены; `scene/irradiance_field.dart:100 origin` — обычное поле без обработчика сдвига |
| 19 | DONE | `plugin_api/loop.dart:199 world => throw StateError`, `simulation.dart:54 PublishedEvent` (encoded); потребитель `game/lib/src/visuals/actor_visuals.dart`; «именованная форма query» не найдена |
| 20 | NOT DONE | refcount/retain нет; только `render_target_pool.dart:205 release`; правила про утечки в `tool/structure` нет |
| 21 | DONE | `foundation/lib/src/exceptions.dart:29–85`; правило «every exception hangs from Flutter3dException» |
| 22 | DONE | `build/lib/src/material_build.dart generateMaterialAccessors`; `effects/lib/src/liquid_look.dart` использует |
| 23 | PARTIAL | `game/lib/src/input/action_map.dart:146,502`; но `game/lib/src/input/bindings.dart:108 class Bindings` всё ещё публичен (внешних пользователей не нашёл) |
| 24 | DONE | `audio_core/src/listener.dart:35`, `audio_scene.dart:32 AudioEmitter`, `mixer.dart:10 AudioBus`, `mix_snapshot.dart:30` |
| 25 | DONE | `app/lib/src/view/flutter3d_view.dart:233`, `:151 EngineLoop` |
| 26 | DONE | `render/render_view.dart:65,252`; используется stereo_rig и editor |
| 27 | DONE | `sim/ecs/ecs_world.dart:47 EcsWorld extends SimWorld` (SimWorld — база в plugin_api, дубликата нет) |
| 28 | DONE | правило `public identifiers spell in American`, `britishSpellingAllowed = {}` (`repository.dart:1944`) |
| 29 | PARTIAL | правило `every public number says its unit in its doc`; `unitsUndocumentedPending: effects 5` (`repository.dart:1995`); CONTRACTS §SI/Y-up/радианы есть |
| 30 | PARTIAL | `plugin_api/ecs.dart:91 ComponentCodec` с версией; отдельного правила/генератора кодеков не нашёл |
| 31 | DONE (финальный проход — UNVERIFIABLE) | `build/lib/migrations/0.8_to_1.0.yaml` 1538 записей; `fix_data.yaml` в 40 пакетах; `lints/src/migration/`; `tool/api/baseline/v0.8.5`, `migrate_corpus.sh`, `migrate_fixture_test.dart`. Записи про `flutter3d_matter`/`flutter3d_elements`/`WorldProperties` отсутствуют — догадка: переезд physics→matter без миграции (physics его не реэкспортирует) |
| 32 | DONE | `build/bin/flutter3d.dart` (convert/doctor/create/init/plugins/migrate/lights, `--version` читает версию пакета); `lib/src/convert/` (godot/unity/usd/materialx/ply…); `test/fixtures/convert/`; `site/content/reference/bringing-assets-in.md`; `api/flutter3d_build.cli` |
| 33 | DONE | `f3d_writer.dart:37–40 programs/prefabs/files`; секции 29–35 в `f3d_format.dart:303–329`; `core/test/fixtures/v2/bundle.f3d`; `convert/bundle.dart`; `convert/command.dart:39 split` |

## 2. tasks/1.0-arch-review.md

| Must | Состояние | Свидетельство |
|---|---|---|
| 1 | DONE | `sim/loop/genre_plugin.dart:283 _GenrePart extends SnapshotPart`; `engine_loop.dart:416–432` rewindTo бросает StateError; `RunTimeline({rewind, loop})`. `RewindBuffer` loop не берёт (PARTIAL по букве) |
| 2 | DONE | `render_view.dart:38–59` история на view |
| 3 | PARTIAL | см. scope 18 (IrradianceField.origin не сдвигается) |
| 4 | DONE | `f3d_wire.dart:21 alphaModeCode`; правило `.f3d writes codes, not enum ordinals` |
| 5 | DONE | `core/formats/model_writer.dart:123–134` |
| 6 | DONE | `TEMPSILENT` нет; правило `no tracked source mutes the sound for now` |
| 7 | DONE | ARCHITECTURE.md:4659–4681 L0–L9; правило `the publishing order names every package` |
| 8 | DONE | `flutter3d_view.dart:503–509` |
| 9 | DONE | см. scope 19 |
| 10 | PARTIAL | HAL: nullable `create*`/`readPixels` нет, `WebGlDevice.open` non-null (`webgl_device.dart:231`), `openSpeakers → Future<Speakers>` (`speakers.dart:36`). **`readBufferSync` остался** (`hardware/graphics_device.dart:781`). Цвета: 223 `LinearColor` в core, остались `RenderView.clearColorSrgb: Vector4` (`render_view.dart:165`), `IrradianceField.writeIrradiance(Vector3 color)`, внутренние `vm.Vector4 clearColor` в pass-нодах. A.1/A.2: все `abstract base`, `ModelFormat` — `final class` (`model_loader.dart:26`). Дубли имён: по одному объявлению |
| 11 | DONE | `TraceEvent`, `ToolContent` — abstract base; `PeerWire.listen → Registration` (`net/peer_wire.dart:102`); `constrain → Registration` (`physics_backend.dart:192`); `maxLights` — static getters (`light_node.dart:110`); `section() → F3dExtraSection?`; `registerTimelineExtensions → Registration`. `SaveFile.read` не проверен |
| 12 | DONE | `flutter3d_net/lib/src/{peer_wire,rollback_session,wire_hello}.dart`; `flame_multiplayer/pubspec.yaml:33` |
| 13 | DONE | trace `formatVersion` (`trace.dart:54`), `VoxelWorld.format: FormatSpec` (`voxel_world.dart:133`), `projectFormat` (`project_format.dart:109`); `.name` на :3392 — `BlendMode` там класс, не enum; `ext.flutter3d.hotSwap` оставлен алиасом до 2.0 (`hot_swap.dart:67`); `.vm` снапшоты содержат `->` результаты |
| 14 | DONE | кросс-пакетных `package:…/src/` импортов нет (только в migration yaml); правило есть |
| 15 | PARTIAL | `SkySettings.sunIntensity` через `luxToEngine` (`sky_settings.dart:248`); но `Photometric.legacyUnit/legacyNits` публичны (`light_node.dart:316,323`, в `.api:3108`), `LightNode.intensity = Photometric.legacyUnit`, `Atmosphere` по умолчанию `2.0 * legacyUnit` — решение C «константы спрятаны» не выполнено |
| 16 | DONE | `supportsX` getters: 0; `needsSurfaceBuffer`, `emitFor` только в migration table; 8 `@Deprecated` с версиями |
| 17 | DONE | `flutter3d_plugins:` в 1 pubspec; `plugin_discovery.dart pluginMarkerKey` + `@Deprecated` старый ключ (:111) |
| 18 | DONE | Flutter3dView: `demo_platformer/lib/main.dart`, `game/example`, `editor_core/scaffold_templates.dart`, `site/content/quickstart.md:125`; `Scene3D` на Flutter3dView, `clearColor: LinearColor?` (`scene_widgets.dart:139`); flutter_bloc в шаблоне нет |
| 19 | DONE | `game/config/game_config.dart:17 SettingKey<T>`, `:146 GameSettings`, v2 — конверт (:208–210) |
| 20 | DONE | `audio_core/listener.dart:30 placeAt(WorldPosition)` |
| 21 | PARTIAL | ARCHITECTURE/README: «57 packages / 17 applications» (согласовано правилом); **README:12 «fifty-two packages on pub.dev»** — публикуемых 56; `:789 «the three backends»` — исторический абзац; CONTRACTS:242 смягчено («as a file of its own»); сайт: `renderSteps.addContributor` соответствует решению |

Should: DeviceLoss слушается (`flutter3d_view.dart:100`); `addMaterials` один путь (`renderer_steps.dart:424`); `FlameInputBridge({actions})`, PadRoutes/slotKeys удалены; `audio_core` без Flutter; `postGameEvent` нет; `StereoSurface` на Flutter3dView; `flatDartPackages` покрывает все пакеты; `ConstraintCycleException extends PluginException` (`order.dart:14`). **Не сделано:** `SequencePlayer`, `Lightmap`, `LightmapBaker` всё ещё в sim (`sim/src/cinema`, `sim/src/level/lightmap*.dart`); `exceptionNamePending` держит `GpuUnavailable`, `RenderRefusal`, `UnsupportedCapability` (`repository.dart:1927`); `outputSchema` 23 упоминания в mcp (не на всех инструментах — догадка). Решения: A DONE, B DONE, C PARTIAL, D DONE, E DONE, F DONE, G DONE (`flutter3d_game_physics` без hook, зависит от physics_native; `flutter3d_build_hooks` без mcp), H PARTIAL (`ShaderBundleException`, `ReplayException` переименованы; три ждут).

## 3. tasks/1.0-boundaries.md

Перемещения 1–14: **все DONE** — `flutter3d_foundation` (deps только vector_math; world_position, linear_color, exceptions, issues, formats, registration, portable_math, vectors), `flutter3d_matter` (world_properties, materials/, physical_constants, standard_world), `liquidMeshes` → `effects/liquid_shapes.dart`, `SkeletonRagdoll` → `game_physics/ragdoll/`, `SimulationHandle` → `sim/loop/simulation_handle.dart`, `flutter3d_elements` (TrackedBody «holds nothing that draws it», `elements.dart:416` looks в effects), `flutter3d_level_scene/level_scene.dart` (app и editor_core зависят; app без editor_core), сим без `export 'package:`, `flutter3d` без sim/physics/audio в pubspec и barrel, `flutter3d_game` с `show`-списками (`flutter3d_game.dart:50–71`), виджеты в `game_ui/src/{screens,touch,hud}`, дубли имён — по одному, `DataSectionRegistry` в plugin_api + регистрации в particles/matter/plugin_runtime. Пункт 7 («marker registries → owners») UNVERIFIABLE: registries по-прежнему объявлены в plugin_api.

Правила 1–9: все девять в `--list` (layers.dart матрица, `reexportsAllowed` с 11 записями и `reexportedWhole` = только game→flutter3d, `boundaries.dart:154–194`).

Шаги: A DONE, B1/B3 DONE (файл говорит «cut off»), C DONE. **D:** цвета PARTIAL (см. выше); `physicalMaterials` в `.f3d` — **NOT DONE** (секции контейнера кончаются на 35 `files`; есть только data-секция для `.f3dplugin`: `matter/materials/material_sections.dart`, `plugin_runtime/data/data_sections.dart:35`); данные matter — **NOT DONE**: 33 записи `f3d.*` (8 жидкостей, 1 газ, 22 твёрдых, 2 сыпучих) против «~100+~100», `*.verified.json` нет; группа неупругих деформаций (Mooney/Ogden/Prony/Johnson-Cook) **NOT DONE**; порог σ 1e-5 не найден.

## 4. tasks/1.0-physics-audit.md

| Пункт | Состояние | Свидетельство |
|---|---|---|
| Одна гравитация | DONE | `matter/world_properties.dart:16,57`; `platformer/runner.dart:64`; `racing_world.dart:25`; `shooter_world.dart:13`; `ParticleGravity([this.acceleration])` (`particle_affector.dart:49`); `crypt_elements.dart:104`; правило `a world's gravity, air and sea…` + `worldLiteralExempt`. Остались `ParticleGravity(-N)` в platformer/dungeon/racing/showcase эффектах — догадка: художественные, не баллистика |
| Небо π | DONE | `core/CHANGELOG.md:24`, `physical_sky.dart:48` |
| Константы 20 °C, C+Dart | DONE | `csrc/src/f3d_materials.g.h` (generated), правило `the core reads its substances…`; 998.2 только в `csrc/tests` |
| de Leva 73 кг | DONE | `skeleton_ragdoll.dart:94` |
| sunAngularRadius | DONE | `shadow_settings.dart:170 = 0.00465`, `sky_settings.dart:60` |
| Seabed | UNVERIFIABLE | в `seabed_look.dart` refract/σ не нашёл |
| Lux | DONE | `daylight.dart:54`, `project_template.dart:73 intensity: 92650`, правило `a light's intensity is lux or candela`; glTF-двойная конверсия не проверена |
| Emissive /π | UNVERIFIABLE | `meteors.dart:217 Blackbody.color(...)` |
| Chemlab | DONE | `education/example/lib/src/bench.dart:143–160` (HCl белый, KMnO₄ «labelled»), Beer–Lambert в linear (:485,1145) |
| Маятник | DONE (формула витрины не проверена) | `lab/pendulum.dart:69–78` ω·(L/L′)², damping 1/s (:48), фикс. шаг `lab_pendulum/main.dart:63` |
| Плавучесть на g | DONE | `physics/fluid/buoyancy.dart:158–164` |
| NativeDynamics | DONE | `native_dynamics.dart:97–100`; `physics_native/test/gravity_rewind_test.dart:91` |
| WorldProperties | DONE | плотность из T,p (:25,103), `speedOfSound` (:27), ветер → `xpbd_solver.dart:143`, `particle_system.dart:94`; вакуум убран (:52–55); racing ρ (`sphere_vehicle.dart:731`) |
| Дубли констант | DONE (догадка) | в Dart-lib 0.0728/998.2 только в документации |
| MaterialCatalog | PARTIAL | `material_catalog.dart:215 extends PluginRegistry`; `materials:` в data plugin (:413); conformance `plugins/plugin_checks.dart`. Читают: collider, rigid_body, collision_world, dynamics, `FluidMedium.of`, native_world (C-header — огонь). **Не читают:** cloth (`cloth_settings.dart`), `sound_occlusion.dart`, elements |
| Документация | PARTIAL | occlusion теперь −6 dB (`sound_occlusion.dart:40`), 1100 K исправлено (`fire_light.dart:42`), gain 29× задокументирован (`fire_view.dart:232`); `standard_world.dart:2 «the one place»` и `legacyNits` в effects остались; остальное не проверял |

## 5. tasks/1.0-stability.md

1–3 DONE (56 `api/*.api`, правила snapshot/Breaking/deprecation). 4 DONE (8 `@Deprecated` формата «Deprecated in 1.0.0, removed in 2.0.0»). 5 UNVERIFIABLE. 6 DONE (`abstract interface class` только Bridged3d/Drawn3d/StepFollower/StepClock во flame + `PlacedEvent` в allowed). 7 PARTIAL (все `export 'package:` с `show`, кроме game→flutter3d — разрешено целиком). 8 DONE (фикстуры v1…v4 в 17 пакетах; `fmat.dart:43 legacyVersionKey`; `ShaderBundleException`). 9 DONE (`simulation_version.dart`, `pose_record.dart`, `ReplayException`). 10 DONE (`constants.dart:8 abiVersion = 37`; 17 секций не считал). 11 DONE (`.mcp` ×3, `.vm` ×3 — plugin_api тоже, `.cli`). 12 DONE (`net/wire_hello.dart:11–18`). 13 UNVERIFIABLE. 14 PARTIAL (`platforms:` 56/57, SUPPORT LTS 18 мес. :188; CI-матрица не найдена). 15 UNVERIFIABLE. 16 DONE (код); перезапись голденов/тейпов — NOT DONE.

## 6. tasks/1.0-publish.md

Шаг 1 DONE (53 пакета на `1.0.0-rc.1`, 393 каретки), но **числа устарели**: приложения на 0.1.0–1.0.0+1, не rc.1; `flame_multiplayer` 0.3.0 (в плане 0.2.0), `dashwire` 0.2.0 (0.1.1). Шаги 2–5 NOT DONE. `publish_check.sh:77 NEVER_PUBLISHED=demo_content` DONE; `api_against_pub.sh` есть; TEMPSILENT DONE; миграция — см. scope 31. Список L0–L8 в плане расходится с ARCHITECTURE L0–L9 (там foundation, matter, elements, level_scene, net, game_physics, build_hooks).

## 7. tasks/1.0-api-review.md (решения)

1 DONE (post/mcp/education/game_kit/game_ui/camera; `flutter3d_addon_*` и lab/lti нет). 2 DONE (`SurfaceMaterial`, `RenderMaterial`, `WorldRay`, `LocalRay`, `FlameChaseCamera`). 3 DONE. 4 DONE (bare `FormatException` в core/build/sim/particles/plugin_runtime/model_core/webgpu = 0). 5 DONE. 6 DONE (9 `Registration on*`). 7 DONE (`game_ui/l10n/game_localizations.dart`, ru). 8 DONE (`bin/lights.dart`). 9 DONE. 10 DONE (`ToolSpec`/`ToolResult`; flutter_bloc нет в pubspec'ах). 11 DONE. 12 заменено wave 3d → `flutter3d_demo_content` `publish_to: none`, в pubspec'ах shooter/sim_mcp только комментарии. Wave 3d: 7/7 sealed, `GameState`/`RunState`/`RacePhase` — классы. Ответы: `GameEvents` удалён; `.fmat` v1 + конверт. Интеграция: `StorageException extends ResourceException` (`storage.dart:88`), editor `await storage.read`, `BatonStream({required bool holding})`, `Ghost.toJson` с конвертом — DONE.

## Что планы упускают или где противоречат друг другу

1. **Счёт пакетов:** scope «~70», api-review «~40», arch-review «51/17», stability «46», boundaries «53», publish «52 published», README «fifty-two on pub.dev» — фактически 57 каталогов, 56 публикуемых, 17 приложений в списке структуры против 19 каталогов в `apps/` (`flutter3d_demo_crawler`, `flutter3d_template_app` не в `applications`).
2. **Счёт правил:** publish «43 → 58», stability «44-е правило» — сейчас 70.
3. **Версии своих линий:** publish называет flame_multiplayer 0.2.0 / dashwire 0.1.1; факт 0.3.0 / 0.2.0. «66 pubspecs moved» против 53 на rc.1 (apps остались 0.x).
4. **Порядок публикации:** publish L0–L8 (без foundation/matter/elements/level_scene) против ARCHITECTURE L0–L9.
5. **Boundaries «State when the weekly limit hit»** устарел: B1/B3 и C выполнены, но D (данные matter, `.f3d`-секция, неупругая группа) не начат — файл не отражает.
6. **Physics-audit** требует ~200 материалов и группу inelastic — в коде 33 и ни одной; план говорит «after step A… the data goes into matter» — не произошло.
7. **arch-review Must 10 / scope 20** противоречат «What holds» того же файла («one exception root» — да, но `readBufferSync` и ref-counting остаются открытыми).
8. **Решение C (фотометрия)** помечено решённым, но публичные `Photometric.legacyUnit/legacyNits` и дефолт `LightNode.intensity` противоречат «константы спрятаны».
9. **scope 9** указывает тесты в неверных местах (они в `flutter3d_core/test/formats/` и `flutter3d_build_hooks/test/`).
10. **stability 5/11**: «.vm для game и app» — есть ещё `flutter3d_plugin_api.vm`; «.mcp для трёх серверных пакетов» — это build, mcp, sim_mcp.
11. **api-review decision 12** (samples) отменено wave 3d в пользу demo_content — scope/arch не обновлены.
12. **Переезд physics→matter** (`WorldProperties`, `MaterialCatalog`) не имеет записей в `0.8_to_1.0.yaml`, при этом physics намеренно не реэкспортирует matter — догадка: ломающее изменение без миграции (правило структуры не запускалось).
