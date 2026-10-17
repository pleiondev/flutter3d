# Что ждут от 3D-движка на «1.0» и чего требуют типовые приложения (2026-10-09)

Заметки агента. Уровни: **Б** = базовое (есть почти у всех сравниваемых движков / почти во всех запросах), **Ч** = частое (у большинства), **П** = продвинутое (у немногих). Факты из официальных страниц фич и трекеров; ссылки собраны в легенде в конце, в таблицах — короткие метки.

Контекст по «1.0»-планке: Godot 4.0 вышел с полным списком ниже (G40); Bevy на 0.17+ сам пишет «important features are missing», ломает API каждые ~3 месяца и советует Godot для серьёзных проектов (BEVY-QS), а в птичьих постах 2025–2026 называет недостающим редактор, формат сцен .bsn, виджеты UI и физику как «open question» (BEVY5, BEVY6). То есть «stable» у сравнимых движков означает набор из таблицы 1 плюс редактор и стабильный формат сцены.

## Часть 1. Базовый набор движков на «1.0 / stable»

### Рендеринг

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| PBR metallic-roughness + normal/AO/emissive | Б | все десять | G40, BAB, PC, FIL, THREE, UNITY, STR, WICK, EVG, BEVY |
| Пользовательские шейдеры/материалы | Б | все | G40, THREE, BAB, PC, FIL, STR |
| Графовые материалы (node/shader graph) | Ч | Godot, Babylon, Unity, three.js TSL, Stride | G40, BAB, UNITY, THREE |
| Расширенный PBR: clearcoat, sheen, transmission, anisotropy, IOR, volume | Ч | Filament, Babylon (+OpenPBR), three MeshPhysical, Wicked, Unity HDRP; URP только clearcoat | FIL, BAB, WICK, UNITY |
| Directional/point/spot + тени от них | Б | все | G40, BAB, FIL, UNITY |
| Area (rect) lights | Ч | Babylon, PlayCanvas, three.js, Unity HDRP | BAB, PC, THREE, UNITY |
| IES-профили, физические единицы света, физическая камера | П | Filament, Babylon, Godot 4, Unity HDRP | FIL, BAB, G40, UNITY |
| Clustered/Forward+ для многих источников | Ч | Filament, Babylon, PlayCanvas, Godot, Wicked, URP Forward+ | FIL, BAB, PC, G40, WICK |
| Каскадные тени + PCF | Б | все | FIL, BAB, PC, UNITY |
| Мягкие тени PCSS/VSM/EVSM | Ч | Filament, Babylon, PlayCanvas, Unity HDRP | FIL, BAB, PC, UNITY |
| Contact shadows | П | Filament, Wicked, Unity HDRP | FIL, WICK, UNITY |
| IBL / environment map / skybox | Б | все | FIL, BAB, PC, THREE |
| Baked lightmaps / light probes / reflection probes | Ч | Godot, Unity, PlayCanvas, Wicked, Stride, Babylon | G40, UNITY, PC, WICK, STR, BAB |
| Real-time GI (SDFGI/VoxelGI/DDGI/SSGI/RSM) | П | Godot 4, Wicked, Unity HDRP, Babylon | G40, WICK, UNITY, BAB |
| SSAO | Б | все кроме Bevy-core (есть в 0.x) | G40, BAB, PC, FIL, UNITY, WICK, THREE |
| SSR, планарные отражения | Ч | Godot, Babylon, Filament, Wicked, Unity, three | BAB, FIL, WICK, UNITY |
| Bloom, tone mapping, exposure, color grading, DoF | Б | все | FIL, BAB, PC, UNITY, STR, EVG |
| FXAA/MSAA + TAA | Б/Ч | TAA: Filament, PlayCanvas, Wicked, Unity, Evergine, three addon | FIL, PC, WICK, UNITY |
| Motion blur, lens flare, chromatic aberration, vignette, grain | Ч | Unity, Wicked, Babylon, Sketchfab-viewer | UNITY, WICK, BAB, SKF |
| Декали | Ч | Godot 4, Unity URP/HDRP, Wicked, Babylon | G40, UNITY, WICK, BAB |
| Небо: cubemap/skybox | Б | все | UNITY, BAB |
| Физическая атмосфера / sky shader | Ч | Godot 4, Babylon, Unity HDRP, Cesium | G40, BAB, UNITY, CES |
| Объёмный туман / volumetrics | П | Godot 4, Unity HDRP, Wicked, Babylon | G40, UNITY, WICK, BAB |
| Прозрачность: blend/cutout/сортировка | Б | все | UNITY, BAB |
| OIT | П | Cesium, Wicked (stochastic) | CES, WICK |
| Частицы CPU | Б | все игровые движки | G40, UNITY, STR |
| Частицы GPU (+коллизии, аттракторы) | Ч | Godot 4, Babylon, PlayCanvas, Wicked, Unity VFX Graph, Evergine | G40, BAB, PC, WICK, UNITY, EVG |
| Террейн (слои, инстансинг, деревья, дыры) | Ч | Unity, Wicked; Godot 4.0 только heightmap-коллизия; нет в three/Bevy/Filament | UNITY, WICK, G40 |
| Вода (волны, пена, подводный рендер, каустика) | П | Unity HDRP, Wicked (FFT-океан), Cesium | UNITY, WICK, CES |
| Instancing/batching | Б | все | UNITY, BAB, FIL |
| LOD (авто/ручной), HLOD | Ч | Godot 4 auto-LOD, Babylon, three, Unity | G40, BAB, UNITY |
| Occlusion culling (GPU/Hi-Z, queries) | Ч | Godot 4, Babylon, Unity, Wicked | G40, BAB, UNITY, WICK |
| Gaussian splats | Ч | Babylon, PlayCanvas, Wicked, three addon, Evergine | BAB, PC, WICK, THREE, EVG25 |
| Reversed-Z, HDR-вывод, VRS | П | Wicked, Unity URP/HDRP (HDR output) | WICK, UNITY |
| Upscaling (FSR/DLSS/STP), динамическое разрешение | Ч | Godot 4 (FSR1), Unity, Filament (FSR) | G40, UNITY, FIL |
| Debug views, render stats, frame profiler | Ч | Unity, Wicked, Babylon Inspector, PlayCanvas | UNITY, WICK, BAB |

