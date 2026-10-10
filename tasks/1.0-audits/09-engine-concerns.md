# Аудит «движковых» аспектов flutter3d перед 1.0.0-rc.1 (рабочее дерево, 2026-10-09)

Заметки агента. Все пути — от корня репозитория. Порядок — по убыванию серьёзности.

## ВЫСОКАЯ

### 1. Нативный снапшот физики доверяет индексам из файла (OOB-read в C)
- `packages/flutter3d_physics_native/csrc/src/f3d_snapshot.c:575` читает `part->hull` составной части, а `consistent()` (:1138-1173) проверяет только диапазоны вершин/треугольников хуллов, мешей и частей — **не** сами id хуллов. Потребитель `csrc/src/f3d_compound.c:246` делает `&world->hulls[part->hull - 1u]` без проверки (в отличие от тел: `f3d_collide.c:31-47`, `f3d_motion.c:151-155, :190, :219`, `f3d_tree.c:393` проверяют `s->hull <= hull_count`).
- Индексы треугольников меша читаются в `f3d_snapshot.c:959` без проверки `>= vertex_count`, которую обычный API делает в `f3d_mesh.c:62`.
- `make()` (:803) выделяет count×size из входа до того, как `IO_LIST` сверит count с длиной буфера (:883) — DoS по памяти.
- В `csrc/tests/test_snapshot.c:525-540` только бит-флипы и версии; фаззинга декодеров (Dart и C) нет вообще.
Следствие: подсунутое сохранение/реплей/сетевой снапшот — чтение за границей массива в нативном коде, а не типизированное исключение.

### 2. MCP-серверы: файловые инструменты без «клетки», инъекция в cmd.exe
- HTTP-транспорт корректно: loopback (`packages/flutter3d_mcp/lib/src/kit/loopback_http.dart:77-78`), 32-байтный `Random.secure` токен (:182), проверяется на каждом запросе (:136). Но: токен принимается и в `?token=` (:179, утекает в логи/историю), сравнение `!=` не constant-time, тело запроса без лимита (:142), файл сессии с токеном пишется с дефолтными правами (:237).
- Нет ни одного `isWithin`/`canonicalize`/проверки корня: пути из аргументов инструмента идут прямо в `File()` — `model_tools.dart:3059, :3083, :3125, :3180, :1269`; `editor_session.dart:410`; `capture_files.dart:117, :138`; `sim_session.dart:73, :549`. `safeRelativeAssetPath` (`flutter3d_core/lib/src/formats/asset_source.dart:64`) не отвергает `C:` и симлинки; `flutter3d_sim_mcp/lib/src/diagnostic_renderer.dart:153-157` принимает абсолютные пути и `..` из файла уровня.
- `play_session.dart:39-44`, `flutter3d_editor_play/lib/src/flutter_run.dart:31`, `devices.dart:72` — `runInShell: Platform.isWindows`, а строка `device` из `editor_tools.dart:459` попадает в `-d <id>` без валидации → инъекция команд на Windows.
- `packages/flutter3d_net/bin/relay.dart:94` слушает `anyIPv4` без аутентификации и без лимита наблюдателей (:239); accept-цикл `await`-ит каждый апгрейд — один медленный клиент тормозит всех.
- Из 81 `Process.run/start` все передают аргументы списком; `bash -c`/`sh -c` только с константами (`tool/release_dashboard/lib/src/gates.dart:207-226`, `tool/godot_check/bin/godot_check.dart:62`).
Следствие: агент, подключённый к MCP, может читать/писать любой файл пользователя; на Windows — выполнить команду.

