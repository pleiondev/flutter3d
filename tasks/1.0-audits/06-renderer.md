# Баг-хант рендера 1.0.0-rc.1 (ветка 0.9.0, рабочее дерево, 2026-10-09)

Заметки агента. Проверено чтением: core (projection, renderer_depth, scene/transparency/shadow/sky/post/mesh_encode), все четыре бэкенда, шейдеры (surface, depth_predraw, pbr, color, material_maps, light_list, shadow, PRECISION.md), flutter3d_app (Flutter3dView, SceneSurface), flutter3d_sim (FrameCadence), физкамера и физнебо, capture JSON, web-декодер текстур. Запущено три тестовых файла: `frame_pacing_test` (10/10 ок), `depth_precision_test` (17/18), `lod_test` (31/32). Серьёзных ошибок «неверная картинка на бэкенде X» не найдено; ниже — по убыванию важности.

## 1. `Flutter3dView` с `frameRateCap` замирает после перезапуска тикера (verified by reading)

`packages/flutter3d_app/lib/src/view/flutter3d_view.dart:618-640` + `packages/flutter3d_sim/lib/src/loop/frame_cadence.dart:66-86`. `_startTicker` вызывает `Ticker.start()` после `stop()` (переключение `continuous` в `didUpdateWidget`, :691-695); у `Ticker` `elapsed` после рестарта считается заново от нуля, а `_cadence._lastDrawn` хранит старое, большое значение; `_cadence.reset()` в app не вызывается нигде. В `due()`: `vsync − drawn` отрицательно → `refreshes = max(1, round(отриц.)) = 1`; при `interval ≥ 2` (любой cap ниже частоты экрана) каждый refresh пропускается, пока новый `elapsed` не догонит старый `_lastDrawn`. Сценарий: `frameRateCap: 30`, `continuous` выключили на паузе и включили через 10 минут — вид не рисуется 10 минут, при этом `_owed` копится и первый же кадр шагнёт симуляцию на всё это время. Лечение: `_cadence.reset()` в `_startTicker`.

## 2. `FrameCadence.cap = 0` — краш (verified by reading)

`frame_cadence.dart:46-52`: конструктор проверяет `cap > 0`, но поле `cap` публично мутабельно, и `Flutter3dView._tick` (:638) пишет `widget.frameRateCap` без проверки. При 0: `limit >= refreshRate` ложно → `(refreshRate / 0 − 1e-3).ceil()` → `UnsupportedError: Infinity or NaN toInt`. `Scene3D.frameRateCap` (`scene_widgets.dart:121,275`) и `Flutter3dView.frameRateCap` (:400) — публичные double? без assert, «0 = без ограничения» — естественная ошибка пользователя.

## 3. `Display.refreshRate == 0` молча отключает cap (suspected)

`flutter3d_view.dart:639`: `_cadence.refreshRate = View.maybeOf(context)?.display.refreshRate`. На платформах, где Flutter отдаёт 0 (десктоп-эмбеддеры без `NotifyDisplayUpdate`), `_refreshRate` становится 0.0, а не null: `interval` → `limit >= 0` → 1 (cap выключен), `period = ∞`, измеренная частота никогда не используется. Нужно трактовать `<= 0` как «неизвестно». Кроме того `_measure` (:97-105) берёт любой короткий промежуток ≥ 2 мс как новую частоту мгновенно и остывает по 1 % за кадр: один сдвоенный тик (4 мс → 250 Гц) на сотни кадров превращает cap 60 в ~30 fps. Проявляется только когда `refreshRate` не задан (SceneSurface без Flutter3dView).

## 4. `viewAxisOf` даёт NaN при бесконечной far (verified by reading; достижимо из плагина)