### Анимация, физика, звук

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Скиннинг + blending клипов | Б | все | G40, BEVY, BAB, PC, FIL, THREE |
| Morph targets | Б | все | BEVY, BAB, PC, FIL, WICK |
| Анимация произвольных свойств / tween | Ч | Godot 4, Stride, three KeyframeTrack, Babylon | G40, STR, THREE |
| State machine / blend tree | Ч | Godot 4, Unity, Stride | G40, UNITY, STR |
| IK | Ч | Godot, Wicked, three CCDIK, Babylon | WICK, THREE, BAB |
| Ретаргетинг | Ч | Godot 4, Babylon, Wicked | G40, BAB, WICK |
| Rigid bodies, формы, raycast, триггеры, слои/маски | Б | Godot, Babylon (Havok), PlayCanvas (ammo), Stride, Wicked, Unity, Evergine; three/Bevy — сторонние | G40, BAB, PC, STR, WICK, EVG, GPHYS |
| Character controller | Б | Godot CharacterBody3D, Babylon Havok CC, Wicked, Unity | G40, BAB, WICK |
| Joints | Ч | Godot, Evergine, Babylon, Wicked | G40, EVG, BAB |
| Транспорт (raycast vehicle, wheel collider) | Ч | Godot VehicleBody3D, Unity WheelCollider, UE Chaos, Wicked | GVEH, UWHEEL, CHAOS, WICK |
| Ragdoll | Ч | Babylon, Wicked, Unity | BAB, WICK |
| Soft body / cloth | П | Godot 4 SoftBody3D, Wicked, Unity cloth | G40, WICK |
| Жидкости (SPH, fluid rendering) | П | Wicked, Babylon | WICK, BAB |
| Navmesh + crowd/avoidance | Ч | Godot 4 (NavigationServer, obstacles, links), Babylon, Stride, Wicked | G40, BAB, STR, WICK |
| Позиционный 3D-звук | Б | Godot, Babylon, PlayCanvas, Stride, Wicked, Unity; Bevy — «bare-bones» | G40, BAB, PC, STR, WICK, BEVY5 |
| Эффекты/фильтры/шины, HRTF | Ч/П | PlayCanvas (WebAudio-фильтры), Stride (HRTF), Godot (AudioServer) | PC, STR, G40 |

