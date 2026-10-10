# flutter3d глазами Flutter-разработчика без 3D (2026-10-09)

Заметки агента в голосе персонажа. Контекст: два года на Flutter (виджеты, Riverpod/Bloc, go_router), 3D не трогал. Хочу: GLB-модель товара с орбитой и тапом по детали; маленькую казуальную игру на телефон; может быть, маятник для класса. Читал: `site/content/quickstart.md`, `site/content/index.md`, `site/content/reference/packages.md`, `site/content/core/*.md`, три README (`packages/flutter3d`, `flutter3d_app`, `flutter3d_game`), примеры в `packages/*/example`, снимки API `packages/flutter3d_app/api/flutter3d_app.api` и `packages/flutter3d/api/flutter3d.api`, `apps/flutter3d_demo_platformer/lib/main.dart`, и планы `tasks/1.0-readiness-review.md` §3/§6 и `tasks/1.0-rc1-plan.md`. Пометки: [есть] — вижу в дереве сейчас, [обещано] — записано в плане rc.1, [нет] — ни там, ни там.

## 1. Первый час

1. Открыл `site/content/index.md`. Заголовок — «пять игр, один движок», ниже «One frame, as this engine encodes it: shadow / opaque / transparent / bloom / composite» и mermaid с пятнадцатью пакетами. Я ещё не знаю, что такое pass, а мне уже объясняют, почему у Metal один encoder на command buffer. Понял, что это сайт для тех, кто пишет движок, а не для того, кто хочет показать кружку. [есть]

2. `quickstart.md` начинается с «Resolve the workspace»: клонировать репозиторий, `flutter pub get` на 57 пакетов, `build_shaders.sh`. Только в середине, в разделе «Your own application», выясняется, что для пользователя pub.dev ничего этого не нужно: две зависимости, `flutter3d: ^1.0.0-rc.1` и `flutter3d_app: ^1.0.0-rc.1`, и bundle едет внутри `flutter3d_impeller`. Первые 95 строк quickstart — про чужой checkout. [есть]

3. Счёт пакетов не сходится: `index.md` — «Forty-five packages», `packages.md` — «Fifty-five», `quickstart.md` — «fifty-seven packages and seventeen applications», `packages/flutter3d/README.md` — «one of thirty-eight» и «Three graphics backends» там, где везде четыре. Для новичка это сигнал «документация отстаёт от кода», и я начинаю не доверять остальному. В плане 5.4 обещаны «rule-held counts» [обещано].

4. Минимальный код из quickstart — 20 строк (`packages/flutter3d_app/example/lib/first_scene.dart`): `Flutter3dView(onCreated: (engine) => engine.scene.add(MeshNode(DeviceMesh.upload(engine.device, CuboidShape().build()), RenderMaterial(baseColor: LinearColor.fromSrgb(0.9, 0.5, 0.2, 1.0)))))`. Это нормально. Но в одной строке четыре слова, которых я не знаю: `DeviceMesh.upload` (зачем «upload», куда?), `.build()` на фигуре, `RenderMaterial` (а есть ещё `Material3D`, `SurfaceMaterial`, `MaterialDocument`, `PhysicalMaterial` — пять «материалов» в одном индексе), `LinearColor.fromSrgb` (почему не `Color`? ответа рядом нет; в `packages.md` сказано только, что это «crossings into vector_math»). [есть]

5. Свет. В `widgets_main.dart`: `Light3D.point(intensity: 92650.0, range: 20.0)` с комментарием «Candela: bright, for a camera exposed for daylight». В `minimal_main.dart` рядом: `intensity: 16.0 * Photometric.legacyUnit`. В `core/scene.md`: `color: Vector3(...)`, в quickstart — `LinearColor`. Три способа написать лампочку в трёх примерах одного пакета, и один из них (`Photometric.legacyUnit`) план 2B делает приватным [обещано]. Я бы хотел `Light3D.point()` без чисел, которое просто светит.

