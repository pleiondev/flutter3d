# flutter3d 1.0.0-rc.1: взгляд из студии (2026-10-09)

Заметки агента в голосе персонажа: senior engine/gameplay programmer, 15 лет на Unreal, Unity, своём движке, немного Godot и Bevy. Читал: ARCHITECTURE.md (§2–§16), docs/CONTRACTS.md, site/content/core/backends.md, reference/material-language.md, comparison.md, plugins.md, SUPPORT.md, снапшоты `api/*.api` core/hardware/plugin_api/sim/physics/physics_native/game/net, `packages/flutter3d_core/lib/src/engine/render/renderer.dart`, `packages/flutter3d_sim/lib/src/loop/engine_loop.dart`, `packages/flutter3d_physics_native/csrc/include/f3d_physics.h`, `packages/flutter3d_net/lib/src/rollback_session.dart`, и оба документа в `tasks/` (`1.0-readiness-review.md` от 2026-10-09 и `1.0-rc1-plan.md`). Пометки: [есть] — в дереве, [обещано] — в плане rc.1 / решениях §6, [нет] — ни там, ни там.

## 1. Что впечатляет (и что я бы украл)

1. **Структурные сканы вместо договорённостей** [есть]. `tool/structure.dart`, 70 правил, первый шаг CI: «симуляция не видит Flutter», «движок не называет бэкенд», «шаг не трогает часы и libm», «API — это снапшот». За 15 лет я видел три движка, где слои держались на code review и разваливались за год. Здесь слои держит детектор, который сам проверяет, что сработает, прежде чем сканировать. Это я унёс бы к себе в понедельник.

2. **Детерминизм как измеренный факт, а не лозунг** [есть]. §9.3: 12 функций `dart:math` × 20 000 аргументов × 3 среды, таблица «только `sqrt` портабелен», и выведенный из неё `Portable` (минимакс-полиномы на `+ - * / sqrt`). Паритет-тест машины ↔ браузер ↔ ubuntu: контроллер персонажа 40/40, машина — 17/40 до `Portable`, 40/40 после. Плюс double-step check в `EngineLoop(determinismCheck:)`, который называет *какую* систему прорвало. У нас в шутере на поиск такого уходили недели.

3. **Один снапшот на сейв, реплей, роллбэк и тест** [есть]. `EngineLoop.snapshots` — единственный путь состояния; `Demo` = level + snapshot + `InputTape` интентов; `SimulationVersion` в хендшейке `WireHello` и в тейпе с честным отказом. Это правильная форма, мы к ней пришли через боль.

4. **CPU-растеризатор как второе независимое мнение** [есть]. `flutter3d_cpu` даёт 96 golden-сцен без GPU в CI и ловит то, что GPU-бэкенды «согласовали случайно» (sampler default, `setDepthWrite`). И `.f3dtrace` — запись вызовов HAL с реплеем на другом устройстве — это почти RenderDoc для своего контракта.

5. **Честный HAL с conformance-сьютом** [есть]. `GraphicsDevice` как `abstract base` с телами-отказами, `DeviceFeature`, «decline ≠ pass» в отчёте, таблица «что стоит неправильный ответ». Мне нравится, что `readback` обязан отдать «предыдущий кадр» и не ждать GPU — это редко пишут явно.

6. **Фотометрические единицы и контракт единиц одним документом** [есть]. CONTRACTS.md: lux/candela/nits, EV100, `LinearColor`, `WorldPosition` в double. Filament-уровень дисциплины.

7. **Сортировка по packed keys с честным описанием бюджета** [есть]. §4.2: 43 бита, глубина opaque насыщается за 256 м, material id заворачивается на 32 767. Автор сам написал, что таблица врала «в десять раз» — это тон, которому я верю.

8. **Shadow-атлас с инкрементальной перерисовкой каскадов и статическим слоем через `ShadowCopy`** [есть] — приятная инженерия, 68 → 12 кастеров на кадр.

## 2. Возражения

### Производительность: потолки