### 3. Ошибки на границах: WebGPU молчит, Impeller/CPU не знают о потере устройства
- WebGPU: ошибки компиляции шейдеров и валидации только складываются в `_errors` (`packages/flutter3d_webgpu/lib/src/webgpu_device.dart:524`) и достаются одним `debugDrainErrors` (:740), который в проде никто не зовёт (единственный вызов — `example/.../backend_web.dart:130`). Слушателя `uncapturederror` нет (0 совпадений). Пользователь получает чёрный кадр без исключения.
- Там же **утечка**: `_guard` (:713) добавляет Future в `_pending` на каждый pipeline, submit прохода (`webgpu_encoder.dart:1355`) и present (:1577); список очищается только в `debugDrainErrors` (:741-742) → несколько записей за кадр, миллионы за час игры.
- Потеря устройства: поток `DeviceLoss` (`flutter3d_hardware/lib/src/graphics_device.dart:790`) реализован для WebGL (`webgl_device.dart:146/161`) и WebGPU (:1390), вид её обрабатывает (`flutter3d_app/.../flutter3d_view.dart:552-566`). **Impeller и CPU не переопределяют `lost`/`isLost`** — на Android/iOS потеря контекста не замечается.
- Компиляция шейдера WebGL — нетипизированный `StateError` (`webgl_shaders.dart:160, :342`); отсутствующий ассет — `StateError`/сырой `FlutterError` (`flutter3d/lib/src/engine/assets/load_model_asset.dart:202/209`, `bundle_asset_source.dart:32`), типа `AssetNotFound` нет при 31 типизированном исключении в движке.
- `DidNotStart` — виджет с текстом ошибки (`flutter3d_app/lib/src/surface/did_not_start.dart:18`, `flutter3d_view.dart:536, :711-718`), а не структурированный отчёт.
Следствие: три из пяти пограничных случаев на части бэкендов проявляются как пустой кадр или строка, а не как тип, который можно поймать.

### 4. Горячий путь: аллокации на каждый draw и перекомпиляция графа кадра
Худшие 10 (все проверены чтением функции):
1. **Новый буфер на каждое связывание uniform-блока во всех бэкендах**: `flutter3d_impeller/lib/src/gpu_command_encoder.dart:335` (`ByteData(size)` + closure `members.forEach` + строковый поиск слота на каждый член; :658 копирует побайтно), `flutter3d_webgpu/lib/src/webgpu_encoder.dart:374`, `flutter3d_webgl/lib/src/webgl_encoder.dart:821` (`Float32List` на bind). Меш связывает 6-10 блоков (`renderer_mesh_encode.dart:496-1039`) → 6-10 typed-array на меш на вид, включая теневые проходы; skin-блок 4 КБ на скиннед-draw (1024 `setFloat32` на Impeller).
2. **Граф кадра пересобирается и компилируется каждый кадр**: `flutter3d_core/lib/src/engine/render/renderer.dart:4863-4931` («nodes are rebuilt every frame») + `frame_graph_compile.dart:167-337`: `where().toList()`, 2-3 `Map<String,int>` и `Set<int>` на узел, `keys.toList()` дважды, `edges[i].toList()..sort()` — ~100+ контейнеров за кадр при неизменной сцене.
3. ECS `query.entities` (`flutter3d_sim/lib/src/ecs/ecs_world.dart:569-610`): `Set<Type>`, список кандидатов по всем сущностям или `keys.toList()..sort()` — на каждый запрос каждого шага.
4. Избегание акторов (`flutter3d_sim/lib/src/actors/actor_system.dart:837-860`): список записей + `sort` с closure на актора за шаг, O(A²).
5. Блендинг поз (`engine/animation/pose.dart:155-180`): 2 `Quaternion` + slerp на сустав за кадр при кроссфейдах.
6. IK: FABRIK (`inverse_kinematics.dart:243, :291`) — `pose.worldMatrices()` на сустав цепи (nodeCount `Matrix4` каждый); two-bone (`graph/animation_goals.dart:126`) — список и матрицы на цель за кадр.
7. Transmission-кадры копируют список непрозрачных (`renderer_scene_pass.dart:373-375, :426-437`, 3 `clone()`; `renderer_transmission_pass.dart:222-236`).
8. Декали (`renderer_decal_pass.dart:106-113, :257-270`): сортировка с closure + `Matrix4.copy`, 8 `Vector4`, список на декаль на вид.
9. Сортировка частиц по глубине (`flutter3d_particles/lib/src/particle_system.dart:755-768`): `Iterable.generate` + comparator-closure на систему за кадр (render list уже использует packed keys, а тут нет).
10. Жидкость (`flutter3d_physics/lib/src/fluid/particle_fluid.dart:289, :609`): `Vector3` на частицу за шаг (и ×substep×obstacle), `removeAt` O(n).
Плюс: пост-цепочка — ~25 мест с новыми `Map` литералами на fullscreen-draw (`renderer_post_pass.dart:272-298`); тени — хеш всех мешей на каскад за кадр (`renderer_shadow_pass.dart:557-600`). Счётчики: `engine/render/` — 15 `.toList()`, 71 `Vector3(`; `flutter3d_sim/lib` — 33 и 43.
Следствие: GC-паузы и джиттер на мобильных при сотнях draw; первые два пункта — самые дешёвые в исправлении (scratch-буфер на блок; кэш скомпилированного графа до смены входов).