6. Impeller. Пропустить `FLTEnableFlutterGPU` / `FLTEnableImpeller` в `Info.plist` (или `io.flutter.embedding.android.EnableFlutterGPU` в манифесте) — и приложение *молча* рисует через `flutter3d_cpu` с одной строчкой в консоли `flutter3d_app: Impeller would not start` (`first-project.md`). Для Flutter-разработчика, который привык, что `flutter create` даёт рабочий проект, это худший вид ошибки: всё работает, только в 5 fps. [есть]

7. Шейдерный bundle. Я три раза прочитал про `build_shaders.sh`, `impellerc`, «the bundle format is tied to the SDK version», и только потом понял, что с pub.dev это не моя проблема — пока не сделаю `flutter upgrade` и не окажусь на SDK новее, чем тот, под который собран `flutter3d_impeller`. Что тогда делать пользователю pub, кроме «ждать новую версию», не написано. [есть]

8. Build hook. `Model3D(source: 'assets_src/robot.glb')` в README `flutter3d_app` выглядит как обычный asset. На деле (`scene_widgets.dart:729`) это «a path under `assets_src/`, read as `loadModelAsset` reads it», а `loadModelAsset` вне debug бросает `StateError naming flutter3d_build:init` (`reference/asset-pipeline.md`). То есть нужен `dart run flutter3d_build:init`, `hook/build.dart`, `flutter3d_generated/`, и `flutter clean` после добавления зависимости. В README про это ни слова. [есть]

9. Три фасада. `flutter3d` (рендер), `flutter3d_app` (виджет, backend, storage), `flutter3d_game` («the one facade», но его пример `packages/flutter3d_game/example/lib/main.dart` импортирует ещё `flutter3d_game_ui/theme.dart`, `flutter3d_plugin_api`, `flutter3d_sim`, а pubspec — восемь пакетов). `packages.md` честно говорит «Import them by name, so the choice shows in the pubspec» — это философия, а не удобство. [есть]

10. Словарь, который пришлось гуглить по репозиторию: `publish` (фаза цикла), `step` (фиксированный шаг), `WorldPosition` (vs `Vector3`), `Portable` (математика «одинаковая везде»), `.f3d`/`.f3dmat`/`f3d.settings`/`.f3dplugin`, `BusEvent` с `EventCodec`, `Snapshot`, `PluginManifest`, `PluginTouches.simulation`, `LoopContext`, `GenrePlugin`. `reference/glossary.md` существует [есть], но из quickstart на него ссылки нет.

## 2. Что тяжелее, чем Flutter / Flame / three.js

11. Куб с освещением и орбитой: `packages/flutter3d_app/example/lib/main.dart` — 130 строк: `openDevice`, `Renderer.create`, `RenderView`, `OrbitController`, `SceneSurface(settings: () => const RenderSettings(), onBeforeFrame: ..., presentFrame: presentFrame)`, `Listener` с `onPointerMove`/`onPointerSignal`. В react-three-fiber это `<Canvas><OrbitControls/><mesh><boxGeometry/><meshStandardMaterial/></mesh></Canvas>`. Через `Flutter3dView` + `Scene3D` получается ~25 строк, но орбиты в `Scene3D` нет: `Camera3D` принимает только `position`/`target`. [есть]; `ModelViewer3D` с «orbit by gestures with limits and auto-rotate» — D47, волна 4.5 [обещано].

12. GLB из сети. В `flutter3d.api` только `BundleAssetSource` и `FileAssetSource`; `core/assets.md` их же перечисляет. Сетевого источника нет: надо самому скачать байты, положить `decodeModelBytes` (есть в экспортах), потом `ModelAsset.fromDocument(document, device: device)`, потом `asset.instantiate(scene)`. Для «показать товар с CDN» это четыре API и ручной `dispose()`. [нет сейчас]; `ModelViewer3D` «a model from the network, a file or an asset through `ModelDecoders.addSource`» [обещано, D47]. Acceptance в плане обещает «a networked GLB in `ModelViewer3D` with orbit, a hotspot and an AR button in under twenty lines» — вот это мне и нужно, но это wave 4.5, последняя перед релизом.

