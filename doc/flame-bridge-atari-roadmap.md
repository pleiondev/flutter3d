# flame_flutter3d и шесть игр Atari: сводка по дырам моста

## 1. Вердикт

Основа сделана правильно. Хостинг двух слоёв на одних часах (`Flutter3dFlameWidget` + `BridgeClock`), оси `BridgePlane`, синхронизация позиции и yaw, попадания через хитбоксы Flame и клавиши через общий `Bindings`/`InputState` одинаково годятся всем шести играм. Этого хватает, чтобы игра заработала, но не чтобы её было просто написать. Каждая из шести игр заново написала бы то, что уже вручную лежит в River Sortie:

- holder → pivot → model;
- подмену моделей (dressing);
- отложенное освобождение буферов;
- камеру;
- звук;
- осколки взрывов.

Почти все дыры сидят в мосте. В движке не хватает немногого: tint у MeshNode, слотов в InstancedMeshNode, публичного отложенного release, lerp атмосферы, открытого пути с лентой, сеточного меша и trail-узла.

Отдельно три скрытые ошибки корректности в `Object3dComponent`, которые стоит чинить первыми:
- эффекты Flame отстают на кадр;
- удалённый компонент рисуется ещё один кадр;
- вложенный компонент рисуется в локальных координатах так, будто они мировые.

Ещё одна мелочь: `PhysicsStepComponent` передаёт в `Dynamics.step` сырой dt Flame, хотя step документирован как фиксированный шаг.

## 2. Roadmap (игры × удаляемый код / трудоёмкость)

Коды игр: P = Pitfall, A = Asteroids, M = Missile Command, I = Space Invaders, E = Enduro, F = Frogger.

**Tier 1: сам `Object3dComponent`** (всё в мосте)

1. **Корректность синхронизации** (P A M I E F, S). Синк переносится после детей: `updateTree(dt) { super.updateTree(dt); _sync(); }`. В `removeFromParent` сразу ставится `node.visible = false`. Добавляется `space: SyncSpace.absolute | hierarchy`: в режиме hierarchy узел вешается под узел ближайшего предка `Object3dComponent`, и `plane.constant` у ребёнка не прибавляется второй раз. Удалять в River нечего, зато становятся доступны `MoveEffect`/`RotateEffect` и вложение компонентов вместо ручного движения в `update`.
2. **Полный transform** (P A M I E F, S).
   ```dart
   Object3dComponent(syncScale: ScaleSync.fromSize, elevation: 0.4, visual: model)
   SceneNode get visual; Quaternion visualRotation; Vector3 visualOffset;
   ```
   `elevation` уходит в `plane.to3d(position, at: plane.constant + elevation)`. Удаляется: `RiverGame.air`/`water` (river_game.dart:100-101), пары holder/pivot в staging.dart:25-33 и pieces.dart:16-64 (`bankTowards`, `_goDown`), `setUniformScale` в `BurstComponent`.
3. **Владение GPU-ресурсами** (P A M I E F, S). В мосте: `Object3dComponent(owns: [mesh])` и `BridgeResources.of(game).releaseAfterFrame(mesh)`. В движке сделать публичным кольцо `Renderer._releaseAfterFrame` (renderer.dart:4809-4848) и распространить его на `DeviceMesh`. Удаляется: `_releaseLater` (river_game.dart:180, 469-474), staging.dart:160-173.
4. **Видимость** (P A I F M, S). `with HasVisibility`, `isVisible` пишется в `node.visible`, которое иерархично. Удаляется: мигание вручную в arcade_game.dart:396-427, `show`/`hide` в pieces.dart:60-66.
5. **`ModelSlot`**: плейсхолдер, асинхронная загрузка, fit и facing (P A M I E F, M). Логику вынести из `ActorVisuals` (flutter3d_game/.../actor_visuals.dart:63, 91-110).
   ```dart
   Object3dComponent(node: ModelSlot(placeholder: box, asset: load('jet.glb'), fitLength: 1.2, facing: Facing.posZ))
   ```
   Удаляется: craft.dart:119-186 (`_dress`, `dressWithModels`), карта `_dressed` (river_game.dart:164-165) с регистрацией в staging.dart, `dressWithCrafts` в Meteor Yard (main.dart:160).