### 5. Точность: во всём движке нет ни одного double-вектора
- ~1100 импортов `package:vector_math/vector_math.dart`, 0 `vector_math_64` → `Vector3`/`Matrix4` хранятся в `Float32List`. Позиция узла — float32 с момента записи (`engine/scene/scene_node.dart:62, :66-68`); `RigidBody.position/velocity` Dart-физики — тоже float32 (`flutter3d_physics/lib/src/rigid_body.dart:97, :99, :151`), хотя `rigid_dynamics.dart:5-9` называет её «reference … in doubles».
- `WorldPosition` (double, `flutter3d_foundation/lib/src/world_position.dart:24`) вычитается в double **до** сужения (`relativeTo` :53; `scene.dart:126-131`; `vectors.dart:31-34`) — это правильно, но схема — плавающий origin, а не camera-relative на upload: `renderer_mesh_encode.dart:389, :492-494` копирует `.storage` как есть. `Scene.rebaseAround` (:179) не вызывается нигде; `loop.shiftOrigin` (`flutter3d_sim/.../engine_loop.dart:599`) не зовёт ни одно приложение. `docs/CONTRACTS.md:34-38` это признаёт.
- Тестов рендера/физики вдали от origin нет: `flutter3d/test/depth_precision_test.dart:130, :281` — только глубина (1 см на 10 км, стена на 20 км); origin-тесты на 10-90 м (`flutter3d_physics/test/origin_test.dart:22`).
- Reversed-Z включён по умолчанию (`render_settings.dart:1534`), но зависит от устройства: Impeller — только при `d32FloatS8UInt` (`gpu_capabilities.dart:103-104`, т.е. не GLES), WebGL — только с `EXT_clip_control` (`webgl_device.dart:421`), WebGPU — только с `depth32float-stencil8` (`webgpu_formats.dart:305`), CPU — всегда. Near-plane подгоняется покадрово (`renderer_scene_pass.dart:309-311`).
- C-ядро: `f3d_real` = `float` (407 раз в `csrc/include/f3d_physics.h`, `double` только для origin :393-399, :1720), маршалинг 244 `Float` против 3 `Double` (`calls_native.g.dart`). Дайджест Dart↔native **не сравнивается**: `native_dynamics.dart:22-25` прямо говорит, что нативные дайджесты «не референса»; `native_dynamics_test.dart:18-29` сверяет оба движка с фиксированными числами, допуски от 1e-9 до 0.15 м (:60, :76, :137).
Следствие: на уровнях > ~1-2 км от origin дрожание геометрии и физики без предупреждения; детерминизм обещан только внутри одного движка.

## СРЕДНЯЯ

### 6. Память GPU: нет общей модели владения, Impeller ничего не освобождает
- Общий интерфейс — `GraphicsDevice` в `flutter3d_hardware/lib/src/graphics_device.dart:458-473` («what release means is a property of the backend, not a promise»); `releasePipeline/ComputePipeline/RenderBundle` (:707-713) — no-op по умолчанию и **ни один бэкенд их не переопределяет**; рендерер сбрасывает кэши пайплайнов без вызова (`renderer.dart:289-294, :1235-1270`).
- Impeller: `dispose`, `releaseTexture`, `releaseGeometry`, `releaseStorageBuffer` пустые (`gpu_device.dart:911-923, :130`) — по ограничению flutter_gpu (нет native dispose у `gpu.Texture`), только GC. WebGL — самый полный (`webgl_device.dart:760, :780, :789`); WebGPU — `destroy()` (`webgpu_device.dart:1430-1458`), пайплайны/layouts только в `dispose` (:2304-2332).
- Единственный refcount — `ResourceCache` (`engine/assets/resource_cache.dart:25-39`), но ноль → не вытесняет, `evictUnused()` (:122) из библиотек не вызывается (только `example/lib/main.dart:482`).
- Растут без вытеснения: пул staging-текстур readback Impeller по ключу `"${w}x$h/format"` (`gpu_readback.dart:52, :128-150`); `ProjectModelDocument._meshCache/_lodCache` по `(id, version)` — версия меняется на каждую правку, документ живёт всю MCP-сессию (`flutter3d_model_core/lib/src/project_document.dart:112, :169`); `FieldPass._pipelines` (`field_pass.dart:34`); `Renderer._anisotropicSamplers` (`renderer.dart:3948`).
- `_ViewState`: Expando + `whenDisposed` (`renderer.dart:406-462`), простой выброс через 16 кадров (:415, :481-495) — нормально; пробел: при перехвате состояния старого вида (:455-459) хук не регистрируется.
- Frame capture без лимита: все draw с декодированными uniform'ами (`draw_journal.dart:116-121, :170`), 128px-thumbnail PNG base64 всегда, полный PNG/float при флагах (`frame_capture.dart:113-153`, `capture_json.dart:99`); в памяти полный RGBA каждого прохода (:165, :174).
- `Finalizer`: 6, все в physics_native (`native_world.dart:1343` и др.); 0 в рендере.
Следствие: долгие сессии редактора/игры на Impeller зависят от GC; readback разных размеров копит текстуры.