13. Тап по детали. У `Mesh3D` нет `onTap`. Путь: `GestureDetector` → `Scene3DController.camera/scene` → `Raycaster().setFromScreen(camera, dx, dy, width:, height:).intersectScene(scene)` → `HitResult`, причём `core/tutorial.md` предупреждает: «The `HitResult` is reused by the next call. Copy anything that has to outlive it». Я пришёл из мира, где у виджета есть `onTap`. Ближе всего `Tap3dCallbacks` из `flame_flutter3d` — но это уже Flame. [есть]; декларативный `onTap` на узле — [нет], в плане не нашёл.

14. Анимация. Императивно: `instance.player.crossFadeToNamed('idle', duration: 0.14)` и `player.update(dt)` *каждый кадр из `onFrame`* (tutorial: «Advance the player once a frame, not once a simulation step»). Декларативно: `Model3D(animation: 'Walk', playing: true, speed: 1.0)` — вот это хорошо. [есть]. Но «покрутить куб» всё равно `var spin = 0.0` глобально и `setRotationYawPitchRoll` в `onFrame` (quickstart). `AnimationController`-подобного API для свойств узла нет [нет].

15. Кнопка поверх сцены — обычный `Stack` (`flutter3d_game/example`). Это честно лучше, чем Unity. Виджет *внутри* сцены — `WidgetSurface` [есть]. Претензий нет.

16. State management. `RunSession` — «ordinary class», платформер оборачивает в cubit (`flutter_bloc` в `apps/flutter3d_demo_platformer`). Для `Scene3D` работает `setState` (пример `widgets_main.dart`). Riverpod — ничего против, ничего за. Но «живое» состояние сцены (куда повернулся узел) живёт в `SceneNode`, а не в моём стейте, и переход «стейт → узел» делаю руками через `onCreated` контроллера. `SceneBinding` (D37, «component → node kind and material, interpolation, lifetime») — это как раз мостик [обещано].

17. Hot reload. `Flutter3dView.onCreated` вызывается один раз; `didUpdateWidget` (`flutter3d_view.dart:688`) только включает/выключает тикер. Всё, что я добавил в `onCreated`, после hot reload не перестроится — надо hot restart. `Scene3D` лучше: виджеты пишут свойства в узлы на каждом билде. Плюс `HotSwap` для моделей/текстур/шейдеров [есть] — но это отдельный механизм со своим `registerScene`, а не Flutter-овский reload. Pitfall «No cursor anywhere after a hot restart» намекает, что hot restart с движком — тоже не бесплатно. [есть]

18. Дерево виджетов vs граф сцены. В `Scene3D` материал — *родитель* меша: `Material3D(children: [Mesh3D(...)])`. Интуиция Flutter говорит, что материал — свойство меша (`Mesh3D(material:)` тоже есть, но через `engine.RenderMaterial`, не виджет). Два способа, один «виджетный», другой нет. [есть]

19. Ключи. README `flutter3d_app`: «A rebuild with the same keys keeps the nodes». Значит, без `key` перестроение *пересоздаёт* узел и теряет всё, что я на нём выставил императивно. В Flutter ключи нужны редко; здесь они — условие корректности, и об этом сказано одной строкой. [есть]

20. `Flutter3dView` — 34 именованных параметра (`flutter3d_app.api:107`), от `drainLook` до `onListenerMoved`. Группировка в `DeviceOptions`/`ViewOptions`/`LoopOptions`/`PluginOptions` — D9 [обещано].

21. Казуальная игра. Шаблон `flutter3d_game/example` — 371 строка «seed, not a game»: `GenrePlugin<LevelWalk>`, `BusEvent` с `EventCodec`, `captureSimulation`/`restoreSimulation` в `Snapshot`, `PluginManifest`, `LevelLoader`, `openRegistryFor(level)`. Для rollback-мультиплеера это правильно. Для раннера на телефоне я хотел бы `update(dt)` как во Flame. Шаблонов четыре (platformer, shooter, racing, strategy, `first-project.md`), и все — про уровни из brushes в JSON, которые правит редактор, запускаемый *из checkout* на macOS. «Flame-подобный» путь есть: `flame_flutter3d` с `HasFlutter3d`, `Object3dComponent`, `ChunkStreamer`, и River Sortie — буквально бесконечный раннер [есть]. Но об этом в quickstart ни слова.