9. **Dart GC и аллокации в горячем пути** [есть, починка обещана]. Ревью §2.7.1 признаёт: новая `ByteData` на каждый bind uniform-блока (6–10 блоков на меш на view, с тенями), 4 КБ на скинированный draw, фрейм-граф **пересобирается и перекомпилируется каждый кадр** (`renderer.dart:4863–4931`, ~100 контейнеров; я это видел своими глазами в `_compileFrameGraph` и в `List<FramePass>` + `Stopwatch` на каждый узел в `:5124–5206`), телеметрия без выключателя, `query.entities` аллоцирует `Set<Type>` на запрос на шаг, avoidance O(A²) с замыканием. D13 обещает scratch-буферы, кеш графа и `RenderSettings.telemetry: off` — в волне 4. До этого цифр на телефоне нет: §14 прямо говорит «no phone report is committed yet». Pacing-отчёт — M3 Pro, 1280×720, медиана 8.26 мс для шутера. Для A55 это ничего не значит.

10. **Нет SIMD, float32 `vector_math`, одиночный поток** [есть]. §14 честно: «realistic gain from C is 2–4×, no FFI in this project». Я согласен с аргументом про радикс-сорт, но 2–4× на культе 50k объектов — это разница между 60 и 20 fps на телефоне. Шаг симуляции на UI-изоляте; `IsolateSimulation` [есть], но `SimulationPlacement.isolate` как настройка [обещано D40], и на вебе «шаг остаётся на потоке». Многопоточен только C-физический core (`f3d_world_set_threads`, до 64) [есть] — и только он.

11. **Нет compute на Impeller и WebGL2** [есть как ограничение]. §2/§15: GPU-частицы, GPU-скиннинг, GPU-culling, indirect — всё на CPU, пока `flutter_gpu` не даст compute pipeline. Это не вина движка, но это потолок, который студия не обойдёт. `FieldPass` (пинг-понг full-screen) — костыль правильной формы, но не замена.

12. **Draw-call бюджет и uniform-аплоады** [нет числа]. Ни в ARCHITECTURE, ни в SUPPORT нет «столько draw'ов за столько мс на таком устройстве». Из §2.7 видно, что uniform-блок = аллокация + копия на каждый draw в каждом проходе. На Mali/Adreno это утыкается в CPU задолго до GPU. Бенчмарк аллокаций в CI [обещано, 4Z] — на CPU-бэкенде, то есть не про Impeller.

13. **Память на Impeller** [есть, плохо]. `dispose`, `releaseTexture`, `releaseGeometry` пусты (§2.7.3, `gpu_device.dart:911–923`) — у `flutter_gpu` нет release. D11/D13: «на Impeller память возвращается через сборщик», плюс issue upstream. Для мобильного тайтла с уровнями по 300 МБ текстур это блокер: я не могу обещать стабильную резидентность, если жизнь текстуры решает GC. Кеши без вытеснения (`_meshCache`, staging readback-текстуры по размеру) — тоже.

### HAL над flutter_gpu: чего нельзя

14. **Bindless, mesh shaders, async compute, явная синхронизация, texture streaming, свои форматы** [нет]. HAL — это WebGL2-уровень с опциями WebGPU: «sampler budget is WebGL2's» (§4.11: 16 сэмплеров, `PbrLayered` съедает все 16, запаса ноль), один render pass на command buffer (§2), `submit` асинхронный без fence'а наружу, readback через `asImage().toByteData()` со staging-текстурой на каждый запрос (§15). `TransferEncoder`, `QuerySet`, `RenderBundle`, indirect — в API [есть], но Impeller их не реализует. Если план студии — что-то выше «мобильный forward с пост-стеком», HAL не даст сделать это ни через Impeller, ни через WebGL2.

15. **Render graph: anchors + setup** [есть анкоры, setup обещан D38]. 50 анкоров, `RenderNode`, `keeps`/`provide`, `FrameResources` по версии — рабочая схема. Чего я хочу и не вижу: явных lifetime'ов транзиентных ресурсов до кадра (D38 обещает `setup(FrameGraphBuilder)` и алиасинг), асинхронного readback как ресурса графа (сейчас `device.readback` из узла, отдельно), multi-queue [нет, и flutter_gpu не даст], per-view ресурсов для стерео (§2.9.10: `FrameContext.view` — только первый view; D20 обещает). `aliasTargets` [есть] выключен по умолчанию и даёт 11 → 10 таргетов — то есть он почти не работает.

### Материалы