**Tier 2: сервисы вокруг компонента** (мост, кроме 10 и 12)

6. **Звук** (P A M I E F, S).
   ```dart
   AudioSceneComponent(bank: Sounds.all, ears: camera, openOnFirstInput: true)
   ufo.add(SoundEmitterComponent(Sounds.siren, loop: true))
   ```
   Удаляется: sounds.dart:126-175 (`hearWith`, `_hold`, `audio.update(_ears)`), `_openAudio` в main.dart:92-104.
7. **Ввод** (P M I F, S): `bridge.bindJoystick(stick, x: moveX)`, `bindButton(btn, fire)`, `onTapDown`/`onPointerMove`, `Vector2? aimCanvas`, `swipes: {SwipeDir.up: hopUp}`, `InputStepComponent`, который сам вызывает `endStep`. Удаляется: river_game.dart:477-481, 516, 523-548.
8. **Камера: подгонка и слежение** (P A M I E F, M).
   ```dart
   FramingCamera(camera, plane, viewfinder).fit(rect, tilt: 0.3, mode: FitMode.contain)
   FollowCamera3dComponent(target: jet, offset: .., tuning: RigTuning())  // поверх CameraRig
   ```
   Ещё нужны пиксельно точный ortho и перенос `viewfinder.angle` в roll. Удаляется: `_frame` в River main.dart:120-130, подгонка aspect/zoom/up в Meteor Yard main.dart:80-130.
9. **Хук рендерера и частицы** (P A M I E F, M).
   ```dart
   Flutter3dFlameWidget(onRendererReady: (r) => ..)
   ParticleSystemComponent(system, plane: plane)..burstAt(effect, flamePoint)
   ```
   Для осколков брать `MeshParticleContributor`. Удаляется: `BurstComponent` (pieces.dart:452-550), фабрика `fire()` в craft.dart:112-117.
10. **Инстансинг** (P A M I E F, M). В движке: `InstanceHandle acquire()`/`release(h)` в `InstancedMeshNode` (swap-remove, чтение цвета и morph обратно). В мосте: `InstancedObject3dComponent(batch: aliens, plane: plane)`. В River выстрелы (river_game.dart:412-420) становятся инстансами.
11. **Проекция и пикинг** (M I F, плюс A для попапов; S, а `ProjectedViewfinder` M). `BridgeProjector(camera, () => game.size).toScreen(world)`, `plane.fromScreen(camera, canvasPoint, viewSize)`, `ProjectedViewfinder`, чтобы `TapCallbacks` и отладочные хитбоксы совпадали с перспективой.
12. **Движок: tint и opacity на MeshNode** (P A I F, M): `meshNode.tint = Vector4(1, 1, 1, .5)`, `SceneNode.setTintRecursive`, при батчинге значение уходит в цвет инстанса. После этого `OpacityProvider` и `ColorEffect` в мосте становятся тривиальными. Удаляется: материал на каждый burst в River.
13. **Хост** (P M, S): `overlayBuilderMap`, `initialActiveOverlays`, `focusNode`, `Vector4 Function()? clearColor`. Упростится `Stack` в Meteor Yard (main.dart:150).
14. **Анимация моделей** (P I, M): `AnimatedModelComponent.play('run', crossFade: .15)`, `MeshFlipbookComponent`. Удалять нечего, ни одно из двух демо модели не анимирует.
15. **Фиксированный шаг** (A I, плюс корректность Meteor Yard; S): `Flutter3dFlameWidget(fixedStep: 1/60)` поверх `FixedStep` из flutter3d_sim. `PhysicsStepComponent` тоже переходит на фиксированный шаг.