`packages/flutter3d_core/lib/src/engine/scene/projection.dart:781-793`: `far = inverse·(0,0,1,1)`; для `PerspectiveProjection.infinite` эта clip-точка на бесконечности (`w = 0`) → деления дают NaN, `length2 > 0` ложно, `_forward` остаётся NaN. Внутренние вызовы защищены: планарный проход подменяет far на конечную (`renderer_planar_pass.dart:300-310`), пробы строят конечные грани (`renderer_probe_pass.dart:304-320`). Открытый путь — `Renderer.encodeScene` (`renderer.dart:4057`), которому контрибьютор передаёт `frame.viewProjection` (как советует `pass_contributor.dart:311-316`) при камере `far: infinity`: surface-buffer получает `ViewDepth = NaN` на его пикселях, SSAO/туман/soft-particles/decals там ломаются. Защита как в `_skyCornerRay` (`renderer_sky_pass.dart:345-347`) или точки на z = 0.5 вместо z = 1.

## 5. Два теста красные из-за допусков, не кода (verified by running)

- `packages/flutter3d/test/depth_precision_test.dart:98-108` «an infinite one is near over distance»: ожидание `closeTo(0.1/d, 1e-9)`, факт `1.0000000149` — `Matrix4` из `vector_math` хранит Float32, 1.49e-8 = 2⁻²⁶, округление near=0.1 в float. Допуск должен быть ~1e-6.
- `packages/flutter3d/test/lod_test.dart:447`: `baseColor.toSrgb().r == 1.0`, факт `0.9999999999999999` — sRGB→linear→sRGB round-trip; нужен `closeTo`.
Остальное в обоих файлах (reversed == ordinary на CPU, стена на 20 км, тени каскадов, кросс-фейд) проходит.

## 6. Подгонка ближней плоскости фактически не работает в живых сценах (verified by reading)

`contributor_registry.dart:67` — единственное определение `boundsFor`, переопределений нет нигде (`rg boundsFor\(` по всем пакетам). `_fittedNear` (`renderer_depth.dart:460-464`) при любом активном контрибьюторе с `null` возвращает `authored`, и так же при любом узле с `frustumCulled == false` (:455, скайдомы). Частицы, декали, гизмо, любой плагин — значит в демо A2.9 и «0.18 м floor ближних каскадов» не проявляются; голдены перезапишутся с фитом только в голых тестовых сценах. Это не неверная картинка, а невыполненное обещание плана 5. Обратная сторона (подозрение): фит включён ключом `settings.reversedDepth`, а не `reversed` (`renderer_scene_pass.dart:309`) — т.е. и на WebGL без `EXT_clip_control`, и на Impeller/GLES без float-depth; там выигрыша нет, а риск есть: узел с устаревшими `worldBounds` (скиннинг с bind-pose bounds, вершинный wind), выходящий ближе bounds более чем на 10 % (`_kNearFitMargin`, :276), режется near-плоскостью. «Bit-identical с прошлыми релизами» (:388-391) верно только при `reversedDepth: false`.

## 7. Хеш-альфа и сдвиг origin (verified by reading, low)

`surface.glsl:317-320` и `depth_predraw.frag:68-71` якорят шум на `v_world_position` — это scene-space, т.е. относительно `Scene.origin`. Каждый `shiftOrigin` (`scene.dart:152-171`, `rebaseAround` округляет до метров, но скалярное произведение меняется) перебрасывает узор всех hashed-материалов и кросс-фейдов → однокадровое «искрение» всей листвы при каждом ребейзе в большом мире. Кроме того `fract(sin(·)·43758)` на аргументах ~10⁵ (500 м × 16 × 78) не бит-идентичен между GPU (разные range-reduction у sin); CPU транскрибирует его в double (`cpu_shaders_surface.dart:270`, `cpu_shaders_shadow_passes.dart:222`). Кросс-бэкендные голдены hashed-материалов могут быть только с допуском.

## 8. Владение ресурсами (item 20) — обещание шире реализации (verified by reading)

`packages/flutter3d_hardware/lib/src/texture.dart:48-80`: хендлы без счётчика ссылок — один `_release`, `dispose` идемпотентен. Правила структуры, ловящего утечки, нет (`tool/structure/*.dart` не содержит детектора по leak/undisposed; фейковый бэкенд тоже не считает живые хендлы). Сами жизненные циклы в рендере в порядке: `_releaseViewState` (`renderer.dart:497-510`) — через кольцо отложенного освобождения, `_ensureTargets` (:716-770) освобождает цели ресайза сразу (на Impeller/WebGPU безопасно: буферы команд держат свои ссылки, `destroy()` не трогает уже отправленную работу), `_lastResult` обнуляется, чтобы held-кадр не отдал освобождённую текстуру (:763-764).