### 7. Потоки: декодеры на web — в главном потоке, прогрев пайплайнов никто не зовёт
- Шаг симуляции синхронный (`flutter3d_physics/lib/src/dynamics.dart:228`, `native_world.dart:1578`, `isolate_simulation.dart:174`), `Renderer.render` синхронный (`renderer.dart:4510`). Единственное async на кадровом пути — `RunSession.advance()` (`flutter3d_game/lib/src/run/run_session.dart:278`), вызывается `unawaited` каждый кадр (`apps/flutter3d_demo_platformer/lib/main.dart:1366`, dungeon :1552, strategy :586) — Future за кадр, не блокирует.
- glTF (с Draco/meshopt) декодируется в `Isolate.run` (`engine/assets/model_isolate_io.dart:34`), но web-ветка (`model_isolate.dart:8` → `model_isolate_web.dart:10`, `model_loader.dart:30, :60`, `background_web.dart:4`) выполняет всё на UI-потоке; Web Worker есть только для wasm-физики (`physics_native/lib/src/core/module_web.dart:31`). На native KTX2 уходит в фон только если Basis (`texture_upload.dart:309-313`, `ktx2_loader.dart:805`); zstd/универсальные блоки парсятся на UI-изоляте; HDR-панорамы синхронно (`environment_map.dart:302-303`).
- Пайплайны строятся лениво на первом draw (`renderer_resources.dart:71` ← `renderer_mesh_encode.dart:371`; `??= createPipeline` в `renderer_sky_pass.dart:107`, `splat_contributor.dart:694-803`, `renderer.dart:3715`). `warmUp` (:4381) и `warmUpInSlices` (:4425-4459, ломтики 8 мс через `Future.delayed`) **не вызываются ни одним приложением и ни одним game-kit** — только тесты. WebGPU на draw-пути использует синхронный `createRenderPipeline` (`webgpu_encoder.dart:762`), `createRenderPipelineAsync` только в `_warm` (:1283/1308), который никто не зовёт; WebGL — синхронные compile/link без `KHR_parallel_shader_compile` (`webgl_shaders.dart:153/329`).
Следствие: на web загрузка большой модели замораживает UI; первый кадр с новым материалом — стойл компиляции на всех бэкендах, хотя инструмент прогрева написан.