**Tier 3: жанровые** (по одной игре, кроме ChunkStreamer)

- `ChunkStreamer<K>` (E P, M): удаляет `_ensureStretches`/`_buildStretch`/`_dropStretch` в staging.dart. По соотношению пользы и труда это лучший пункт тира.
- `WrapSpace` с ghost-узлами и `ToroidalCollisionDetection` (A, M).
- Интерфейс `BridgeSpace`, чтобы `BridgePlane` его реализовывал, и `CurvilinearSpace(path)` (E, M).
- Движок: `Atmosphere.lerp`/`AtmosphereCycle`, плюс в мосте `AtmosphereComponent` (E, M).
- Движок: `OpenPath` с `ribbon(path, from:, to:)` (E, M).
- `CellGridMesh.fromMask` и `CellGridComponent.hitAt` (I, M).
- Движок: `LineStripNode` (append, count) и `TrailComponent` (M, M).
- `PlatformerBody` поверх `CharacterController` с лестницами (P, L).
- Мелочи: `closed` у `buildPolyline` (A, S), контроль тумана для horizon-слоя (E, S), `LightGroup.level` (E, S).

## 3. Уже есть, заново не строить

- Flame 1.38 `ComponentPool<T>` работает с `Object3dComponent` как есть.
- Renderer доступен через `existing: (device, renderer)` (flutter3d_flame_widget.dart:67), так делают страницы showcase.
- `clearColor` можно менять уже сейчас: `RenderView` хранит тот же `Vector4` без копии (render_view.dart:44,64). Это стоит задокументировать.
- `BridgePlane.to3d(flat, at:)`. Ручное родительство узла до mount работает (`if (node.parent == null)`, object3d_component.dart:74), кроме плоскостей с ненулевым `constant`.
- `InstancedMeshNode`: swap-remove собирается из `readTransform`/`setTransform`/`count`, только цвет и morph надо держать у себя.
- Толстые линии: `buildPolyline` + `Material.polyline` (polyline_shape.dart:42, material.dart:107). Правка вершин на месте: `DeviceMesh.overwriteVertices`.
- Экран: `projectPoint` и `screenBoundsOfBox` (screen_bounds.dart:31,63), `Raycaster.setFromScreen` (raycaster.dart:194), `groundUnder` в стратегии (pointing.dart:41).
- Камера: `CameraRig` не привязан к типу цели, есть easing и shake (camera_rig.dart:32,135). `OrbitController.frameBounds` (orbit_controller.dart:123).
- Горизонт: `skyNode` и `followCamera` (sky.dart:175,200). Фары: `node.add(LightNode(...))`.
- Персонаж: `CharacterController` уже ходит через мост (showcase flame_ecs_bridge.dart:96-173). У Flame есть `raycast`.
- `ActorVisuals` (плейсхолдер, анимация, интерполяция) для Actor. `TouchStick`/`TouchButton` пишут в `InputState`. `openSpeakers` с тихим fallback.
- Частицы: `MeshParticleContributor`, `BoxEmitter`/`DriftEmitter`. Шаг: `FixedStep` в flutter3d_sim. У `GameWidget` autofocus включён по умолчанию.

## 4. Игры-доказательства по тирам

- **Tier 1: Frogger.** Маленькая игра, которая задевает каждый пункт тира. Дуга прыжка (`elevation` + `MoveEffect`, то есть лаг эффектов), сплющивание (scale), езда на бревне (иерархия), мигание (visibility), плейсхолдеры и смена досок (release). Инстансинг ей не нужен, так что результат про сам компонент ничем не замутнён. Параллельно стоит перевести River Sortie на tier 1: удалить перечисленный выше код, и goldens должны совпасть с текущими. Это регрессионное доказательство.
- **Tier 2: Space Invaders.** 55 инстансов с tint-вспышкой, частицы вместо `BurstComponent`, точная подгонка поля 224x256 при любом aspect, попап UFO через проекцию, ритм шагов в звуке, тач-кнопки. Если нужен отдельный тест пикинга и pointer-ввода, Missile Command проверяет их прямее.
- **Tier 3: сначала Asteroids.** Это самый узкий жанровый пункт (`WrapSpace`), и он заодно проверяет fixed step. **Затем Enduro**: самый крупный тир (`BridgeSpace`, атмосфера, `ChunkStreamer`, open path), и на нём видно, выдерживает ли мост нелинейное отображение. **Pitfall последним**, потому что `PlatformerBody` оценён как L.