16. **Один язык на четыре бэкенда — что теряется** [есть]. `.f3dmat`: нет циклов, нет своих блоков, только 5 слотов текстур движка, нельзя сэмплировать то, что движок не привязал. Таблица в material-language.md говорит прямо: Impeller — только build (нет `impellerc` в рантайме), WebGPU runtime — без `light`/`vertex`/`sceneDepth`, compute — только CPU. То есть «один язык» де-факто означает «наименьшее общее подмножество WebGL2 ES 3.00». Node graph [нет, и роадмап говорит «не делаем»]. D21 обещает extra uniform-блоки и текстуры для плагинных lit-моделей, D24 — открытый AST с visitor. Пока `MaterialExpression` `sealed` — внешний транслятор ломается на новом узле.

17. **Шейдерный бандл 8.5 МБ в каждом APK/IPA, 2.7 МБ GLSL + 2.5 МБ WGSL строками в `main.dart.js`** [есть]; бандл привязан к версии SDK и пересобирается при каждом апдейте Flutter (§2). D15/D19 обещают выборку стейджей по проекту. Для мобильного тайтла с бюджетом на размер это пункт в план, не мелочь.

### ECS и published state

18. **Двойная бухгалтерия** [есть]. `EcsWorld` — `Map<Entity, Object?>` на компонент (боксинг, не SoA), `publishedComponents()` строит `Map<String, Map<Entity, Object?>>` каждый шаг, `save()` — `Map<String, Object?>` (JSON-подобный). Сцена — отдельный граф, `ActorVisuals` руками переносит строки в ноды; D37 `SceneBinding` обещает декларативный мост. Интерполяция — `InterpolatedVector3` по месту, не системная. На 10k сущностей с published state каждый шаг я вижу: 10k боксов × N компонентов × 60 Гц через `Map`. §9.5 говорит, что сериализуемость — цель ECS, не скорость; это честно, но это не ECS для большого мира. Большие миры: `WorldPosition` в double [есть], но ноды/тела float32, и ни одна игра не сдвигает origin; D1 обещает автосдвиг в `Flutter3dView` — после того, как волна 1 починит `EngineLoop.restore`, который сейчас origin не восстанавливает (§2.1.3).

### Детерминизм vs float32 C-core

19. [есть, с дырой]. Dart-симуляция детерминистична через `Portable`. C-core — `f3d_real = float` по умолчанию (`F3D_REAL_DOUBLE` — флаг сборки), и §2.7.2: «their digests are not compared, tolerances in tests reach 0.15 m». Записи говорят, на каком бэкенде шли, и реплей отказывает другому — это правильно. Но `Quaternion.axisAngle` в `native_ragdoll.dart:314` и `Matrix3.rotationY` в `prefab.dart:413` ходят в libm (§2.1.2) — «правило не ловит». D3 вводит `SimulationProfile.deterministic | accurate`, что честно разводит игру и лабораторию. Для кроссплатформенного роллбэка (Android ↔ web ↔ iOS) на C-core вопрос «одинаковы ли биты `float` между clang на ARM64, MSVC и Wasm» в документах не задан. Я бы его задал первым.

### Роллбэк: шутер, 60 Гц, 32 игрока

20. [есть, не в этом масштабе]. `RollbackSession`: 2..32, `inputDelay` 2, `maxRollbackFrames` 8, `redundancy` 8, и `_Ran<S>` хранит *полный* `S` (snapshot) до каждого шага. Save = `EngineLoop.capture()` → `Map`; restore + ресимуляция до 8 шагов на одном потоке. Крипта — 1.6 КБ JSON-снапшота; шутер на 32 с ракетами и рэгдоллами в C-core (бинарный `f3d_snapshot`, тоже restore per rollback) — другой порядок. Тесты и гонка идут на 4 машинах (comparison.md). Ни одного измерения «ресимуляция 8 шагов × 32 слота на A55» нет. Плюс §2.1.1: `FiredBy` не в снапшоте — после роллбэка ракета бьёт стрелка. Я бы не называл это «rollback in the box» до soak-теста на телефонах.

### Физика