## 9. `executeBundles` под реверсом (verified by reading, low)

`renderer_depth.dart:178-183`: бандл, записанный плагином с `less`, воспроизводится в scene-pass без поворота теста; `ContributorFrame.reversedDepth` (`pass_contributor.dart:432-440`) обещает «ничего делать не нужно» — для бандлов это неверно. Также небо на реверсе (`renderer_sky_pass.dart:94-98`, depth 0 + `greaterEqual`) перекрывает поверхность, лежащую ровно на конечной far-плоскости — неразличимо.

## Что проверено и чисто

**Reversed-Z.** Один флаг на кадр `_reversedFor = settings && DeviceFeature.reversedDepth` (`renderer_depth.dart:285`); обёртка `_ReversedDepthEncoder` (:34-260) поворачивает `less↔greater`, `lessEqual↔greaterEqual`, оставляет `equal` (pre-draw, `renderer_mesh_encode.dart:456-461`), меняет знак `DepthBias`. Обёрнуты scene, transparency, transmission, солнечный атлас; clear `farDepth` 0/1 (:296). Матрицы `withDepthPlanes` (`projection.dart:697-741`) проверены вручную: конечная reversed `(n/(f−n), nf/(f−n))`, бесконечная `(0, n)` → depth = near/d; `toReversedDepth` инволютивен; `_viewFrustum` (`renderer_depth.dart:330-348`) явно заменяет NaN-плоскость бесконечной far на «пропускает всё». Бэкенды: WebGL — `clipControlEXT(LOWER_LEFT, ZERO_TO_ONE)` с проверкой `getError` (`webgl_device.dart:916-934`), тогда `depthRange = zeroToOne`, `D32F_S8`, фича; без расширения — `toDepthRange` удваивает строку, фича false, обычная матрица. WebGPU — `depth32float-stencil8` в `GpuFeature.requested` (`webgpu_interop.dart:1622`), фича только при гранте (`webgpu_formats.dart:305`), иначе `depth24plus-stencil8`. Impeller — фича iff `defaultDepthStencilFormat == d32FloatS8UInt` (`gpu_capabilities.dart:103`); без неё рендерер строит обычную матрицу, не «реверсную с less». CPU — float32-буфер, восемь сравнений, клип по w. Шейдеры не читают аппаратную глубину вовсе: SSAO/DoF/туман/soft particles/decals/outline/TAA берут `.a` surface-buffer в метрах (`color.glsl:186`), линеаризации и `F3D_REVERSED_DEPTH` нет и не нужно; режим хранения тени (0/1/2) выставляется из одного места и читается четырьмя GLSL- и четырьмя CPU-читателями. `gl_FragDepth` только в `shadow_copy.frag:64`. Публичного readback глубины нет. Кластеры режут по clip-w `log(w/near)` (`light_clusters.dart:248`, `light_list.glsl:124`) с нереверсной матрицей камеры — к реверсу и фиту near нечувствительны; при бесконечной far стандин 65504 м делает 24 слайса в 1.75× вместо 1.47× — терпимо.

**Mediump.** Стретчи ровно те, что в `PRECISION.md`: `SrgbToLinear`, `EncodeOctahedral`, три `Apply*Map`, `F_Schlick`/`F90`, `MultiscatterScale`; позиции, глубина, шум, GGX, свет — highp; `depth_predraw.frag:31` highp; `color.glsl:21` highp по умолчанию. WebGL `highpMaterials` → `\bmediump\b` → highp (`webgl_shaders.dart:130,218`); WebGPU/Impeller переключателя нет (naga/Metal отбрасывают) — документировано.

**LOD и pre-draw.** `lodFade` +(1−share)/−share (`lod_group.dart:311-326`), pre-draw узор взаимодополняющий (`pattern < share` / `pattern ≥ 1+share`, `depth_predraw.frag:74-79`), тот же хеш и тот же вершинный стейдж в обеих фазах (`renderer_mesh_encode.dart:281-300, 347-359`), батч берёт отдельный `_instancedVertexShader`, маршрут `_opaqueRoute` (:1299-1337) исключает blend, coverage, layered с трансформом base colour.