### Ассеты, сеть, UI, инструменты, платформы

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| glTF 2.0 импорт в рантайме | Б | все (Godot 4.0 добавил runtime) | G40, FIL, BAB, PC, THREE, BEVY |
| glTF-расширения: Draco, meshopt, KTX2/Basis, variants, texture_transform | Ч | Filament (16 ext.), PlayCanvas, three, Babylon, Wicked | FIL, PC, THREE, WICK |
| OBJ/STL/FBX | Ч | three (десятки загрузчиков), Babylon, Wicked, Sketchfab | THREE, BAB, WICK, SKF |
| USD/USDZ (импорт или экспорт) | П | three (USDLoader), Babylon (USDZ export), Evergine, Omniverse | THREE, BAB, EVG25 |
| Экспорт сцены (glTF/USDZ/OBJ) | Ч | Babylon, Sketchfab, model-viewer exportScene | BAB, MV |
| Асинхронная/потоковая загрузка, стриминг сцены | Ч | PlayCanvas, Babylon (incremental), Stride, Wicked (texture streaming) | PC, BAB, STR, WICK |
| Hot reload ассетов/шейдеров/сцен | Ч | Bevy, Stride, flutter_scene, Godot | BEVY, STR, FSPUB |
| Сжатие текстур (ASTC/ETC/DXT/KTX2) | Ч | PlayCanvas, Babylon, Filament, Godot | PC, BAB, FIL, G40 |
| HTTP/WebSocket/UDP | Ч | Godot, Wicked (UDP), PlayCanvas (браузер) | G40, WICK |
| Высокоуровневая репликация (spawner/synchronizer, RPC) | Ч (игровые) | Godot 4 (MultiplayerSpawner/Synchronizer), UE Lyra; нет у three/Babylon/PlayCanvas/Stride/Bevy | G40, LYRA, STR |
| Встроенный UI c текстом (bidi, fallback-шрифты, SDF-текст) | Б (игровые) | Godot 4 TextServer, Babylon GUI (SDF), Bevy UI, Stride UI, PlayCanvas SDF, Wicked TrueType | G40, BAB, BEVY, STR, PC, WICK |
| Редактор сцен с инспектором и гизмо | Ч | Godot, Unity, Stride, PlayCanvas, Wicked, Babylon (Inspector + node-редакторы); нет у Filament; у Bevy — главный долг | G40, STR, PC, BAB, BEVY6 |
| Профилировщик/render-graph viewer | Ч | Unity, Wicked, Babylon | UNITY, WICK, BAB |
| Скриптинг с горячей перезагрузкой | Ч | Stride (.NET), Godot (GDScript), Wicked (Lua) | STR, G40, WICK |
| Desktop + iOS + Android | Б | все | FIL, BEVY, G40 |
| Web (WebGL2) | Б для веб-движков, Ч для остальных | Godot, Unity URP (не HDRP), Bevy, Filament, Evergine | G40, UNITY, BEVY, FIL, EVG |
| WebGPU | Ч | Babylon, PlayCanvas, three, Filament, Bevy, Evergine (experimental) | BAB, PC, THREE, FIL, EVG |
| XR (OpenXR/WebXR) | Ч | Godot 4 (OpenXR в ядре), Babylon, PlayCanvas, three, Unity, Stride | G40, BAB, PC, UNITY, STR |
| Headless/серверный режим | Ч | Godot 4 (headless + placeholder-ассеты) | G40 |
| Детерминированная запись/реплей | П | OpenRA (replays), Lyra (client replay, experimental) | OPENRA, LYRA |

## Часть 2. Запросы по типам приложений

### (a) Игры

| Жанр | Что просят почти всегда | Источник |
|---|---|---|
| FPS | FPS-контроллер (sprint, crouch, slide), оружие как ресурс (cooldown, damage, spread), hitscan + projectile, reload/патроны, procedural recoil/sway/bob, camera shake, перебиндинг клавиш и меню настроек, враги/боты, интерактив (двери, рычаги), подбираемые health/ammo, destructibles; Lyra добавляет сетевой режим, ability system, матчмейкинг | KEN, GFPS, GWEEB, UFPS, LYRA |
| Платформер | Coyote time (~0.1 с), jump buffer (~0.15 с), variable jump height, shape-cast к земле и потолку, порог склона, grace-период контактов, движущиеся платформы без парентинга (сохранение скорости), wall jump, камера с демпфированием и коллизиями, camera-relative ввод | KCC, KARL, GEN3D |
| Гонки | Wheel collider (slip-кривые, подвеска spring/damper), центр масс и дрифт, VehicleBody/Chaos-аналог, чекпоинты по порядку, таймер в физическом шаге с микросекундной точностью, ghost replay (семплы 10 Гц, slerp), AI по сплайнам/waypoints с обгонами, split-screen viewport, круги/позиции | UWHEEL, GVEH, CHAOS, GHOST |
| Стратегия | Box-selection с shift, очередь команд (move/attack/gather, force-move), формации с превью, навмеш + RVO только для движущихся, стаггер запросов пути, fog of war шейдером/текстурой, миникарта, attack-move/stances, производственные очереди, тысячи юнитов без per-unit коллайдеров, реплеи и observer, lockstep-мультиплеер | RTSC, EMASS, OPENRA |