21. [есть, двухмесячное]. C-core (comparison.md: начат 2026-10-04): вращение, 5 типов joint'ов (`F3D_JOINT_FIXED/SPHERICAL/REVOLUTE/PRISMATIC/DISTANCE`), hull и mesh, speculative CCD по умолчанию (`f3d_world_set_speculative`) + `f3d_body_set_bullet`, substeps «как Box2D v3», sleep, threads. Это нормальный скелет. Чего нет: soft body [нет, 1.x], ragdoll — `RagdollBall/Bend/Hinge` поверх тех же joint'ов, зрелость — «the games pass their suites on it; it tells you much less about yours». Dart-референс: тела **без вращения** (§10), triangle mesh — нет. Снапшот C-core не валидирует индексы (§2.2.2: OOB, `sec_wind` до 16 ГБ) — волна 1C. Жёстко: ни один внешний проект на нём не бегал.

### Asset pipeline

22. [есть частично]. glTF/OBJ/STL/`.f3d`, FBX отказан с объяснением [нет]. KTX2 BC/ETC2/ASTC да, UASTC/zstd/arrays/cube — нет. LOD с измеренной Hausdorff-ошибкой, импосторы, кластеры, файлы по классу устройства — хорошо. Но: **streaming нет, приоритетов и отмены загрузки нет** (§15 «only needed for open worlds, and there is no such scenario here»), бюджетов памяти нет, на вебе декодеры на UI-потоке (§2.7.4). Для гоночного open-world это закрытая дверь; для мобильной стратегии с уровнями — терпимо.

### Инструменты

23. Редактор [есть, не раздаётся], MCP-серверы [есть]. Профайлер: CPU-время по проходам; `gpuMicros` только на WebGPU (§15), на Impeller и телефоне — encode-time. RenderDoc-пути нет, зато `.f3dtrace` и `FrameCapture` (полный RGBA каждого прохода, в памяти). Crash reporting, cvars, levelled logging — [нет] по §15. Для студии профайлер без GPU-времён на целевой платформе — это слепота на самом важном.

### Платформенный риск

24. [есть]. Impeller на Linux не рисует (`gl_VertexID`), Windows «built, not played», iOS — только симулятор, Android — один A55 с платформером, эмулятор — белый экран. `FLTEnableFlutterGPU` молча отключает всё (§1). `flutter_gpu` менял `setDepthWrite` в 3.47 — ARCHITECTURE признаёт, что CPU-бэкенд копировал баг ради сравнимости. Безопасность: path traversal в `convert`, MCP без корня, relay без auth (§2.2) — волна 1. Web: wasm-сборка демо выключена, потому что WebGL-бэкенд падает на первом кадре (§2.8).

### Масштаб и один человек

25. Первый коммит 2026-08-08; 57 пакетов, 17 приложений, 13 267 тестов, 70 правил. На момент ревью: 12 из 19 быстрых сьютов красные (136 падений), 158 непушенных коммитов, ~3 400 незакоммиченных файлов, `flutter3d_foundation` не в git, force-push истории ожидает. **54 решения за один день** (§6, с утра до ночи 2026-10-09), и план rc.1 с ~25 позициями размера L («неделя агенту») плюс волна 4.5 с viewer kit, point clouds, XR, SSS/hair/cloth, терраном и травой. Это не план rc.1, это план 1.3. Сам план говорит: «sizes are for ordering, not for promising».

### Риск расширений

26. Wasm render ABI (D29) [обещано] — интерпретатор i32-only с Q16.16; рендер-нода через `Recorded` поверх HAL из интерпретируемого Wasm — на телефоне это будет медленнее, чем Dart-нода, и никто не знает насколько. Plugin API: `PassEncoder` — 38 абстрактных членов (§2.10.2) против обещания «новый член приходит с телом» (D25 чинит). Ширина API растёт быстрее стабильности: 2 884 деклараций в 57 снапшотах, 53 `sealed`/`enum` только в core.

## 3. Расширяемость: что бы я написал сам

27. **Свой бэкенд (Vulkan/Metal через FFI)** [возможно сегодня до зелёного `runDeviceConformance`, §2.10]. Блокеры: нет `.f3dmat` для пятого бэкенда (`RuntimeShaders` и build hook зашиты на четыре), `compileStage` отдаёт только WGSL, `stageBindings` в `internal.dart` вне semver, гайд backends.md — 0.8 (`supportsX`, `abstract interface`). D25–D28 разблокируют: `MaterialCompilerRegistry`, SPIR-V из `compileStage`, `examples/flutter3d_backend_null`. Но FFI «breaks the web» — это их же аргумент против FFI, и FFI-бэкенд под Flutter означает свой презентер через platform view, с потерей композитинга виджетов. Реалистично: Metal через FFI — месяц, и я получу compute и async readback, но потеряю `Texture.asImage()`. Вряд ли стоит.

