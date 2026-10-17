# Аудит публичных документов flutter3d (ветка 0.9.0, рабочее дерево, 2026-10-09)

Заметки агента. Состояние дерева на 2026-10-09.

**База для сверки.** `packages/` — 57 каталогов (не 59): 53 на `1.0.0-rc.1`, 4 со своей линией (`pad_input` 0.5.0, `pointer_lock` 0.5.0, `flame_multiplayer` 0.3.0, `flame_multiplayer_dashwire` 0.2.0); из 57 публикуются 56 (`flutter3d_demo_content` — `publish_to: none`). `apps/` — 19 каталогов, из них `flutter3d_demo_crawler` и `flutter3d_template_app` **пустые и неотслеживаемые** (0 файлов в git, нет pubspec) — это мусор после удаления, не забытые приложения; реальных приложений 17, все в workspace. Все 57 пакетов в workspace. Полный `dart run tool/structure.dart`: **70 правил, all held** (71 с). Значит числа, которые держат правила, верны: 13267 тестов / 57 пакетов / 17 приложений (README:209, ARCHITECTURE:3566, quickstart:94, reference/testing.md:7), 70 правил (README:261, CONTRIBUTING:62, site/index.md:146), 96 golden-сцен, порядок публикации §16, `platforms:` во всех публикуемых pubspec по SUPPORT.md, ограничения `^1.0.0-rc.1` между соседями, floor Dart `>=3.12.0` / Flutter `>=3.44.0` везде (совпадает с SUPPORT.md:201-202).

## (a) Неверные числа и версии