### (b) Конфигураторы и e-commerce

| Возможность | Ур. | Источник |
|---|---|---|
| Варианты: материалы/цвета/части, show/hide, glTF `KHR_materials_variants` (`variant-name`, `availableVariants`) | Б | MV, ROOMLE, VECT |
| Orbit/turntable: `camera-controls`, `auto-rotate`, min/max orbit и FOV, `interaction-prompt`, `touch-action`, `disable-zoom/pan/tap` | Б | MV |
| AR без приложения: Quick Look (USDZ, `ios-src`, banner/Apple Pay, `allowsContentScaling`) и Scene Viewer (glb, `mode`, `resizable`, `enable_vertical_placement`, лимиты 100k треугольников/10 МБ) | Б | MV, AQL, SV |
| Показ текущей конфигурации в AR, QR-handoff с десктопа | Ч | VECT, ROOMLE |
| Окружение: `environment-image`/`skybox-image`, `exposure`, `tone-mapping`, `shadow-intensity/softness`, пресеты день/ночь | Б | MV, ROOMLE |
| Hotspots: слоты `hotspot-*`, `positionAndNormalFromPoint`, `surfaceFromPoint`, анимированные цели | Б | MV, VECT |
| Анимации: `autoplay`, `animation-name`, crossfade, `appendAnimation` с весами, события play/finished | Ч | MV |
| Poster/прогресс/lazy loading, `toBlob`/скриншот, `getDimensions` | Ч | MV |
| Цены/правила/parts list, интеграция Shopify/WooCommerce | Ч | ROOMLE, VECT |
| Доступность: `alt`, `a11y`-описания | Ч | MV |
| Внешний рендерер/EffectComposer, `createVideoTexture`, экспорт сцены | П | MV |

### (c) CAD/BIM/архитектурные вьюеры

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Импорт IFC (2x3/4.3), glTF, OBJ, STL, LAS/LAZ, CityJSON; USD/E57/STEP у индустриальных | Б | xeokit, Evergine | XEO, EVG25 |
| Section planes с гизмо, x-ray, isolate/hide/show-all | Б | xeokit, APS Viewer, BIM-BAM | XEO, APS, BIMBAM |
| Измерения: расстояние, цепочка, угол, площадь, отметка высоты, snapping к вершинам | Б | xeokit, APS, BIM-BAM | XEOW, APS, BIMBAM |
| Explode (с `lockExplode`) | Ч | APS Viewer | APS |
| Ортографическая проекция, storey/plan views | Ч | xeokit StoreyViews, Cesium | XEOW, CES |
| Аннотации и BCF-viewpoints (камера + видимость + секции = закладки камеры) | Б | xeokit | XEO, XEOBV |
| Дерево элементов/слои, property DB, поиск по метаданным | Б | xeokit TreeView, APS | XEOW, APS |
| Большие модели: сотни тысяч объектов, сплит-модели, XKT-формат; стриминг | Б/Ч | xeokit; стриминг — Cesium 3D Tiles | XEO, XEOBV, CES |
| Selection/highlight/colorize, outline | Б | xeokit, Babylon edges/highlight | XEO, BAB |
| Двойная точность для глобальных координат | Ч | xeokit, Cesium | XEO, CES, SPK |
| Экспорт: markup, print, скриншот, ссылка на вид | Ч | APS, Sketchfab | APS, SKF |
| Diff двух версий модели | П | BIM-BAM | BIMBAM |
| NavCube/gnomon, context menu | Ч | xeokit | XEO |

### (d) Цифровые двойники и промышленные дашборды

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Сегментированный glTF/GLB, элемент = набор мешей, привязанный к twin-ID | Б | Azure 3D Scenes Studio | ADT |
| Привязка телеметрии OPC UA / MQTT / REST к узлам графа сцены | Б | ADT, ICONICS, вендоры | ADT, OPC, ROB |
| Visual rules: окраска мешей и badge по порогам/выражениям | Б | ADT | ADT |
| Виджеты: gauge, value, link, data-history график | Б | ADT | ADT |
| Историческое воспроизведение/скраббинг (окно 30 дней, data history explorer) | Ч | ADT, OPC UA history | ADT, OPC, ROB |
| Алармы: события, acknowledge/resolve | Ч | OPC UA A&E, вендоры | OPC |
| Слои поведения под роли, фильтрация элементов | Ч | ADT | ADT |
| Глобус/гео-привязка сцен (lat/lon), 3D Tiles, Cesium-террейн | Ч | ADT globe view, Cesium для Unity/Unreal/Omniverse | ADT, CES, CESOMNI |
| Облака точек (LiDAR, compute-растеризация) | Ч | Evergine, Cesium, Potree | EVG25, CES, POT |
| Встраиваемый viewer-компонент, шаринг ссылки на сцену с состоянием | Б | ADT (iot-cardboard-js) | ADT |
| Период обновления, анимации из файла, тема | Ч | ADT | ADT |
| Multi-user/collab, USD-коннекторы | П | Omniverse | CESOMNI |
| Цели производительности: 2 000 инстансов при 60 fps, задержка < 400 мс | Ч | вендор | ROB |