28. **Своя lighting-модель** [есть через `.f3dmat light{}` + `LightingModels`]. Hair/cloth/SSS сегодня — нет (§2.9.2: нельзя добавить блоки и текстуры сверх 5 слотов, нельзя G-buffer канал, нельзя shadow lookup). D21/D49 обещают, и 5C пишет три модели именно как доказательство слотов. На Impeller — только через build hook (D19).

29. **Свой проход (screen-space hair, planar area lights)** [full-screen — есть на любом анкоре; с velocity — только при TAA, §2.9.5; D20 чинит]. Area lights: `LightType.custom` рисуется «как base», light loop закрыт (§2.9.3), D22 обещает хук с falloff и packing. Hair: без MRT-канала в сценовом проходе (закрыт, 3 аттачмента) и без своего sort key (`RenderList` закрыт, D22b). Сегодня — нет; после 2.2 — да, если 2X реально закроет 15 пунктов одним агентом.

30. **Геймплейный плагин** [есть, и это лучшая часть]: `Flutter3dPlugin`, `addSystem` с `after`/`before`, события с кодеками, `SnapshotPart`, conformance-бейдж. Единственное — два API систем (`StepSystems` vs `addSystem`), D36 убирает одно.

31. **Over-engineered для 1.0**: pipeline document `f3d.pipeline` (D44) — кому нужен JSON графа, когда плагины и так ставят ноды по анкорам; expression language в foundation (D33) — второй язык в движке, который только что убрал `ScriptRuntime`; Wasm render ABI (D29); viewer kit (D52), point clouds (D48), WebXR (D54), LTI/xAPI, ~200 материалов с источниками и `PropertyLaw.at(T, p)` (D4–D6) — это лаборатория, а не движок для игр. Каждый пункт сам по себе разумен; вместе они съедают rc.1.

