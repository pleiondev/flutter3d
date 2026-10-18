# Готовность тестов/CI/публикации — flutter3d, ветка 0.9.0 (1.0.0-rc.1), 2026-10-09

Заметки агента. Фоновые логи: `analyze.log` → `No issues found! exit=0`; `structure.log` → `70 rules, all held, exit=0`.

**Побочный эффект, о котором надо знать.** `dart pub publish --dry-run` в workspace сам запускает резолв: первый же прогон (foundation) написал в `pubspec.lock` +32 строки (транзитивные `analysis_server_plugin 0.3.18`, `analyzer_plugin`, `dart_style`, `yaml_edit`). Содержимое — то, что любой `pub get` и так запишет; откат: `git checkout pubspec.lock`. (Возвращено в сессии.) Больше ни один tracked-файл не тронут (`tool/publish_check.sh` не запускался — он переписывает pubspec'ы; вместо него `dart pub publish --dry-run` по каждому пакету без правок).

## 1. Быстрые сьюты (`dart test`, последовательно)

| Пакет | ok | fail | skip | время | Первая ошибка |
|---|---|---|---|---|---|
| flutter3d_foundation | 14 | 0 | 0 | 2s | — |
| flutter3d_matter | 15 | 2 | 0 | 3s | `world_properties_test.dart:13` Expected 9.81, Actual 9.8100004196167 (float32); `:23` скорость звука 331.09 vs 331.3 |
| flutter3d_plugin_api | 24 | 3 | 0 | 3s | `plugin_manager_test.dart:185` ждёт `FormatException`, летит `PluginFormatException`; `:228` touches `simulation` vs `network-tick`; `:412` то же с `PluginChange.fromJson` |
| flutter3d_hardware | 95 | 0 | 0 | 3s | — |
| flutter3d_shaders | 5 | 0 | 0 | 2s | — |
| flutter3d_physics | 273 | 10 | 0 | 25s | `fluid/mixture_test.dart:33,90` имя слоя `'olive oil'` вместо `'oil'`; `:64` налив 0.0; `cloth_world_test.dart:33` 1.62 vs float32; `:50` ветер слабее; «standard world to the bit» разошёлся; `wedge_test.dart:331` тело встало на 60°; `character_controller_test.dart:634,854,1011` платформа продавливает, snap, «run 37 escaped through a wall» |
| flutter3d_sim | 913 | 16 | 0 | 11s | `engine_loop_test.dart:431` `LoopChangeFormatException` вместо `FormatException`; `demo_test.dart:97`, `run_service_test.dart:98`, `level_visibility_test.dart:174` — текст «newer than this build reads» не содержит «newer build»; `solver_parity_test.dart:77` Divergence step 5; `parity_test.dart:257` Divergence step 75 (tape с macOS-arm64); `prefab_test.dart:63,102` f3d.level version 3→4; `demo_fixture_test.dart:21` v2-фикстура: digest a308c3c3≠76e52adc; `replay_simulation_test.dart:156,172`; `sequence_test.dart:256`; `demo_loop_changes_test.dart:93`; `isolate_simulation_test.dart:114`; `layers_test.dart` |
| flutter3d_elements | 6 | 0 | 0 | 3s | — |
| flutter3d_particles | 132 | 2 | 0 | 7s | `particle_world_test.dart:70` 3.9999976 vs 4.0 (1e-6); `effect_document_test.dart:255` текст «newer engine» |
| flutter3d_core | 948 | 4 | 0 | 13s | `formats/surface_material_json_test.dart:59` ждёт `Vector4`, вернулся `LinearColor` (sRGB→linear 0.6→0.3185); `formats/obj_writer_test.dart:344` 0.25 vs 0.0509; `animation_pointer_player_test.dart:140` Vector3 vs LinearColor; `engine/frame_history_test.dart:33` `Bad state: Too many elements` (`ListBase.single`) |
| flutter3d_build | 258 | 34 | 0 | **525s** | 17× `plugin_discovery.dart:334` `Cannot modify an unmodifiable list` (`.sort` на unmodifiable; валит `plugin_discovery_test`, `plugin_template_test`); `convert_godot/unity/usd_test` поля `null` (material/prop не читаются); `convert_command_test.dart:75` пути с `./`; `:140` `wedge.f3d` не utf-8; `migrate_test.dart` `flame: ^1.38.2` пропал из pubspec; `migrate_fixture_test.dart` after/ не совпадает (`hide textureBytes` в импортах); `init_test.dart:119` 3 vs 1; `plugin_author_server_test.dart:205` «badge: earned» vs «conformant@1.0» |
| flutter3d_net | 18 | 5 | 0 | 11s | `wire_bytes_test.dart:52,88,106` record `(int, List<int>)` «равны, но не equals» (сравнение List внутри record — нужен `equals`/deep); `relay_test.dart:158` Divergence step 25 через реальный relay; `:248` текст «update to simulation engine 1, racing 7» |
| flutter3d_mesh | 599 | 0 | 0 | 11s | — |
| flutter3d_model_core | 1187 | 5 | 0 | 8s | `project_format_test.dart:1387`, `project_document_test.dart:794,878`, `commands_test.dart:1467` — цвета материалов сравниваются Vector4 vs LinearColor / sRGB-линейно (0.2→0.0331); `lighting_sync_test.dart:82` 26057.6 vs 4.5 (lux вместо множителя — физическая камера) |
| flutter3d_level_scene | 2 | 0 | 0 | 3s | — |
| flutter3d_editor_core | 181 | 9 | 0 | 5s | `set_field_undo_test.dart` в документе появился `'id'`; `shipped_levels_test.dart` генераторы `make_track.py`/`make_templates.py` не воспроизводят закоммиченные байты (**это же шаг `levels` в ci.sh**); `editor_pieces_test.dart:160,200,221,249,270,355` — записи-records «равны, но не equals», дубликат имени плагина не отвергается, 0.8 float32 |
| flutter3d_mcp | 229 | 28 | 1 | 10s | 7× `kit/project_tools.dart:173` `PluginException: plugin "wind" adds the MCP tool "gust" without asking for the tools permission` (тест-плагины без `PluginPermission.tools`); `kit/tool_table_test.dart:132,266` в списке лишний `flutter3d.schema`; `model/audit_tool_test.dart:21` **нет файла** `../flutter3d_model_core/test/model/fixtures/broken_asset.glb`; 8× `tutorial_scenarios_test` (кейсы 1–4, 6), `agent_builds_a_table`, `paint_and_light_mcp`, `getting_started`, `editor/tools_test`, `three_torches_test` |
| flutter3d_conformance | 22 | 0 | 0 | 3s | — |
| flutter3d_cpu | 639 | 9 | 1 | 31s | `conformance_test.dart` cpu: readback принял `r16g16b16a16Float` (контракт — ArgumentError); `cpu_shaders_sky.dart:56` `RangeError 0..8: 9` в `SkyCubeVertexShader` (cube map faces); `render_anchors_test.dart:360,456` порядок 244→260, лишний `'legacy'`; `render_steps_test.dart` ×3 — с выключенным step пропадает `transparent`; `decal_test.dart:377,392` unlit/emissive decal цвет (sRGB) |

Итого: 7 зелёных из 19, **136 падений**. Кластеры: (а) `LinearColor`/sRGB-миграция цветов — core, model_core, cpu decal; (б) `FormatSpec.open` из `flutter3d_foundation` сменил класс и текст исключений — plugin_api, sim, particles; (в) float32-«to the bit» константы мира — matter, physics, particles, editor_core; (г) records с List внутри в `expect(equals)` — net, editor_core; (д) `plugin_discovery.dart:334` unmodifiable sort — 17 тестов build; (е) фикстуры: sim v2 demo digest, `broken_asset.glb` отсутствует, парити-тейпы разошлись (sim step 75, solver step 5, relay step 25).

## 2. Покрытие CI

`tool/ci.sh` (494 строки) + `.github/workflows/ci.yml` (762; diff к HEAD — только комментарий flat-dart про `flutter3d_mcp`). Jobs: `check` (ci.sh, ubuntu, 90 мин: structure, format, pub get, api snapshots, shaders×3, icons, models, levels, webgl/webgpu/compute tables, engine tables, gltf validate, analyze, publish check, modeller screenshots, тесты всех `packages/*` с тестами, 3 cloud-сервиса, `tool/release_dashboard`, `tool/api`, browser-прогоны webgl/webgpu/pointer_lock/app/editor/physics/sim/physics_native/game, `packages/*/example`, все `apps/*` без тега golden, `build web --wasm` dungeon, компиляция бенчей), `flat-dart` (Dart 3.13 без Flutter), `render` (CPU-голдены через `golden.sh --cpu`, 150 мин), `render-apps` (tag golden: modeler, showcase), `desktop` (linux+windows build: dungeon, platformer, racing, arcade, strategy, editor), `physics-native-windows` (MSVC `flutter test`), `godot`, `macos` (analyze + structure + 4× `build ios --no-codesign`), `pacing` (continue-on-error), `android` (4 демо, debug + release при наличии ключа).

Дыры:
- **Nightly Impeller — нет**: `rg 'schedule:|cron' .github/workflows` пусто; Impeller-половина голденов только руками `packages/flutter3d/tool/golden.sh` (ci.sh:12–17, SUPPORT.md:48).
- Не запускаются сьюты `tool/convert_asset` (13), `tool/skills` (13), `tool/init` (6), `tool/tutorial` (29) — названо в ci.sh:228–235 как «дыра»; root `test/structure_test.dart` тоже никто не вызывает.
- Пакеты без тестов: `flutter3d_samples` (0 файлов), `flame_flutter3d_audio` (1 файл, 0 `test(`/`testWidgets(` по регэкспу правила — проверить). Приложения без тестов и без build-шага вообще: `flutter3d_demo_hollow`, `flutter3d_demo_water`; `apps/flutter3d_demo_crawler` и `apps/flutter3d_template_app` — пустые каталоги без pubspec.
- Приложения, у которых есть тесты, но нет ни одной сборки: reef, river, sandbox, lab_incident, lab_pendulum, lesson_viewer, stereo_lesson_viewer, showcase, modeler (только golden-тег).
- Web-сборка только dungeon; iOS/Android — 4 демо (без arcade, editor).
- Условные skip'ы: `physics_native` (GPU, node, wasm), `flutter3d_webgpu/runtime_material_test` (naga), `build/migrate_fixture_test` (Flutter на PATH), `mcp/editor/dungeon_frame_test` (`FLUTTER3D_RUN_GAMES`, `@Timeout(12 min)`), `flutter3d/render_benchmark_test` и `mesh/lscm_test` (`CI==true`), `webgl/cross_backend_test:440` `_provisional`-набор. Безусловный skip: `apps/flutter3d_demo_platformer/test/playing_the_game_test.dart:327` («textures stop decoding at the third»). `solo:` — нет, `@Skip` — нет.
- `print(` в тестах: 41 место (cpu 8, flutter3d 9, webgl 6, dungeon 5, mesh 4, …) — диагностические, не отладочный мусор.

Правило «says N tests»: `tool/structure/rules.dart:1812` считает `^\s*(test|testWidgets|testWithFlameGame)\(` по `packages/*/test`, `apps/*/test`, `packages/*/example/test`; сейчас = **13267**, и столько же в README.md:209, ARCHITECTURE.md:3566, site/content/quickstart.md:94, site/content/reference/testing.md:2,7 — правило держится (structure.log). ARCHITECTURE.md:3705 «1230 tests» — это исторический пример в прозе, не утверждение.

## 3. Голдены и тейпы

| Набор | всего | M | newest PNG | вывод |
|---|---|---|---|---|
| `packages/flutter3d/test/goldens` (Impeller) | 96 | 25 | 2026-10-08 02:50 | старее шейдеров |
| `flutter3d_cpu/test/goldens` | 97 | 22 | 10-08 06:58 (`frame_order.jsonl` 14:40) | старее |
| `flutter3d_webgl/test/goldens` | 96 | 25 | 10-08 06:54 | старее |
| `flutter3d_webgpu/test/goldens` | 96 | **0** | 10-06 05:36 | **не перезаписан** (0.9-release.md:43 «WebGPU set is still open») |
| `apps/flutter3d_demo_platformer/test/goldens` ascent-120/600 | 2 | 2 | 10-08 05:54 | = тейпам |
| `apps/flutter3d_demo_dungeon/test/goldens/replay-frame.png` | 2 | 0 | 10-05 | не трогали |
| `apps/flutter3d_modeler/test/goldens` | 75 | 0 | 10-06 | — |

Исходники новее всех голденов: `packages/flutter3d_shaders/shaders/lib/pbr.glsl` 10-09 02:34, `surface.glsl`, `contributor_lights.glsl`, `post/volumetric_fog.frag` 02:33, `sky_physical.frag/.vert` 02:12, `bloom_threshold.frag`, `contact_shadow.frag` 01:37 (24 M + 12 новых `*_opaque.frag`, `depth_predraw.frag`, `shadow_storage.glsl` — п.5–6 scope-additions, reversed-Z/opaque-варианты); `flutter3d_cpu/lib/src/cpu_shaders_color.dart` 10-09 12:08; `flutter3d_webgl/lib/src/webgl_shaders.dart` 12:08; `flutter3d_core/.../render/material.dart` 12:02. То есть все четыре набора нужно перезаписать после правок 10-09 (план: 0.9-release.md:47–115 — constants, Portable, depth/precision на всех четырёх бэкендах; 1.0-publish.md:39 — «platformer, water/seabed looks, WebGPU»). Ещё 134 M PNG в `cloud/server/web/assets/learn/modeler/*` и `site/assets/modeler` (скриншоты туториала, проверяет `publish_modeler_screenshots.dart --check`).

Тейпы: `apps/flutter3d_demo_platformer/test/tapes/ascent.f3drun` и `site/assets/samples/platformer.f3drun` — M, 10-08 05:54 (перезаписаны до правок 10-09 в `flutter3d_physics/lib/src/character_controller.dart` 12:08 и `game_platformer/lib/src/staging.dart` 12:08 → скорее всего снова устарели; 10 падений character_controller это подтверждают). `site/assets/samples/racing.f3drun` 10-06 — план (0.9-release.md:73–78) требует перезаписи из-за `Portable.atan2`, не сделано. `shooter.f3drun` 09-12 — остаётся. **Untracked** фикстуры: `packages/flutter3d_sim/test/fixtures/v1..v4/run.f3drun`, `packages/flutter3d_game_strategy/test/fixtures/v1,v2/match.f3drun` — не в git; `demo_fixture_test` падает на v2 (digest уровня изменился после записи).

## 4. Публикация

`dart pub publish --dry-run` × 56 пакетов (+ `flutter3d_demo_content` publish_to: none, намеренно): **41 ready, 15 с warnings, 0 ERROR**. 14 из 15 — только «N checked-in files are ignored by .gitignore» = удалённые/перенесённые в рабочем дереве файлы (напр. `flutter3d_game_shooter/lib/sample.dart` D), уйдут после коммита. Реальные блокеры:
- **`flame_multiplayer` 0.3.0** (`packages/flame_multiplayer/pubspec.yaml:3,33`): `flutter3d_net: ^1.0.0-rc.1` → pub: «Packages dependent on a pre-release… should themselves be published as a pre-release». Нужно `0.3.0-rc.1` (или дождаться 1.0.0). `flame_multiplayer_dashwire` 0.2.0 зависит от `flame_multiplayer: ^0.3.0` и `flutter3d_plugin_api: ^1.0.0-rc.1` (pubspec:30,42) — та же проблема после первого фикса (сейчас dry-run её не показал, перепроверить).
- `flutter3d_lints`: `analysis_server_plugin: ^0.3.17` (pubspec:36) — уже не пин, dry-run чист. Снято.
- `flutter3d_build`: `test/fixtures/migrate_0_8/` исключён через `.pubignore` — dry-run чист. Снято.
- `dart-apitool` не установлен → `tool/api_against_pub.sh` пропустит сравнение (скрипт read-only, качает только через dart-apitool; не запускал). 1.0-publish.md:120 просит перепрогнать после последнего API-изменения.
- Метаданные: все 57 pubspec имеют `repository/homepage/issue_tracker/topics/platforms`, LICENSE, CHANGELOG, README; `flutter3d_post` — ключ `flutter3d_plugins:`; `flutter3d_demo_content` без `platforms:` (не публикуется). `screenshots:` — ни у кого. Описания >180 символов (pana снижает балл, не ошибка): editor_widgets 312, camera 299, plugin_runtime 276, lints 236, app 225, post 214, sim_mcp 213, core 202, dashwire 194, flame_flutter3d 190, level_scene 184, build 183, flame_flutter3d_audio 182.
- Пол SDK одинаков: 57× `sdk: ">=3.12.0 <4.0.0"`, 25× `flutter: '>=3.44.0'` — совпадает с SUPPORT.md:201–204 (CI Flutter 3.47.0 / Dart 3.13.0, ci.yml:48,195).
- `packages/flutter3d_foundation/` — **весь пакет untracked** (`?? packages/flutter3d_foundation/`), при этом он в workspace и от него зависят sim/particles/plugin_api. (Добавлен в git в тот же день.)

## 5. Остатки в коде

| Маркер | Всего | Худшие |
|---|---|---|
| `TEMPSILENT` / `setGlobalVolume(0)` | 0 в коде | только `tasks/*.md` и детектор `tool/structure/detectors.dart:2298` |
| TODO/FIXME/XXX/HACK в `packages/*/lib` | 69 | impeller 39 (`gpu_device.dart:51,83,952,963,1193,1204,1262,1293` — все `TODO(impeller)` про отсутствующие фичи flutter_gpu), webgl 15, webgpu 5, cpu 4, build 3, lints 2 |
| `print(` в lib | 1 | `flutter3d_testing/lib/src/golden.dart:80` (сообщение о записи голдена) |
| `debugPrint(` | 16 | app 5 (`hot_swap.dart:901`, `frame_timing_log.dart:69`), flutter3d 2, game 2, game_kit 2, stereo 2 |
| `// ignore:` | 53 | core 18, sim 10 — почти все `prefer_initializing_formals` (`sim/lib/src/level/brush.dart:100,102`, `core/.../light_node.dart:32`); `ignore_for_file` 11 |
| `UnimplementedError` | 1 | `flutter3d_mesh/lib/src/mirror.dart:46` |
| `throw UnsupportedError` | 52 | webgl 25 (`webgl_transfer.dart:77,141,147,153`, `webgl_resources.dart:456`), cpu 9, impeller 4 |