Ключевые файлы:
- /Users/dmitrii/flutter3d/packages/flame_flutter3d/lib/src/transform/object3d_component.dart
- /Users/dmitrii/flutter3d/packages/flame_flutter3d/lib/src/host/flutter3d_flame_widget.dart
- /Users/dmitrii/flutter3d/packages/flame_flutter3d/lib/src/camera/camera_sync_controller.dart
- /Users/dmitrii/flutter3d/apps/flutter3d_demo_river/lib/src/{craft,staging,pieces,river_game,sounds}.dart
## 5. Состояние на конец сентября 2026 (ветка river-0.8.3)

Всё ниже проверялось на River Sortie, отдельных игр под Atari не писали.

### Сделано

- **Tier 1 целиком.** Синхронизация после детей (эффекты Flame не отстают на кадр), скрытие при `removeFromParent`, вложенность через абсолютный transform, `elevation`, масштаб (абсолютный, с учётом родителей), видимость с учётом скрытых предков, `visual` для поворотов модели. Вместо `ModelSlot` в движке появились `ModelWardrobe` и `instantiateFitted`. Отложенное освобождение мешей: `Renderer.releaseMeshAfterFrame`.
- **Хост.** Миксин `HasFlutter3d`: сцена, камера, рендерер и проектор принадлежат игре, мир строится в `onOpen3d`, рендерер приходит в `onRenderer3d`. `Flutter3dFlameWidget(game: game)` больше ничего не требует; виджет следует за новой камерой и цветом фона при пересборке и предупреждает о непрозрачном фоне игры. Тесты виджета снова включены: «зависание» было проблемой исполнителя тестов, а не Flame.
- **Камера и экран.** `ChaseCamera` поверх `CameraRig` (с тряской), `BridgeProjector` (`toScreen`, `onPlane`, `boundsOf`), касания по тому, что видно в перспективе (`Tap3dCallbacks`, `Taps3dComponent`), хитбоксы в 3D (`debugHitboxes3d`, в движке `Renderer.debugLines`).
- **Ввод.** `followJoystick`, `bindButton`.
- **Симуляция.** Физика и акторы на фиксированном шаге с интерполяцией (`stepper`), `ColliderRegistry`, `BridgePriority` как порядок кадра по умолчанию.
- **Много объектов и эффекты.** `InstancedObject3dComponent` на слотах `InstancedMeshNode.acquire/release`; `Particles3dComponent` с аддитивным и затемняющим (`MeshParticleContributor.darkening`) смешиванием; `ChunkStreamer`.
- **Tint и opacity.** `MeshNode.tint` в движке без правки шейдеров; `Object3dComponent` реализует `OpacityProvider` и `tint`, так что `OpacityEffect` работает в 3D.
- **Звук.** Отдельный пакет `flame_flutter3d_audio` (`AudioSceneComponent`, `SoundEmitterComponent`), чтобы мост не тащил нативный SoLoud.
- **Производительность.** Неподвижный мостовой объект больше ничего не пишет в сцену и не вызывает перерисовку теней каждый кадр.
- **Попутно найденные ошибки движка.** Полосы теней в длинных сценах на Metal (смещение каскада меньше шага half-float) и молчащий звук у файлов 22 кГц (срез фильтра выше частоты Найквиста).

### Сделано во втором заходе