### (e) Образование и виртуальные лаборатории

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Множественные представления: объект, график, числа одновременно | Б | PhET | PHET |
| Инструменты-пробы: линейка, секундомер, вольтметр, термометр | Б | PhET | PHET |
| Сбор данных, графики, подгонка по собственным точкам | Ч | PhET | PHET |
| Встроенные квизы с автооценкой, подсказки, first/best/last score | Б | Labster | LAB |
| LTI 1.3 Advantage (launch + grade passback), SCORM-пакет, xAPI в LRS | Б | Labster (Canvas/Moodle/Blackboard/D2L/Schoology), общие стандарты | LAB, LTI |
| Теория, лабораторный журнал/отчёт-шаблон, сценарии | Ч | Labster | LAB |
| Доступность: alternative input (клавиатура), interactive description (скринридер), сонификация с mute, voicing, pan&zoom | Б | PhET | PHETA11Y, PHET |
| HTML5/браузер без установки, офлайн, многоязычность | Б | PhET | PHET |
| Авторинг сценариев и инструктирование (hints, диагностика ошибок) | Ч | обзоры | LAB |
| Аналитика пути ученика (где остановился) через xAPI | Ч | — | LTI |

### (f) Визуализация данных

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Инстансированные глифы: scatterplot (860k кругов), icon, column, text | Б | deck.gl | DECK, UBER |
| Point cloud layer (миллионы точек, радиус в px/м) | Б | deck.gl, Potree, VTK.js | DECK, POT, VTKJS |
| Агрегация: heatmap, hexagon/grid bins, contour, screen-grid | Б | deck.gl | DECK |
| Octree-LOD, point budget, EDL, классификация, clipping volumes | Ч | Potree | POT |
| Volume rendering (ray-cast), isosurface (marching cubes), срезы (cutter, reslice) | Ч | VTK.js | VTKJS |
| Terrain/3D Tiles/MVT слои, пути во времени (trips) | Ч | deck.gl | DECK |
| Picking по объекту/ребру, виджеты (transform, seed, sphere) | Ч | VTK.js | VTKJS |
| Композиция слоёв с blending/clipping, offscreen/multi-canvas | Ч | deck.gl, Babylon | DECK, BAB |
| WebGPU/compute для сортировки/растеризации | П | Evergine, PlayCanvas | EVG25, PC |

### (g) Медицина и наука

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| DICOM (все transfer syntaxes, JPEG2000), DICOMweb | Б | Cornerstone3D, OHIF | CS3D, OHIF |
| Стек- и объёмные вьюпорты, аксиал/сагиттал/корональ без перезагрузки, oblique | Б | Cornerstone3D | CS3D |
| MIP/AIP-проекции, PET/CT fusion, цветные объёмы | Ч | Cornerstone3D, OHIF | CS3D, OHIF |
| 3D volume rendering с пресетами (Bone, Soft tissue, Lung) | Б | Cornerstone3D, OHIF | CS3D |
| Window/level, zoom/pan/scroll, калибровка pixel spacing | Б | Cornerstone3D | CS3D |
| Измерения в физическом пространстве: length, bidirectional, ROI (mean/SD), crosshairs, reference lines | Б | Cornerstone3D | CS3D |
| Сегментация: labelmap в 2D/3D, поверхность из labelmap, scissors, threshold | Ч | Cornerstone3D, OHIF 3.3 | CS3D, OHIF |
| Синхронизация W/L и камеры между вьюпортами, tool groups | Ч | Cornerstone3D | CS3D |
| CPU-fallback без GPU, потоковая подгрузка слайсов | Ч | Cornerstone3D | CS3D |
| 16-бит текстуры (`useNorm16Texture`), лимиты памяти | Ч | OHIF FAQ | OHIFFAQ |
| Микроскопия, 4D, видео, hanging protocols | П | OHIF | OHIF |