22. Туториал `core/tutorial.md` расходится с quickstart: там `flutter3d_impeller: ^1.0.0-rc.1` в pubspec, `GpuRenderBackend.open()`, `Material(baseColor: Vector4(...))`, `GpuFrameImage`; в quickstart — `flutter3d_app`, `openDevice`, `RenderMaterial`, `LinearColor`. План A9/D9 чинит код [обещано]; туториал в списке 5.4 не назван.

## 3. Десять изменений, которые сэкономили бы больше всего

23. Quickstart для pub-пользователя в начале, checkout — в конец: `flutter create`, два пакета, два ключа в plist/manifest, `Scene3D` с `Model3D`. Сейчас ровно наоборот.

24. `ModelViewer3D` (D47) — поднять в приоритете: это то, за чем Flutter-разработчик приходит первым (сам review §2.12 пишет «the first ask in every Flutter 3D tracker»). [обещано]

25. `Mesh3D.onTap` / `Model3D.onTap(ModelPart)` как виджетное свойство поверх `Raycaster`. [нет]

26. `OrbitCamera3D` для `Scene3D` — тот же `OrbitController`, но без `Listener` руками. [нет]

27. `flutter3d doctor` [есть, `packages/flutter3d_build/lib/src/doctor.dart`] проверяет Dart, Flutter, `impellerc`, `glslangValidator`, `naga`. Не проверяет единственное, на чём я споткнусь: `Info.plist`/`AndroidManifest` ключи, `hook/build.dart`, строки `assets:` в pubspec для `flutter3d_generated/`. Добавить — полчаса работы, экономит час каждому. D19 расширяет doctor только на бандлы плагинов [обещано].

28. Ошибка вместо тихого fallback: `openDevice` упал в `flutter3d_cpu` — показать баннер `DidNotStart`-стиля (виджет уже есть [есть]) с текстом «Impeller is off: add these two keys», а не строку в консоли.

29. Один материал-тип в quickstart и README. `RenderMaterial` для кода, `Material3D` для виджетов, и список «остальные четыре — не для вас» в глоссарии.

30. Свет по умолчанию в человеческих словах: `Light3D.sun()`, `Light3D.lamp()` с разумными `candela`, а числа — в doc-комментарии.

31. Cookbook. `apps/flutter3d_showcase` и `/showcase/learn/` — «every capability of the engine on a page of its own, with a step-by-step guide» [есть], это почти cookbook, но организован по фичам движка (bloom, SSR), а не по задачам («показать GLB с кнопкой "в корзину"», «раннер на 60 fps на телефоне», «маятник со слайдером длины»). Нужны 20 рецептов по задачам, каждый ≤40 строк, копируемый.

32. Playground: демо в браузере есть [есть], модельер на models.pleion.dev есть [есть], а «вставил `Scene3D`-код, увидел картинку» — нет [нет]. Web-backend (WebGL2/WebGPU) есть, так что это вопрос страницы, а не движка.

33. Шаблон `flutter3d create project` [есть] дополнить `--kind viewer` и `--kind arcade` (Flame-мост). План 4K обещает «twin-shaped» и «laboratory-shaped» примеры [обещано], viewer и casual — нет.

34. Счётчики и имена в документах пусть держит правило (5.4 [обещано]) — а до тех пор лучше без чисел, чем с четырьмя разными.

## 4. Что ждёт потом

35. Телефон. `SUPPORT.md`: Android Vulkan «Supported», но «played on a Galaxy A55» — одно устройство; OpenGL ES fallback «has not run on a real device»; iOS — «runs clean in the simulator; no physical device has run them». Мой магазинный товар будет смотреть кто-то на Redmi с Mali — и это «Best effort». [есть, честно написано]

36. Размер. `index.md` даёт 2,5 МБ `main.dart.js` для стратегии; про APK ни слова [нет]. Бандл шейдеров «97 KB with seven shaders» (README, старое число) и растёт; D15 «shader bundle selected per project by the build hook» [обещано]. Физическое ядро на C собирается хуком — ещё и компилятор на CI нужен.