### 8. Шейдеры: взрыва вариантов нет, но 8.5 МБ в каждом бинарнике и 5 МБ в JS
- Бандл `packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle` — **8 457 КБ**, 105 стадий (86 frag, 19 vert по `flutter3d_shaders/shaders/flutter3d.shaderbundle.json`), в gitignore (`.gitignore:56`), но ассет pubspec'а (`flutter3d_impeller/pubspec.yaml`, комментарий про 0.4.0) — чекаут не работает без `tool/build_shaders.sh`, бандл привязан к версии Flutter.
- Пермутации — не комбинаторика: всего 8 define'ов (`F3D_MEDIUMP` 12, `F3D_NO_SURFACE_BUFFER` 10, `F3D_NO_FOG` 8, `F3D_OPAQUE` 6, `F3D_SOFT_PARTICLE` 3, `F3D_LAYERED` 2, по одному `F3D_NO_POINT_SHADOW`, `F3D_NO_LIGHT_LIST`); 6 моделей освещения × opaque = 12 стадий, skinned/instanced/lightmapped — отдельные вершинные стадии, masked/hashed — uniform'ами, mediump — compile-time константа стадии (`shaders/PRECISION.md`), не выбор по устройству.
- Web: `flutter3d_webgl/lib/engine_shaders.dart` — 2 728 628 байт GLSL-строк, `flutter3d_webgpu/lib/engine_shaders.dart` — 2 478 703 байт WGSL, оба как `final Map<String,String>` → целиком в `main.dart.js`.
Следствие: +8.5 МБ к каждому APK/IPA и +2.5-2.7 МБ (до gzip) к web-бандлу, даже если игра использует десять стадий из 105.

### 9. Сборка и хуки: wgpu-native закреплён и проверен, но оффлайн-сборка молча другая
- `physics_native/hook/wgpu_native.dart:18-46`: `v29.0.1.1`, sha256 на 13 целей (android ×4, ios ×3, linux ×2, macos ×2, windows ×2); при отсутствии сети/несовпадении хеша — `say(...)` и сборка **без GPU-проходов** (:9-10, :128-131), т.е. оффлайн-билд работает, но физика идёт по другому пути без ошибки сборки. CMake/podspec нет — всё через `hook/build.dart` (`CBuilder`, `-ffp-contract=off -fno-fast-math`, `/fp:precise`, SSE2 на ia32); wasm собирается отдельно `tool/build_wasm.dart`, два `.wasm` по ~390 КБ лежат в репо как ассеты.
- Решение G выполнено наполовину: `flutter3d_game_kit` больше не зависит от physics_native (pubspec), но `flutter3d_effects:46`, `flutter3d_elements:41`, `flutter3d_game_physics:77` зависят → все 11 демо с водой/огнём компилируют C и качают wgpu-native. `flutter3d_build_hooks` зависит только от core/hardware/foundation/shaders — mcp в игры больше не тянется.
- Другие хуки: `flutter3d_effects/hook/build.dart` + `material_bundles.dart`, `flutter3d_impeller/hook/build.dart`. Внешние FBX2glTF/Blender — только подсказки пользователю (`flutter3d_build/lib/src/convert/external.dart:70, :86`), не скачиваются.
Следствие: первая сборка любой игры с эффектами требует сети и C-тулчейна; без сети поведение физики на GPU тихо отличается.

### 10. Наблюдаемость: всегда включена, экспорта трассы нет
- `FrameResult` (`engine/render/frame_result.dart:109`): cpuMicros, submitMicros, drawCalls, triangles, instances, culled, pipelineSwitches, lights, lightsDropped, shadowCasters, skinnedDraws, batchedDraws, targetBytes, exposure, passes, skipped, `pipelineStalls` (:146), `held` (:154), `ev100` — getter (:159). `toHeld()` (:163) теряет `pipelineStalls`.
- Сбор не отключается: за кадр `<FramePass>[]` (`renderer.dart:5124`), `Stopwatch()` на узел (:5153), `Timeline.startSync` на узел (:5160, константные имена), списки `skipped`/`declinedSkips` + `List.unmodifiable` (:5383-5392), два `passTimings.any` (:5346, :5352). Журнал draw'ов — за флагом (:5135). GPU-тайминги только WebGPU (`webgpu_timer.dart`); Impeller/WebGL/CPU — заглушки (`gpu_device.dart:80`, `webgl_device.dart:59` с TODO).
- Экспорт Chrome trace/Perfetto: 0 совпадений; `MemoryReport` есть (`memory_report.dart:97`, `Renderer.memoryReport` :1333, экспорт `flutter3d.dart:252`), строится по требованию.
Следствие: цена телеметрии — десятки аллокаций за кадр без возможности выключить; профилирование ограничено DevTools-таймлайном.