### (h) AR/VR

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| Session, device tracking, камера, plane detection, anchors — есть на всех 6 платформах AR Foundation | Б | AR Foundation (ARCore/ARKit/visionOS/OpenXR/Quest/sim) | ARF |
| Hit test / raycast | Б | AR Foundation (5/6), WebXR, PlayCanvas | ARF, PCXR, ANDXR |
| Meshing, environment probes, image tracking | Ч | ARF (4–5/6), PlayCanvas XR | ARF, PCXR |
| Occlusion / depth sensing | Ч | ARF (3/6), WebXR depth, PlayCanvas | ARF, PCXR, ANDXR |
| Hand tracking (joints), input sources: контроллеры/руки/gaze/tap | Ч | PlayCanvas, Chrome Android XR, Babylon | PCXR, ANDXR, BAB |
| Light estimation | Ч | ARF, WebXR, PlayCanvas | ARF, ANDXR, PCXR |
| Persistent anchors | П | PlayCanvas XR | PCXR |
| DOM overlay, passthrough-окна | Ч | PlayCanvas, Android XR | PCXR, ANDXR |
| Стерео: multiview/single-pass instanced, foveated | Ч | Unity URP, Stride (single-pass), Babylon multiviews | UNITY, STR, BAB |
| Object/face/body tracking, participants | П | ARF (1–2/6) | ARF |
| Quick Look / Scene Viewer как «AR без движка» | Б (e-commerce) | model-viewer | MV, AQL, SV |

### (i) GIS и карты

| Возможность | Ур. | У кого | Источник |
|---|---|---|---|
| WGS84-глобус, 3D/2D/Columbus, перспектива/орто | Б | CesiumJS | CES |
| Террейн из DEM (quantized-mesh), exaggeration, height/slope-материалы | Б | CesiumJS | CES |
| Imagery: WMS/WMTS/TMS/OSM/ArcGIS, слои с alpha/brightness/split | Б | CesiumJS, deck.gl WMS/Tile | CES, DECK |
| 3D Tiles: фотограмметрия, здания, BIM, облака точек, стилизация, classification, Draco | Б | CesiumJS, deck.gl Tile3DLayer, Cesium for Omniverse/Unity/Unreal | CES, DECK, CESOMNI |
| KML/GeoJSON/TopoJSON с clamp-to-ground, ground primitives, z-order | Б | CesiumJS | CES |
| Большие координаты: логарифмический depth + multiple frusta, эмуляция double, relative-to-center/floating origin | Б | Cesium, xeokit, three.js-практики | CES, XEO, JIT, SPK |
| Камера: инерция, flights, terrain collision, геокодер, timeline | Ч | CesiumJS | CES |
| Время: CZML, Julian dates, UTC/TAI; референсные фреймы ICRF/ENU | Ч | CesiumJS | CES |
| Кластеризация точек/меток/билбордов, военная символика | Ч | CesiumJS | CES |
| Clipping planes для tileset/террейна/моделей, picking | Б | CesiumJS | CES |
| Атмосфера, солнце/луна/звёзды, вода, тени от солнца, OIT | Ч | CesiumJS | CES |
| H3/S2/geohash/quadkey слои, MVT | Ч | deck.gl | DECK |

## Часть 3. Что Flutter-разработчики просят от 3D-пакета

Трекеры (сортировка по числу комментариев; числа — из GitHub API на 2026-10-09): flutter_scene 100 выбранных тикетов, flutter_3d_controller 88, model_viewer_plus 100, flutter_cube 61, three_dart 100.