37. Web. WebGPU по умолчанию, WebGL2 fallback [есть]; `--wasm` «throws on its first frame» (quickstart) [есть]. Для встраивания виджета товара на сайт это нормально; для раннера — «the four genre games at a fixed resolution».

38. Ассеты. `assets_src/` + хук + `flutter3d_generated/` + «Flutter's own asset bundler does not read a declared directory recursively» + «needs `flutter clean` before the hook runs» (`asset-pipeline.md`). Каждая из этих строк — вечер отладки для того, кто не читал страницу.

39. Обновления. «Skip 0.7.0» в quickstart, четыре пакета «discontinued», `flutter3d migrate` и `fix_data` [есть/обещано], `migrating-to-1.0.md` [есть]. Хорошо, что есть; плохо, что история уже такая в 1.0-rc.1. Правила «strict semver from 1.0» и снимки API — это аргумент за.

40. Где искать ответы. Stack Overflow по `flutter3d` пуст. Есть `reference/pitfalls.md` — отличный, но это список симптомов *движка* («`SIGSEGV` in `AGXG15XFamilyRenderContext`»), а не моих ошибок. Плюс `dart run flutter3d:skills` кладёт навыки для агента в `.claude/skills` [есть] — похоже, автор рассчитывает, что отвечать будет ИИ, а не форум. Honest, но одинокий путь.

41. ECS/симуляция для казуалки. `publish`, `Snapshot`, `EventCodec`, `Portable`, `flutter3d_lints` «no clock, no unseeded `Random`» — всё это оправдано для детерминизма, но для раннера на телефоне это налог без выгоды. D46 `PluginGroup` (`StandardPlugins.set(BloomAddon(...)).without<FogAddon>()`) [обещано] упростит сборку, но не уберёт обязанность писать `captureSimulation`.

42. Маятник для учителя. `apps/flutter3d_lab_pendulum/lib/main.dart` — 342 строки императивного кода с `Raycaster`, `WidgetSurface`, `LabClock`, ручным `Ticker` [есть]; `flutter3d_education/lab.dart` с `PendulumSimulation` [есть]. Учителю обещан документ `f3d.experiment` («a level, substances by id, probes, a scenario with steps») редактируемый в редакторе без кода (D31), `TimeSource.manual` слайдер (D2), `SimulationProfile.accurate` с тестом против аналитики (D3), `Probe` с единицами (D6) [всё обещано, волны 2–4]. Это правильная цель — но сегодня учитель получает 342 строки Dart.

## 5. Выбрал бы?

43. Против WebView с `<model-viewer>` — для одной витрины товара сегодня нет: `<model-viewer>` даёт URL, орбиту, hotspot и AR-кнопку в пять строк, а здесь это D47 на волне 4.5. Когда `ModelViewer3D` выйдет с обещанным «under twenty lines» и тапом по детали — да, потому что это настоящий виджет в дереве, а не iframe.

44. Против Unity — для казуалки на телефон Unity проще начать и тяжелее встроить в Flutter-приложение; здесь наоборот. Если игра — экран внутри моего приложения с go_router, flutter3d (через `flame_flutter3d`, а не через `GenrePlugin`) выигрывает. Если игра — это весь продукт, Unity.

45. Против Flame + flutter_scene — сам сайт (`reference/comparison.md`) говорит: Scene — «an editor you can download today», Windows/Linux через Impeller, Rapier, два чужих проекта на нём. flutter3d даёт мне мост к Flame [есть], CPU-бэкенд для тестов без GPU [есть], детерминизм [есть], которых мне для раннера не надо. Я бы начал с flutter_scene за счёт порога входа — и смотрел бы на flutter3d после rc.1, когда `ModelViewer3D`, `Scene3D` с группированными опциями и cookbook по задачам будут не в `tasks/`, а в `packages/`.

46. Итог честно: движок огромный и продуман для тех, кто знает, что такое frame graph. Всё, чего мне не хватает, в плане *есть* — но сдвинуто в волны 2–4.5, а первый час устроен так, будто я пришёл писать пятый бэкенд. Я приду, когда quickstart начнётся со слова `Model3D`.