### 11. Платформенная матрица — в основном чисто
- `platforms:` не объявлен ни в одном pubspec (pub выводит сам) — [уточнение другого аудита: объявлен во всех публикуемых]. `dart:html` — 0; `package:web`/`dart:js_interop` — webgl 13/8, webgpu 15, physics_native 4 → dart2wasm-совместимо. Условных импортов 22, все через `dart.library.js_interop`. `dart:io` в `flutter3d_shaders/lib` только за отдельной точкой входа `compile.dart` (`wgsl_compiler.dart:43`, `source_package.dart:19`), рантайм-пакеты её не импортируют; `flutter3d_impeller/lib/src/gpu_loaded_shaders.dart:13` импортирует `Platform` без условия (Impeller и так не web).
- `pointer_lock`: macOS/Windows/Linux + чистый Dart на web, без iOS/Android (по смыслу); `pad_input`: android/ios/macos/windows/linux/web. Мусор: `packages/pointer_lock/mouse_capture.iml`, каталоги `build/` в pointer_lock, pad_input, physics_native (не отслеживаются git, но лежат в дереве).
Следствие: мелочи; реальный риск — только п. 9.

### 12. Доступность/локализация
- `flutter3d_game_ui` лучше, чем говорит `tasks/1.0-arch-review.md:195`: `game_localizations.dart` с `en`/`ru` (:59-60), режимы цветового зрения Protan/Deutan/Tritan (`flutter3d_core/lib/src/formats/color_vision.dart:8`), 50 ссылок на `highContrast`, 11 `Semantics`, 0 `Text('Английская строка')`. Но 0 ссылок на `textScaler`/`disableAnimations`/`reduceMotion`; 35 `Color(0x…)` + 30 `Colors.*` в game_ui.
- Приложения: 152 `Text('English…')` и 476 фиксированных цветов в `apps/*/lib`.
Следствие: пакет UI можно локализовать и подстроить под дальтонизм, демо — нет; масштаб системного шрифта игнорируется.

## НИЗКАЯ / СПРАВОЧНО

### 13. Костыли из `tasks/0.9-no-crutches.md` (секция Games)
Остались: платформер — таблица хазардов по именам уровней/бассейнов (`apps/flutter3d_demo_platformer/lib/src/dressing.dart:69-190`, `run_elements.dart:230-233, :494`); River — дно у водосливов выравнивается, т.к. плоскость игры ровная (`river_water.dart:23-30, :349-355`), сетки по 60 м на каждый плёс вместо одной скроллящей (:14-21, :199, :273); Strategy — русло захардкожено (`map_world.dart:47-72`), не врезано в землю (`packages/flutter3d_demo_content/lib/map_world.dart:645-655`), головни кидают кубики и `setTemperature(body, dry.flameTemperature)` (:1363-1402), попадание — по близости `range + 3.0` (:1256-1286), капы `_mostFires = 4`, `_mostBrands = 6`; Hollow — бомбы наводятся своей баллистикой и `setTemperature(body, 1300.0)` (`props.dart:826`), на крыше их обнуляют и пришпиливают призматическим шарниром (:763-794); Racing — порог крушения `_wrecking = 14.0` (`elements.dart:580-584`) и тушение по таймеру `_burnsFor = 25.0`/`_douse` (:905-921); Dungeon — тепло на игроке считается в игре `CryptHarm.flux` (`crypt.dart:1094-1140`), доля `_splits = 0.35` (:515); Arcade — метеоры `setTemperature(body, 1400.0)` (`meteors.dart:324`); Reef — массы находок заданы вручную (`finds.dart:67-130`).
Убраны: колёса как кинематические цилиндры, несколько пожаров, водослив вместо контроллера, Manning n, дерево без подпорок, факелы-горелки, один FireView, тушения в dungeon, машина в Hollow, крыша одним телом, течение рифа с открытых краёв, лодка силой, доски в sandbox через `Igniter`. В девяти приложениях 0 `TODO/HACK/workaround`.
Следствие: шесть из девяти игр всё ещё показывают числа, которых нет в ядре — для пользователя, читающего демо как образец, это ложный пример API.

## Что бы я закрыл до rc.1
(1) проверка `part->hull` и индексов треугольников в `f3d_snapshot.c` + выделение после валидации; (2) корневая «клетка» для путей MCP-инструментов и валидация `device`; (3) дренаж `_pending`/`uncapturederror` на WebGPU; (4) scratch-буфер на uniform-блок и кэш скомпилированного графа кадра; (5) вызов `warmUpInSlices` из game-kit/`Flutter3dView`; (6) один тест рендера+физики на 5 км от origin с документированным пределом.