| Ожидание | Ур. | Свидетельство | Источник |
|---|---|---|---|
| Загрузка glTF/GLB в рантайме из сети/файла/ассетов — самый частый тикет во всех пяти трекерах | Б | flutter_scene #12 (12 комм.), three_dart #134 (44), #133 (13), flutter_cube #5 (13), #21 (12), #16, mvp #93 (10), #2, f3d #16, #32 | FS, TD, CUBE, MVP, F3D |
| Сборка/запуск на всех платформах: Windows/macOS/Linux/arm64, release-режим | Б | flutter_scene #55 (10), #182, #386, #65, #88; f3d #49 (16), #88, #1; three_dart #136 (10), #139, #8; mvp #70, #95 | FS, F3D, TD, MVP |
| Web-поддержка (пакет без Impeller в браузере) | Б | flutter_scene: WebGL2-бэкенд «в preview» с 0.19; f3d #34, #58, #24; mvp #5 | FSPUB, F3D, MVP |
| Производительность на мобильных и слабых устройствах, память | Б | flutter_scene #39 (Android), #388/#391 (RPi 5), #371 (web), #35 OOM; three_dart #58 (утечка), f3d #26 | FS, TD, F3D |
| Hit-testing: клик по узлу/части модели, hotspots с onClick, ray picking API | Б | flutter_scene #117 (Camera.castRay), three_dart #53 (9), #149; f3d #63, #4, #22; mvp #18 | FS, TD, F3D, MVP |
| Управление камерой: orbit/pan/zoom жестами, лимиты орбиты, auto-rotate, 360°, сброс | Б | f3d #26 (9), #25, #73, #57, #67, #68, #33; mvp #36, #40; flutter_cube #32, #47 | F3D, MVP, CUBE |
| Жесты внутри ListView/PageView и после диалогов (конфликт с WebView) | Ч | mvp #11, #65; f3d #27, #66; flutter #117813 | MVP, F3D |
| Управление анимацией: play/pause/once/loop, несколько клипов, кроссфейд, события загрузки | Б | f3d #52, #28, #14, #15, #60; mvp #66, #68, #21; three_dart #48 | F3D, MVP, TD |
| Текстуры/материалы в рантайме: смена текстуры по tap, цвет, morph targets для lip-sync | Ч | f3d #8, #20, #75, #65; flutter_cube #11, #25, #51, #45, #36 | F3D, CUBE |
| Освещение, тени, окружение (HDRI), «пикселизация high-poly» | Ч | flutter_cube #13, #8, #19; mvp #67; f3d #43; flutter_scene #60, #234 | CUBE, MVP, F3D, FS |
| Форматы помимо glTF: OBJ/MTL, FBX, STL, VRM | Ч | f3d #46, #21, #44, #23; three_dart #81, #107, #151, #146 | F3D, TD |
| AR-запуск (Scene Viewer / Quick Look) и его надёжность | Ч | mvp #27, #8, #9, #7, #53, #94; three_d_viewer рекламирует AR как фичу | MVP |
| Paritet с `<model-viewer>`: poster, прогресс, variants, hotspots, скриншот | Ч | mvp #26, #13, #23, #12; f3d — «порт model-viewer в WebView» | MVP, MV |
| Требование Impeller/мастер-канала, нестабильный API Flutter GPU, шейдеры через native-assets хук | Б (риск) | Flutter GPU: «requires Impeller», «no API stability», master «strongly recommended»; flutter_scene «early preview… things may break» | FGPU, FSPUB |
| Ожидание «3D как виджет»: прозрачный фон, наклон/вращение API, колбэки сцены, сценовый редактор как в Godot/Unity | Б | flutter/flutter #58145 (68 👍, закрыт в 3.24 со ссылкой на Flutter GPU) | F58145 |
| Физика, рендер в текстуру, несколько вьюпортов, XR/внешние render targets | Ч/П | three_dart #108, #129, #126, #51; flutter_cube #29; flutter_scene #365 (OpenXR) | TD, CUBE, FS |
| Поддерживаемость: «пакет заброшен?», обновление под новый Dart/Flutter | Б | flutter_cube #53, three_dart #160, #161, #166, #72; f3d #38 | CUBE, TD, F3D |

## Легенда источников