- Тела и акторы в покое больше не перерисовывают тени; ввод закрывает шаг сам (`stepEnd`), указатель и свайпы стали вводом.
- Логика самой игры на фиксированном шаге (`HasFixedStep`, `FixedStepUpdate`); River Sortie пролетает одну и ту же дистанцию при любой частоте кадров.
- `CollisionBridge` для любого компонента с коллбэками (акторы тоже), tint и opacity у инстансов, `owns` для мешей компонента, `ProjectedViewfinder`.
- Анимация моделей (`ModelAnimationComponent`, `MeshFlipbookComponent`), пиксельно точная орто-камера и крен, оверлеи и фокус у виджета, позиционный звук в River.
- Жанровые пункты: `WrapSpace` с призраками и хитбоксами через шов (Asteroids), `OpenPath`/`ribbon` и `CurvilinearSpace` (Enduro), `Atmosphere`/`AtmosphereCycle`/`LightGroup`/`Material.fogged` и `AtmosphereComponent` (Enduro), `CellGrid` и `CellGridComponent` (Invaders), `LineStripNode` и `TrailComponent` (Missile Command), `CharacterBodyComponent` поверх бегуна платформера с лестницами (Pitfall), замкнутая `buildPolyline`.

### Сделано по функциональному ревью (30 сентября)

Ревью четырёх областей (хост, трансформы, физика с вводом, камера с миром и звуком), каждая найденная ошибка — с тестом, падающим без правки.

- **Хост.** 3D-мир живёт вместе с игрой: повторный показ рисует сохранённое, `close3d()`/`dispose()` отпускают устройство. Смена игры в виджете даёт новое состояние, ошибка при сборке мира показывается `DidNotStart` и не оставляет устройство открытым, `redraw3d()` для паузы. Часы, звук и конец ввода идут после `CameraComponent` Flame.
- **Трансформы.** Отражённый вложенный компонент поворачивается как у Flame (`FlamePose`), простой `Component` между компонентом и позиционированным предком больше не прячет предка, перенос к другому родителю не отдаёт `owns`.
- **Ввод и физика.** Шаг ввода закрывается после каждого фиксированного шага; физика и акторы идут по часам `HasFixedStep`. Контакт с удалённым партнёром завершается, реестр коллайдеров переживает перенос и повторное добавление. `teleport`, `removeFrom`, удержание `PointerTrack` при перетаскивании, мёртвая зона джойстика, сброс клавиш при потере фокуса, интерполяция поворота актора.
- **Мир и звук.** `WrapSpace` сообщает о контакте один раз, призраки копируют тип, форму и tint. `ProjectedViewfinder` работает с любым вьюпортом, небо — горизонт, а не NaN. Утечки мешей щита, след после ресайза, частицы после повторного добавления. Звук: `pause`/`resume`, повтор открытия после отказа, `close` во время открытия, эмиттеры находят новую сцену, слушатель по мировому повороту камеры.
- **Добавлено.** `Bridged3d` (касания и хитбоксы инстансов, `space` у инстансов), ранжирование касаний по входу луча, отпускание/отмена/долгое нажатие, `TintEffect`, перезапуск клипа, туман дня через `fog3d`.

### Закрыто следом

- Камера Flame ведёт перспективную (`CameraSyncController.eyeOffset`): `follow` с `maxSpeed`, `setBounds`, `moveTo`, эффекты на видоискателе; `visibleWorldRect` и `canSee` считаются по тому, что показывает 3D-камера.
- Разделённый экран: `viewport3d`, `moreViews3d`, `BridgeProjector.viewport`, `SceneSurface.moreViews` (flutter3d_app 0.8.1).
- `WrapSpace` переносит через шов тела, которыми правит физика (`shiftScene`), призрак тапается.
- `onCollision` раз в кадр при переданном `stepper`, `ColliderRegistry.raycast` через мир физики со слоями и триггерами.
- Стик читается до шагов (`HasFixedStep.beforeSteps`).

### Осталось

- Проверить новые страницы showcase, эффекты River и разделённый экран глазами, не только тестами.