- **README.md:12** «fifty-two packages» на pub.dev → публикуемых 56. **README.md:18-19** «Forty-eight of them are the 1.0.0 set» → 52 публикуемых на полке (53 с demo_content).
- **README.md:31-33** «`flame_multiplayer` at 0.2.0 and its dashwire adapter at 0.1.1» → 0.3.0 и 0.2.0 (`packages/flame_multiplayer/pubspec.yaml`, `…_dashwire/pubspec.yaml`). Там же «since neither names a sibling, and so do flame_multiplayer…» — ложно: `flame_multiplayer` зависит от `flutter3d_net: ^1.0.0-rc.1`.
- **SUPPORT.md:162** «The forty-nine packages of the shelf» → 53.
- **site/content/index.md:31** «all 45 packages… Forty-two carry the release candidate… `flame_multiplayer` at 0.2.0 and `flame_multiplayer_dashwire` at 0.1.1» → 56 / 52 / 0.3.0 / 0.2.0.
- **site/content/reference/packages.md:7** «Fifty-five packages… Fifty of them carry the release candidate» → 57 / 53 (версии 0.3.0/0.2.0 там уже верные).
- **AGENTS.md:9** «36 packages and 8 applications», **AGENTS.md:26** «36 rules» → 57/17 и 70. Весь AGENTS.md написан как инструкция по одному модельеру (`doc/model-editor-plan.md is the work`, строки 12-20) — устарел по содержанию.
- **ARCHITECTURE.md:4627-4628** «`flame_multiplayer` names no package at all… takes 0.2.0… the second 0.1.1» — противоречит §3.2 (строка ~295: «over `flutter3d_net`'s wire… which it re-exports») и pubspec.
- **ARCHITECTURE.md:4738-4739** «four demo games, two editors and three lesson viewers» → 10 демо, 3 инструмента, 4 урока (собственный список §3.2 говорит «seventeen»).
- **README.md:75** и **packages.md:306** «147 editing tools» модельера — снимок `packages/flutter3d_mcp/api/flutter3d_mcp.mcp` содержит 154 инструмента в `flutter3d.model` (editor 58, project 1; sim 11, diagnostics 6; plugins 4 = 234, как и сказано в ARCHITECTURE §16).
- **ARCHITECTURE.md:4551** «Three go out for the first time: physics_native, voxel, editor_play» — по CHANGELOG первые релизы также у `flutter3d_foundation`, `_matter`, `_elements`, `_level_scene`, `_build_hooks`, плюс 7 новых имён слияний (`_post`, `_game_kit`, `_game_physics`, `_game_ui`, `_camera`, `_mcp`, `_education`). Занижено.
- **quickstart.md:22** «Dart 3.12.2 or newer» и пример pubspec `sdk: ^3.12.2` (:109) против floor 3.12.0 в SUPPORT.md:201.
- **Публикация:** `flame_multiplayer` 0.3.0 (не pre-release) зависит от `flutter3d_net ^1.0.0-rc.1`. Валидатор `pub publish` на это выдаёт **warning** («packages dependent on a pre-release… should themselves be published as a pre-release»), не error — публикация пройдёт с подтверждением, но решить надо: либо `0.3.0-rc.1`, либо принять предупреждение. `platforms:` отсутствует только у неопубликуемого `flutter3d_demo_content` — норма.

## (b) Ссылки

- Относительные ссылки в README, ROADMAP, ARCHITECTURE, CONTRIBUTING, AGENTS, SUPPORT, SECURITY, docs/CONTRACTS.md и во всех 57 `packages/*/README.md` — **битых нет**. `doc/boundary-0.7.0.md`, `doc/engine-gap-analysis.md`, `tasks/1.0-stability.md`, `tasks/1.0-publish.md`, `tool/verify_plan.dart`, `doc/plan-status.json` существуют. Все пути к скриптам/снимкам из CONTRIBUTING существуют.
- **site/content/reference/packages.md:355** `/showcase/learn/` — нет `site/content/showcase/learn.md` (остальные маршруты сайта из quickstart/packages/index/comparison разрешаются).
- **quickstart.md:196** «`example/lib/widgets_main.dart`» — файл есть только в `packages/flutter3d/example/lib/`, а абзац про `flutter3d_app` (в `packages/flutter3d_app/example/lib/` только `main.dart`, `first_scene.dart`).
- **README.md:306** «recorded beside them in `LICENSES.md`» — корневого файла нет, только по приложениям (`apps/*/assets*/…/LICENSES.md`); читается как один файл.

## (c) Ложные или противоречивые утверждения

- **Таблица README «What is here»** не содержит 7 пакетов: `flutter3d_audio_core`, `flutter3d_demo_content`, `flutter3d_editor_play`, `flutter3d_effects`, `flutter3d_lints`, `flutter3d_physics_native`, `flutter3d_plugin_runtime`, и 3 приложений: `flutter3d_demo_river`, `flutter3d_showcase`, `flutter3d_lab_incident`. Несуществующих записей нет. ARCHITECTURE §3.2 покрывает всё; **packages.md** пропускает `flutter3d_build_hooks`, `_editor_play`, `_physics_native`, `_voxel`.
- **README.md:15** «re-exporting the renderer, the view and what a first game uses…» — **верно**: `packages/flutter3d_game/lib/flutter3d_game.dart:49-79` экспортирует `flutter3d` целиком и поимённо из app/audio_core/physics/sim; согласовано с ARCHITECTURE:268, packages.md:170 и `reexportsAllowed`. «Four backends» (README:70) — верно (native: Impeller+CPU, web: WebGL2+WebGPU в `flutter3d_app/lib/src/backend_*.dart`).
- **README.md:56** и **ARCHITECTURE.md:289-290**: `pointer_lock` «a method channel on macOS… web», `pad_input` «web, Android, macOS and iOS» — устарело: CHANGELOG 0.5.0 обоих добавил Windows и Linux, SUPPORT.md:147-148 их перечисляет. **README.md:60** «flutter3d_impeller | The desktop backend» — он же Android/iOS.
- **README.md:146-152** «Required before the first run… `./tool/build_shaders.sh`» для `flutter3d_impeller` — `packages/flutter3d_impeller/hook/build.dart:1-3` собирает канонический бандл сам; quickstart.md:43 это уже говорит. Шаг нужен только для бандла примера (:157). Сам quickstart при этом в :7 всё ещё «Two of those minutes go on a shader bundle».
- **README.md:184-187** «What the demos are published as. --wasm…» против **site/tool/demos.sh:54-55** («`--wasm` is off… dart2wasm build of the WebGL backend throws on the first frame») и quickstart.md:79. Одно из двух неверно. CI при этом строит dungeon с `--wasm` (`tool/ci.sh:462`), так что README:216 и SUPPORT:69 верны.
- **SECURITY.md:49-50** «Nothing is published to pub.dev yet, and there are no releases to back-port to» — ложно: 0.8.x на pub.dev (README:24, ARCHITECTURE §16), политика бэкпортов есть в SUPPORT.md:183-192. **SECURITY.md:18-19** «not a network it does not open» — теперь есть `flutter3d_net`/`_net_webrtc` (WebSocket-релей, WebRTC), LTI/OIDC с проверкой `id_token` в `flutter3d_education`, Wasm-плагины в `flutter3d_plugin_runtime`; список scope (:21) не знает USDZ/KTX2/`.f3dplugin`.
- **comparison.md:9, :125, :138** «three complete games… A fourth genre, strategy, is in the workspace too» — README:72,94 и ROADMAP:43-44: стратегия — полноценная игра с демо на desktop/web/Android/iOS. Страница датирована 2026-10-09. **comparison.md:112** «`flutter3d_editor_mcp` is on pub.dev» — пакет теперь `flutter3d_mcp` (её же строка 26).
- **packages.md:82** в описании `flutter3d_sim` «`GameLoop`» — удалён в 1.0 (ARCHITECTURE:2418, в коде `EngineLoop`); то же **packages/flutter3d_particles/README.md:19** «`GameLoop.lastFrame`».
- **ARCHITECTURE.md:311 и :384** — два раздела «### 3.3».
- **ROADMAP.md:37-38** «tutorials for each genre» — на сайте `tutorial.md` только у shooter/platformer/racing; README:40 «three of the four» верен.
- **docs/CONTRACTS.md** — проверено по коду: все перечисленные идентификаторы существуют (`FormatSpec.enveloped` — foundation/formats.dart:120; `WorldTiming`/`standardStepRate`; `Scene.toScene`, `DebugDraw.addWorldLine`, `burstInWorld`; `Photometric.legacyUnit/legacyNits`; `MechanicalProperties.friction` — property_groups.dart:119; `MaterialCatalog.contact`; `PhysicalSky.sunIlluminance`; `clearLabel`; `f3d.cli`; `Flutter3dView` собирает реестр из `coreFormats`+`simFormats` — flutter3d_view.dart:505). Идентификаторы конвертов (`f3d.settings`, `saveSlots`, `telemetry`, `voxelWorld`, `run`, `save`, `inputTape`, `materialCache`, `project`, `plugin`…) в коде есть. Правило «Words written to a file… never from a Dart identifier's `.name`» (:291-293) стоит перепроверить: `packages/flutter3d_game/lib/src/run/demo_recording.dart:189` пишет `physics: physics.name`, `platform_cloud_saves.dart:99` — `'provider': provider.name`, `flutter3d_sim/lib/src/loop/engine_loop.dart:884,1021` — `system.name`/`phase.name`; если это enum'ы, попадающие в файл записи, правило нарушено.
- **quickstart.md** — все API существуют: `Flutter3dView`, `Flutter3dEngine`, `onCreated`/`onFrame`, `FrameInfo.seconds`, `DeviceMesh.upload`, `SphereShape`, `RenderMaterial`, `LinearColor.fromSrgb`, `scene.meshes`, `Scene3D`, `Camera3D`, `Light3D.point(range:)`, `Material3D`, `Mesh3D`, `Node3D`, `Model3D`, `ReflectionProbe3D`, `Decal3D`, `Mirror3D`, `Particles3D`, `Contributor3D`, `SceneWidgets.mount`, `SceneSurface`, `openDevice`, `Renderer.create` (renderer.dart:2008), `renderer.addContributor`, `RenderTexture.create`. Устарели только :101 («Skip 0.7.0… moving a project from 0.6.0») и пункты выше.

## (d) ROADMAP.md — что уже неверно

- **:3-9** «revised next on 28 September» — дата прошла без ревизии; файл по своим же правилам (:427-433) просрочен.
- **:47-51** «0.7.0 is prepared and not published. Thirty-three packages carry the number» — опубликовано 0.8.x, дерево на 1.0.0-rc.1 с 53 пакетами.
- **:53-69** сага про красный `main` сентября; требование :84-85 «goes into CONTRIBUTING.md» выполнено (CONTRIBUTING:458).
- **:95-122** редактор + MCP, **:124-156** модельер — сделано (`flutter3d_mcp` 58/154 инструментов, `flutter3d_editor_core`, `_mesh`, `_model_core`, models.pleion.dev).
- **:160-183** «Today a new project reaches its first frame through two manual steps… `dart run flutter3d:init`… move out into `flutter3d_formats`» — хуки есть (`flutter3d_build` hook, `flutter3d_impeller/hook/build.dart`); команда — `flutter3d_build:init` (`packages/flutter3d_build/bin/init.dart`); `flutter3d_formats` не существует (свёрнут в `flutter3d_core`, как :135 сам признаёт).
- **:189-196** диагностический MCP-сервер — есть (`flutter3d.diagnostics`: `render.readPixel`, `render.scanNan`, `render.passes`). **:198-206** редактор запускает игру, hot reload — `flutter3d_editor_play`, инструменты `play.devices/build/swap`.
- **:219-235** стратегия как четвёртый жанр — сделано.
- **:237-256** световой трек: кластеры (`light_buffer.dart:232-239`, comparison:39), декали, FXAA/TAA/SMAA (comparison:52-54) — сделано; **:240** «eight lights is a ceiling» устарело.
- **:260-279** heightfield/triangle mesh — в C-ядре есть triangle meshes (comparison:110); в Dart `flutter3d_physics` классов `Heightfield*`/`TriangleMesh*` нет — частично.
- **:283-298** «WebGPU spike… answer by 28 September» и **:334-338** «WebGPU as a full fourth backend» — WebGPU уже backend по умолчанию (README:175).
- **:339-344** «Two players in lockstep» — `flutter3d_net` rollback 2–32 пиров, релей, `flame_multiplayer`.
- **:347-349** «gamepad and pointer capture on Windows and Linux… unsupported today» — сделано в 0.5.0.
- **:350-352** clustered lights «only if measurement asks» — поставлено. **:361-363** skills для пользователей — README:273-288.
- **:393-399** «Flutter widgets on 3D surfaces», «Rigid bodies with rotation and joints», «temporal antialiasing» ждут после квартала — все три есть (`flutter3d_app/lib/src/widget_surface/`, rigid bodies+joints в `flutter3d_physics_native` (ARCHITECTURE §3.2, comparison:78,110), TAA в `flutter3d_post/lib/motion.dart`, `render_step.dart:380`).
- **:401-405** «Not doing: Comparison tables against other engines» — `site/content/reference/comparison.md` существует. **:416** OIT «not doing» — comparison:49 «yes». **:423-425** «Compute-dependent techniques — platform's» — на WebGPU splats сортируются compute (comparison:57).
- **:381-386** про 1.0 вместо 0.9.0 — актуально. **:87-93** ночной Impeller-прогон — проверить нечем.

## (e) CHANGELOG.md

- Верхний заголовок у всех 53 пакетов полки — `## 1.0.0-rc.1`; у четырёх своих — `## 0.5.0`, `## 0.5.0`, `## 0.3.0`, `## 0.2.0`. `Unreleased` и `0.9.0` не встречаются ни в одном CHANGELOG.
- Пустых/заглушечных секций нет (совпадения по `TODO` — проза про `TODO(impeller)` в коде, не плейсхолдеры).
- `**Breaking:` есть во всех пакетах с предыдущим релизом; без него только первые релизы (`build_hooks`, `demo_content`, `elements`, `foundation`, `level_scene`, `lints`, `matter`) — ожидаемо. Правила «a break in a published API is labelled and versioned» и «every break since the last release has its migration» прошли в полном прогоне.
- Единственное, что стоит подчистить руками: `packages/flutter3d_app/CHANGELOG.md` упоминает `example/lib/widgets_main.dart`, которого в примере `flutter3d_app` нет (см. (b)).