G40 https://godotengine.org/article/godot-4-0-sets-sail/ · BEVY https://bevy.org/ · BEVY-QS https://bevy.org/learn/quick-start/introduction/ · BEVY5 https://bevy.org/news/bevys-fifth-birthday/ · BEVY6 https://bevy.org/news/bevys-sixth-birthday/ · THREE https://threejs.org/docs/ · BAB https://babylonjs.com/specifications/ · PC https://playcanvas.com/products/engine · UNITY https://docs.unity3d.com/6000.0/Documentation/Manual/render-pipelines-feature-comparison.html · FIL https://github.com/google/filament · STR https://stride3d.net/features · WICK https://github.com/turanszkij/WickedEngine/blob/master/features.txt · EVG https://evergine.com/features/ · EVG25 https://www.plainconcepts.com/a-new-evergine-2025-major-release/ · GPHYS https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html · GVEH https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html · UWHEEL https://docs.unity3d.com/2022.3/Documentation/Manual/WheelColliderTutorial.html · CHAOS https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/ChaosVehicles/UChaosVehicleWheel · LYRA https://dev.epicgames.com/documentation/unreal-engine/upgrading-the-lyra-starter-game-to-the-latest-engine-release-in-unreal-engine · KEN https://store.godotengine.org/asset/kenney/starter-kit-first-person-shooter/ · GFPS https://github.com/AxelReviron/Godot-FPS-Template · GWEEB https://gweebo.itch.io/gweebos-fps-template · UFPS https://blog.unity.com/fr/games/take-aim-at-making-your-first-unity-game · KCC https://kidscancode.org/godot_recipes/4.x/2d/coyote_time/index.html · KARL https://karlfayeton.itch.io/test-3d-platformer · GEN3D https://generalistprogrammer.com/game-kits/godot-3d-platformer-starter-kit · GHOST https://arawn-software-publishing.gitbook.io/arawn/modules/time-crystal/ghost-racer-demo · RTSC https://claudeskills.info/skills/thedivergentai/gd-agentic-skills/godot-genre-rts/ · EMASS https://arawn-software-publishing.gitbook.io/enemy-masses/rts/enemy-masses-rts-controller · OPENRA https://www.openra.net/about/ · MV https://modelviewer.dev/docs/ · AQL https://developer.apple.com/augmented-reality/quick-look/ · SV https://developers.google.com/ar/develop/scene-viewer · SKF https://sketchfab.com/features · ROOMLE https://www.roomle.com/en/configurator · VECT https://www.vectary.com/3d-configurator-maker/ · XEO https://xeokit.io/ · XEOW https://github.com/xeokit/xeokit-sdk/wiki/Viewer-Plugins · XEOBV https://xeokit.github.io/xeokit-bim-viewer/ · BIMBAM https://github.com/yaditio/BIM-BAM · APS https://aps.autodesk.com/en/docs/viewer/v5/overview/basics · ADT https://learn.microsoft.com/en-us/azure/digital-twins/how-to-use-3d-scenes-studio · OPC https://opcconnect.opcfoundation.org/2021/03/iconics-opc-ua-and-digital-twins/ · ROB https://www.roboard.com/digital-twin-production-line/ · CES https://github.com/AnalyticalGraphicsInc/cesium/wiki/CesiumJS-Features-Checklist · CESOMNI https://cesium.com/blog/2023/03/21/cesium-for-omniverse-launch/ · POT https://github.com/potree/potree · PHET https://phet.colorado.edu/en/about · PHETA11Y https://onlineteachinghub.education.purdue.edu/phet/ · LAB https://www.labster.com/platform-overview · LTI https://evnedev.com/blog/company/edtech-interoperability/ · DECK https://deck.gl/docs/api-reference/layers · UBER https://www.uber.com/blog/visualizing-data-sets-deck-gl-framework/ · VTKJS https://www.kitware.com/vtk-js-the-visualization-toolkit-on-the-web/ · CS3D https://www.cornerstonejs.org/docs/getting-started/overview · OHIF https://ohif.org/ · OHIFFAQ https://docs.ohif.org/llm/faq/technical.md · PCXR https://developer.playcanvas.com/user-manual/xr/capabilities/ · ARF https://docs.unity3d.com/Packages/com.unity.xr.arfoundation@6.0/manual/index.html · ANDXR https://developer.android.com/develop/xr/web · JIT https://discourse.threejs.org/t/large-coordinates/50621 · SPK https://speckle.systems/blog/speckles-take-on-spatial-jitter-2 · FGPU https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md · F58145 https://github.com/flutter/flutter/issues/58145 · FSPUB https://pub.dev/packages/flutter_scene · FS https://github.com/bdero/flutter_scene/issues · F3D https://github.com/m-r-davari/flutter_3d_controller/issues · MVP https://github.com/omchiii/model_viewer_plus.dart/issues · CUBE https://github.com/zesage/flutter_cube/issues · TD https://github.com/wasabia/three_dart/issues

## Замечания к методике

- Уровни в части 1 выставлены по присутствию в 10 списках фич; «Ч» — у 5–8 движков, «П» — у 1–4. Для веб-движков (three/Babylon/PlayCanvas) WebGL2 — базовое, для остальных — частое.
- Часть 2 опирается на документацию продуктов-лидеров ниши, а не на RFP: формальных requirement-спеков в открытом доступе не нашлось (ближайшее — wiki Europeana «User requirements: 3D viewer», без приоритетов). PhET accessibility-страница грузится скриптом, поэтому список фич взят с Purdue-страницы, цитирующей PhET.
- Трекеры Flutter-пакетов: выгружены первые 100 тикетов по числу комментариев через GitHub API; у model_viewer_plus репозиторий — `omchiii/model_viewer_plus.dart`. flutter/flutter #58145 — тот самый тикет «3D API», закрыт 2024-08-08 ссылкой на релиз 3.24 (Flutter GPU).
- Что в таблицах не встретилось ни у одного движка на «1.0», а есть в flutter3d (по comparison.md): CPU-растеризатор как тестовый бэкенд, детерминированный реплей «до бита», rollback-мультиплеер для 2–32 участников, жанровые пакеты. Это не претензия, просто отметка, что рынок этого не требует и за это не спросит.