32. **Чего не хватает в первую очередь**: профайлер с GPU-временами на Impeller (хотя бы через `Timeline` Impeller'а), бюджет памяти и резидентность текстур, стриминг с приоритетами и отменой, asset cooking с cache-ключами по платформе (`.f3d` по классу — половина), crash reporting и структурированные логи, число размера сборки в quickstart (D15 обещает «size written into the quickstart»).

## 4. Предложения

**Десять дел до 1.0, по приоритету**

33. Волна 1 целиком, и только она: 5 silent-wrong, 3 security, 136 красных тестов, зелёные golden'ы. Без этого тег — обман.
34. D13 (горячий путь) поднять из волны 4 в волну 2: uniform scratch-буферы, кеш фрейм-графа, `telemetry: off`. Это единственное, что меняет цифру на телефоне.
35. Pacing-отчёт на A55 и на iPhone, закоммиченный в `doc/pacing/`, по трём демо. Ни одной публичной цифры с телефона сейчас нет.
36. Память на Impeller: либо upstream `gpu.Texture.dispose` до 1.0, либо `SUPPORT.md` большими буквами «резидентность не контролируется», и тест на утечку через `FakeBackend` (D11).
37. Паритет C-core между clang/ARM64, MSVC и Wasm: таблица как в §9.3, но для `f3d_world_step`. Пока её нет, «rollback 2–32» — обещание.
38. `SimulationPlacement.isolate` (D40) до 1.0, потому что шаг на UI-изоляте с GC — главный источник джанка.
39. Ограничить API-волну 2 до A1–A6 + D8 (`sealed`/enum allowlist) + D25 (тела на энкодерах). Остальное — 1.1 с `dart fix`.
40. D15/D19 (выборка шейдерных стейджей по проекту + компиляция плагинных `.f3dmat` в бандл): это и размер, и единственный путь плагинного рендера на Impeller.
41. Nightly на реальном Mac с Impeller (D16) + один Android-девайс в том же ночном прогоне с pacing-порогом.
42. Streaming-интерфейс минимальный: приоритет и отмена в `ResourceCache`, даже без страниц — иначе все open-world проекты отпадают на этапе RFP.

**Пять вещей вырезать или отложить**

43. Волна 4.5 целиком (viewer kit, point clouds, SSS/hair/cloth, терран, WebXR, LTI) — в 1.1–1.3. Причина: ни одно из этого не делает движок надёжнее, каждое увеличивает API, которое с 1.0 замораживается.
44. D29 Wasm render ABI: интерпретируемый i32-Wasm, записывающий команды энкодера, — исследовательская тема, не контракт 1.0.
45. D33 expression language + D4 `PropertyLaw` + ~200 материалов: оставить `.f3dmat` как есть, каталог 33 материалов, законы — 1.x. Два исследовательских агента на данные до 1.0 — это не инженерия движка.
46. D44 `f3d.pipeline` и D32 полный editor plugin contract: редактор ещё не раздаётся как бинарник; стабилизировать контракт редактора до того, как им кто-то пользовался, — значит заморозить ошибки.
47. D54 WebXR на WebGL2/WebGPU: без нативного XR это демо-страница.

## 5. Вердикт для студии

48. **Мобильный + веб тайтл среднего размера** — пока нет. Причины в порядке веса: нет ни одной цифры с телефона (п. 9, 12); память на Impeller через GC (п. 13); нет streaming и memory budget (п. 22); C-core двух месяцев без внешних пользователей (п. 21); план rc.1 размером в год (п. 25). Жанр, где я бы рискнул первым: **стратегия/головоломка с уровнями**, статичные сцены, без open-world, без 32-роллбэка — там сильные стороны (детерминизм, реплеи, тейпы в тестах, Flame-мост) работают на нас, а потолки не мешают.

49. **Шутер 60 Гц × 32 с роллбэком** — нет, и не из-за сети, а из-за одного потока, `Map`-снапшотов и неизмеренной ресимуляции (п. 20). Гонка open-world — нет (п. 22).

50. **Tooling / digital twin** — да, с оговорками, и это, по-моему, где движок сильнее всего: CPU-бэкенд даёт детерминированные рендер-тесты в CI, `.f3d` + MCP + headless `LevelScene` — хорошая основа для сервиса, `WorldPosition` в double и `SimulationProfile.accurate` [обещано] — то, что нужно твину. Веб-сборка 2.5–2.9 МБ JS приемлема. Что должно быть до старта: D1 автосдвиг origin, D40 изолят, USD-импорт (D30) — но без MaterialX-глубины.

51. **Доказательства, которые я бы запросил** перед подписанием:
    - pacing-отчёт по трём демо на Galaxy A55 и iPhone среднего класса: медиана, p99, кадры >50 мс, резидентная память за 30 минут;
    - soak-тест 2 часа на телефоне с `IsolateSimulation` и без, график RSS;
    - паритет-таблица C-core (ARM64 clang / x64 MSVC / Wasm) на `racing` и `shooter` тейпах, 1000 шагов;
    - роллбэк 8 машин на телефонах по реальному Wi-Fi, `droppedCorrections` и время ресимуляции на шаг;
    - размер APK/IPA/web после D15 для `packages/flutter3d_app/example`;
    - один сторонний проект на C-core (не из репозитория), доживший до релиза;
    - зелёный `tool/ci.sh` на тэге, nightly Impeller, и `git status` без 3 400 файлов.

52. Общая оценка. Это самый дисциплинированный однопользовательский движок, который я читал: он *знает* свои ограничения и записывает их туда, где их найдут. Проблема не в архитектуре, а в расстоянии между «что написано» и «что измерено на целевом железе», и в объёме обещаний rc.1. Если автор сделает пп. 33–42 и вырежет 43–47, я вернусь к разговору через два минора — и, скорее всего, начну с twin-направления.

---

Ключевые файлы, на которые опирается текст: `ARCHITECTURE.md` (§2, §4.2, §4.11, §7, §9.3, §10, §12, §14, §15), `tasks/1.0-readiness-review.md` (§2.1, §2.2, §2.7, §2.9, §2.10, §6), `tasks/1.0-rc1-plan.md`, `site/content/reference/material-language.md`, `site/content/core/backends.md`, `packages/flutter3d_core/lib/src/engine/render/renderer.dart:4510–4660, 4863–4931, 5124–5206`, `packages/flutter3d_net/lib/src/rollback_session.dart:1–120`, `packages/flutter3d_physics_native/csrc/include/f3d_physics.h` (joint types :111–126, `f3d_real` :51–54, threads :495–510, CCD :542–545, :1808–1814), `packages/flutter3d_sim/api/flutter3d_sim.api:645–672` (`EcsWorld`).