**Физкамера (verified by reading + running).** `ev100 = log2(N²/t) − log2(S/100) − comp`, `exposure = 1.6·2^(ref−ev) = 1843.2/(1.2·2^EV)`, ref EV 9.907; `legacyUnit = π·1843.2 = 5790.58`; `illuminanceLux = engine·5790.6`, при `_sun = lux/1843.2` единицы сходятся; солнце по умолчанию 115 812 лк; `cameraExposure` при `physicalCamera:false` = старый множитель; `FrameResult.ev100` из итоговой экспозиции (`frame_result.dart:159`). Тесты проходят.

**Кластеры.** `maxLights`/`maxExtraLights` — геттеры над `LightBuffer` (`light_node.dart:110-114`), упаковка клампит (`light_buffer.dart:137-144, 314, 425`), ячейки режутся матрицей кадра.

**Пейсинг (verified by running).** Impeller settle'ит кадр только после следующего `beginFrame` (`gpu_device.dart:731-737`, `gpu_frame.dart:38-44`), рендерер не считает последний кадр (`renderer.dart:895-898`) → удержание не зацикливается; кольца: Impeller 3 `HostBuffer` (`gpu_device.dart:739-775`), WebGPU арены полагаются на упорядочение `writeBuffer` в очереди (`webgpu_device.dart:1473-1487`), `_kFramesInFlight = maxFramesInFlight = 3`. `warmUpInSlices` — те же шаги, что `warmUp`.

**TAA на вид (Must 2 — закрыто).** `_ViewState` через `Expando` на `RenderView` с переносом на «свежий вид той же камеры» и выселением через 16 кадров (`renderer.dart:406-510`); previous VP и история узлов — на вид (`frame_history.dart:321-332`, `renderer_post_pass.dart:643`). Нюанс по контракту: при нескольких видах в одном `render` берутся `options.settings` только первого (`renderer.dart:4558`), история общая на кадр — верно, т.к. вьюпорты одной цели.

**Origin shift (Must 3 — закрыто).** `_followOrigin` (`renderer.dart:528-541`) + `frameHistory.origin` ребейзит записанные матрицы, hi-Z сбрасывается; `Scene.shiftOrigin` двигает узлы в float32 один раз и `irradianceField.origin` (`scene.dart:152-171`), origin поля грузится каждый кадр (`renderer_mesh_encode.dart:1450`); частицы через `engine.followOrigin` и `Particles3D` (двойной сдвиг возможен, если пользователь подпишет одну систему обоими путями — low).

**Web-текстуры.** `createImageBitmap` с `premultiplyAlpha:'none'`, `colorSpaceConversion:'none'`, ресайз в декоде, cap = min(запрошенный, `MAX_TEXTURE_SIZE`), мипы `generateMipmap` (`webgl_image_decode.dart`, `webgl_device.dart:1311-1331`); KTX2 → браузер отказывает → CPU-путь. Кэш пайплайнов WebGPU в памяти, «ревалидация» — HTTP-ревалидация бандла (`hot_swap.dart:165`).

**Capture JSON.** NaN/±Inf → строки (`capture_json.dart:37-46`, `render_inspection.dart:542`), floats base64, нечитаемые проходы отбрасываются, не роняя файл (`frame_capture.dart:474-512`).

**Flutter3dView.** `FormatRegistry`/`VmExtensions` строятся (`flutter3d_view.dart:498-512`, Must 8 закрыт); потеря устройства слушается, переоткрывается, рендерер пересоздаётся с `replacing:` (:550-616); порядок dispose — плагины → view → renderer → device (:162-169); асинхронный `_open` защищён `mounted`. Device-gating см. выше; Impeller отказывает явно (bias, write mask, clamp), не молча.

## Не проверено
Голдены и поведение на реальном железе (A55/браузер) — только чтение; пути с отозванной `DeviceFeature.reversedDepth` (WebGL без расширения, Impeller/GLES) тестами не покрыты — именно там п. 6 проявляется без выгоды.
