# Редактор 3D-моделей на flutter3d — план разработки

Свод от 2026-09-09. Собран из одиннадцати планов по аспектам (ядро меша,
документ и MCP, форматы, рендер и вьюпорт, оболочка, материалы, анимация,
профессиональные режимы, качество, фаза 0, публикация), написанных поверх
проработки [doc/model-editor.md](model-editor.md) и README дизайн-передачи.
Имена пакетов, экранов и решений — оттуда. Всё, что сказано о движке,
аспекты проверили по коду на `239ccf8e`.

Обозначения в таблицах: **р.** — размер (S до недели, M две–три, L месяц и
больше, для одного человека, как в проработке §6); **ф.** — фаза; **⚙** —
правка движка (`engineChange`); **⚠** — пункт конфликтует с ROADMAP или
ARCHITECTURE, разбор в §8; **⇢ X** — пункт слит с X при синтезе, id
сохранён для ссылок. Пакеты: `mesh` = flutter3d_mesh, `core` =
flutter3d_model_core, `mcp` = flutter3d_model_mcp, `app` =
apps/flutter3d_modeler, `engine` = flutter3d, `hw` = flutter3d_hardware и
четыре бэкенда, `geometry` = flutter3d_geometry и `formats` =
flutter3d_formats — два чистых пакета словаря (§3, решение 2026-09-09; до него
в плане стояло одно рабочее имя на оба), `rig` = flutter3d_rig, `cloth` =
flutter3d_cloth, `fbx` = flutter3d_fbx.

Всего 317 пунктов из аспектов плюс 3 добавленных при синтезе (§3), 9
добавленных по критике 2026-09-09 (суффикс `-n`) и 5 добавленных по решениям
владельца 2026-09-09 (суффикс `-d`; история — в конце файла).

---

## 1. Коротко

1. **Один блокер до первой строки: словарь движка живёт в пакете с Flutter
   SDK.** `packages/flutter3d/pubspec.yaml` объявляет `flutter: sdk`, поэтому
   `flutter3d_model_core → flutter3d` из проработки §5.1 проходит сканер и не
   резолвится под `dart pub get`. Пять аспектов пришли к одному выводу
   независимо (mesh-03, doc-00/01, qa-03, p0-09, rel-03): вынести
   `MeshData`/`VertexLayout`/`Shape`/`Ray`/`ModelDocument`/декодеры/писатели в
   чистые пакеты, которые `flutter3d` реэкспортирует. Решение владельца
   2026-09-09 (В1 закрыт): **два пакета**, не один. `flutter3d_geometry` —
   `MeshData`, `VertexLayout`, `Shape`/`LatheShape` и производные, тангенсы,
   `morph_target`, `CpuMesh`, `math/intersections`, `Ray`, `TriangleBvh`;
   `flutter3d_formats` — `ModelDocument`, `SurfaceMaterial`,
   `MaterialDocument`/`MaterialHint`, `lighting_model`, синхронная половина
   `model_loader` (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`,
   `decodeModel`), декодеры gltf/obj/f3d/ktx2/stl, писатели `F3dWriter`,
   `GltfWriter`, `ObjWriter`. `formats` зависит от `geometry`, `mesh` — от
   `geometry`, `model_core` — от обоих, `flutter3d` реэкспортирует оба; в
   engine из форматов остаются только обёртка изолята и `convert_asset`.
   Срок 2026-09-25.
2. **Критический путь — ядро геометрии, а календарь — сумма.** `mesh-11`
   (half-edge на персистентных массивах, L) и цепочка из восьми M вокруг
   него: ≈29 недель от зелёного `main` до туториала, пройденного когортой,
   если бы всё остальное шло параллельно. Пересчитан 2026-09-09 строго по
   столбцу «зависит»: путь идёт через `mesh-13 → mesh-25` (не `mesh-14 → 19 →
   23`) и после `doc-07` — через `doc-20 → rel-09 → rel-16`. Решение
   владельца 2026-09-09: исполнитель **один, с агентами**, поэтому критический
   путь задаёт порядок, а срок фазы 1 — сумма размеров всех её пунктов: 73 S,
   44 M, 3 L ≈ 198 недель одного человека; с агентами на дорожках форматов,
   оверлеев, платформ и локализации — ориентировочно 172 (предположение, §4.3).
2б. **Четыре платформы и равноправный веб с первой версии.** Решение
   2026-09-09: фаза 1 выходит на macOS, в браузере, на Android
   (планшет и телефон) и iOS (iPad и iPhone); раскладки 03/04, перо, тач и
   платформенные конфигурации — пункты фазы 1 (ui-05, ui-19, ui-21), iPad и
   аккаунт Apple Developer покупаются до середины фазы (rel-19d). Веб — не
   «по замеру»: p0-02/p0-08 стали воротами качества, и непройденный порог
   превращается в пункт фазы 1 (JS-сборка как записанное исключение, порции
   вместо изолята, web worker ui-34d при заморозке дольше 1 с). FBX читается
   своим читателем на Dart в `flutter3d_fbx` — отдельная дорожка фазы 2 после
   того, как фаза 1 в руках у пользователей; серверной конвертации нет.
2а. **Фаза 1 получает шаг «материал».** План дизайна относит базовые
   материалы к фазе 1, а сценарий ядра — «чистит меш, правит материал,
   экспортирует в GLB»; до критики единственный путь к материалу в фазе 1 был
   MCP-командой без интерфейса и без текстур. Добавлены mat-04a-n (панель:
   цвет, металличность, шероховатость, назначение, одна текстура) и
   `SetTexture`/`AddImage` в mat-01; приёмка фазы 1 требует цвет и текстуру
   в GLB.
3. **Фаза 0 — числа, а не мнения.** Двенадцать замеров с записанными
   порогами (p0-*): что нужно вебу, чтобы пройти ворота (не «равный или
   просмотр» — веб равноправен по решению 2026-09-09), чанки или журнал для
   снимка истории, `DeviceMesh.overwrite` в фазе 1 или 4, изолят или порции
   на вебе. Срок ответов — 2026-10-05.
4. **Правок движка — 46, и все нужны играм.** Писатели glTF/OBJ/STL,
   `TriangleBvh`, оверлей `MeshOverlay`, `overwriteGeometry`/`overwriteTexture`,
   `Pose` и IK, счётчик треугольников, LOD в `ModelDocument`, энкодер текстур
   (уже в ROADMAP). Каждая — через конформанс или эталонный кадр (§6).
   Читатель FBX правкой движка не является: это отдельный пакет над `formats`.
5. **Тридцать семь расхождений с ROADMAP, ARCHITECTURE, проработкой и
   дизайном**, каждое с решением (§7); пять главных: «zero engine changes for
   the editor», `apply`/`revert`, «no node-graph materials», «eight lights is
   a ceiling», soft bodies «committed» без строки в Committed. Два добавлены
   по критике: композиция ассетов в сцене (№ 36, закрыт 2026-09-09 —
   расстановка ассетов входит в фазу 2) и градиент вьюпорта (№ 37).
6. **Три дублирующих реализации сведены к одной**: BVH по треугольникам
   (mesh-20 / view-09 / p0-10), формат проекта (doc-09/10 / fmt-17),
   модификаторы (mesh-40 / mat-18 / doc-23), GltfWriter скинов (fmt-07 /
   anim-26), упрощение и развёртка (mesh-70/71 / pro-lod / pro-uv),
   веса (mesh-60 / anim-09). Где кто живёт — §3.
7. **Фазы 2–4 оценены с оговоркой.** Пункты фаз 2–4 (модификаторы, булевы,
   риг, скульптинг, симуляции) написаны до того, как фаза 0 дала числа;
   размеры L там — порядок величины, зависимости — по лучшему знанию кода.
8. **Открытых вопросов — 63 в десяти группах после слияния дубликатов**
   (§8; из 87 строк В1, Ж2 и Г4 закрыты по критике 2026-09-09, ещё 21 — А2,
   Б1, Б3, Б8, Б9, В3, В5, В8, Г2, Г9, Д7, Е1, Е2, Е5, Е8, Е11, Е12n, Ж1, Ж4,
   И1, К2 — решениями владельца 2026-09-09, В1 переписан); шесть из
   оставшихся нужны до старта фазы 1 (перечислены в §5.2), остальные — до
   своей фазы.

---

## 2. Аспекты

### 2.1 Ядро меша (`mesh-`)

Половинно-рёберный `EditMesh` на `Int32List`/`Float32List` с персистентными
чанками, конвертация в/из `MeshData`, выделение, операции фаз 1–2,
модификаторы, проверки, параметрические объекты с квадовой топологией, BSP-булевы,
BVH для CPU-пикинга. В движке уже есть словарь треугольников, генераторы `Shape`,
тангенсы по Ленгьелу, `rayTriangle`, `SceneBvh` по сферам — редактируемой
топологии нет вовсе. Две находки по коду: `flutter3d` тянет Flutter SDK
(mesh-03), а `Shape.build()` отдаёт триангулированный суп с дублями швов,
непригодный для loop cut и Catmull-Clark (mesh-28).

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| mesh-00 | Скелет пакета: pubspec `resolution: workspace`, баррел, тест; регистрация в workspace, `flatDartPackages`, `notARepeatableStep` (иначе `math.sin` запрещён), порядок публикации §16, таблица §3.2. ⇢ qa-02, rel-02/03 | mesh | S | 0 | — | `tool/structure.dart` и `tool/ci.sh` зелёные с пакетом |
| mesh-01 | Спайк 0.2: `EditMesh` на Int32List, куб, экструзия грани, веер, вывод в массивы, кадр через `flutter3d_testing.renderFrame`. ⇢ p0-04 (пороги оттуда) | mesh | M | 0 | mesh-00 | V−E+F=2, объём вырос на площадь×h, кадр `mesh-spike-extrude.png`, замер `toMeshData` 50/200k в doc |
| mesh-02 | Замер 0.3: чанкованный CoW-вектор (256/1024/4096) на 200k вершин, 1 % подряд и 1 % случайно; альтернатива — разреженный патч. ⇢ p0-05 | mesh | S | 0 | mesh-01 | таблица чанк × выборка → байт/мкс; решение о чанке и патче |
| mesh-03 ⚙⚠ | Вынести `geometry/*` (mesh_data, vertex_layout, shape, lathe, tangents, morph, CpuMesh) и `math/intersections.dart` в чистый пакет `flutter3d_geometry`, `flutter3d` реэкспортирует. Решение 2026-09-09: это первый из двух пакетов словаря, второй (`formats`) — doc-01 (§3) | engine + geometry | M | 0 | mesh-00 | сканер зелёный, 4322 теста без правки импортов, `bench_geometry.dart` собирается AOT отдельным `main` без `MeshGeometry` (агрегатный `bench.dart` тянет `GraphicsDevice → Widget` и AOT не собирается — ARCHITECTURE §14) |
| mesh-04 | AOT-бенч пакета по образцу `packages/flutter3d/tool/bench`: `toMeshData`, снимок, `fromMeshData`, BVH, экструзия ×1000 | mesh | S | 0 | mesh-01 | бинарник печатает нс/элемент, числа в doc, разброс <5 % |
| mesh-10 | `PersistentInt32Vector`/`PersistentFloat32Vector` (чанки, CoW, `Transient` с токеном владения, `freeze`, `sharedChunksWith`) + `SparsePatch` по итогу mesh-02 | mesh | M | 1 | mesh-02 | старое значение неизменно, N−1 чанков разделено; транзиент копирует чанк один раз |
| mesh-11 | `EditMesh`: origin/next/twin/face, outgoing, halfEdge грани, грани любой валентности, надгробия + `compact()`→`IdRemap`; `EditMeshBuilder` с Эйлеровыми примитивами; итераторы без аллокаций; `validate()` | mesh | L | 1 | mesh-10, mesh-01 | куб/тор/плоскость: χ, границы, `validate()` после каждой операции; мутация «не обновлять outgoing» ловится |
| mesh-12 | Слои атрибутов: positions, joints/weights по вершине; uv0, color по углу; sharp/seam/crease по ребру; materialSlot/smooth по грани; правила наследования при split в builder. Правило заполнения `uv0` при операциях (добавлено по критике): split — интерполяция по углу, extrude — копия угла исходной грани на боковые квады, новые грани без источника — нулевой UV с пометкой в `OpResult`. Флаг `seam` закрывает pro-uv-01 | mesh | M | 1 | mesh-11 | split посередине: UV среднее, веса нормированы; отсутствующий слой — нейтральное значение |
| mesh-13 | `EditMesh.fromMeshData`: сваривание по позиции (eps от bounds), twins, ремонт ориентации BFS, расщепление неманифолда, `ImportReport` | mesh | M | 1 | mesh-11, 12, 03 | `CuboidShape` → 8/12/6 (треугольники); сфера: шов сварен; три грани на ребре → `splitNonManifold=1` |
| mesh-14 | `MeshLayoutPlan.build` (триангуляция, нормали по углам, ключ GPU-вершины → индексы, `triangleToFace`, `gpuVertexToVertex`) + `fillVertices` без хеша; `toMeshData` по `materialSlot` | mesh | M | 1 | mesh-15, 16, 12, 03 | куб sharp → 24 вершины/36 индексов, нормали = `CuboidShape`; `fillVertices` меняет ровно указанные строки |
| mesh-15 | Триангуляция n-гонов: квад по короткой диагонали с планарностью, ear clipping по Ньюэллу, веер при провале + пометка; без аллокаций | mesh | S | 1 | mesh-11 | L-образный 6-гон → 4 треугольника; квад-«бабочка» выбирает диагональ по планарности |
| mesh-16 | `faceNormals`, `cornerNormals` с разрывом по sharp/углу/smooth, `flipNormals`, `makeConsistent` | mesh | S | 1 | mesh-12 | куб sharp → нормали граней; сфера в 6° от радиальных; flip меняет знак объёма |
| mesh-17 | Тангенсы через `withGeneratedTangents`; тест знака `w` против `CuboidShape`/`PlaneShape` и зеркального острова | mesh | S | 1 | mesh-14 | тест знаков; кадр `mesh-normal-map` в app совпадает с кубом движка |
| mesh-18 | `toBytes`/`fromBytes`: секции с выравниванием 4, неизвестная пропускается, детерминизм | mesh | S | 1 | mesh-12 | round-trip побайтно; лишняя секция читается; мутация «не выравнивать» → RangeError |
| mesh-19 ⚠ | `Selection` (sealed `SelectionLevel`, сортированный Int32List, активный элемент), конверсии уровней, `edgeLoop`, `edgeRing`, grow/shrink, linked, boundary, `selectByMaterialSlot` | mesh | M | 1 | mesh-11 | тор 8×8: loop=ring=8; куб: loop стоит на валентности 3; мутация «ring без проверки квада» ловится |
| mesh-20 | `MeshBvh` по треугольникам плана поверх `TriangleBvh` из view-09: `refit(positions)`, `rebuild(plan)`, `queryRay/Aabb/Frustum`. Одна реализация `TriangleBvh` на mesh-20/view-09/p0-10 (§3); владелец класса — view-09 | mesh | M | 1 | mesh-14, 03, view-09 | 10 000 лучей = перебор; refit = rebuild; бенч 200k в doc |
| mesh-21 | `MeshPicker`: `faceAt`, `vertexNear`/`edgeNear` в радиусе с visibleOnly, `inFrustum` для рамки | mesh | S | 1 | mesh-20, 19 | клик в центр грани куба — грань; рамка вокруг половины куба — 4 или 8 вершин |
| mesh-22 | `translate/rotate/scaleSelection` с pivot; единая сигнатура `op(EditMesh, Selection, Params) → OpResult` | mesh | S | 1 | mesh-19, 10 | туда-обратно побайтно; масштаб 2 → объём ×8; топология разделена 100 % |
| mesh-23 | `extrudeFaces` (регион/individual, боковые квады с UV), `extrudeEdges` (только граничные) | mesh | M | 1 | mesh-19, 11, 12 | грань куба: V=12, E=20, F=10, χ=2; две смежные грани → 6 боковых квадов; UV боковых квадов подтверждены тестом (углы 0..1 по высоте выдавливания) |
| mesh-24 | `loopCut(edge, cuts, factor)` по `edgeRing`, `splitEdge`+`splitFace`, интерполяция атрибутов | mesh | M | 1 | mesh-19, 12 | цилиндр 16: +16 V, +32 E, +16 F, все квады; тор — замкнутая петля |
| mesh-25 | `mergeByDistance`, `dissolveEdge`, `dissolveVertex`, `mergeAt` | mesh | M | 1 | mesh-11, 19, 13 | dissolve диагоналей `fromMeshData(Cuboid)` → 6 квадов; два куба со смежной гранью сливаются |
| mesh-26 | `delete` по уровням, `separate` по компонентам, `duplicate`, `split`; `IdRemap` | mesh | S | 1 | mesh-19, 11 | удаление грани куба → 6 граничных рёбер; separate двух кубов → 2 меша |
| mesh-27 | `MeshChecks`: ngons, nonManifoldEdges, boundaryEdges, isolatedVertices, degenerate, inverted, duplicateVertices, χ по компонентам; `MeshIssue(kind, ids)` | mesh | S | 1 | mesh-11, 15, 13 | по тесту на функцию с мутацией; `signedVolume` подтверждает inverted |
| mesh-28 ⚠ | Sealed `ParametricShape` (Cuboid/Plane/Cylinder/Sphere/Torus/Lathe со спеками движка) → `toEditMesh()` с квадами, sharp вместо дублей, n-гон-крышки; UV по углам как у `Shape.build()` (`VertexLayout.standard` несёт `texcoord`) — иначе куб фазы 1 в GLB не принимает текстуру | mesh | M | 1 | mesh-11, 12, 16 | цилиндр 16: `validate()`, `edgeRing` замкнут, объём >0; мутация «без sharp на повторённой точке» ловится нормалями; слой `uv0` заполнен у всех шести фигур |
| mesh-29 | Parity-тест `ParametricShape.toEditMesh().toMeshData()` против `Shape.build()` (объём, bounds, множество треугольников, 24 GPU-вершины куба, `texcoord` с допуском 1e-6) | mesh | S | 1 | mesh-28, 14, 13 | шесть пар, стандартные и нестандартные параметры; texcoord совпадает по углам |
| mesh-30 | `EditMesh`/`Selection`/`OpResult` пригодны для `Isolate.run` (без замыканий), `TransferableTypedData` через mesh-18; документировано «на вебе — основной поток порциями или worker (ui-34d)» | mesh | S | 1 | mesh-11, 18 | экструзия в изоляте = на месте; время передачи 200k в doc |
| mesh-31 | Замеры фазы 1: fromMeshData, план/заполнение, BVH build/refit, экструзия ×1000, loop cut ×256, снимок 1 %; AOT-сборка в `tool/ci.sh` | mesh | S | 1 | mesh-04, 14, 20, 23, 24 | ≥8 строк в doc, разброс <5 % |
| mesh-32 | Фаззинг: `Random(1234)`, 500 операций × 3 сида, `validate()` + `nonManifoldEdges` пуст + round-trip после каждой; минимизация печатает Dart-код. ⇢ qa-07 | mesh | S | 1 | mesh-22..27 | <10 с; мутация в `dissolveEdge` ловится за 50 шагов |
| mesh-33 | `lib/testing.dart` с фикстурами; кадры `mesh-extrude`, `mesh-loop-cut`, `mesh-lathe`, `mesh-sharp-vs-smooth` в тестах app, не в 43 сценах | mesh + app | S | 1 | mesh-14, 23, 24, 28 | 4 PNG, нулевой допуск; мутация «без sharp» меняет кадр |
| mesh-40 | `sealed class Modifier { apply(base, ctx); toJson }`, `ModifierContext`, `ModifierStack.evaluate` = fold с мемоизацией по identity базы. Единственное место типа `Modifier` (§3) | mesh | M | 2 | mesh-11 | стек считается один раз при двух evaluate; round-trip JSON |
| mesh-41 | `mirror(plane, mergeDistance, bisect, flipUv)` + `MirrorModifier` | mesh | S | 2 | mesh-40, 25, 16 | половина куба → замкнутый куб 8/12/6; мутация «не переворачивать копию» ловится объёмом |
| mesh-42 | `ArrayModifier(count, offset, mergeDistance)` с детерминированными id | mesh | S | 2 | mesh-40, 25 | 4 копии куба → 32 вершины, объём ×4 |
| mesh-43 | `insetFaces(thickness, depth, individual)` с поправкой на угол | mesh | S | 2 | mesh-23 | грань куба: +4 V, +4 квада, площадь (1−0.2)²; мутация без поправки ловится на 30° |
| mesh-44 | `bevelEdges/Vertices(width, segments, profile, clampOverlap)`, угловые n-гоны | mesh | L | 2 | mesh-11, 19, 12, 15 | 12 рёбер куба, segments=1 → 24 V, 26 F, χ=2; `boundaryEdges`=0 |
| mesh-45 | Catmull-Clark с crease (Pixar), UV по углам, `SubdivisionModifier(levels, viewLevels)`, `subdivideSimple` | mesh | M | 2 | mesh-11, 12, 40 | куб уровня 1 → 26 V, 24 квада; crease=1 сохраняет объём |
| mesh-46 | `smoothVertices` (Лаплас + HC при preserveVolume), `SmoothModifier` | mesh | S | 2 | mesh-19, 40 | сфера 10 итераций: усадка <5 % с HC; топология разделена 100 % |
| mesh-47 | BSP-булевы (csg.js): `CsgPolygon`, `CsgNode` на явном стеке, eps по bounds, бюджет полигонов, детектор копланарности; вход через план, выход через `fromPolygons` | mesh | L | 2 | mesh-13, 15, 30, 27 | cube ∪ cube объём аналитически; cube − sphere в 1 %; копланарный случай предупреждает, не падает |
| mesh-48 | `BooleanModifier(operation, operandId, transforms)` через `ModifierContext`, циклы отклоняются | mesh | S | 2 | mesh-47, 40 | стек = операция по объёму; смена трансформа операнда инвалидирует кэш |
| mesh-49 | Кадры фазы 2: bevel, Catmull-Clark 2, cube − sphere, зеркальная ваза | app + mesh | S | 2 | mesh-44, 45, 47, 41, 33 | 4 PNG, нулевой допуск |
| mesh-60 | Веса через операции: накопление до 8 пар, усечение до `maxInfluences`, перенормировка; `normalizeWeights`, `limitInfluences`, `weightsOf`. Хранилище для anim-09 (§3) | mesh | M | 3 | mesh-12, 24, 44, 45 | loop cut (1,0)/(0,1) → (0.5,0.5); 5 костей → 4, сумма 1±1e-6 |
| mesh-61 | `ShapeKey(name, positions)` полными слоями, split применяется ко всем ключам, `blend(weights)` | mesh | M | 3 | mesh-12, 13 | импорт 2 targets → 2 ключа; loop cut сохраняет ключи |
| mesh-62 | `toMeshData` с `morphTargets` через `gpuVertexToVertex` | mesh | S | 3 | mesh-61, 14 | round-trip дельт; мутация «по вершинам EditMesh» → `ArgumentError` MeshData |
| mesh-70 | QEM-упрощение с UV/швами/весами. ⇢ pro-lod-01/02 (одна реализация, §4) | mesh | L | 4 | mesh-14, 60, 27 | см. pro-lod-01/02 |
| mesh-71 | UV: острова, LSCM, упаковка, растяжение. ⇢ pro-uv-02..05 | mesh | L | 4 | mesh-12, 19 | см. pro-uv-* |
| mesh-72 ⚠ | `SculptSession` над `EditMesh` с патч-слоем, кисти, refit. ⇢ pro-sc-02..07 (структура решена 2026-09-09: `SculptMesh` с мультиразрешением, Б8/Б9; id остаётся для ссылок) | mesh | L | 4 | mesh-10, 20, 16, 31 | см. pro-sc-* |
| mesh-73 | Спайк изотропного remesh. ⇢ pro-rt-01 | mesh | M | 4 | mesh-20, 25, 46 | см. pro-rt-01 |

### 2.2 Документ, команды, MCP (`doc-`)

Повторить форму редактора уровней (sealed-команда с `name/says/arguments/apply/
fromJson`, история с транзакциями, сессия и таблица инструментов из списка
имён команд, сценарий через `StreamChannelController`), но поверх неизменяемого
`ModelProject` со структурным разделением вместо снимков `level.toJson()`.
Найдено по коду: сканер ищет только текст `package:flutter/`, транзитивную
зависимость через `flutter3d` не видит (doc-00); ROADMAP пишет `apply`/`revert`,
код хранит снимки, для мешей план — прежнее значение (doc-29).

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| doc-00 ⚠ | Спайк: пустой пакет с зависимостью на `flutter3d`, `dart pub get`/`dart test` из каталога; результат в doc §6 п. 0.4. ⇢ p0-09, rel-04 | core | S | 0 | — | вывод зафиксирован; при отказе — doc-01; иначе правило на транзитивную SDK-зависимость (qa-03) |
| doc-01 ⚙⚠ | Вынести файлы без Flutter-импортов в чистый пакет: geometry/*, assets/{model_document, model_node, surface_material, material_document, material_hint}, `render/lighting_model.dart` (его импортируют material_document и material_hint; сам без импортов — переносится как есть), f3d/*, gltf/* (кроме resolvers), obj/*, fmat/*, animation/{clip, track}; `model_loader.dart` делится: синхронная половина (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`, `decodeModel`) — в `formats`, `kIsWeb` → `const bool.fromEnvironment('dart.library.js_interop')`, изолятная половина (`ModelLoadRequest`, `loadModelInIsolate`) остаётся в engine; путь экземпции `ModelFormat` в `repository.dart` обновляется. `flutter3d` реэкспортирует; в `flatDartPackages`, workspace, §16, §3.2, `ci.sh`. Решение 2026-09-09: пакетов два — `flutter3d_geometry` (mesh-03) и `flutter3d_formats` (этот пункт: всё перечисленное здесь, кроме geometry/*), `formats` зависит от `geometry`; порядок публикации geometry → formats → flutter3d | engine + geometry + formats | M | 0 | doc-00, mesh-03 | `dart test` в обоих пакетах зелёный; 43 сцены и golden без изменений; `publish_check.sh` принимает порядок; `decodeModel` вызывается из `dart test` пакета `formats` без Flutter; число пакетов в README/§3.2/§16 сдвинуто в том же коммите (28 → 30) |
| doc-02 | Каркас `flutter3d_model_core`: pubspec, баррел, LICENSE/CHANGELOG/README; регистрация в списках. ⇢ qa-02, rel-02/03 | core | S | 1 | doc-00 | сканер и `ci.sh` зелёные с пустым тестом |
| doc-03 ⚠ | `ModelProject {profile, objects, materials, images, skeletons, clips, nextId}`; `ModelObject` со стабильными id и `version`; sealed `Geometry`: Parametric / Edited(EditMesh) / Imported(MeshData); `withObject`/`copyWith` со структурным разделением | core | M | 1 | doc-02, mesh-11 | `withObject` разделяет нетронутое (`identical`); id уникален после delete+add |
| doc-04 ⚠ | `Selection {mode, submode, objects, level, elements}` с JSON и `says`; `Modeling` — сессия над документом, все изменения через историю | core | S | 1 | doc-03 | selection переживает undo, если id есть; JSON round-trip |
| doc-05 ⚠ | Sealed `ModelCommand` (`name`, `says`, `arguments`, `toJson`, `fromJson` → null, `apply(project, selection) → Outcome?`), `modelCommandNames`; тест-таблица по каждому имени | core | S | 1 | doc-04 | 100 % имён покрыты образцами; неполный JSON → null, не исключение |
| doc-06 | Объектные команды: `AddPrimitive`, `AddLathe`, `SetParametric`, `BakeToMesh`, `MoveBy/RotateBy/ScaleBy`, `SetTransform`, `Rename`, `SetParent`, `Delete`, `Duplicate`, `SetField`, `AssignMaterial`, `SetOrigin` (пивот объекта: центр bounds / низ / курсор) и `ApplyTransform` (запечь трансформацию узла в геометрию — добавлено по критике, частый шаг перед экспортом в движок); id в аргументах, не из selection | core | M | 1 | doc-05 | тест на каждую с мутацией; `Duplicate` даёт новые id; `SetField` отказывает на невалидном; `ApplyTransform` даёт единичную матрицу узла и те же мировые позиции |
| doc-07 | Мешевые команды с `Selection` в аргументах: `Move/Rotate/ScaleElements`, `Extrude`, `LoopCut`, `MergeByDistance`, `DissolveEdges`, `DeleteElements`, `Separate`, `Triangulate`, `RecalculateNormals`; отказ на Parametric | core | M | 1 | doc-05, mesh-22..26 | счётчики на кубе после каждой; JSON round-trip; 100 `MoveElements` на 200k в бюджете mesh |
| doc-08 ⚠ | `ModelHistory`: `run`, `transaction`, undo/redo, `undoSays`, `isDirty`, `amend(replacement)` для карточки операции; глубина 64 + лимит по байтам чанков | core | M | 1 | doc-05 | drag из 100 команд — один шаг; `amend` не растит стек; шаг после сдвига 1 % из 200k <10 % полной копии |
| doc-09 | `project_format.dart`: магия, версия, заголовок 16, директория секций, выравнивание 4; секции manifest/materials/editMeshes/importedMeshes/images/skins/animations/journal/history (последняя — doc-31d, решение 2026-09-09); неизвестная пропускается, будущая версия — отказ. Расширение `.f3dproj` (решение 2026-09-09, Г2); магия и место автосохранения — Г1 | core | S | 1 | doc-03 | тест на константы (кратность 4, не индекс enum) |
| doc-10 ⚠ | `ProjectWriter`/`ProjectReader`: интернирование строк, канонический JSON (сортированные ключи, одно округление), `warnings`, внешние `.fmat` относительным путём. ⇢ fmt-17 (§3) | core | L | 1 | doc-09, doc-03 | write→read→write побайтно на проекте с тремя геометриями; версия+1 — отказ; 200k вершин <100 мс |
| doc-11 ⚠ | `ModelProject.fromModelDocument(document, ImportOptions {scale, upAxis})` + `ImportReport {issues, counts}`: nodes→объекты, surfaces→Imported, skins→skeletons, animations→clips, morphWeights; `ImportOptions` (добавлено по критике): множитель единиц (STL обычно в мм, OBJ без единиц) и ось вверх (Z-up → Y-up поворотом корня), по умолчанию 1.0 / Y | core | M | 1 | doc-03, doc-13 | BoxAnimated/simple_skin: объекты = узлы, треугольники = `triangleCount`; warnings декодера дословно; `scale: 0.001` даёт bounds в 1000 раз меньше, `upAxis: z` — тот же куб, повёрнутый на −90° по X |
| doc-11a-n ⁶ *(добавлено по критике)* | Безусловно (решение 2026-09-09, §7 № 36 и Ж4 закрыты): `ImportInto(project, document, options)` — слияние импортированного документа в существующий проект (новые объекты, дедуп материалов и изображений по хэшу, скелеты как новые), в отличие от doc-11, который создаёт проект заново. На нём стоит расстановка нескольких ассетов в режиме «Сцена» (mat-24) | core | M | 2 | doc-11, doc-06, mat-01 | два импорта подряд → объекты обоих, один `SurfaceMaterial` на одинаковый материал; отмена второго импорта возвращает первый проект по `identical` |
| doc-12 ⚠ | `ProjectModelDocument extends ModelDocument` с кэшем `MeshData` по `(ObjectId, version)`; экспорт — session-verb; `.f3d` сегодня, GLB/OBJ через fmt | core | M | 1 | doc-03, doc-06 | проект→документ→`F3dWriter`→parse: равны; повторный экспорт отдаёт `identical` MeshData |
| doc-13 | `ProjectProfile {name, target, maxTriangles, maxJoints ≤ 64, maxInfluences, maxTextureSize, maxTextureBytes, requireTriangles, requireManifold}` с пресетами и `profileHints` из `MaterialHint` | core | S | 1 | doc-02 | JSON round-trip; тест-зеркало на `Skeleton.maxJoints` в app |
| doc-14 ⚠ | `ExportReadiness.check(project) → List<Issue>` с кэшем по версии объекта; правила бюджета, n-гонов, манифолдности, костей, текстур, слотов, имён; правило «вершин с морф-целями > `maxTextureSize` профиля» (`MorphTexture` кладёт колонку на вершину — добавлено по критике, риск 28); `headline` для статуса | core | M | 1 | doc-13, 03, 15 | по тесту на правило с мутацией; после правки одного объекта проверяется только он; объект с 5000 морфируемых вершин при `maxTextureSize: 4096` даёт Issue |
| doc-15 | `imageDimensions(bytes)` для PNG/JPEG/KTX2 без декодера | core | S | 1 | doc-02 | три фикстуры; обрезанный файл → null |
| doc-16 | `CommandJournal`: JSON Lines с метками транзакций, `replay`; отказ с номером строки | core | S | 1 | doc-08, doc-10 | 30 команд → журнал → replay → те же байты `ProjectWriter` |
| doc-17 ⚠ | `AutosavePolicy` и чистые функции `shouldSave`, `recoveryPathFor`, `RecoveryDecision`; таймер, атомарная запись и диалог — в app (ui-18). ⇢ fmt-18 | core | S | 1 | doc-10, 08, 16 | границы интервала; чистый документ не сохраняется; выбор свежего восстановления |
| doc-18 | `contentsOf(project) → List<Listed>` в порядке objects; `materialsOf`, `skeletonsOf`, `clipsOf` | core | S | 1 | doc-03 | стабилен между вызовами; каждый объект ровно раз |
| doc-19 ⚠ | Каркас `flutter3d_model_mcp`: `ModelSession` (listing, select, run, undo, redo, check, save, export, import, journal), `ModelMcpServer`, `bin/model_mcp.dart` (заглушка `--help` заводится в rel-02, здесь — настоящий сервер) создаёт проект по несуществующему пути | mcp | S | 1 | doc-08, 10, 18, 14 | `dart run flutter3d_model_mcp:model_mcp new.proj` отвечает на `tools/list`; та же проверка в контейнере без Flutter SDK (скрипт rel-04) |
| doc-20 | `ModelTool` из `modelCommandNames`, схемы `_vector/_ids/_selection`, сессионные verbs; `tools_test`: каждое имя предложено, всё сверх — именованное множество, описания >40 символов | mcp | M | 1 | doc-19, 05, 06, 07 | добавление команды без инструмента — красный тест |
| doc-21 ⚠ | Сценарий «агент строит стол» через реальный протокол: примитивы, трансформации, материал, check, save, export GLB и `.f3d`; дифф с `fixtures/table.proj`, `table.glb`, `table.jsonl`; отказы как `isError`. ⇢ qa-12 | mcp | M | 1 | doc-20, 12, 16 | зелёный на ubuntu и macOS с одними байтами |
| doc-22 | Skills `project-document`, `editing-order`, `what-it-refuses`; README с таблицей инструментов; CHANGELOG. ⇢ rel-14 (тест на skills в архиве) | mcp | S | 1 | doc-20 | каждая строка отказов имеет тест с той же фразой |
| doc-23 ⚠ | Команды стека: `AddModifier`, `SetModifierField`, `ToggleModifier`, `ReorderModifier`, `RemoveModifier`, `ApplyModifier`; тип `Modifier` — из mesh-40, тяжёлое — через doc-24. ⇢ mat-19 | core | M | 2 | doc-06, doc-12 | `ApplyModifier` = экспорт с включённым модификатором; round-trip через doc-10 |
| doc-24 ⚠ | `JobRequest` — чистая функция над значениями; приложение исполняет через `Isolate.run` или на основном потоке порциями; `ApplyJobResult` одним шагом истории, отказ по устаревшей `version`. ⇢ pro-job-01, anim-25 (один раннер, §4) | core | M | 2 | doc-23, doc-08 | результат по устаревшей версии отвергнут; JobRequest сериализуем |
| doc-25 ⚙⚠ | Команды материалов: `AddMaterial`, `SetMaterialField` через JSON-кодек `SurfaceMaterial`, `SetTexture`, `AddImage`, `LinkFmat`, `RemoveMaterial`. ⇢ mat-01 (фаза 1, включая `SetTexture`/`AddImage` — перенесены в фазу 1 по критике) и mat-08 (`LinkFmat`, фаза 2); правка движка (публичный кодек `SurfaceMaterial ↔ Map` в fmat.dart, S) остаётся | core + engine | M | 2 | doc-06, doc-15 | см. mat-01/08 |
| doc-26 ⚠ | Команды скелетов и клипов: `AddSkeleton`, `AddJoint`, `SetJointRest`, `BindSkin`, `AddClip`, `SetKey`, `SetInterpolation`… ⇢ anim-03, anim-04, anim-29 | core | L | 3 | doc-11, 12, 10 | см. anim-* |
| doc-27 | Команды морф-целей и веса морфов. ⇢ anim-19 | core | M | 3 | doc-26 | см. anim-19 |
| doc-28 | Миграции формата: фикстуры `test/fixtures/v1/*.proj` навсегда; версия растёт только при смене смысла; CHANGELOG при каждой раскладке | core | S | 2 | doc-10 | каждая фикстура читается; бамп без фикстуры — красный тест |
| doc-29 ⚠ | ARCHITECTURE §8.7 о формате проекта и трёх моделях отмены (§8.6 занимает fmt-16 Writers; сегодня в ARCHITECTURE §8.1–8.5); §3.2, §16; ROADMAP без «apply and revert»; doc §5.1 про сканер | docs | S | 1 | doc-08, doc-10 | сканер зелёный; ROADMAP не содержит `revert` в абзаце про редактор |
| doc-30 | `tool/ci.sh` читает список `dart test` из `flatDartPackages`. ⇢ qa-04 | tool | S | 0 | — | см. qa-04 |
| doc-31d *(добавлено по решениям 2026-09-09)* | История в файле проекта (Г2 закрыт: история пишется в файл): секция `history` в контейнере doc-09 — список шагов, каждый шаг = `says` + команда в JSON (та же форма, что в журнале doc-16) + ссылки на прежние значения через чанки, которые уже лежат в секциях `editMeshes`/`materials` как блобы: неизменённый чанк записывается один раз и адресуется по индексу, так структурное разделение из памяти переносится в файл; лимит глубины и байтов из Г5 (doc-08) применяется и к файлу; `ProjectWriter(includeHistory:)`; «сохранить без истории» — опция экспорта проекта (ui-33d); журнал doc-16 остаётся | core | M | 1 | doc-08, doc-10, doc-16 | round-trip: три команды → сохранить → открыть → отменить три шага → проект равен исходному, нетронутые чанки `identical`; файл с историей ≤ файл без неё + Σ изменённых чанков + JSON шагов; файл без секции `history` открывается с пустой историей; лимит Г5 срезает хвост при записи |

### 2.3 Форматы (`fmt-`)

Писатель glTF/GLB как зеркало `F3dWriter` поверх того же `ModelDocument` —
единственный выход редактора в движок и единственный пункт, полезный движку без
редактора; рядом `ObjWriter` с `.mtl`, `StlDecoder`, энкодер текстур из ROADMAP.
В репозитории три декодера, `F3dWriter`, KTX2-читатель, `convert_asset.dart` только
в `.f3d`; ни одного писателя glTF/OBJ/STL на Dart. Словарь `ModelDocument` не
хранит имена glTF-мешей, extras, `asset.generator`, URI картинок, признак авторских
атрибутов, четыре mip-варианта сэмплера, `KHR_texture_transform` — без части
этого round-trip не сойдётся.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| fmt-01 ⚙ | `compareModelDocuments(a, b)` из `_compare` конвертера в lib с категориями (структура, байты, материалы, узлы, скины, клипы, морфы) | formats | S | 1 | — | тест на каждую категорию через поломку; конвертер даёт тот же результат |
| fmt-02 ⚙ | `PlainModelDocument` вместо `_FakeDocument` в тестах; `sniffImageMimeType` (PNG/JPEG/KTX2/WebP) | formats | S | 1 | — | тесты переведены; sniff на четыре магии и пустой буфер |
| fmt-03 ⚙ | `ModelSurface.authoredAttributes` из декодеров; `.f3d` секция `surfaceAttributes` (kind 17); писатели пропускают сгенерированное | formats | S | 1 | — | Box.glb → {position, normal}; старый `.f3d` читается как «все» |
| fmt-04 ⚙ | `ModelSurface.meshName`, `ModelDocument.asset`, `EncodedImage.sourceUri`; секции `meshNames` (18), `asset` (19), `imageUris` (20) | formats | S | 1 | — | BoxTextured → `meshName == 'Mesh'`; старые `.f3d` с null |
| fmt-05 ⚙ | `TextureSampling.mipLinear`, разбор 9984–9987, бит 7 в `F3dSamplingFlags`, `toGltfFilters()` | formats | S | 1 | — | 9985 → mipLinear=false; обратно 9985; golden не меняется |
| fmt-06 ⚙ | `GltfWriter` + part-файлы: де-интерливинг по `floatOffsetOf`, u16 индексы при `fitsIn16BitIndices`, дедуп мешей/сэмплеров/текстур, узлы из `nodes`, материалы с расширениями, картинки в GLB/файлы; `GlbContainer.encode` из `buildGlb`. Живёт в чистом пакете `formats`, как и `F3dWriter` после переезда — иначе `flutter3d_model_mcp` не экспортирует GLB (В1 закрыт 2026-09-09) | formats | M | 1 | fmt-01..05, doc-01 | 8 моделей: decode→writeGlb→decode, `compareModelDocuments` пуст; мутации выравнивания/min-max/кватерниона ловятся; `dart test` пакета `formats` пишет GLB без Flutter SDK |
| fmt-07 ⚙⚠ | `gltf_writer_animation.dart`: skins, animations (`AnimationInterpolation.toGltf`, CUBICSPLINE тройки, weights), morph targets с `targetNames`. Один писатель на fmt-07/anim-26 (§3) | formats | M | 1 | fmt-06 | 7 риггированных моделей round-trip; поза t=0.5 через `AnimationPlayer` совпадает |
| fmt-08 ⚙ | `ObjWriter` + `.mtl`: дедуп v/vt/vn, V-флип, `MeshData.transformed`, обратная аппроксимация Kd/Ns/Ks, `map_Kd`, warnings о потерянном | formats | M | 1 | fmt-01, 02, 04, doc-01 | teapot round-trip по множеству треугольников; Box.glb → 12 треугольников с Kd |
| fmt-09 ⚙⚠ | `StlLoader implements ModelDecoder`: бинарный (`84 + 50·count` как детектор), ASCII, `StlNormals`, warnings; `ModelFormat.stl`, снифф до OBJ; `convert_asset`. `ModelDecoder`/`ModelFormat`/`sniffModelFormat` живут в синхронной половине `model_loader.dart`, которую doc-01 переносит в `formats` | formats | M | 1 | fmt-03, doc-01 | пять фикстур через `build_stl.dart`; `sniffModelFormat` на бинарном STL → stl; sendable; декодируется из `dart test` пакета без Flutter |
| fmt-10 | Дифференциальные кадры: оригинал против перечитанного экспорта через `renderFrame`, нулевой допуск; не в `kGoldenScenes` | cpu | M | 1 | fmt-06, 07, 08 | зелёный на всех моделях; мутация сдвига offset нормалей даёт разницу |
| fmt-11 ⚙ | Валидация экспорта пакетом `gltf` (Khronos, Dart) или `npx gltf-validator` в `ci.sh`, или минимальный чекер. ⇢ qa-09 | engine + tool | S | 1 | fmt-06 | ноль ошибок; сломанный min/max даёт ошибку |
| fmt-12 ⚙ | `warnings` у всех писателей (и `F3dWriter`), `ExportReport {files, writerWarnings, differences}` = записать → перечитать → сравнить | formats | S | 1 | fmt-01, 06, 08 | RiggedFigure в OBJ → предупреждение о скине; Box.glb → пустые differences |
| fmt-13 ⚙⚠ | `ModelWriteRequest`, `encodeModelInIsolate` с `kIsWeb`-фолбэком, Timeline-спан — обёртка над писателями из `formats`; единственный кусок форматов, которому нужен Flutter | engine | S | 1 | fmt-06, fmt-08 | байты через изолят = синхронные; замер 200k в doc |
| fmt-14 ⚙ | `convert_asset -f glb|gltf|obj|stl|f3d`, `--textures keep|external`, печать `ExportReport` | engine | S | 1 | fmt-12, fmt-13 | `teapot.f3d -f glb` открывает лоадер и валидатор |
| fmt-15 ⚙⚠ | Draco/meshopt-примитив без bufferView пропускается с предупреждением, а не читается нулями; `hasBufferView` | formats | S | 1 | — | рукописный glTF → 0 surfaces и предупреждение |
| fmt-16 ⚙ | Документы и сканер: §8.1 четыре декодера, §8.6 Writers (формат проекта — §8.7, doc-29), README, `assets.md`, `boundaryEnumExempt` для `ModelFormat` по новому пути в `formats`, CHANGELOG | engine + docs | S | 1 | fmt-06, 08, 09 | сканер зелёный после каждого писателя |
| fmt-17 ⚠ | Секционный формат проекта с миграциями. ⇢ doc-09, doc-10, doc-28 (одна реализация; идея «неизвестный ключ manifest переписывается как есть» через `json_write_through` — в doc-10) | core | M | 1 | — | см. doc-10, doc-28 |
| fmt-18 ⚠ | Политика ассетов (копия внутри контейнера, `.fmat` путём + fallback, опциональный `sources`) и `ProjectStorage.writeAtomic`. ⇢ doc-17 (политика) и ui-18 (диск) | core | S | 1 | fmt-17 | см. doc-17, ui-18 |
| fmt-19 ⚙⚠ | `extras` на узле/материале/скине/клипе/документе, `TextureBinding.transform` из `KHR_texture_transform` сквозным проходом; секция `extras` (21) | engine | S | 2 | fmt-06 | побайтное равенство JSON-фрагментов; предупреждение о неприменённом transform остаётся |
| fmt-20 ⚙⚠ | `StlWriter` (бинарный и ASCII) | engine | S | 2 | fmt-09 | Box.glb → stl → 12 треугольников; размер `84 + 50·count` |
| fmt-21 ⚙ | KTX2 сквозь `GltfWriter` (`KHR_texture_basisu` только для Basis), `.f3d` как есть, OBJ — предупреждение | engine | S | 2 | fmt-06, fmt-12 | etc1s-фикстура → GLB → лоадер читает; BC-файл → предупреждение |
| fmt-22 ⚙⚠ | `Ktx2Writer` + BC1/BC3/ETC2-энкодеры на Dart, `--textures bc1|bc3|etc2` в конвертере (пункт ROADMAP). ⇢ mat-30 (один энкодер, §4) | engine | M | 2 | fmt-14 | PSNR ≥30 dB через тестовый распаковщик; конформанс на файле из энкодера |
| fmt-23 ⚙⚠ | Basis Universal ETC1S для glTF: решение (порт / FFI офлайн / сервер) + спайк | engine | L | 3 | fmt-22 | `doc/texture-encoding.md` с замером; транскод существующим `etc1s_transcoder` |
| fmt-24 | Свой читатель FBX на Dart (Д7 закрыт 2026-09-09): бинарный 7.x с inflate на Dart, ASCII, `FbxDecoder`, геометрия/материалы/иерархия с пивотами, UnitScaleFactor/UpAxis; фикстуры из Blender против glTF той же сцены. Отдельная дорожка фазы 2, стартует после rel-16 (фаза 1 в руках); кандидат для агента под готовые фикстуры | fbx | L | 2 | fmt-29d, fmt-01, fmt-03 | куб бинарный и ASCII = glTF до float; иерархия с pre-rotation даёт те же мировые матрицы |
| fmt-25 ⁵ | FBX: скины и анимация (Deformer/Cluster, AnimationStack → linear-ключи, euler → кватернионы) | fbx | L | 2 | fmt-24 | поза t=0.5 = glTF-экспорт с допуском 1e-4 |
| fmt-26 ⁷ | Снят 2026-09-09: серверной конвертации FBX (`ConversionService`, HTTP-реализация, сервер вне репозитория) не делаем — читатель свой (fmt-24/25). id остаётся, чтобы ссылки не повисли | — | — | — | — | — |
| fmt-29d *(добавлено по решениям 2026-09-09)* | Скелет пакета `flutter3d_fbx`: плоский (`flatDartPackages`), `resolution: workspace`, зависимость только на `flutter3d_formats` (`geometry` транзитивно), баррел, `FbxDecoder implements ModelDecoder` заглушкой с отказом-значением; регистрация в workspace, `notARepeatableStep`, §16 (после `formats`, независимо от `flutter3d`), §3.2, `ci.sh`; число пакетов 33 → 34 в README/§3.2/§16 в том же коммите | fbx | S | 2 | doc-01, rel-16 | сканер зелёный; `dart pub get` в пакете без Flutter SDK (qa-03); `publish_check.sh` принимает порядок |
| fmt-27 ⚙⚠ | USDZ по спросу: спайк (Quick Look принимает usda?), `UsdzWriter` + zip без сжатия | engine | M | 4 | fmt-06 | скриншот Quick Look в doc; выравнивание 64 побайтно |
| fmt-28 ⚙⚠ | `ModelLight`/`ModelCamera` в словаре, `KHR_lights_punctual` и `cameras` в лоадере/писателе, секции 22–23 | engine | S | 4 | fmt-06, fmt-19 | round-trip рукописного glTF с двумя источниками и камерой |

### 2.4 Рендер и вьюпорт (`view-`)

Почти всё уже в движке и его надо дотянуть, а не писать: `DebugDraw` и
`DebugLineVertex`/`DebugLine`, `PassContributor`, `Renderer.pickPixel`,
`Raycaster`, `OrbitController`, `RenderView.viewportFraction`/`layerMask`,
`EnvironmentMap.fromSky`, вершинный цвет в `surface.glsl`. Нет: частичной
перезаписи буфера, точек как примитива (CPU-растеризатор бросает на point,
WebGPU — 1 px), толстых линий, смещения глубины, счётчика треугольников, BVH по
треугольникам, каркаса вне Impeller. Новый шейдер стоит одинаково дорого на
четырёх бэкендах, поэтому план заводит максимум два вершинных стейджа и ни одного
фрагментного.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| view-01-bench | Микрозамеры оверлея на стенде p0-01: (б) `bindVertexData` 200k квадов в кадр, (в) CPU-смещение 200k вершин к камере. (а) `DeviceMesh.upload` в кадр ⇢ p0-06; сцена на 1 млн ⇢ p0-01/02/03 | engine example + `packages/flutter3d/tool/bench` | S | 0 | — | пороги: (в) >2 мс → view-06 обязателен; (а) >8 мс → view-14 в фазу 1 |
| view-02-viewport-skeleton ⚠ | `modeler_viewport.dart`: `Renderer` через `flutter3d_backend`, `Ticker`, поверхность с `List<RenderView>`, камера в `State`; фон — плоский `#0E1112` или небо `SkySettings` (решение); `frame_test` | app | M | 0 | view-01 | два `RenderView` половинами экрана; GLB виден на macOS |
| view-03-orbit-gestures ⚙ | `OrbitGestures` (чистый Dart): мышь/палец/трекпад/перо → `rotate/pan/zoom`; стилус не двигает камеру; движок: орто-зум меняет `height`, `frameBounds` для орто, `animateTo(yaw, pitch)`. ⇢ ui-06 (жесты), ui-19 (политика ввода) | app + engine | M | 1 | view-02 | два пальца → `distance`/`target`; стилус не меняет `yaw`; тест орто-зума в движке |
| view-04-display-modes | Перспектива/орто с сохранением кадрирования, стандартные виды, чипы «Материал/Нормали/Каркас» (каркас до view-07 — оверлеем) | app | S | 1 | view-03 | пиксель грани +Y в «Нормали» = (128,255,128)±2; орто не зависит от `distance` |
| view-05-mesh-overlay ⚙⚠ | `MeshOverlay extends PassContributor` с `OverlayBatch` в раскладке `positionColor`: тонкие линии, точки-квады к камере, ленты и заливка 55 %; пайплайн `DebugLineVertex`+`DebugLine`, `lessEqual` + CPU-смещение; сцена `mesh-overlay` в `kGoldenScenes`, 43 → 44. ⇢ qa-10 | engine | M | 1 | — | батч из N рёбер — 3 draw; квад не зависит от `distance`; 4 набора, 0 пикселей; заливка `#004F58` 55 % ±3 |
| view-06-overlay-shader ⚙ | Условно (view-01(в) >2 мс): `overlay.vert` с `depth_bias`, фрагмент `DebugLine`; бандл, `kRequiredShaders`, CPU-стадия, две таблицы, сайт | shaders + 4 бэкенда | S (усл.; по цене риска 9 — GLSL, `impellerc`, `naga`, CPU-транскрипция, четыре таблицы — считать M, если пункт срабатывает) | 1 | view-05, view-01 | `mesh-overlay` в допуске 8; `manifest_test`; `structure --only 'shader bundle'` |
| view-07-wire-edges ⚙⚠ | `MeshData.edgeIndices()`, `DeviceMesh.upload(withEdges)`, стейдж `MeshWireVertex`, рендерер рисует рёбра линиями там, где `supportsWireframe == false`; сцена `wireframe-edges` | engine + shaders + бэкенды | M | 2 | view-06 | куб → 18 рёбер; `wireframeDeclined` не бывает true |
| view-08-pick-objects ⚠ | `object_picking.dart`: `pickPixel` → `MeshNode` → `ModelObject`; Shift добавляет; служебные узлы исключены; `RenderSettings.highlighted` до view-10 | app | S | 1 | view-02 | клик в куб — объект; по стрелке гизмо — не объект под ней |
| view-09-triangle-bvh ⚙⚠ | Владелец `TriangleBvh` (уточнено по критике): реализация над `Float32List`/`Uint32List` с `refit` в пакете `geometry` (решение 2026-09-09); `Raycaster.intersectTriangles` по дереву, если `MeshData.bvh` зарегистрирован. Одна реализация с mesh-20/p0-10 (§3): p0-10 меряет прототип этого класса, mesh-20 строит `MeshBvh` поверх | engine (geometry) | M | 1 | doc-01, p0-10 | 10k лучей по тору = перебор; луч <0,2 мс, refit <5 мс, build <150 мс на 200k |
| view-10-pick-elements ⚠ | `element_picking.dart`: грань по лучу, вершина/ребро по экранному расстоянию (8 lp мышь, 24 lp палец) с окклюзией, рамка по проекции; результат — `Selection` | app | M | 1 | view-09, view-08 | центр грани → грань, ±3 lp от ребра → ребро, 12 lp от вершины → ничего; задняя вершина без флага не выбирается |
| view-11-grid-orientation | Сетка пола батчем `MeshOverlay` с затуханием и `lessEqual`; гизмо ориентации ⌀60 — `CustomPainter`, клик → `animateTo` | app | S | 1 | view-05, view-04 | пиксели сетки ≈ `#2A3234`; `−X` → yaw π/2 |
| view-12-transform-gizmo ⚠ | `transform_gizmo.dart`: рукоятки из `Shape`, `unlit`, `always`, поздний bucket, экранный размер; `GizmoHit`/`GizmoDrag` по образцу `AxisDrag`; привязка Ctrl; одна транзакция. ⇢ ui-06 (манипулятор) | app | L | 1 | view-08, view-03 | лучи вдоль X → сдвиг по X, один шаг; `steady_gizmo_test` два кадра побайтно; стрелка X `#FF6B8A`±2 |
| view-13-mesh-mode-app ⚠ | `mesh_overlay_builder.dart`: `EditMesh` + `Selection` → три батча, пересборка по версии, квады — по камере, прореживание >100k | app | M | 1 | view-05, view-10 | куб с гранью: 12 линий, 4 ленты, 2 треугольника; 200k рёбер <20 мс при смене выделения, 0 мс при повороте |
| view-14-overwrite-geometry ⚙⚠ | `GraphicsDevice.overwriteGeometry(target, offset, bytes)` с семантикой «видно со следующего прохода», четыре реализации + fake; `DeviceMesh.overwrite` с bounds/version; конформанс «partial overwrite draws what a fresh upload draws», 33 → 34. ⇢ pro-eng-01, qa-11; фаза 1, если p0-06 не проходит | hw + 4 бэкенда + engine + conformance | M | 2 | view-01 | конформанс на четырёх; overwrite 1 % из 200k <1 мс |
| view-15-multi-view ⚙ | `ViewportPane {view, orbit, layerMask}`, маршрутизация указателя по `viewportFraction`; `SceneSurface.views:` в session | app + session | S | 3 | view-02, view-08 | клик в правую половину даёт сферу на слое 2 |
| view-16-material-preview ⚠ | Отдельные `Renderer` и `Scene`, фигуры, `EnvironmentMap.fromSky`, синхронизация `SurfaceMaterial → Material`. ⇢ mat-15 | app | M | 2 | view-02 | см. mat-15 |
| view-17-game-preview ⚙⚠ | `FrameResult.triangles`/`instances` в `renderer_mesh_encode.dart`; вьюпорт с профилем «игра», оверлей метрик, полосы бюджетов, `AnimationPlayer`. ⇢ anim-24 (бюджеты), ui-28 (оболочка) | engine + app | M | 3 | view-02 | куб + сфера ×3 → `triangles == 12 + 3·N`; превышение красит `#FFB86B` |
| view-18-weight-gradient ⚠ | Вес кости → атрибут `color` по пяти стопам, `unlit`, `tonemap: false`; обновление через overwrite; легенда — Flutter. ⇢ anim-11 | app | M | 3 | view-14 | вес 1 → `#FF3B5C`±3; мазок меняет только 1 % `source` |
| view-19-uv-view ⚠ | Швы лентами, растяжение цветом по углам, 2D-панель на `CustomPaint`. ⇢ pro-uv-07 | app | M | 4 | view-13, view-18 | см. pro-uv-07 |
| view-20-lod-views | Три `ViewportPane`, подписи с `triangleCount`, ползунок расстояния → выбор уровня `LodGroup` по покрытию. ⇢ pro-lod-04 | app | S | 4 | view-15 | см. pro-lod-04 |
| view-21-brush-cursor-pressure ⚠ | Курсор ⌀140 Flutter-оверлеем или лентой на поверхности через `HitResult.normal`; `pressure` только для stylus; мазки батчами раз в кадр. ⇢ pro-sc-08, ui-29 | app | S | 4 | view-03, 09, 14 | pressure 0,5 → сила 0,5; палец не создаёт мазка |
| view-22-tests-numbers-ci | `test/viewport/*` в `ci.sh`; тест-стражник draw call `1 + 3 + 1 + N`, `pipelines` не растёт; приложение в `repository.dart`; числа. ⇢ qa-14 | app + tool | S | 1 | view-13, 12, 11 | `ci.sh` зелёный; лишний draw в `MeshOverlay` — красный |

### 2.5 Оболочка и платформы (`ui-`)

Повторить разрез редактора уровней: Cubit держит документ, режим, фразу статуса,
параметры последней операции, готовность к экспорту; камера, сцена и гизмо — в
`State` виджета; каждая правка — команда; тесты через `flutter3d_cpu`. В
репозитории нет ни строки локализации, ни чтения `PointerDeviceKind.stylus` или
`pressure`; `documents.dart` тянет `dart:io`; на вебе бэкенд рисует в
фиксированный размер (`kFixedResolution`).

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| ui-00 ⚠ | Спайк оболочки: `openDevice` из `flutter3d_app`, GLB из `--dart-define`, `SceneSurface` + `OrbitController`, `FrameTimingLog`; раннеры macOS и web. Замер 0.1 ⇢ p0-01/02/03; файлы становятся `staging.dart`/`viewport.dart` | app | S | 0 | — | `flutter build web --wasm` собирается; модель крутится на macOS |
| ui-01 | Регистрация: workspace, `applications`, README/LICENSE/analysis_options, `Info.plist` с `FLTEnableFlutterGPU`/`FLTEnableImpeller`, `staging.dart` как единственная сборка мира. ⇢ qa-02 | app | S | 0 | ui-00 | сканер 30/30; `ci.sh` зелёный |
| ui-02 ⚠ | Тема M3 из таблицы токенов явной `ColorScheme.dark` (не `fromSeed`), `ModelerColors` extension, TextTheme 400/500, `VisualDensity.compact`, темы компонентов; набор иконок — `Icons` из SDK с таблицей соответствия глифам Material Symbols из README передачи (Е12n закрыт 2026-09-09; внешний пакет `material_symbols_icons` не берём) | app | S | 1 | ui-01 | каждая роль = hex из таблицы; строка 32, кнопка рельсы 36; иконки без внешней зависимости или зависимость записана в pubspec с лицензией |
| ui-03 ⚠ | `ModelerState` = Opening / Choosing / Ready(project, mode, submode, said, activeOperation, viewport, readiness, jobs) / Failed; `ModelerCubit` из предложений; камера и сцена не в Cubit | app | M | 1 | ui-01 | смена режима не сбрасывает выделение; `ran()` обновляет readiness; undo после транзакции — один шаг |
| ui-04 | Каркас: TopBar 52 с двумя `SegmentedButton`, Rail 52, Properties 250–330, StatusBar 30; содержимое из таблицы режима (ui-07) заменяется целиком | app | M | 1 | ui-02, ui-03 | при 1440×900 высоты/ширины по `RenderBox`; режимы фаз 2–4 присутствуют выключенными |
| ui-05 ⚠ | `LayoutClass.of(width)`; планшет — палитра 48, лист ~200 с ручкой; телефон — `NavigationBar` 80, FAB 56, лист 130 | app | M | 1 | ui-04, ui-07 | границы 599/600/1199/1200; одинаковые ключи инструментов в трёх оболочках |
| ui-06 ⚠ | Вьюпорт приложения: `Listener` только на картинке, `SceneSurface`, `scene_sync.dart` (ModelObject ↔ MeshNode), coalesce GPU-обновлений раз в кадр. Жесты ⇢ view-03, пикинг ⇢ view-08/10, манипулятор ⇢ view-12, гизмо ориентации ⇢ view-11 | app | M | 1 | ui-03, ui-00 | `pick_test` на CpuDevice 128×96; `manipulator_drag_test` — один шаг |
| ui-07 | `ModelerTool` (id, icon, label-ключ, shortcut, режим, группа, команда) и `toolsFor(Mode)` — один источник для рельсы, палитры, листа, клавиш | app | S | 1 | ui-03 | уникальные id и shortcut; три оболочки — одно множество id |
| ui-08 ⚠ | Экран 01: список объектов, `NumberField` 3×3, стек модификаторов с переключателем и перетаскиванием; `section_label.dart` | app | M | 1 | ui-04, ui-03 | «1,5» и «1.5» приняты; ввод в X эмитит `SetTransform` |
| ui-09 ⚠ | Экран 02: `operation_card.dart` из параметров команды на вершине истории (`ParamHint` из syn-01), `history.amend` без подтверждения; сводка выделения | app | S | 1 | ui-08, ui-06, doc-07, syn-01 | ползунок вызывает amend без нового шага; крестик не трогает историю |
| ui-10 ⚠ | Строка статуса: метрики режима, первый `Issue` из `ExportReadiness` (зелёный/оранжевый), клик → диалог экспорта; `NumberFormat` локали | app | S | 1 | ui-04, ui-03 | n-гон → оранжевый текст; 1240000 → «1 240 000» |
| ui-11 ⚠ | Undo/redo в трёх раскладках, tooltip с `undoSays`, ⌘Z/⇧⌘Z, все перетаскивания — в транзакции | app | S | 1 | ui-03, ui-06 | 40 событий → один шаг; undo восстанавливает меш по `identical` |
| ui-12 ⚠ | `Shortcuts`/`Actions` из `ModelerTool.shortcut` + общие; набор Blender-подобный — G/R/S/E/I, 1/2/3, Tab — там, где не конфликтует с платформой (Е5 закрыт 2026-09-09); meta/control по платформе; фокус в `NumberField` перехватывает | app | S | 1 | ui-07, ui-11 | «E» с гранью запускает экструзию; в поле — вводит символ |
| ui-13 ⚠ | Экран 09: `profile_editing.dart` (чистый Dart: точки, сегменты-кривые — квадратичная/кубическая Безье с допуском уплощения в полилинию для `LatheShape`, который принимает только полилинию; ось, hit ⌀12, привязка 40), `profile_editor.dart` (`CustomPainter`), `lathe_dialog.dart` 720 со вторым `RenderView`; чипы «Точка / Кривая / Ось» по README передачи; `AddLathe` хранит кривую, а не полилинию (уточнено по критике) | app | M | 1 | ui-06, ui-08 | hit внутри ⌀12; сегменты 24→12 меняет сводку; кадр предпросмотра = golden; кривая из 3 точек даёт N сегментов, сумма длин хорд ≈ длине кривой в допуске уплощения |
| ui-14 ⚠ | `ProjectFiles` с conditional export: native (`file_selector` + запись по итогу p0-13n — `saveFile` и прямая запись без rename под сандбоксом, либо security-scoped доступ к каталогу; `writeFileAtomically` только там, где каталог доступен), web (Blob → `<a download>`); `documents.dart` без `dart:io`. Спайк 0.5 ⇢ p0-08, спайк сандбокса ⇢ p0-13n | app | M | 0 | ui-00, p0-13n | на `--wasm` открывается GLB и скачивается `.f3d`; обе половины анализируются; на macOS с включённым сандбоксом «Сохранить как» записывает файл |
| ui-15 | Стартовый экран: «Открыть файл», недавние через `defaultStorage('flutter3d_modeler')` (`Storage` — абстрактный интерфейс с текстовым `write(name, contents) → bool`; конструируется через `defaultStorage`, как `SaveFile`/`SettingsFile`), «Новый проект» с профилем | app | S | 1 | ui-14, ui-03 | 8 записей, без дублей, битый JSON — пустой список |
| ui-16 ⚠ | Экран импорта: `warnings` списком, метрики против профиля, флажки (сварить, нормали, триангулировать), единицы (мм/см/м → множитель `ImportOptions.scale`) и ось вверх (Y/Z) с предпросмотром bounds; лимиты входа (размер файла на вебе, вершин с морфами против `maxTextureSize`, треугольников против мобильного пресета) показываются до кнопки; прогресс на месте кнопки; на вебе декод на основном потоке. Единицы и лимиты добавлены по критике | app | M | 1 | ui-14, ui-03, doc-11 | `import_plan_test` без Flutter; на файле из samples диалог показывает число предупреждений; STL в мм с выбором «мм» даёт bounds в метрах; файл сверх лимита на вебе — отказ до декодирования |
| ui-17 ⚠ | Экран экспорта: формат, список `Issue` с «показать», полосы бюджетов, флажки (в том числе «запечь трансформации узлов» через `ApplyTransform` из doc-06 — добавлено по критике); `toModelDocument()` → писатель → `saveAs`; ⌘E. При `Issue` уровня error — предупреждение и экспорт после явного подтверждения, отказ только при пустой геометрии (Г9 закрыт 2026-09-09) | app | M | 1 | ui-10, ui-14 | round-trip куб + ваза → GLB → decode: мешей и треугольников столько же, кадр = golden; с флажком узлы GLB несут единичные матрицы; объект с n-гоном экспортируется после подтверждения, пустой проект — отказ |
| ui-18 ⚙⚠ | Автосохранение: debounce 2 с / ≤1 раз в 15 с, сериализация в фоне, `Storage.write('autosave/<id>')`, предложение восстановить; `BinaryStorage`/IndexedDB в flutter3d_screens (правка пакета репозитория). ⇢ fmt-18 (атомарная запись) | app + screens | M | 1 | ui-03, ui-14 | три команды → одна запись (FakeAsync); `write() == false` сообщается один раз |
| ui-19 | `InputPolicy` (чистый Dart): mouse — всё; stylus — рисует, `pressure` нормирован; touch — камера/долгое нажатие; inverted — ластик; tap target 48 на тач | app | S | 1 | ui-06 | touch в sculpt → camera; мышь → сила 1.0 |
| ui-20 ⚙⚠ | macOS: `CFBundleDocumentTypes`, сандбокс включён с `user-selected.read-write` (совместимость с записью — по p0-13n; редактор уровней выключил сандбокс именно из-за `PathAccessException` при записи), своя иконка; web: index.html без soloud, manifest, `--base-href=/modeler/`; `kFixedResolution` — пересоздание устройства при смене класса или resize `WebGlDevice` | app + webgl | S | 1 | ui-01, ui-14, p0-13n | правило GPU зелёное; `flutter build macos` и `web --wasm` в CI; сохранение под сандбоксом проходит в `flutter test` на macOS-раннере |
| ui-21 ⁴ | Android (`EnableFlutterGPU`, без блокировки ориентации, intent-filter), iOS (document types, `UISupportsDocumentBrowser`, `file_selector_ios`, `FLTEnableFlutterGPU`); debug-сборки в CI (qa-17); проверка на физических iPad и Galaxy A55. Фаза 1 по решению 2026-09-09: четыре платформы с первой версии | app | S | 1 | ui-20, ui-05, ui-19, rel-19d | сканер по обоим каталогам; на iPad с Pencil pressure 0..1; приложение открывает GLB на iPad и Galaxy A55 |
| ui-22 ⚠ | `flutter_localizations` + `intl`, `app_ru.arb` шаблон, `app_en.arb`, все строки через l10n; русский и английский с первой версии (Е2), язык `says` — английский (Г4); оба закрыты 2026-09-09 | app | S | 1 | ui-04 | множества ключей ru/en равны; под `Locale('en')` нет кириллицы |
| ui-23 ⚠ | Semantics/tooltip, порядок фокуса, контраст (outline 11 px на грани), textScaler 1.3, tap 48 на тач | app | S | 1 | ui-05, ui-02 | `textContrastGuideline`, `androidTapTargetGuideline`; без overflow при 1.3 |
| ui-24 | `PopScope` с диалогом несохранённого, маркер в заголовке, `beforeunload` на вебе | app | S | 1 | ui-14, ui-03 | при isDirty — диалог; неудачная запись не закрывает |
| ui-25 | `Job` в `ModelerReady.jobs`, `Isolate.run` на native, чанки с уступкой на вебе, `JobButton` с индикатором. Раннер для doc-24 (§3) | app | S | 1 | ui-03 | 10 чанков → прогресс 0.1…1.0; cancel на 3-м без результата |
| ui-26 ⚠ | `frame_test` (картинка следует документу), `mesh_overlay_frame_test`, все через `staging.dart`; числа в README/ARCHITECTURE/сайте. ⇢ qa-15 | app | M | 1 | ui-06, 09, 13, 17, doc-07 | `flutter test` без GPU; мутация «сцена не пересобирается» роняет |
| ui-27 ⚙⚠ | `flutter3d_editor_widgets` (новый): `FieldRow`, hint-контролы, `NumberField`; оба редактора зависят; панель материала экрана 05 из подсказок. Ворота записи `.fmat` ⇢ mat-03 | editor_widgets (новый) | M | 2 | ui-08 | тесты редактора уровней зелёные после переноса; §16 и число пакетов в README/§3.2/§16 сдвинуты в том же коммите |
| ui-28 ⚠ | Оболочка фазы 3: таймлайн 270 (транспорт 44, кости 180, дорожки, playhead), `playback` в состоянии, тик через `AnimationPlayer` в `State`; экран 19 оверлей и панель бюджетов; экран 15 строки форм. ⇢ anim-07 (таймлайн), view-17/anim-24 (превью) | app | L | 3 | ui-04, ui-06 | клик по дорожке ставит ключ; 28/64 — зелёная полоса 44 % |
| ui-29 ⚙⚠ | Раскладка скульптинга без панелей, палитра кистей, карточка 250, курсор ⌀140, сила из `InputPolicy`; мазок — транзакция. ⇢ pro-sc-08, view-21 | app | M | 4 | ui-19, ui-05 | нет Rail/Properties; touch не создаёт мазка |
| ui-30n *(добавлено по критике)* | Необработанные исключения: `FlutterError.onError` и `runZonedGuarded` в `main`, аварийная запись автосохранения (ui-18) до показа ошибки, окно «что случилось» с кнопкой «Report a problem» (rel-15) и локальным логом последних N команд из журнала doc-16; без телеметрии | app | S | 1 | ui-18, rel-15, doc-16 | брошенное в `apply` исключение → автосейв записан, окно показано, URL формы содержит имя команды; тест через `FlutterError.onError` в widget-тесте |
| ui-31n *(добавлено по критике)* | Drag-and-drop файла в окно (macOS через `desktop_drop` или свой канал, веб — `dragover`/`drop` через `package:web`) → тот же путь, что «Открыть файл» (ui-14/16); Е7 покрывает только Finder/intent в фазе 2 | app | S | 1 | ui-14, ui-16 | drop GLB открывает экран импорта; drop неизвестного расширения — сообщение в статусе; на вебе тест через синтетическое событие |
| ui-32n *(добавлено по критике)* | Справка в приложении: пункт меню/`?` с таблицей горячих клавиш из `ModelerTool.shortcut` (ui-07, набор Е5) и ссылкой на туториал rel-09; без второго источника правды для клавиш | app | S | 1 | ui-07, ui-12 | таблица содержит каждый `shortcut` из `toolsFor(Mode)` ровно раз; ссылка ведёт на страницу сайта |
| ui-33d *(добавлено по решениям 2026-09-09)* | Флажок «Сохранить без истории» в «Сохранить как» и в экспорте проекта (ui-17) → `ProjectWriter(includeHistory: false)` из doc-31d; автосохранение (ui-18) пишет с историей всегда | app | S | 1 | doc-31d, ui-17, ui-14 | с флажком секции `history` в файле нет; без флажка после повторного открытия undo доступен на три шага |
| ui-34d ⁸ *(добавлено по решениям 2026-09-09)* | Web worker для неделимых операций на вебе (Е11 закрыт: заморозка с прогрессом на месте кнопки допустима, worker — пункт фазы 1, а не 2, по условию): изолят компилируется в worker под wasm/JS, передача через `TransferableTypedData`/`postMessage`, в фазе 1 — импорт (`decodeModel` + `fromMeshData`) и экспорт (`toMeshData` + писатель), тем же `Job` из ui-25. Условие включения: p0-07/p0-08 показывают заморозку дольше 1 с на эталонной операции (импорт 30 МБ или экспорт 200k) | app | M | 1 (усл.) | ui-25, p0-07, p0-08, mesh-30 | импорт 30 МБ в Chrome не держит кадр дольше 100 мс; результат через worker = на основном потоке побайтно; если условие не сработало, пункт не делается и это записано в doc §6 |

### 2.6 Материалы и модификаторы (`mat-`)

Ядро в движке есть и покрыто тестами: `SurfaceMaterial`/`TextureBinding`,
`.fmat` с `MaterialHint`, `bindMaterial`, `uploadEncodedImage`, `EnvironmentMap`,
восемь источников с отбором по объекту, тени, `ProceduralTexture`. Панель из
подсказок и ворота записи `.fmat` уже в `apps/flutter3d_editor/material_panel.dart`.
Нет: материала в документе редактора, метаданных слотов, графа-компоновщика и
вычислителя, PNG с deflate на чистом Dart, `.hdr`, модификаторов, освещения как
части проекта, бюджета текстур. Граф держится в рамках ROADMAP: ноды считаются
на CPU и запекаются в пять слотов PBR, шейдер не меняется.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| mat-01 | `ProjectMaterial {surface, images, fmatPath, version}`, `ModelObject.materialSlots`; команды `AddMaterial`, `RemoveMaterial`, `SetMaterialField` (ключи `writeFmat`), `AssignMaterial`, `DuplicateMaterial`, `SetTexture(materialId, slot, imageId, sampling)`, `AddImage(bytes, name)` (обе перенесены из doc-25 в фазу 1 по критике — без них импортированная текстура не назначается); `toModelDocument()` с дедупом изображений. Поглощает doc-25 | core | M | 1 | doc-03, doc-05 | round-trip команд; два объекта с одним материалом → один `SurfaceMaterial`; `AddImage` + `SetTexture` → `TextureBinding` в экспортированном документе |
| mat-02 | `TextureInfo(width, height, format, bytesOnDevice, hasOwnMips)` из заголовков PNG/JPEG (doc-15) и `Ktx2Texture.parse`; вес с мипами и `blockLayout` | core | S | 2 | mat-01 | размеры = `TextureHandle` после загрузки; мутация порядка байтов IHDR |
| mat-03 ⚠ | Перенести `materialWith`, `materialDocumentFields`, `materialDocumentHint`, `_fits`, `_sameJson` в `flutter3d_editor_core/lib/src/material_edit.dart`; оба редактора импортируют. `editor_core` — плоский пакет (`flatDartPackages`) с зависимостью только на `flutter3d_sim`, а библиотека принимает `MaterialDocument`/`MaterialHint` из `flutter3d` — поэтому переезд возможен только после doc-01, и `editor_core` получает зависимость на `flutter3d_formats` (ярус в §16 сдвигается — rel-03). Уточнено по критике | editor_core | S | 1 | doc-01 | тесты переезжают зелёными; `flutter analyze` чист; `dart pub get` в `editor_core` без Flutter SDK проходит (правило qa-03) |
| mat-04 | Панель «Материал» полная: список материалов объекта, свойства из `builtInMaterialHints` через `HintRow` в токенах M3, «Дополнительно», неактивные ползунки по `LightingModel`; drag — транзакция. Фаза 1 получает урезанную версию mat-04a-n | app | M | 2 | mat-01, mat-03, mat-04a-n | у lambert металличность неактивна; hex `#5FD4E4` → (0.373, 0.831, 0.894); три события — один шаг |
| mat-04a-n *(добавлено по критике)* | Панель «Материал» фазы 1 — план дизайна относит «Базовые материалы» к фазе 1, а сценарий ядра «чистит меш, правит материал, экспортирует в GLB» без неё не проходит: список материалов проекта, назначение объекту (`AssignMaterial`), цвет / металличность / шероховатость из `builtInMaterialHints` по образцу `apps/flutter3d_editor/lib/src/material_panel.dart`, слот `baseColorTexture` через `file_selector` (`AddImage` + `SetTexture`) без параметров сэмплера; drag — транзакция | app | S | 1 | mat-01, mat-03, ui-08 | смена цвета → `SetMaterialField`, один шаг на drag; выбранный PNG появляется в GLB как `baseColorTexture`; кадр `mesh-material-colour` в тестах app |
| mat-05 | Слоты текстур: превью 26×26 из миниатюры, имя, `w×h`, вес; `file_selector` с `TextureHint.extensions`; параметры `TextureSampling`; `texCoordSet` только 0 | app | M | 2 | mat-02, mat-04 | PNG 256×128 → «256×128», «170 КБ»; KTX2 BC7 → плашка формата |
| mat-06 | `ColorField`: образец, hex, HSV, альфа при `channels == 4`, флаг `linear` для эмиссии | app | S | 2 | mat-04 | linear (0.214…) → `#808080`; 3-канальный hint без альфы |
| mat-07 | `MaterialBinder`: кэш `Material` по версии, текстуры по хэшу байтов через `ResourceCache`, обновление полей без замены объекта; warnings в статус | app | S | 2 | mat-01 | 100 правок roughness — `createTextureFromPixels` = число уникальных изображений |
| mat-08 | `.fmat` внешний: `LinkMaterialFile`, `EmbedMaterial`, `MaterialFileWriter.write` через ворота mat-03; диск в app; экспорт разворачивает пути | core + app | M | 2 | mat-01, mat-03 | link → правка → write → `readFmat` без warnings; шейдер не найден — предупреждение |
| mat-09n *(добавлено по критике)* | Декодер изображений на чистом Dart для ноды Image: PNG (inflate, фильтры, 8/16 бит, палитра) и baseline JPEG; свой или `package:image` в core — решение вместе с Г6. В репозитории ни одного чистого декодера: golden-тесты читают PNG через `dart:ui`, `cpu_png.dart` — только писатель со stored-deflate. Альтернатива, если декодер не берётся: запекать в app через `dart:ui`, а core держит граф без пикселей — тогда `bakeTextureGraph` из mat-32 в MCP невозможен, и это записывается | core | M | 2 | mat-01 | фикстуры PNG (RGB/RGBA/палитра/16 бит) и JPEG декодируются побайтно как `dart:ui` в тесте app; обрезанный файл → отказ значением |
| mat-10 ⚠ | `TextureGraph` (неизменяемое): фиксированные ноды Image/Color/Blend/Channels/Levels/Invert/UvTransform/Checker/Noise/NormalFromHeight/Output с `hints`; проверки цикла и типов. Это «компоновщик текстур» с фиксированным набором нод, не шейдерный граф (Ж1 закрыт 2026-09-09; ROADMAP переформулируется на ревизии 28 сентября) | core | M | 2 | mat-01 | round-trip JSON; цикл отвергнут с нодой; тип входа проверен |
| mat-11 | `bakeTextureGraph` на CPU в линейном пространстве, кэш по структурному хэшу поддерева, предпросмотр 256² чанками, полное — `Isolate.run`/чанки; без `Random` | core | M | 2 | mat-10, mat-09n | два прогона побайтно; правка `factor` не декодирует Image повторно; замер 6 нод 2048² в doc |
| mat-12 ⚠ | `BakeTextureGraph(materialId)` → изображения в слоты, метка «запечён в версии N»; PNG с deflate (свой LZ77+Хаффман или `package:archive` — вопрос); в проекте сырые RGBA | core | M | 2 | mat-11, mat-01 | PNG декодируется `flutter3d_cpu`; градиент 1024² <25 % stored |
| mat-13 | `TextureGraphPanel` 250 (свёрнута), `InteractiveViewer`, ноды 170–210, Безье `primary` 2, `HintRow` по `node.hints`, миниатюры 64², команды `AddNode`/`Link`/`Unlink`/`SetNodeField`/`MoveNode`, «Запечь 2048²» с прогрессом | app | L | 2 | mat-10, 11, 04 | связь Цвет→маска отвергнута без команды; удаление ноды — один шаг |
| mat-15 | `MaterialStudio`: своя `Scene`, тела (сфера/куб/чайник/этот объект), два `LightNode`, пол, три пресета `SkySettings` → `EnvironmentMap.fromSky(size: 32)`, `OrbitController`. Поглощает view-16 | app | M | 2 | mat-07 | кадр `material-studio` на CPU; смена пресета отдаёт старый handle на dispose |
| mat-16 ⚠ | `equirectToCubeFaces` (LDR-панорама, порядок граней как `_directionFor`) → `prefilter(size: 128)`; пресет «Своя панорама» | core | S | 2 | mat-15 | верх белый/низ чёрный → +Y/−Y; замер 128² levels 4 |
| mat-17 ⚙⚠ | Декодер Radiance `.hdr` (RGBE RLE), `prefilterFloat`, куб в `r16g16b16a16Float`, конформанс float-куба, кадр `ibl-hdr` | engine + conformance | M | 4 | mat-16 | фикстуры Khronos с провенансом; конформанс на четырёх |
| mat-18 ⚠ | `ModelObject.modifiers`, `evaluatedMesh` с кэшем по `(geometryVersion, modifiersHash, targetVersion)`; значения `Mirror/Array/Smooth/Boolean` — из mesh-40..48, здесь только `hints` и обёртки (§3) | core | M | 2 | — | зеркало со сшивкой; отключённый не меняет хэш; смена материала не инвалидирует |
| mat-19 | Команды стека и MCP-инструменты. ⇢ doc-23 (команды), mat-32 (инструменты) | core | S | 2 | mat-18 | см. doc-23 |
| mat-20 ⚠ | Стек в панели «Объект»: строка 32, перетаскивание, меню из четырёх, карточка параметров на `surfaceContainerHigh` с `HintRow`, «Применить»/«Удалить», предупреждения; тяжёлое через `jobs` | app | M | 2 | mat-19, mat-18 | `count` массива — одна `SetModifierField`; кадр `modifier-mirror-array` |
| mat-22 ⚠ | Правила `ExportReadiness`: n-гоны после булева, неманифолд после зеркала, blend с непрозрачной альфой, `texCoordSet != 0`, `extraTextures`/`parameters` при glTF, текстура вне бюджета, `.fmat` без копии | core | S | 2 | mat-18, 01, 28 | по правилу тест с мутацией; кэш по версии объекта |
| mat-23 ⚠ | `SceneLighting {lights, environment, ambientIntensity, shadows, exposure, пост}`; команды света/окружения/теней; `LightingSync` → `LightNode`/`RenderSettings`; пресеты как значения | core + app | M | 2 | mat-16 | `SetLightField('intensity', 'много')` отвергнут; `RemoveLight` отсоединяет узел |
| mat-24 ⚠ | Режим «Сцена» v1: источники как пикаемые маркеры с гизмо, панели источника/окружения/теней/пост, статус `Источников N · теневых M из 6`, предупреждение по `lightsDropped`/`shadowsDenied`. Расширен решением 2026-09-09 (Ж4, §7 № 36): расстановка нескольких ассетов в одном проекте — «Импортировать в сцену» через `ImportInto` (doc-11a-n), перемещение объектов гизмо view-12, экспорт сцены одним GLB через `toModelDocument()` (все объекты как узлы) | app | L | 2 | mat-23, 25, 06, doc-11a-n, view-12 | кадр `scene-lit`; девятый источник → оранжевый статус; два импорта + сдвиг второго → GLB с двумя узлами и разными матрицами, один `SurfaceMaterial` на общий материал |
| mat-25 ⚠ | `LightGizmos` поверх `DebugDraw`: стрелка, сферы дальности, конус; маркер-билборд в id-проходе | app | S | 2 | mat-23 | пиксели конуса на месте; поворот узла переносит стрелку |
| mat-28 ⚠ | `ProjectProfile.textures: TextureBudget(maxSide, maxBytesOnDevice, targetFormat, requirePowerOfTwo)` с пресетами; `measure(project) → TextureUsage` с пересчётом под формат | core | S | 2 | mat-02 | одна картинка у двух материалов — один раз; bc7 = 1/4 RGBA8; 3000² в `overs` |
| mat-29 | `resizeRgba` (box/билинейный), `toPowerOfTwo`, `FitTexturesToProfile` с сохранением источника; опция «ужать при экспорте» | core | S | 2 | mat-28, mat-12 | 4×4 шахматка → 2×2 серые; 1000×600 → 512×512 |
| mat-30 ⚙⚠ | Энкодер BC1/BC3/ETC2/ASTC 4×4 → KTX2, опция экспорта; в glTF PNG. ⇢ fmt-22 (одна реализация в движке) | engine + core | L | 2 | mat-28 | см. fmt-22; экспорт `.f3d` с `.ktx2` грузится без предупреждений |
| mat-31 | Кадры `material-studio`, `modifier-mirror-array`, `scene-lit` 320×200 в `test/goldens` app; числа | app | S | 2 | mat-15, 20, 24 | три PNG зелёные на ubuntu |
| mat-32 ⚠ | MCP: `listMaterials`, `setMaterialField` (схема из `MaterialHint`), `assignMaterial`, `linkMaterialFile`, `bakeTextureGraph`, `addLight`/`setLightField`, `setEnvironment`, `setShadowField`; сценарий «агент красит стол и ставит свет» | mcp | S | 2 | mat-01, 19, 23, 12 | каждая команда аспекта имеет инструмент; сценарий воспроизводится |

### 2.7 Анимационный конвейер (`anim-`)

Рантайм-половина в движке: `Skeleton` (64 кости), `AnimationTrack` с тремя
интерполяциями, `AnimationPlayer` со слоями, `MorphTarget`/`MorphBlend`,
`BakedPoses`, декодер glTF и полный писатель `.f3d`; программный растеризатор
транскрибирует skinned-стадию, golden-сцены `skinned-figure`/`morph-*` есть.
Нет ничего, что редактирует. Главное дополнение — «поза без сцены» (`Pose` + FK
на типизированных массивах), на ней стоят IK, ретаргет, драйверы, запекание и
тесты паритета. Алгоритмы рига предлагаются в четвёртый чистый пакет
`flutter3d_rig` — вопрос владельцу.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| anim-01 ⚙ | `Pose`: локальные TRS в `Float32List` по индексам `nodes`, `parents`, `restOf`, `sampleClip`, `worldMatrices`, `jointMatrices` по формуле `Skeleton.update` | engine | M | 3 | — | RiggedSimple/BoxAnimated: матрицы = `Skeleton.matrices` после `seek` (1e-5) |
| anim-02 ⚙ | `SkinBlend(MeshData)`: скиннинг на CPU по `joints/weights` с нормализацией как в `mesh_skinned.vert`, пропуск при неизменных матрицах | engine | S | 3 | anim-01 | позиции = `MeshSkinnedVertexShader` из cpu (1e-4) |
| anim-03 ⚠ | `ProjectSkeleton`, `ProjectClip` в core; `fromModelDocument` читает skins/animations/targets; `toModelDocument` собирает `ModelSkin`/`AnimationClip`; секции проекта. Поглощает doc-26 (типы) | core | M | 3 | — | RiggedFigure/BoxAnimated/AnimatedMorphCube round-trip: joints, inverseBind 1e-6, треки побайтно |
| anim-04 | `KeyTable`: `setKey`, `moveKeys`, `deleteKeys`, `setInterpolation` (linear↔cubic), `setTangent`; `to/fromAnimationTrack`; команды `SetKey`, `MoveKeys`, `DeleteKeys`, `SetInterpolation`, `SetTangent`. Поглощает doc-26 (клипы) | core | M | 3 | anim-03 | `sample(t)` после правок; round-trip на InterpolationTest побайтно |
| anim-05 ⚠ | `PoseJoint(joint, path, frame)` — автоключ из позы, ключ на отпускание, транзакция | core | S | 3 | anim-04 | три `PoseJoint` в транзакции — один шаг, один ключ |
| anim-06 | `curveSamples`, `tangentHandles`, `valueRange`; Эйлер только для показа | core | S | 3 | anim-04 | step кусочно-постоянен; cubic = `AnimationTrack.sample` (1e-6) |
| anim-07 ⚠ | Экран 07: `TimelinePanel`, `SkeletonTree`, `ConstraintsList`, `ActionsList`; `AnimationPlayer` на инстансе; `playback` в Cubit, кадр в State. Поглощает таймлайн из ui-28 | app | L | 3 | anim-04, 06, 08 | перетаскивание ромба — `MoveKeys`; кадр `modeler-timeline` |
| anim-08 | Оверлей скелета через `DebugDraw.addLine` (октаэдры, крестики, `#FF458E` проблемные); пикинг сустава по проекции в экран, радиус 8 lp | app | S | 3 | anim-01 | кадр `skeleton-overlay`; клик по суставу 7 выбирает 7 |
| anim-09 ⚠ | `VertexWeights` персистентно; `paint`, `normalize`, `pruneTo`, `mirror`, `smooth`, `gradient`, `assignSelection`. Хранилище — слои mesh-60, операции — в `flutter3d_mesh/skin/` (§3) | mesh (rig?) | M | 3 | — | сумма 1±1e-6, ≤n влияний; зеркало на кубе; мазок 1 % ≤10 % копии |
| anim-10 ⚠ | `PaintWeights(joint, samples, strength, mode, mirror, normalize)` со списком вершин; попадание по `SkinBlend`-позициям через BVH; давление → strength | core | M | 3 | anim-09, anim-02 | мазок в согнутой позе попадает в локоть; один drag — один шаг |
| anim-11 | Веса градиентом через вершинный цвет. ⇢ view-18 | app | S | 3 | anim-09 | см. view-18 |
| anim-12 | Полоса 74: ползунок сгиба крутит `SceneNode` без истории, «Сбросить позу» через `Pose.restOf` | app | S | 3 | anim-01, anim-03 | ползунок меняет `poseVersion`, стек не растёт |
| anim-13 ⚠ | `rigIssues(project, profile)`: суставов > profile / > 64, влияний, нулевые суммы, ненормированные, неиспользуемые, неравномерный scale, треки на несуществующий узел, незапечённые IK/драйверы; кэш | core | S | 3 | anim-03, anim-09 | по проверке с мутацией |
| anim-14 ⚙ | `TwoBoneIk.solve` (закон косинусов, pole), `FabrikIk.solve` над `Pose`; `Pose.writeTo(targets)` | engine | M | 3 | anim-01 | достижимая цель 1e-4; pole задаёт сторону сгиба; FABRIK ≤10 итераций |
| anim-15 | `IkConstraint` в `ProjectSkeleton.constraints`, применение после FK; `BakeIk(clip, fps)`; экспорт всегда запекает | core | M | 3 | anim-14, anim-04 | после `BakeIk` эффектор в 1e-3 от цели |
| anim-16 ⚙⚠ | `ExtractRootMotion`, `BakeRootMotionIntoClip`; экспорт «в анимации»/«кодом» (extras `flutter3dRootMotion`); движок: `AnimationPlayer.rootMotionDelta` | core + engine | M | 3 | anim-04, anim-26 | корень стоит, сумма delta за цикл = 2 м; round-trip побайтно |
| anim-17 | `BoneMap` с `autoMap` по словарю гуманоида и L/R; `retargetClip` в rest-относительной форме, масштаб таза по росту, прижим стоп через `TwoBoneIk`; первый пункт пакета `flutter3d_rig` | rig | L | 3 | anim-01, anim-14 | тот же скелет — тождество; рост ×2 — стопа ≤1 см от пола; число пакетов в README/§3.2/§16 сдвинуто в том же коммите |
| anim-18 | Экран 14: библиотека клипов, два `RenderView`, дорожки смешивания через `crossFadeTo`/`layers`, таблица сопоставления, `RetargetClip` | app | M | 3 | anim-17, 03, 16 | импорт без скина — предупреждение; кадр `modeler-retarget` |
| anim-19 ⚠ | `SetShapeWeight`, `KeyShape` (weights-трек), `AddShapeFromMesh`, `RenameShape`, `DeleteShape` со сдвигом индексов, `ShapeSet`; строки экрана 15. Поглощает doc-27 | core + app | M | 3 | anim-04, anim-03 | `KeyShape` кадр 10 → sample; `DeleteShape` не ломает `AnimationTrack`; кадр `modeler-morphs` |
| anim-20 ⚠ | `ShapeDriver(shape, joint, axis, from, to, curve)`, оценка из `Pose`, аддитивно через `MorphSink`; `BakeDrivers(clip)` | core | M | 3 | anim-01, anim-19 | локоть 90° → 1.0, 45° → 0.5; запечённое = живое (1e-5) |
| anim-21 | `RigTemplate.humanoid/quadruped`, `buildSkeleton(template, markers, bounds, options)` → `ProjectSkeleton` с симметрией, ≤64 деформирующих | rig | M | 3 | anim-03 | число костей по таблице; L/R зеркальны 1e-6; `inverseBind·worldRest = I` |
| anim-22 ⚠ | `bindWeights`: оболочки по расстоянию до сегментов, видимость по BVH, smooth/mirror/prune/normalize; heat diffusion — после | rig | L | 3 | anim-09, anim-21 | цилиндр с двумя костями: стык 0.5/0.5; две «ноги» не тянут друг друга |
| anim-23 | Экран 16: силуэт в `RenderView`, 8 маркеров, шаблон/состав/привязка, `SetSkeleton` + `SetWeights` транзакцией | app | M | 3 | anim-21, 22, 25 | RobotExpressive → скелет ≤64, шаг истории; кадр `modeler-autorig` |
| anim-24 ⚙⚠ | Экран 19: бюджеты профиля (треугольники, кости, текстуры, влияния), `wireframeDeclined` честно. `FrameResult.triangles` ⇢ view-17 | app | M | 3 | anim-13, anim-03 | `skinnedDraws` = 1; maxJoints=16 на 19 суставах — оранжевая полоса |
| anim-25 ⚠ | `RigJob` (bindWeights, retargetClip, bakeIk, bakeDrivers, bakeRootMotion) через раннер doc-24/ui-25 с `TransferableTypedData` | core | M | 3 | anim-09 | через job = напрямую побайтно; отмена не меняет документ |
| anim-26 ⚙⚠ | GltfWriter: skins/animations/targets. ⇢ fmt-07 (фаза 1)² | engine | M | 3 | — | см. fmt-07 |
| anim-27 ⚙ | `.f3d` round-trip правленого рига; имя формы в `F3dRecord.morphTarget` (новая ревизия секции 15, если нет) | engine | S | 3 | anim-03, anim-19 | документы равны; обнулённое имя — красный |
| anim-28 | Паритет: `Pose.sampleClip` = `AnimationPlayer.seek` = `BakedPoses.of`; кадр `modeler-edited-clip` | core | S | 3 | anim-01, anim-04 | три пути 1e-5; мутация тангенсов ловится всеми |
| anim-29 | `AddJoint`, `RemoveJoint` (веса родителю + normalize), `ReparentJoint`, `RenameJoint`, `SetRestPose` с пересчётом inverseBind, `MirrorJoints`; перенумерация треков. Поглощает doc-26 (скелет) | core | M | 3 | anim-03, 09, 04 | после `RemoveJoint` сумма 1 и `Skeleton` строится; треки перенумерованы |
| anim-30 ⚠ | MCP: `setKey`, `paintWeights`, `autoRig`, `retargetClip`, `bakeIk`, `bakeDrivers`, `extractRootMotion`, `addShape`, `validateRig`; сценарий «RobotExpressive без скина → авториг → веса → ключи → GLB» | mcp | M | 3 | anim-13, 21, 26 | сценарий проходит; GLB с клипом и скелетом |
| anim-31 | Замер фазы 0 — только то, для чего код уже есть: FK `Skeleton.update` 64 × 1000 (`scene/skeleton.dart`); остальное — anim-31a-n (сужено по критике: мазок, `SkinBlend` и `bindWeights` меряют код фазы 3) | rig | S | 0 | — | число в doc с датой и машиной |
| anim-31a-n *(добавлено по критике)* | Замеры старта фазы 3: мазок 1 % на 200k (по слоям mesh-60/anim-09), `SkinBlend` 200k, `bindWeights` 100k; порог 8 мс для изолята | rig | S | 3 | anim-02, anim-09, anim-22 | числа в doc; (a) >10 % копии — пересмотр чанка до anim-10 |
| anim-32 ⚠ | `maxInfluences ∈ {1..4}`, `maxJoints ≤ 64` с текстом отказа; кисть и авториг читают лимит | core | S | 3 | anim-09, anim-13 | профиль с 8 влияниями отвергнут; кисть при 2 оставляет ≤2 |

### 2.8 Профессиональные режимы (`pro-`)

Из семи экранов фазы 4 движок закрывает только сырьё: UV в вершинном формате,
`LodGroup` по доле экрана, frame graph с внешним ресурсом версии 0, узлы
bloom/SSAO/composite, `readback`, программный растеризатор, `RigidBody` без
вращения. Ничего, что пишет геометрию или текстуру, нет. Почти всё считается на
CPU в чистом Dart и тестируется `dart test`; движок получает три правки контракта
(буфер, область текстуры, внешний HDR-вход) плюс LOD в документе. Честная
граница: LSCM + проекция, мультиразрешение, ретопология «упрощение → квады →
проекция», CPU-запекание, XPBD-ткань, снимок растеризатором, QEM с UV и весами,
покраска со слоями — в фазе 4; ABF++, dyntopo, quadriflow, GPU-запекание,
самопересечение ткани, вращение тел, трассировщик — после.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| pro-job-01 ⚠ | `Job<T>` с `progress`/`cancel`, изолят на нативе, `step()` порциями на вебе. ⇢ doc-24 + ui-25 (один раннер)¹ | core | S | 2¹ | — | 100 шагов монотонно; отмена на середине; чужой microtask между шагами |
| pro-eng-01 ⚙⚠ | `overwriteGeometry` + `DeviceMesh.overwriteVertices(firstVertex, count)`. ⇢ view-14 | hw + бэкенды | M | 2 | — | см. view-14 |
| pro-eng-02 ⚙⚠ | `overwriteTexture(texture, region, rgba)` только RGBA8 базовый уровень; Impeller — весь уровень из CPU-копии; конформанс «область читается обратно» | hw + бэкенды | M | 3 | — | readback региона теми же байтами; отказ на сжатом/mip>0 |
| pro-eng-03 ⚙⚠ | `Renderer.renderPost(hdr, settings)` с внешним ресурсом версии 0, `keepHdr: true`; сцена `post-only` | engine | M | 4 | — | полный кадр = сцена без post + `renderPost`; версия 1 отбраковывается графом |
| pro-eng-04 ⚙ | Смещённая перспектива `TiledProjection(base, tileX, tileY, tilesX, tilesY)` для тайлового снимка | engine | S | 4 | — | 2×2 тайла 240×180 сшиты = кадр 480×360 побайтно |
| pro-eng-05 ⚙ | `FrameResult.passes: (name, active, micros)` по `CompiledFrameGraph.order` | engine | S | 4 | — | без bloom `bloom` отсутствует в `passes` |
| pro-eng-06 ⚙⚠ | `ModelNode.lods: ModelLod(surfaceIndices, maxScreenFraction)`, секция `LODS` (kind 24 — сегодня максимум 16, fmt-03/04/19/28 занимают 17–23) в `.f3d`, `LodGroup` в `ModelAsset`, `MSFT_lod` в glTF; сцена `lod-asset` | engine | M | 4 | — | round-trip `.f3d` и GLB; старый `.f3d` грузится |
| pro-eng-07 ⚙⚠ | Ленты заданной толщины в оверлее (экранное расширение отрезка) для швов 3,5 lp, сетки ретопологии 1,6, обводки 2. Расширяет view-05 (там ленты собираются на CPU) | engine | S | 4 | — | сцена `overlay-ribbon`; ширина не зависит от глубины |
| pro-uv-01 ⚠ | Флаг `seam` в `EditMesh` ⇢ mesh-12 (фаза 1); `MarkSeamCommand(selection)` и оверлей — здесь | mesh + core | S | 4 | — | швы переживают экструзию; снимок пометки копирует один чанк |
| pro-uv-02 | `splitIslands(mesh, seams)`, `lscm(island)` — разреженная система на CSR, сопряжённые градиенты, две закреплённые вершины; UV по углам; `Job` по островам. Поглощает mesh-71 | mesh | L | 4 | pro-uv-01, pro-job-01 | плоская сетка 10×10 в себя (1e-4); цилиндр в прямоугольник; 50k граней <2 с AOT |
| pro-uv-03 | `projectUv(island, planar|box)` — второй чип вместо ABF++ | mesh | S | 4 | pro-uv-01 | куб → 6 островов без растяжения |
| pro-uv-04 | `stretchOf(island)` по Sander (L2 через сингулярные числа якобиана) | mesh | S | 4 | pro-uv-02 | изометрия 1,0±1e-6; сжатие вдвое — известное число |
| pro-uv-05 | `packIslands(islands, margin, allowRotate90)` — полки/skyline, бинарный поиск масштаба, `fillRatio` | mesh | M | 4 | pro-uv-02 | AABB не пересекаются с отступом; 100 прямоугольников ≥60 % |
| pro-uv-06 ⚠ | `UnwrapCommand(selection, method, margin, autoPack)` с переприменением; UV в `texcoord` через расщепление швов; MCP `unwrap` | core + mcp | S | 4 | pro-uv-02, pro-uv-05 | `toMeshData().layout.has(texcoord)`, вершины выросли на швовые углы; MCP-сценарий куб → GLB с UV |
| pro-uv-07 | Экран 06: `RenderView` со швами слева, `CustomPainter` 400×400 справа (шахматка 32, острова, цвет по растяжению, клик), панель метода/отступа/списка. Поглощает view-19 | app | M | 4 | pro-uv-06, pro-eng-07 | три острова, растянутый `#FF458E`; швы видны в 3D |
| pro-sc-01 | Замер 1,2 млн под мазок на macOS/Chrome/A55: upload 38 МБ, кадр, правка 20k вершин + нормали + overwrite, BVH build/raycast, мусор на событие; пороги 8/16 мс, 3 с | core + tool/bench | S | 4 | pro-eng-01 | числа в doc §6; решение по pro-sc-09 |
| pro-sc-02 ⚠ | `SculptMesh`: чанки по 1024 вершины CoW, `triangles`, CSR-смежность, сетка по вершинам, конверсия `EditMesh ↔ SculptMesh` на входе/выходе режима. Один чанковый тип с mesh-10; структура выбрана 2026-09-09 (Б8 закрыт): `SculptMesh`, не патч-слой mesh-72; pro-sc-01 меряет её, а не выбирает | mesh | L | 4 | pro-sc-01 | мазок 1 % копирует ≤2 % чанков; радиус = перебор; конверсия сохраняет позиции и UV |
| pro-sc-03 | Кисти draw/clay/smooth/flatten/inflate/grab/pinch/crease, `Brush(kind, radius, strength, falloff)`, симметрия по X, локальные нормали | mesh | M | 4 | pro-sc-02 | по кисти тест с мутацией; симметрия зеркальна 1e-6 |
| pro-sc-04 ⚠ | BVH по треугольникам `SculptMesh` с `refit(dirtyTriangles)`. Тот же `TriangleBvh` (§3) | mesh | M | 4 | pro-sc-02 | рейкаст = перебор; refit = перестроение |
| pro-sc-05 | Грязные чанки → `DeviceMesh.overwriteVertices`, не чаще кадра; фолбэк — новый `DeviceMesh` в кадр | app | S | 4 | pro-eng-01, pro-sc-03 | кадр отличается только в области кисти; замер (в) в пороге |
| pro-sc-06 ⚠ | `SculptStrokeCommand(brush, points, pressures)` — один шаг, `historyBudgetBytes` 512 МБ; MCP `sculpt_stroke` | core | S | 4 | pro-sc-03 | 100 мазков по 1 % на 200k <10 % от 100 копий; undo побайтно |
| pro-sc-07 ⚠ | `Multires(base, levels)`: подразбиение фазы 2, дельты в локальном базисе, спуск для экспорта с картой смещений; dyntopo — после (Б9 закрыт 2026-09-09: мультиразрешение) | mesh | L | 4 | pro-sc-02, pro-sc-03 | куб 5 уровней; спуск/подъём сохраняют смещения 1e-4; до 1,2 млн <5 с |
| pro-sc-08 | Экран 08: раскладка без панелей, палитра 48, карточка 250, курсор ⌀140, `pressure`, touch — орбита; кнопка «Подразбить» (уровень `Multires`) вместо «плотности кисти» в макете — следствие Б9 (решение 2026-09-09), дизайн экрана 08 правится. ⇢ ui-29 (оболочка), view-21 (курсор) | app | M | 4 | pro-sc-05, pro-sc-06 | см. ui-29, view-21 |
| pro-sc-09 | Веб: `ProjectProfile.sculptTriangleLimitWeb` по замеру, BVH с уступкой кадру | app + core | S | 4 | pro-sc-01, pro-sc-08 | число в профиле; мазок на 300k <16 мс на wasm |
| pro-lod-01 | QEM Garland–Heckbert над `MeshData`: квадрики, куча на `Float64List`/`Int32List`, проверка переворота, `Job` по 1000 коллапсов. Поглощает mesh-70 | mesh | L | 4 | pro-job-01 | сфера 20k → 2k, Хаусдорф <1 % радиуса; 200k → 20k <3 с AOT |
| pro-lod-02 | Квадрики с атрибутами (Hoppe): штраф швов/границ, перенос `joints/weights` с перенормировкой и лимитом профиля | mesh | M | 4 | pro-lod-01 | швы ⊂ исходных; сумма весов 1; кадр `lod-uv` |
| pro-lod-03 | `ModelObject.lods: List<LodSpec(ratio, maxScreenFraction)>` с кэшем по версии; `AddLod`, `SetLodRatio`, `RegenerateLods`; метры ↔ доля экрана в редакторе | core | S | 4 | pro-lod-02, pro-eng-06 | правка базы инвалидирует кэш; round-trip |
| pro-lod-04 | Экран 17: три `RenderView` по третям с `layerMask`, подписи, полоса 96 с зонами. Поглощает view-20 | app | M | 4 | pro-lod-03 | три трети различаются; widget-тест ползунка |
| pro-rt-01 | `retopologize(source, targetQuads)`: упрощение → жадная квадрификация → shrink-wrap по BVH; quadriflow — после. Поглощает mesh-73 | mesh | L | 4 | pro-lod-01, pro-sc-04 | квадов ≥70 % на сфере и торе; расстояние <0,5 % диагонали |
| pro-rt-02 ⚠ | `DrawQuadCommand(4 × world)` с рейкастом и прилипанием; активный квад — переприменение; вершины с проекцией | core | M | 4 | pro-rt-01 | четыре точки на сфере → квад на поверхности |
| pro-rt-03 | Оверлей ретопологии: исходник с `alpha`, сетка лентами 1,6, активный квад `#FF458E` 22 % | app | S | 4 | pro-eng-07, pro-rt-02 | кадр `retopo-overlay` при двух прозрачностях |
| pro-rt-04 | `bake/`: UV-растеризатор low-меша, лучи ±оболочка в BVH high-меша → карта нормалей в тангенс-пространстве, дилатация; GPU-путь — после | mesh | L | 4 | pro-sc-04, pro-job-01 | сфера→куб: центр грани = аналитика (<2/255); 1024² на 100k <10 с |
| pro-rt-05 | AO (Хальтон, косинус), кривизна, толщина на той же растеризации | mesh | M | 4 | pro-rt-04 | плоскость AO=1; угол 90° ≈0,5 |
| pro-rt-06 ⚠ | `BakeCommand(source, target, maps, resolution, shell)` → `EncodedImage` и `TextureBinding`; MCP `bake_maps` | core + mcp | M | 4 | pro-rt-05, pro-rt-01 | сценарий сфера → скульпт → ретопо → bake → GLB; кадр `bake-relief` |
| pro-rt-07 | Экран 10: панель 290 в два блока, прогресс на месте кнопки | app | S | 4 | pro-rt-06, pro-rt-03 | Job меняет кнопку на индикатор; отмена |
| pro-sim-01 ⚠ | `flutter3d_cloth` — отдельный плоский солвер, фаза 4 (В3/И1 закрыты 2026-09-09): XPBD (расстояние, изгиб cross-edge, закреплённые, гравитация, ветер, демпфирование, подшаги), столкновения с `CollisionShape` из physics; детерминизм как в sim | cloth (новый) | L | 4 | — | ткань 20×20 в покое за 300 шагов; ошибка длины <1 %; побайтно при одном seed; число пакетов в README/§3.2/§16 сдвинуто в том же коммите |
| pro-sim-02 ⚠ | Твёрдое тело через `Dynamics`/`RigidBody` (без вращения, с подписью), частицы через `ParticleSystem` в кэш | core | S | 4 | pro-sim-03 | куб падает и останавливается; частицы детерминированы |
| pro-sim-03 | `SimulationCache(frames, vertexCount)`, `BakeSimulationCommand` как Job, секция проекта, полоса кэша | core | M | 4 | pro-sim-01, pro-job-01 | 120×400 — ожидаемый размер; отмена на 50-м оставляет 50 |
| pro-sim-04 | Проигрывание кэша через `overwriteVertices` целиком, столкновения `DebugDraw` | app | S | 4 | pro-sim-03, pro-eng-01 | кадры 0 и 60 различаются; 4k вершин <2 мс |
| pro-sim-05 ⚠ | Экспорт симуляции: (а) ≤8 морф-целей, (б) секция вершинной анимации `.f3d` + узел, (в) только предпросмотр; рекомендация (а) | core | M | 4 | pro-sim-03 | ткань → 8 целей → GLB → кадр = кэш (`cloth-morph`) |
| pro-sim-06 | Экран 11: чипы типа, параметры, взаимодействия, полоса 150 с транспортом и кэшем | app | M | 4 | pro-sim-04, pro-sim-02 | widget-тесты; закрепление через выделение фазы 1 |
| pro-rn-01 | Замер `flutter3d_cpu` на 1080p и 4К с тенями/SSAO/bloom, AOT и wasm; порог 4К SSAA×2 <3 мин на M3 | cpu | S | 4 | — | числа в doc §4.2 |
| pro-rn-02 ⚠ | `RenderSnapshotJob(project, RenderPreset)`: снимок тем же рендерером — своё `CpuDevice`, тайлы, SSAA ×1/×2, проходы frame graph (pro-eng-05), PNG; изолят на нативе, тайл за кадр на вебе; трассировщик вне плана, слово «сэмплы» из макета экрана 12 уходит (решение 2026-09-09) | core | M | 4 | pro-rn-01, pro-eng-04, pro-job-01 | 480×360 = golden побайтно (×1); ×2 <1 % пикселей |
| pro-rn-03 ⚠ | `CompositeGraph` — фиксированный DAG Scene → SSAO → Reflections → Bloom → Tonemap → Look → Output ↔ `RenderSettings`; post-правка через `renderPost` | core | M | 4 | pro-eng-03, 05, pro-rn-02 | round-trip; правка bloom помечает только post-ветку |
| pro-rn-04 ⚠ | Экран 12: панель проходов из `passes`, результат 760×428 с прогрессом тайлов, граф 260 (виджет из mat-13); MCP `render_snapshot` | app + mcp | M | 4 | pro-rn-03 | снимок 96×64 = `renderFrame` |
| pro-pt-01 | `PaintLayer` + `PaintStack.flatten`, режимы normal/multiply/add/overlay/screen, тайлы 64×64 CoW | core | S | 4 | — | по режиму известные числа; порядок слоёв |
| pro-pt-02 | `projectBrush(mesh, bvh, hit, radius) → List<UvSpan>` через растеризатор pro-rt-04, falloff в 3D | mesh | M | 4 | pro-rt-04, pro-sc-04 | мазок через шов красит оба острова; тексели вне 3D-радиуса не тронуты |
| pro-pt-03 | `PaintStrokeCommand`, `overwriteTexture` грязным прямоугольником раз в кадр, мипы по завершении, маски AO/кривизны; MCP `paint_stroke` | core + mcp | M | 4 | pro-pt-01, 02, pro-eng-02 | кадр отличается только в области; маска AO=0 гасит; undo побайтно |
| pro-pt-04 ⚠ | Сведение слоёв в `baseColorTexture` при экспорте, слои в секцию проекта, импортированная текстура — фоновый слой | core | S | 4 | pro-pt-03 | кадр `paint-export` |
| pro-pt-05 | Экран 18: курсор ⌀96, панель развёртки 300 с `ui.Image` из flatten, слои/палитра/маски | app | M | 4 | pro-pt-03, pro-uv-07, pro-sc-08 | холст обновляется после мазка |
| pro-doc-01 ⚠ | Секции `SEAM`, `UVIS`, `MRES`, `BAKE`, `SIMC`, `PNTL`, `LODS`, `RNDR` с версиями; проект фазы 1 читается | core | M | 4 | pro-uv-01, sc-07, rt-06, sim-03, pt-01, lod-03, rn-03 | round-trip каждой; файл фазы 1 открывается |
| pro-test-01 | Восемь кадров фазы 4, MCP-сценарий «куб → … → GLB», числа | app + mcp | M | 4 | pro-uv-07, sc-08, rt-07, sim-06, rn-04, lod-04, pt-05 | `ci.sh` зелёный; сценарий воспроизводится |
| pro-after-01 | Раздел «после фазы 4» в doc с причинами по каждому отложенному; отдельной строкой — «совместная работа» из фазы 4 плана дизайна и README передачи («основание для будущей совместной работы»): в план не входит, задел — журнал команд doc-16 и команды как значения (добавлено по критике) | doc | S | 4 | pro-sc-01, pro-rn-01 | согласован владельцем; строка о совместной работе ссылается на doc-16 |

### 2.9 Тесты, CI, структура (`qa-`)

Инфраструктура жёсткая и уже есть: 30 правил сканера, `tool/ci.sh`,
`flutter3d_testing`, 33 конформанс-проверки, образец агентского сценария в CI.
Проверено: `main` красный по трём причинам из HANDOFF — блокер фазы 0. Пробой
детектора: `brush`, `bone`, `face`, `bevel`, `loop`, `manifold` проходят;
`dashed`, `reload`, `spike`, `oneWay`, `lap`, `boss`, `magazine` — нет.
Списки числительных сканера кончаются на twenty-eight (пакеты) и forty-five (сцены).

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| qa-01 | Зелёный `main`: `dart format` четырёх файлов, 4322 → 4327 в четырёх документах, guard WebGPU через `requestAdapter()` | repo | S | 0 | — | 30 of 30; format молчит; три зелёных прогона подряд; дата в HANDOFF |
| qa-02 | Три пакета, `geometry`, `formats` и приложение под сканером: workspace, `flatDartPackages` с причинами, `applications`, `notARepeatableStep`, числительные до forty (28 сегодня + geometry/formats/mesh/core/mcp = 33 к концу фазы 0, до 37 с editor_widgets/rig/cloth/fbx; список в `rules.dart` расширяется до появления каталога, как требует его же комментарий), §16, README, `packages.md`, `testing.md`, Info.plist, CHANGELOG/LICENSE/README. Общий с mesh-00, doc-02, ui-01, rel-02/03 | tool/structure + docs | S | 0 | qa-01 | сканер зелёный с шестью каталогами; `publish_check.sh` доволен |
| qa-03 ⚠ | Правило «a flat Dart package resolves without the Flutter SDK»: обход `dependencies` до `flutter: sdk`; доказательство детектора; счёт правил 30 → 31 в шести местах | tool/structure + docs | S | 0 | qa-02 | зелёное на трёх плоских; красное на мутации и на model_core → flutter3d |
| qa-04 | `ci.sh` читает список `dart test` из `flatDartPackages` (`--flat-dart`); `-p chrome` для mesh; процессный тест `dart run bin/model_mcp.dart`. Поглощает doc-30 | tool | S | 0 | qa-02 | удаление имени из списка меняет команду без правки скрипта |
| qa-05 | Словарь запрещённых слов в doc и CONTRIBUTING (`dashed` → `dotted`, `reload` → `reopen`, `spike` → `peak`); примеры в `proveDetectorsWork` | tool/structure + docs | S | 0 | — | `dashedAxis` зажигает, `bevelWidth` молчит |
| qa-06 | Политика enum и публичных членов: `ElementLevel`, `IssueSeverity` — enum с экземпцией; содержимое — sealed; тест как вызывающий | tool/structure + docs | S | 1 | qa-02 | скелет с enum и sealed проходит; таблица в doc |
| qa-07 ⚠ | Аудит инвариантов half-edge, χ по операциям, манифолдность, round-trip, фазз с сидом, персистентность ≥90 % чанков. ⇢ mesh-11 (`validate`), mesh-32 (фазз), mesh-10 | mesh | M | 1 | qa-02, qa-04 | см. mesh-11/32; зелёный на VM и `-p chrome` |
| qa-08 ⚙⚠ | Round-trip писателей и STL-фикстуры с провенансом в `assets/ATTRIBUTION.md` пакета `flutter3d_samples` (там провенанс записан сегодня, по файлу с автором и источником; `LICENSES.md` лежат только в `apps/*/assets/`), bump samples 0.4.2 → 0.4.3. ⇢ fmt-06/07/08/09/10 (тесты там) | engine + samples | M | 1 | qa-01 | см. fmt-*; допуск 1e-6, не побайтно |
| qa-09 | glTF-Validator в `ci.sh`. ⇢ fmt-11 | tool | S | 1 | qa-08 | см. fmt-11 |
| qa-19n *(добавлено по критике)* | Проверка экспорта во внешнем движке автоматически, как требует план дизайна («экспортированный файл открывается в Godot и Unity» автотестом): headless Godot (`godot --headless --import` + скрипт, печатающий число мешей/треугольников/материалов) на фикстурах doc-21 и rel-09 в отдельном job CI; Unity и Blender — ручной чек-лист перед релизом (К2 закрыт 2026-09-09; headless-лицензии Unity в CI нет) | tool + ci | S | 1 | fmt-11, doc-21 | job зелёный на `table.glb` и GLB туториала; число мешей и треугольников совпадает с `compareModelDocuments`; время шага в `ci.yml` |
| qa-10 ⚙⚠ | Сцены `mesh-overlay` (⇢ view-05) и `material-preview` (⇢ mat-15 в app, не в 43 сценах); бюджеты, `_provisional`, forty-three → forty-four | engine example + бэкенды | M | 1 | qa-01 | см. view-05; `_provisional` пуст к мержу |
| qa-11 ⚙⚠ | Конформанс-проверка перезаписи буфера, 33 → 34. ⇢ view-14³ | conformance + hw | M | 2³ | qa-01 | см. view-14; Impeller-прогон с датой в HANDOFF |
| qa-12 ⚠ | Сценарий «агент строит стол» и `tools_test` round-trip. ⇢ doc-20, doc-21 | mcp | M | 1 | qa-02, qa-04 | см. doc-21 |
| qa-13 ⚠ | Бенч-артефакт CI `bench-mesh` (⇢ mesh-04/31), стресс-сцена и `FrameTimingLog` (⇢ p0-01/02/03), таблица в HANDOFF и doc | mesh + engine + ci | M | 0 | qa-02 | артефакт в каждом `check`; таблица с машиной |
| qa-14 | `draw_count_baseline_test` на CPU с точными числами. ⇢ view-22 | cpu | S | 1 | qa-01 | см. view-22 |
| qa-15 ⚠ | Тесты приложения через растеризатор. ⇢ ui-26 (+ `scaffold_test`, `theme_test` из ui-05/ui-02) | app | M | 1 | qa-02, qa-14 | см. ui-26 |
| qa-16 | Документы догоняют дерево: README, `packages.md`, `testing.md`, §3.2/§13/§16, skills, рецепт «новый тест → `structure.dart` → четыре документа». Общий с rel-07, fmt-16 | docs + site | S | 1 | qa-02 | сканер зелёный после каждого мержа; 33 пакета и 7 приложений |
| qa-17 ⚠ | Веб-сборка редактора (wasm), `flutter build macos`, iOS `--no-codesign`, Android-матрица в CI; время шагов записано | tool + ci | S | 1 | qa-02, qa-13 | сборки зелёные; время до/после в `ci.yml` |
| qa-18 ⚠ | Тесты формата проекта, команд, истории, `ExportReadiness`. ⇢ doc-05/08/10/14 (тесты там) | core | M | 1 | qa-02, qa-07 | см. doc-*; фикстура одинакова на ubuntu и macOS |

### 2.10 Фаза 0: замеры (`p0-`)

Инструменты замера уже есть, но разрознены: `Timeline` вокруг проходов,
`FrameResult.cpuMicros/submitMicros/drawCalls`, `FrameTimingLog`, HUD примера,
`bench_util.dart`; форма записи задана ARCHITECTURE §14 и `tool/webgpu_spike/README.md`
(«The answer»). Пять пунктов проработки разложены на двенадцать единиц; половина
решений §7 принимается порогом на числе, и для каждого записан порог и действие
при каждом исходе.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| p0-01 ⚠ | Стенд: `StressSource` в примере движка (`FLUTTER3D_STRESS_TRIANGLES`, `_OBJECTS`), орбита на 600 кадров, HUD с `FrameTimingLog` и временем загрузки, генератор `.f3d`/GLB на 1 млн, Android-раннер примера с `EnableFlutterGPU`. Общий стенд для view-01, qa-13, ui-00 | engine example + tool/model_spike | S | 0 | — | profile-запуск на macOS печатает тайминги; wasm собирается; тест 10k треугольников через golden |
| p0-02 | Замер 0.1: macOS Metal, Chrome WebGL2/WebGPU, JS и wasm; один меш на 1 млн и 1000×1000; build/raster mean/worst, `cpuMicros`, загрузка, память; три прогона | doc | S | 0 | p0-01 | ворота качества (решение 2026-09-09: веб равноправен, замер не выбирает «просмотр»): ≤16,6 мс → бюджет веб-профиля 1 млн; 16,6–33 → бюджет профиля ≤300k; >33 или загрузка >10 с → в фазу 1 входит то, что нужно для прохождения — JS-сборка как записанное исключение ARCHITECTURE §1, порции вместо изолята (p0-07), ui-34d; до 2026-10-05 |
| p0-03 | Замер 0.1 на Galaxy A55 (200k/500k/1M, загрузка через изолят, память) и на iPad после rel-19d | doc | S | 0 | p0-01 | значение при ≤16,6 мс → «мобильный» пресет профиля; 200k >33 мс → мобильный пресет ужимается до прошедшего бюджета, телефон остаётся платформой фазы 1 (решение 2026-09-09) |
| p0-04 ⚠ | Спайк `EditMesh` (куб → экструзия → toMeshData → кадр) с бенчем 50/200k. ⇢ mesh-01 (в пакете, не в `tool/`); пороги: ≤8 мс → перестройка целиком в кадр; 8–33 → `writePositions(into:)` в 1.2 и p0-06 обязателен; >33 → пересмотр структуры | mesh | M | 0 | p0-09 | см. mesh-01; ответ до 2026-09-25 |
| p0-05 ⚠ | Персистентность: `ChunkedFloat32` (128/256/1024) против `PatchedFloat32` (журнал прежних значений), кластер и случайное распределение, RSS за 64 шага. ⇢ mesh-02 | mesh | S | 0 | p0-04 | ≤10 % копии и ≤2 мс в обоих → чанк фиксируется; только кластер → плоский массив + журнал; ни одно → снимок на транзакцию |
| p0-06 ⚙⚠ | `DeviceMesh.upload` в кадр против прототипа `overwriteGeometry` (Impeller `DeviceBuffer.overwrite`, WebGL `bufferSubData`, WebGPU `writeBuffer`) на 200k при 1 % правок; прототип в ветке | engine example + hw (ветка) | M | 0 | p0-01 | (а) ≤16,6 мс → overwrite в фазу 4; (б) проходит → view-14 в фазу 1; ни одно → предпросмотр оверлеем |
| p0-07 ⚠ | `Isolate.run` (с/без `TransferableTypedData`) против порций с уступкой на wasm для fromMeshData+toMeshData на 200k | mesh + engine example | S | 0 | p0-04 | накладные ≤20 % / ≤50 мс; порции: worst ≤50 мс и +≤25 % → операции пошаговые с первого дня; иначе заморозка с прогрессом на месте кнопки (Е11), а при заморозке >1 с на эталонной операции — ui-34d в фазе 1 |
| p0-08 ⚠ | Веб-спайк файлов под `tool/`: `openFile` → `readAsBytes` → `decodeModel` → кадр; скачивание через `package:web`; `--wasm`; Chrome/Safari/Firefox; `.gltf` с `.bin` через `openFiles`; 30 МБ. Код переходит в ui-14 | tool/web_files_spike | S | 0 | — | ворота качества: (1)–(3) проходят → 1.15 берёт код; не собирается под wasm → JS-сборка как записанное исключение; Safari/Firefox нет → своя обёртка через `package:web` в ui-14 (веб равноправен, решение 2026-09-09); заморозка >1 с на 30 МБ → ui-34d |
| p0-09 ⚙⚠ | Три скелета под сканером + проверка в контейнере `dart:stable` без Flutter + правило на транзитивную SDK-зависимость. ⇢ doc-00 (спайк), qa-02 (регистрация), qa-03 (правило), rel-04 (контейнер) | packages + tool/structure | S | 0 | — | см. doc-00/qa-03; ответ до 2026-09-25 |
| p0-10 ⚠ | Прототип `TriangleBvh` (становится реализацией view-09) + проекция вершин/рамка на 50k/200k/1M против `Raycaster` перебором. ⇢ mesh-20 / view-09 (одна реализация, §4); здесь — замер | mesh | S | 0 | p0-04 | луч ≤1 мс/200k, ≤3 мс/1M, build ≤100 мс, проекция ≤4 мс → пикинг на CPU; иначе окрестность по half-edge / id-проход граней в фазе 2 |
| p0-11 ⚠ | Сквозной конвейер перетаскивания на 600 кадров: правка → снимок → toMeshData → буфер → кадр; GC-паузы, аллокации, доля медленных кадров | mesh + engine example | S | 0 | p0-01, 04, 05, 06 | нет пауз >8 мс и ≤5 % медленных → API на значениях; 8–16 → `toMeshData(into:)`, снимок на транзакцию; >16 → изменяемый рабочий режим внутри транзакции |
| p0-12 | README спайков «The answer», таблица §6 с измеренными значениями (дата, машина, Dart), §7 со столбцом «решено», дубли в ARCHITECTURE §14 | doc | S | 0 | p0-02..11, p0-13n | ни одной строки фазы 0 без числа; §7 без «решает замер»; срок 2026-10-05 |
| p0-13n ⚠ *(добавлено по критике)* | Спайк «сохранение под сандбоксом macOS»: `file_selector.saveFile` + прямая запись без rename, против `writeFileAtomically` (временный файл + rename — под `user-selected.read-write` rename в каталог выбранного файла не разрешён; редактор уровней выключил сандбокс именно с этой формулировкой в `Release.entitlements`), против security-scoped доступа к каталогу. Ответ закрывает Е4 и native-ветку ui-14 | app (спайк под `tool/`) | S | 0 | ui-00 | таблица «способ × сандбокс → записалось / `PathAccessException`»; выбранный способ записан в ui-14 и Е4 |

### 2.11 Публикация и продукт (`rel-`)

Инфраструктура выхода почти вся автоматическая: `publish_check.sh`, сборка
API-справочника по каталогам, `llms.txt` из NAV, `demos.sh`, CI строит iOS без
подписи и Android с ключом. Набор на 0.6.0, 27 из 28 на pub.dev; имена
`flutter3d_mesh`, `flutter3d_model_core`, `flutter3d_model_mcp`, `flutter3d_modeler`
свободны (проверено 2026-09-09), как и `flutter3d_geometry`, `flutter3d_formats`,
`flutter3d_fbx`, `flutter3d_cloth`. Точки трения — ручные списки; сайт не показывает четвёртую
игру, так что «рядом с четырьмя играми» опирается на незакрытый пункт ROADMAP.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| rel-01 | Зафиксировать имена (решение 2026-09-09, В5: mesh / model_core / model_mcp, geometry / formats, app `flutter3d_modeler`, bundle `dev.flutter3d.modeler`; код в этом монорепозитории) в doc §7 с датой проверки | doc + ARCHITECTURE | S | 0 | — | строка «Название» с датой; те же имена в §16 |
| rel-02 | Каркас трёх пакетов, зелёный в `publish_check` (version = набор, `resolution: workspace`, `^0.6.0` на соседей, LICENSE/CHANGELOG); в mcp — заглушка `bin/model_mcp.dart`, отвечающая на `--help` (нужна rel-04 в фазе 0; настоящий сервер — doc-19). Общий с qa-02 | mesh, core, mcp | S | 0 | rel-01, mesh-00 | `publish_check.sh` печатает `ready` для трёх; `dart run flutter3d_model_mcp:model_mcp --help` печатает usage |
| rel-03 ⚠ | Сканер, §16 (`geometry` раньше `formats`, `formats` раньше `flutter3d`; mesh после `geometry`, core после `formats`, `editor_core` после `formats` — новая зависимость mat-03, mcp ярусом ниже; порядок по решению 2026-09-09), `ci.sh`, числительные. ⇢ qa-02/qa-04 | tool + ARCHITECTURE | S | 0 | rel-02 | см. qa-02 |
| rel-04 | Job на `setup-dart` без Flutter: временный pubspec с `dependency_overrides`, `dart pub get`, `dart run …:model_mcp --help` (заглушка из rel-02; `tools/list` в контейнере — приёмка doc-19); тот же скрипт для `editor_mcp`. ⇢ doc-00/qa-03 (контейнерная половина). Зависимость от doc-19 снята по критике: пункт фазы 0 ждал пункт фазы 1 | mcp + ci | S | 0 | rel-02, rel-03 | зелёный на чистом SDK; красный при `flutter: sdk` |
| rel-05 | Место в поезде: §16 «carries X and does not go out» для пяти новых пакетов до набора, в котором выходит rel-06 (после rel-16; В8 — 27 декабря целью не является); CHANGELOG под номером следующего набора по ходу; один тег на набор | ARCHITECTURE + CHANGELOG | S | 1 | rel-02, rel-03 | §16 называет, кто выходит; правило версий зелёное |
| rel-06 | Первая публикация в порядке §16 (geometry → formats → flutter3d → mesh → core → mcp), сверка архива с деревом (skills/ в архиве), README/`index.md`/`packages.md`, `deploy-docs.sh`. Решение 2026-09-09 (В8): только когда фаза 1 в руках у первых пользователей — после rel-16; 27 декабря целью не является | mesh, core, mcp, geometry, formats + site | S | 1 | rel-05, rel-14, rel-16, doc-10, doc-14 | pub.dev отвечает 200; pub points ≥150; /docs/ с 33 пакетами |
| rel-07 | README «What is here», §3.2, `packages.md`, `testing.md`, `quickstart.md`, счётчики. Общий с qa-16 | docs + site | S | 0 | rel-02, rel-03 | сканер зелёный; `rg 'twenty-eight'` только в §16 |
| rel-08 | Секция сайта `Modeler` (badge `tool`): `index.md`, `tutorial.md`, `demo.md`; карточка на главной; картинки из тестов app в `site/assets/modeler/` или расширение `goldenSets` | site | M | 1 | rel-07, ui-04 | три страницы в сайдбаре и `llms.txt`; картинки существуют |
| rel-09 | Туториал «ассет из импорта в движок за 15 минут» шагами; тот же сценарий как `tutorial.jsonl` через MCP в CI с диффом GLB и кадром; измеренное время с датой; `first-project.md` — четыре шаблона | site + app + mcp | M | 1 | rel-08, ui-16/17, doc-20, fmt-06 | сценарий в CI; `GltfLoader` без warnings; время с машиной на странице |
| rel-10 ⚠ | `"modeler:apps/flutter3d_modeler"` в `demos.sh`, `demo.md` с iframe и full screen; тем же компилятором, что шипит сайт (dart2js без wasm); COOP/COEP проверить в Safari; веб-демо редактирует, не только показывает — при непройденных воротах p0-02 сначала делается то, что их закрывает (решение 2026-09-09) | site + app | M | 1 | rel-08, ui-14, p0-02 | /demo/modeler/ открывает GLB и скачивает в Chrome и Safari |
| rel-11 | `flutter build macos --release` в job `macos`, `upload-artifact`, GitHub Release на тег; подпись и нотаризация не в фазе 1, релиз открывается «правый клик → Open» (Е8, решение 2026-09-09) | ci + app | S | 1 | rel-03, ui-20 | артефакт открывается на чистом Mac через «правый клик → Open»; Release несёт zip |
| rel-12 ⚠ | Запись в ROADMAP на ревизии 28 сентября: трек «A modeller, and the same agent driving it» с Acceptance; правка «After this quarter» об экспортёре, «Not doing» о графе, `apply and revert` (⇢ doc-29) | ROADMAP | S | 0 | rel-01, rel-17 | ROADMAP с датой ревизии содержит трек; согласован с doc §4 |
| rel-13 ⚙⚠ | Модели шаблонов редактора уровней из документов редактора моделей: исходники в `tool/models/`, `dart run flutter3d_model_core:export`, `git diff --exit-code`; требует детерминированного `GltfWriter`; опция — пятый шаблон `showcase` | tool + шаблоны редактора уровней + core | M | 2 | rel-09, fmt-06, doc-10 | `make_templates.py && git diff --exit-code` зелёный на macOS и ubuntu |
| rel-14 | Skills `editing-order`, `model-document`, `what-it-refuses` + `skills_test` (и для `editor_mcp`). ⇢ doc-22 | mcp | S | 1 | rel-02, doc-20 | см. doc-22; `--dry-run` показывает skills/ в архиве |
| rel-15 | `modeler_report.yml` (label `modeler`), кнопка «Report a problem» с предзаполненным URL без телеметрии, `bug_report.yml` с четырьмя бэкендами | .github + app + site | S | 1 | rel-08, doc-14 | форма в chooser; widget-тест URL |
| rel-16 | Когорта 5–10 человек, задание — туториал с засечкой, абзац в «Where it stands» с числами; фаза 2 не начинается без него | ROADMAP + doc | S | 1 | rel-09, 10, 11, 15 | ≥5 прохождений с временем; фраза о 15 минутах подтверждена или переписана |
| rel-17 | Ответ о платформах (решение 2026-09-09): фаза 1 — macOS, браузер, Android (планшет и телефон), iOS (iPad и iPhone), все четыре равноправно; Windows/Linux — после трека ROADMAP; сайт не обещает платформу без сборки в CI; замеры p0-02/03/08 — ворота, не выбор | doc §7 + ROADMAP + ci | S | 0 | p0-02/03, p0-08 | таблица в §7 и на странице; для каждой из четырёх платформ есть шаг CI (qa-17) |
| rel-19d *(добавлено по решениям 2026-09-09)* | Закупка: физический iPad с Pencil и аккаунт Apple Developer до середины фазы 1 (А2, Е8); владелец — Дмитрий; после покупки p0-03 дозамеряется на iPad, ui-21 и qa-17 получают устройство для ручной проверки; подпись и нотаризация macOS в фазе 1 остаются «правый клик → Open» | владелец | S | 1 | — | строка iPad в таблице p0-03 заполнена числом с датой; сборка ui-21 стоит на iPad и Galaxy A55; аккаунт записан в HANDOFF без секретов |
| rel-18 | SECURITY.md: STL, формат проекта, писатели в scope; `config.yml` → форма | SECURITY + .github | S | 1 | rel-15, fmt-06/08/09 | перечислены; согласовано с ARCHITECTURE §8 |

### 2.12 Сноски к изменённым фазам

Размеры не менялись. Фаза изменена у трёх пунктов при синтезе (¹–³) и ещё у
пяти по решениям владельца 2026-09-09 (⁴–⁸), причина у каждого:

¹ pro-job-01 — с фазы 4 на 2: слит с doc-24 (фаза 2), потому что раннер задач
нужен уже булевым модификаторам и запеканию графа фазы 2 (mat-11, mat-20), а
не только фазе 4.

² anim-26 — с фазы 3 на 1: слит с fmt-07, потому что писатель glTF без скинов
молча теряет риг импортированной модели, и fmt сам ставит скины в фазу 1 (⚠ с
ROADMAP, §7 п. 7).

³ qa-11 — с фазы 1 на 2: слит с view-14, у которого фаза 2 по умолчанию и
фаза 1 по исходу p0-06; конформанс-проверка идёт вместе с правкой контракта,
а не раньше неё.

⁴ ui-21 — с фазы 2 на 1: решение 3 (фаза 1 выходит на macOS, вебе, Android и
iOS), платформенные конфигурации нужны к первой версии; §7 № 34 поправлен.

⁵ fmt-25 — с фазы 3 на 2: решение 18 (свой читатель FBX), скины и анимация
идут той же дорожкой сразу за fmt-24, а не ждут конвейера персонажа.

⁶ doc-11a-n — фаза та же (2), снято условие «по §7 № 36»: решение 10,
расстановка ассетов входит в режим «Сцена» безусловно.

⁷ fmt-26 — снят: решение 18, серверной конвертации нет.

⁸ ui-34d — новый пункт фазы 1 по условию, тогда как Е11 отводил web worker
в фазу 2: решение 2, если p0-07/p0-08 покажут заморозку дольше 1 с.

---

## 3. Зависимости между аспектами

Текстовые ссылки из планов («mesh: EditMesh.toMeshData») разрешены в id. Где
несколько аспектов написали одну и ту же вещь, ниже сказано, чья реализация
остаётся, а чей id помечен «⇢» в таблицах.

### 3.1 Одна реализация вместо нескольких

| Вещь | Кто написал | Где живёт | Кто становится потребителем |
|---|---|---|---|
| Чистые пакеты словаря движка | mesh-03 (`flutter3d_geometry`), doc-01 (прежнее рабочее имя одного общего пакета), p0-09 (`flutter3d_model`), qa-03, rel-03 | **два пакета** (В1 закрыт решением владельца 2026-09-09): `flutter3d_geometry` — mesh-03 (`MeshData`, `VertexLayout`, `Shape`/`LatheShape`, тангенсы, `morph_target`, `CpuMesh`, `math/intersections`, `Ray`, `TriangleBvh`); `flutter3d_formats` — doc-01 (`ModelDocument`, `SurfaceMaterial`, `MaterialDocument`/`MaterialHint`, `lighting_model`, синхронная половина `model_loader`, декодеры gltf/obj/f3d/ktx2/stl, писатели `F3dWriter`/`GltfWriter`/`ObjWriter`); `formats → geometry`, `mesh → geometry`, `model_core → оба`, `flutter3d` реэкспортирует оба | mesh-13/14/17/20 (geometry), doc-11/12/19 (formats), fmt-01..09/12/15 (писатели в `formats`; в engine остаются только fmt-13 и fmt-14), mat-03 (formats), fmt-29d (`fbx → formats`) |
| Регистрация пакетов в сканере/CI/документах | mesh-00, doc-02, ui-01, qa-02, qa-04, doc-30, rel-02, rel-03, rel-07, qa-16 | qa-02 (списки), qa-04 (`ci.sh`), rel-02 (pubspec), rel-07 (документы); mesh-00/doc-02/ui-01 — по одному пакету | всё |
| Спайк `EditMesh` и персистентности | mesh-01/02, p0-04/05 | mesh-01/02 в `packages/flutter3d_mesh` (не `tool/model_spike`), пороги из p0-04/05 | mesh-10/11 |
| `TriangleBvh` по треугольникам | mesh-20, view-09, p0-10, pro-sc-04 | класс в пакете `geometry` (после mesh-03), чтобы и `Raycaster`, и `flutter3d_mesh` его видели; **владелец — view-09** (реализация + интеграция в `Raycaster`, зависит от doc-01 и p0-10); mesh-20 = `MeshBvh` над ним с refit (зависит от view-09); p0-10 — замер прототипа | view-10, mesh-21, anim-10, pro-rt-04, pro-pt-02 |
| Частичная перезапись буфера | view-14, pro-eng-01, qa-11, p0-06, mesh-72, ui-29 | view-14 (контракт + конформанс из qa-11); p0-06 решает фазу | pro-sc-05, pro-sim-04, view-18 |
| Формат проекта | doc-09/10/28, fmt-17/18 | doc-09/10/28; из fmt-17 берётся write-through неизвестных ключей manifest, из fmt-18 — политика ассетов (в doc-17) и `ProjectStorage` (в ui-18) | pro-doc-01, anim-03 |
| `Modifier` | mesh-40..48, mat-18, doc-23, mat-19 | тип и функции — mesh-40..48; `ModelObject.modifiers` и кэш — mat-18; команды — doc-23 | mat-20, mat-32 |
| Материал в документе | mat-01, doc-25 | mat-01 (фаза 1, включая `SetTexture`/`AddImage`); кодек `SurfaceMaterial ↔ Map` в fmat.dart (правка движка S из doc-25) — в doc-10 | mat-04a-n (фаза 1), mat-04..08, doc-12 |
| GltfWriter скинов/анимаций/морфов | fmt-07, anim-26 | fmt-07 (фаза 1) | anim-16, anim-30 |
| Фоновые задачи | doc-24, ui-25, pro-job-01, anim-25 | doc-24 (`JobRequest` в core), ui-25 (раннер в app); pro-job-01 → фаза 2¹; anim-25 — `RigJob` поверх | mat-11/13, pro-* |
| Веса скиннинга | mesh-60, anim-09 | слои — mesh-12/60; операции кисти — anim-09 в `flutter3d_mesh/skin/` (пакет `rig` только для ретаргета и авторига) | anim-10, anim-22, pro-lod-02 |
| Морф-цели | mesh-61/62, doc-27, anim-19 | хранилище — mesh-61/62; команды и UI — anim-19 | anim-20, anim-27 |
| Скелет и клипы в документе | doc-26, anim-03/04/29 | anim-03 (типы), anim-04 (ключи), anim-29 (скелет) | anim-07, anim-18 |
| Упрощение (QEM) | mesh-70, pro-lod-01/02 | pro-lod-01/02 над `MeshData` | pro-lod-03, pro-rt-01 |
| Развёртка UV | mesh-71, pro-uv-02..05, view-19, pro-uv-07 | pro-uv-02..05 (ядро), pro-uv-07 (экран) | pro-pt-05 |
| Швы | mesh-12, pro-uv-01 | флаг `seam` в mesh-12 (фаза 1); команда и оверлей — pro-uv-01 | pro-uv-02 |
| Скульптинг | mesh-72, pro-sc-02..07 | pro-sc-* (`SculptMesh` с мультиразрешением — Б8/Б9 закрыты 2026-09-09; pro-sc-01 меряет, не выбирает) | pro-sc-08, view-21, ui-29 |
| Remesh | mesh-73, pro-rt-01 | pro-rt-01 | pro-rt-02 |
| Веса градиентом | view-18, anim-11 | view-18 | anim-10 |
| Превью «как в игре» | view-17, anim-24, ui-28 | `FrameResult.triangles` и вьюпорт — view-17; бюджеты — anim-24; оболочка — ui-28 | rel-09 |
| Предпросмотр материала | view-16, mat-15 | mat-15 | mat-31 |
| Курсор кисти и перо | view-21, ui-19, ui-29, pro-sc-08 | `InputPolicy` — ui-19; курсор — view-21; раскладка — ui-29 | pro-pt-05 |
| Вьюпорт: жесты, пикинг, гизмо | ui-06, view-03/08/10/12 | view-*; ui-06 — интеграция и `scene_sync.dart` | ui-09, ui-13 |
| Golden-сцены и draw-count | qa-10, qa-14, view-05, view-22 | view-05 (сцена `mesh-overlay`), view-22 (baseline) | — |
| Тесты app и core | qa-15, qa-18, ui-26, doc-* | ui-26 и тесты пунктов core | — |
| Сценарий MCP и skills | qa-12, doc-21, doc-22, rel-14 | doc-21, doc-22 (+ `skills_test` из rel-14) | rel-09 |
| Стенд замеров | p0-01, view-01, ui-00, qa-13 | p0-01 (пример движка); ui-00 — скелет приложения; view-01 — только (б)(в); qa-13 — артефакт CI | p0-02/03/06/11 |
| Веб-файлы | p0-08, ui-14 | p0-08 (спайк под `tool/`), ui-14 (полная версия) | rel-10, ui-15 |
| Энкодер текстур | fmt-22, mat-30 | fmt-22 в движке; mat-30 — редакторный экспорт поверх | mat-28 |

### 3.2 Разрешённые межаспектные ссылки

| Откуда | Ссылка в плане | Разрешено в |
|---|---|---|
| doc-03 | «mesh: EditMesh как неизменяемое значение с identity-равенством и структурным разделением» | mesh-10, mesh-11 |
| doc-06 | «mesh: построители примитивов и Lathe, `EditMesh.transformed`» | mesh-28, mesh-22 |
| doc-07 | «mesh: чистые функции операций; стабильность id элементов» | mesh-22..26; надгробия + `IdRemap` в mesh-11 |
| doc-10 | «mesh: `EditMesh.encode/decode` с чанками» | mesh-18 |
| doc-11 | «дизайн: STL-импорт» | fmt-09 |
| doc-12 | «mesh: `toMeshData(VertexLayout)`; стек модификаторов как функция; движок: GltfWriter/ObjWriter детерминированные» | mesh-14, mesh-40; fmt-06, fmt-08 |
| doc-14 | «mesh: проверки n-гонов/манифолдности/нормалей по id» | mesh-27 |
| doc-17 | «app: таймер, атомарная запись, диалог, recent» | ui-18, ui-15 |
| doc-19 | «import/export под `dart run` только после doc-01» | doc-01 |
| doc-21 | «движок: GltfWriter детерминирован на двух ОС» | fmt-06 (квантование — см. риск libm) |
| doc-23 | «mesh: mirror/array/smooth/boolean» | mesh-41, 42, 46, 47 |
| doc-26 | «mesh: joints/weights с перенормировкой» | mesh-60 |
| fmt-06/07/08 | «база для anim-26, экспорт для doc-12» | — |
| fmt-17 | «model_core: схема ModelProject; mesh: сериализация EditMesh» | doc-03, mesh-18 |
| view-02 | «app: каркас, Cubit, ModelObject → MeshNode» | ui-03, ui-06 |
| view-08 | «app: карта ModelObject ↔ MeshNode» | ui-06 (`scene_sync.dart`) |
| view-10 | «mesh: позиции Float32List, рёбра парами, карта треугольник → грань» | mesh-11, mesh-14 (`triangleToFace`) |
| view-12 | «model_core: команда трансформации и `history.transaction`; mesh: перемещение выделения» | doc-06, doc-08, mesh-22 |
| view-13 | «mesh: Selection и версии EditMesh» | mesh-19, mesh-11 (identity = версия) |
| view-16/17 | «app/model_core: SurfaceMaterial, команда материала; ProjectProfile» | mat-01, doc-13 |
| view-18 | «mesh/model_core: веса и кисть с перенормировкой» | mesh-60, anim-09/10 |
| view-19 | «mesh: развёртка, острова, растяжение, раздельные углы в toMeshData» | pro-uv-02/04, mesh-14 |
| view-20 | «mesh: упрощение» | pro-lod-01 |
| view-21 | «mesh: операции кисти» | pro-sc-03, pro-pt-03 |
| ui-03 | «model_core: ModelProject, команды с says, история с amend, ExportReadiness» | doc-03, 05, 08, 14 |
| ui-06 | «mesh: Selection и BVH; flutter3d: оверлеи (1.10)» | mesh-19/20/21, view-05 |
| ui-08 | «model_core: SetTransform, Rename, AddModifier…; модификаторы фазы 1 (зеркало)» | doc-06, doc-23; зеркало фазы 2 — mesh-41 (в фазе 1 стек пуст) |
| ui-09 | «model_core: ParamHint и `history.reapplyTop`; mesh: операции фазы 1» | `amend` в doc-08; ParamHint — **добавлено при синтезе: syn-01**; mesh-22..26 через doc-07 |
| ui-10 | «model_core: ExportReadiness, ProjectProfile; mesh: проверки» | doc-14, doc-13, mesh-27 |
| ui-13 | «mesh: Lathe параметрический; model_core: AddLathe/SetLatheParams» | mesh-28, doc-06 (`AddLathe`, `SetParametric`) |
| ui-16 | «дизайн: макет экрана импорта; model_core: fromModelDocument; flutter3d: StlLoader» | **добавлено при синтезе: syn-02**; doc-11; fmt-09 |
| ui-17 | «дизайн: макет экспорта; flutter3d: GltfWriter/ObjWriter; model_core: toModelDocument, ExportReadiness» | syn-02; fmt-06/08; doc-12/14 |
| ui-26 | «flutter3d: оверлей рёбер (1.10)» | view-05 |
| ui-28 | «model_core: клипы, ключи, ProjectProfile» | anim-03/04, doc-13 |
| ui-29 | «flutter3d_hardware: DeviceMesh.overwrite; mesh: кисти» | view-14, pro-sc-03 |
| mat-03 | «редактор моделей зависит от editor_core ради одной библиотеки» | В4; переезд только после doc-01 (editor_core плоский, а библиотека принимает типы из `flutter3d`) |
| mat-18 | «mesh: mirror/array/smooth/subdivide/booleanBsp, toMeshData» | mesh-41/42/46/45/47, mesh-14 |
| mat-19 | «model_core: общая иерархия команд; mcp: генерация таблицы» | doc-05, doc-20 |
| mat-20/24 | «оболочка: правая панель, jobs, карточка; вьюпорт: манипулятор, пикинг маркеров» | ui-08, ui-25, ui-09; view-12, view-08 |
| mat-22/28 | «model_core: ExportReadiness, ProjectProfile; mesh: проверки» | doc-14, doc-13, mesh-27 |
| mat-25 | «вьюпорт: id-проход маркеров, общий DebugDraw» | view-08, view-05 |
| mat-32 | «mcp: сервер, сессия, схемы» | doc-19, doc-20 |
| anim-03 | «core: ModelProject персистентный, from/toModelDocument» | doc-03, doc-11, doc-12 |
| anim-05 | «app: гизмо поворота сустава» | view-12 |
| anim-07 | «app: каркас, тема, раскладки, режимы» | ui-04, ui-02, ui-05 |
| anim-09 | «mesh: joints/weights как атрибуты, adjacency, BVH» | mesh-12/60, mesh-11 (`vertexRing`), mesh-20 |
| anim-10 | «mesh: BVH с обновлением по массиву позиций» | mesh-20 (`refit`) |
| anim-11 | «mesh/hardware: DeviceMesh.overwrite» | view-14 |
| anim-13 | «core: ExportReadiness принимает поставщиков; ProjectProfile с fps» | doc-14; fps в профиле — **добавлено при синтезе: syn-03** |
| anim-19 | «mesh: правка копии вершин без смены топологии» | mesh-61 (`ShapeKey` как слой позиций) |
| anim-22 | «mesh: BVH и adjacency для MeshData» | mesh-13 + mesh-20 (через `fromMeshData`) |
| anim-24 | «core: ProjectProfile с байтами текстур и целевым движком» | doc-13, mat-28 |
| anim-25 | «core: состояние jobs, результат как команда» | doc-24, ui-25 |
| anim-26 | «fmt: ядро GltfWriter с part-структурой» | fmt-06 |
| anim-30 | «mcp: сервер и таблица из команд» | doc-19, doc-20 |
| pro-eng-07 | «вьюпорт: контрибьютор фазы 1» | view-05 |
| pro-uv-01 | «mesh: атрибуты рёбер и переотображение индексов» | mesh-12, mesh-11 (`IdRemap`) |
| pro-uv-06 | «mesh: toMeshData с атрибутами углов» | mesh-14 |
| pro-sc-02 | «mesh: общий чанковый тип» | mesh-10 |
| pro-sc-04 | «mesh: BVH пикинга фазы 1» | mesh-20 |
| pro-sc-06 | «model_core: история с персистентными значениями» | doc-08 |
| pro-sc-07 | «mesh: Catmull-Clark фазы 2» | mesh-45 |
| pro-rt-02 | «mesh: добавление грани, слияние по расстоянию» | mesh-11 (`addFace`), mesh-25 |
| pro-rt-06, pro-pt-04, pro-eng-06 | «экспорт: GltfWriter с изображениями / фазы 1» | fmt-06 |
| pro-rn-04 | «материалы: виджет графа экрана 05» | mat-13 |
| pro-doc-01 | «model_core: секционный формат» | doc-09/10 |
| qa-07 | «mesh: validate/audit, to/fromMeshData, чанки» | mesh-11, 13/14, 10 |
| qa-08 | «formats: GltfWriter, ObjWriter, StlLoader» | fmt-06/08/09 |
| qa-10 | «render: PassContributor оверлея» | view-05 |
| qa-11 | «hardware: `writeGeometry`/`DeviceMesh.overwrite`» | view-14 |
| qa-12 | «model_core: команды с arguments/fromJson, квантование в формате» | doc-05, doc-10 |
| qa-13 | «mesh: спайк 0.2, чанки 0.3» | mesh-01, mesh-02 |
| qa-15 | «app: EditorState/Cubit, манипулятор, раскладки; mesh: BVH» | ui-03, view-12, ui-05, mesh-20 |
| rel-02 | «mesh: пустая библиотека с одним экспортом» | mesh-00 |
| rel-04 | «model_mcp: bin с ответом на tools/list» | rel-02 (заглушка `--help` в фазе 0); `tools/list` в контейнере — приёмка doc-19 |
| rel-06 | «model_core: фаза 1 закрыта (1.7, 1.8); mesh: API стабилен» | doc-10, doc-14; mesh-31/33 |
| rel-08 | «app: режимы Объект и Меш (1.11)» | ui-04, ui-08, ui-09 |
| rel-09 | «app: импорт/экспорт (1.15); model_mcp: таблица (1.17); engine: GltfWriter (1.9)» | ui-16/17, doc-20, fmt-06 |
| rel-10 | «app: диск на вебе (1.15, спайк 0.5); perf: замер 0.1 в Chrome» | ui-14, p0-08, p0-02 |
| rel-11 | «app: собирается на macOS (1.11)» | ui-20 |
| rel-13 | «engine: GltfWriter детерминированный; model_core: формат и bin/export» | fmt-06, doc-10 (+ `bin/` — вопрос §8) |
| rel-17 | «perf: замер 0.1; app: спайк 0.5» | p0-02/03, p0-08 |

### 3.3 Добавлено при синтезе

Три ссылки не разрешались ни в один пункт; для них заведены пункты. Девять
пунктов с суффиксом `-n` (mat-04a-n, mat-09n, doc-11a-n, anim-31a-n, p0-13n,
ui-30n, ui-31n, ui-32n, qa-19n) добавлены по критике 2026-09-09, пять с
суффиксом `-d` (doc-31d, ui-33d, ui-34d, rel-19d, fmt-29d) — по решениям
владельца 2026-09-09; все стоят в таблицах своих аспектов.

| id | что | пакет | р. | ф. | зависит | приёмка |
|---|---|---|---|---|---|---|
| syn-01 *(добавлено при синтезе)* | `ParamHint` — свой sealed-тип в core (Int / Double / Bool / Enum / Vector3 с `step`, `unit`, диапазоном) для карточки операции; `ModelCommand.hints` у команд с параметрами (Extrude, LoopCut, MergeByDistance, MoveElements, AddPrimitive, AddLathe). Без него ui-09 не может строить контролы, а doc-05 говорит только об `arguments`. Тип решён по критике 2026-09-09 (Г4/Ж2): `MaterialHint` не подходит — у него только `RangeHint(double, step)`/`ColorHint`/`TextureHint`/`EnumHint`, ни целых (`LoopCut.cuts`), ни флагов (`Extrude.individual`), ни единиц, и файл тянет `LightingModel` | core | S | 1 | doc-05 | у каждой команды с числовым аргументом есть hint; тест: ключи `hints` ⊂ ключей `arguments`; `LoopCut.cuts` — `IntHint`, `Extrude.individual` — `BoolHint` |
| syn-02 *(добавлено при синтезе)* | Макеты двух экранов фазы 1, которых нет в передаче: импорт с проверкой и экспорт с проверками (README передачи сам требует их до начала фазы; ui-16/17 и fmt-12 описывают данные, но не вид). Тот же стиль `.dc.html`, таблица токенов та же | дизайн | S | 0 | — | два экрана в архиве передачи; ui-16/17 ссылаются на них |
| syn-03 *(добавлено при синтезе)* | `ProjectProfile.fps` и `frameSnap` — временная база анимации в профиле (anim-04 округляет кадр как `round(time·fps)`, anim-13 читает fps); doc-13 не содержит поля | core | S | 3 | doc-13 | JSON round-trip; `KeyTable` читает fps из профиля |

---

## 4. Критический путь и дорожки для агентов

Считается по `dependsOn` после слияния дубликатов. Веса: S = 1 неделя, M = 2,5,
L = 5 — середины интервалов проработки §6, для одного человека. После решения
владельца 2026-09-09 (исполнитель один, с агентами) критический путь задаёт
порядок работ, а календарь фазы 1 считается в §4.3 как сумма размеров.

### 4.1 Критический путь

Пересчитан 2026-09-09 по критике: в столбец «зависит» дописаны рёбра, которые
§4 подразумевал, а таблицы не несли (doc-03 ← mesh-11; doc-07 ← mesh-22..26;
ui-09 ← doc-07, syn-01; ui-26 ← doc-07; mat-01 ← doc-03, doc-05), и путь
выведен строго по ним. Прежняя цепочка шла через mesh-14 → mesh-19 → mesh-23,
но mesh-19 зависит только от mesh-11, а самый длинный предшественник doc-07 —
mesh-25 (dissolve ждёт `fromMeshData` из mesh-13, тот — слои mesh-12). Хвост
прежней цепочки ui-09 → ui-26 (3,5 недели после doc-07) короче, чем
doc-20 → rel-09 → rel-16 (6 недель), которые тоже стоят в приёмке фазы 1 и
тоже ждут doc-07.

```
qa-01 → qa-02 → mesh-01 → mesh-02 → mesh-10 → mesh-11 → mesh-12 → mesh-13
      → mesh-25 → doc-07 → doc-20 → rel-09 → rel-16
```

| звено | р. | недель | что открывает |
|---|---|---|---|
| qa-01 зелёный main | S | 1 | любой merge |
| qa-02 регистрация пакетов | S | 1 | первый коммит кода |
| mesh-01 спайк EditMesh | M | 2,5 | форму API и цену `toMeshData` |
| mesh-02 замер персистентности | S | 1 | чанк или патч |
| mesh-10 персистентные векторы | M | 2,5 | — |
| mesh-11 half-edge | L | 5 | doc-03 (документ), mesh-15/16/18/19 параллельно |
| mesh-12 слои атрибутов | M | 2,5 | mesh-13, 14, 16, 18, 23, 24 |
| mesh-13 fromMeshData | M | 2,5 | mesh-25, 27, 29, doc-11 |
| mesh-25 merge/dissolve | M | 2,5 | doc-07 (последний из mesh-22..26) |
| doc-07 мешевые команды | M | 2,5 | ui-09 → ui-26 (3,5 нед., параллельно), doc-20 |
| doc-20 таблица инструментов MCP | M | 2,5 | doc-21 (2,5 нед., параллельно), rel-09 |
| rel-09 туториал как тест | M | 2,5 | rel-16 |
| rel-16 когорта | S | 1 | приёмка фазы 1 (календарное время когорты сверх недели) |
| **итого** | 4 S, 8 M, 1 L | **≈ 29** | |

Три замечания. Цепочка целиком лежит в ядре геометрии до doc-07; всё, что до
mesh-11, — фаза 0 и первые недели фазы 1, и ускорить её нельзя, только не
задерживать решениями (§5.2). После mesh-11 пункты mesh-14/15/16/18 и
mesh-22..24/26 параллельны mesh-12 → 13 → 25 по зависимостям, но при одном
исполнителе стоят в той же очереди — это и есть разница между ≈29 неделями
пути и календарём §4.3. Число ≈29 не изменилось случайно: две M (mesh-14,
mesh-19) ушли с пути, две M (doc-20, rel-09) на него встали. Решения
2026-09-09 путь не изменили: doc-31d (история в файле) висит на doc-08/10 в
стороне от цепочки, ui-21 и rel-19d — S без последователей на пути, а
приёмка «открывается на iPad и Galaxy A55» стоит на ui-21, который готов
задолго до rel-16.

### 4.2 Дорожки для агентов: что не зависит от `EditMesh`

Пункты ниже не зависят от `EditMesh` и могут стартовать в день зелёного
`main`. При одном исполнителе (§4.3) они не идут «параллельно» сами по
себе — это те дорожки, которые отдаются агентам под готовые тесты;
кандидаты помечены **(агент)**, критерий — есть механическая проверка
(round-trip, эталонный кадр, сканер, множество ключей), которую человек
пишет раньше кода.

- **Форматы (агент):** fmt-01 → fmt-02/03/04/05 → fmt-06 (после doc-01, срок
  25.09) → fmt-07 → fmt-10/11/12/13/14, fmt-08, fmt-09, fmt-15, fmt-16.
  Проработка §8 называет `GltfWriter` единственным пунктом, который можно
  начать «сегодня, ничего не согласовывая»; после В1 «сегодня» означает «в
  engine, с переездом в `formats` вместе с doc-01». Тесты — round-trip на
  моделях Khronos и `compareModelDocuments`, готовы до писателя.
- **Рендер (агент — оверлеи с эталонным кадром: view-05/06/11/13):** p0-01 →
  view-01 → view-05 → view-06, p0-10 → view-09 (после mesh-03) → mesh-20,
  view-14 (по p0-06), p0-06.
- **Платформы (агент):** ui-20, ui-21, qa-17, rel-11 — конфигурации
  Android/iOS/macOS/web и их сборки в CI; проверка — сканер и зелёный job.
- **Локализация (агент):** ui-22 — проверка «множества ключей ru/en равны,
  под `Locale('en')` нет кириллицы».
- **Словарь:** doc-00 → doc-01 (с mesh-03) — на нём стоят mesh-13/14, doc-11/12,
  doc-19; срок 2026-09-25.
- **Оболочка:** ui-00 → ui-01 → ui-02 → ui-03 → ui-04 → ui-05/07/12/22/23, ui-14
  (со спайком p0-08), ui-15, ui-25; view-02 → view-03 → view-04/08/12 → view-11.
  Всё это работает на `Imported(MeshData)` и параметрических объектах, пока
  `EditMesh` нет.
- **Документ:** doc-02 → doc-13/15/18 → doc-09 → doc-10 (на `Imported`, секция
  `editMeshes` пустая до mesh-18) → doc-16/17; doc-05/06 — как только есть
  `ModelProject` (doc-03 ждёт только identity-семантику mesh-11, теперь это
  записано в его `зависит`); mat-01 → mat-04a-n за doc-03/05.
- **Замеры:** p0-02/03/07/08/10/11/13n, anim-31 (только FK), qa-13.
- **Анимация без приложения:** anim-01, anim-02, anim-14, anim-17, anim-21 — чистый
  Dart и движок, могут идти параллельно фазе 1 (аспект anim это прямо предлагает).

### 4.3 Состав

Решение владельца 2026-09-09: исполнитель **один, с агентами**. План дизайна
называл минимальный состав из трёх (ядро геометрии, рендер, интерфейс), и
прежняя таблица «1 / 2 / 3 человека» снята: дорожек по-прежнему несколько,
но идёт по ним один человек, поэтому календарь фазы 1 — сумма размеров всех
её пунктов, а не длина критического пути.

**Счёт по таблицам §2.** Пункты с фазой 1, у которых есть собственная работа
(без одиннадцати, чьё содержимое целиком слито в другой пункт и в приёмке
стоит «см.»: fmt-17/18, qa-07/08/09/10/12/14/15/18, rel-14), с пунктами
решений 2026-09-09 (ui-21 перенесён, doc-31d, ui-33d, rel-19d добавлены) и
без условных (ui-34d, view-14 в фазе 1 только по p0-06, view-06 считается
как S):

| размер | пунктов | недель за пункт | недель |
|---|---|---|---|
| S | 73 | 1 | 73 |
| M | 44 | 2,5 | 110 |
| L | 3 (mesh-11, doc-10, view-12) | 5 | 15 |
| **итого** | **120** | | **≈ 198** |

Перевод в недели — S = 1, M = 2,5, L = 5, середины интервалов проработки §6.
Если срабатывают условные пункты (ui-34d M, view-06 как M вместо S), к сумме
добавляется 4 недели: ≈ 202.

**Оценка 1 — один человек без агентов:** ≈ 198 недель чистой работы, около
3,8 года; критический путь ≈ 29 недель внутри этой суммы — порядок, в
котором её проходить.

**Оценка 2 — один человек с агентами на дорожках §4.2.** Агентам под
готовые тесты отдаются:

| дорожка | пункты фазы 1 | размер | недель |
|---|---|---|---|
| писатели форматов с round-trip тестами | fmt-01..05, 11, 12, 13, 15, 16 (S), fmt-06, 07, 08, 09, 10 (M) | 10 S + 5 M | 22,5 |
| оверлеи с эталонным кадром | view-05, view-13 (M), view-06, view-11 (S) | 2 S + 2 M | 7 |
| платформенные конфигурации | ui-20, ui-21, qa-17, rel-11 | 4 S | 4 |
| локализация | ui-22 | 1 S | 1 |
| **итого агентам** | | | **34,5** |

Агент не снимает пункт с календаря целиком: тесты ему пишет человек,
результат читает человек. Если положить это в четверть размера пункта —
это предположение, а не замер, — человеку остаётся 198 − 34,5 + 8,6 ≈ **172
недели**, около 3,3 года. Второе число проверяется первой же дорожкой:
fmt-01..05 (5 S) отдаются агенту под тесты fmt-01; если на приёмку уходит
больше недели с четвертью, доля пересматривается и оценка вместе с ней.

Следствие для сроков: 27 декабря целью не является (В8); первая публикация
и релиз — когда фаза 1 в руках у первых пользователей (rel-16 → rel-06).

---

## 5. Вехи по фазам

### 5.1 Фаза 0 — замеры и спайки (до 2026-10-05)

**Входит:** qa-01, qa-02 (с mesh-00, ui-01, rel-02, rel-03, rel-07), qa-03,
qa-04, qa-05, qa-13, doc-00, doc-01 (с mesh-03), mesh-01, mesh-02, mesh-04,
p0-01..p0-12, p0-13n, view-01, view-02, ui-00, ui-14 (спайк p0-08 и спайк
сандбокса p0-13n), anim-31 (только FK), rel-01, rel-04, rel-12, rel-17, syn-02.

**Выполнено, когда:**
*`main` зелёный три прогона подряд, и `dart run tool/structure.dart` держит 31
правило при шести новых каталогах в дереве (33 пакета: 28 сегодняшних,
`geometry`, `formats`, mesh, core, mcp). Словарь разложен в два пакета —
`flutter3d_geometry` с геометрией и `TriangleBvh`, `flutter3d_formats` с
документом, декодерами и писателями поверх него, — `flutter3d` реэкспортирует
оба, порядок публикации geometry → formats → flutter3d принят
`publish_check.sh`, и в контейнере без Flutter SDK `dart pub get` и
`dart run flutter3d_model_mcp:model_mcp --help` (заглушка rel-02; `tools/list`
— приёмка doc-19 в фазе 1) проходят. Известно, каким вызовом модельер пишет
файл под сандбоксом macOS (p0-13n). Половинно-рёберный куб
с выдавленной гранью нарисован программным растеризатором и совпадает с
эталоном; `toMeshData` на 200 тыс. треугольников, снимок при сдвиге 1 %
вершин в двух распределениях, `DeviceMesh.upload` против перезаписи,
изолят против порций, миллион треугольников на macOS, в Chrome и на Galaxy A55
— всё это числа с датой и машиной в doc/model-editor.md §6, и ни одна строка
§7 не говорит «решает замер». Веб открыл GLB через панель браузера и скачал
`.f3d` в трёх браузерах; там, где порог p0-02/p0-08 не пройден, в §5.2
записан пункт, который его закрывает (JS-сборка, порции, ui-34d) — замеры
веба стали воротами качества, а не выбором между «равный» и «просмотр»
(решение 2026-09-09). ROADMAP на ревизии 28 сентября содержит трек редактора
моделей со строкой Acceptance и переформулированный пункт о графе нод (Ж1).*

**Решения до старта:** нет. Имена пакетов и место кода закрыты 2026-09-09
(В5: этот монорепозиторий, mesh / model_core / model_mcp / geometry / formats
/ modeler), rel-01 записывает их с датой проверки. В1 закрыт двумя пакетами
и стоит в фазе 0 как решение со сроком 25.09, а не как вопрос; всё остальное
фаза 0 производит.

### 5.2 Фаза 1 — первая версия

**Входит:**
- mesh: 10–33 (с anim-09 не входит);
- core: doc-02..22, doc-29, doc-31d (история в файле проекта), mat-01 (с
  `SetTexture`/`AddImage`), mat-03, syn-01;
- форматы: fmt-01..16 (fmt-17/18 слиты; fmt-01..09/12/15 — в `formats`);
- движок/рендер: view-03..06, view-08..13, view-22, view-09; view-14 — только
  если p0-06 не проходит;
- оболочка: ui-02..13, ui-15..26 (ui-21 — Android и iOS, перенесён из
  фазы 2), ui-30n..33d, ui-34d по условию p0-07/p0-08, mat-04a-n (панель
  материала фазы 1);
- MCP: doc-19..22 (с rel-14);
- качество: qa-06..10, qa-12, qa-14..18, qa-19n;
- публикация и закупка: rel-05, rel-06 (только после rel-16 — В8), rel-08..11,
  rel-15, rel-16, rel-18, rel-19d (iPad и аккаунт Apple Developer до
  середины фазы).

**Выполнено, когда:**
*Модель Khronos импортирована с экраном предупреждений (единицы и ось вверх
выбраны там же), одна грань выдавлена мышью, значение смещения поправлено
числом в карточке без нового шага истории; у выдавленного куба изменён базовый
цвет и назначена текстура в панели «Материал», и оба видны в GLB; результат
ушёл в GLB, который читает загрузчик шутера без предупреждений, который
glTF-Validator принимает без ошибок и который headless Godot открывает в CI с
тем же числом мешей; кадр оригинала и кадр перечитанного экспорта равны на
программном растеризаторе. Тот же сценарий
проигран агентом через `flutter3d_model_mcp` по stdio и сравнён в CI с
эталонным файлом проекта и журналом команд. `EditMesh` держит `validate()` на
500 случайных операциях по трём сидам, снимок истории после сдвига 1 % вершин
из 200 тыс. стоит меньше 10 % полной копии, и это число печатает бенч.
Проект сохранён с историей, открыт заново, и три последних шага отменены —
нетронутые чанки `identical` исходным. Приложение собрано для macOS,
браузера, Android и iOS: открывается на iPad и Galaxy A55, в Chrome — с
редактированием, а не просмотром; три раскладки показывают одно множество
инструментов, интерфейс переключается между русским и английским без
кириллицы под `Locale('en')`, горячие клавиши Blender-подобные и перечислены
в справке, экспорт с красным `Issue` предупреждает и после подтверждения
пишет файл, строка статуса зелёная или оранжевая по `ExportReadiness`,
тесты приложения идут через `flutter3d_cpu` с эталонными кадрами. Сцена
`mesh-overlay` записана в четыре набора. Пять человек прошли туториал, и
время на его странице измерено, а не обещано.*

**Решения до старта (оставшиеся из вопросов §8):** стабильные id с
надгробиями (Б2); enum против sealed (Б7); `materialSlot` в фазе 1 (Б6);
магия файла проекта и место автосохранения (Г1); экспорт скинов в
фазе 1 (Д4); `overwrite` в фазе 1 или 2 (по p0-06). Закрыты 2026-09-09
решениями владельца: чанк или патч — персистентные значения, разбивку меряет
p0-05 (Б3); неманифолд расщепляется при импорте (Б1); иконки — `Icons` из
SDK (Е12n); веб равноправен, замеры — ворота (Е1); В1 — два пакета. Г4
(язык `says` — английский, подсказки — `ParamHint`) закрыт по критике и
подтверждён владельцем.

### 5.3 Фаза 2 — материалы, модификаторы, сцена, форматы

Оговорка: пункты фазы 2 написаны до чисел фазы 0 и до того, как форма
`EditMesh` устоялась; размеры — порядок величины, зависимости внутри mesh-4x
надёжны, между mat-/doc-/mesh — по лучшему знанию.

**Входит:** mesh-40..49; doc-23, doc-24 (с pro-job-01), doc-28, doc-11a-n
(безусловно — расстановка ассетов, решение 2026-09-09); mat-02, mat-04..16,
mat-09n, mat-18..20, mat-22..25 (mat-24 с расстановкой и экспортом сцены),
mat-28..32; fmt-19..22; FBX отдельной дорожкой после rel-16 — fmt-29d,
fmt-24, fmt-25 (fmt-26 снят); view-07, view-14 (если не в фазе 1), view-16
(⇢ mat-15); ui-27; rel-13. ui-21 ушёл в фазу 1.

**Выполнено, когда:** *стек «зеркало → массив → сглаживание → булево» на объекте
считается по кэшу версий, «Применить» оставляет один шаг истории, булево на
копланарных гранях предупреждает и не падает; материал правится ползунками из
подсказок и компоновщиком текстур с фиксированным набором нод, который
запекает в пять слотов и не меняет ни одного шейдера — эталонные кадры
движка не сдвинулись; режим «Сцена» держит свет, окружение и тени, девятый
источник виден в статусе как отброшенный, два ассета импортированы в один
проект через `ImportInto`, расставлены гизмо и ушли одним GLB с двумя узлами;
кадры `bevel`, `subdivision`, `boolean`, `material-studio`, `scene-lit`
зелёные на ubuntu; FBX из Blender — бинарный и ASCII — читается своим
читателем `flutter3d_fbx` до float против glTF той же сцены, скины и клипы с
допуском 1e-4, и пакет резолвится без Flutter SDK; текстуры под профиль
ужимаются, а `.ktx2` из энкодера движка загружается конформансом на четырёх
бэкендах.*

**Решения до старта:** PNG-deflate и декодер PNG/JPEG — свои или
`package:archive`/`package:image` (Г6, mat-09n); один флаг модификатора или
два (Ж3); цифры бюджета текстур (Ж5). Закрыты 2026-09-09: «граф нод» →
«компоновщик текстур» с записью в ROADMAP на ревизии 28 сентября (Ж1);
режим «Сцена» = свет/окружение/тени/пост плюс расстановка ассетов (Ж4,
§7 № 36); FBX — свой читатель на Dart (Д7).

### 5.4 Фаза 3 — конвейер персонажа

Оговорка та же, плюс: `Pose`, IK и ретаргет не проверялись ни на одном
реальном mocap-клипе — только на образцах Khronos.

**Входит:** anim-01..08, anim-10, anim-12..18, anim-19..23, anim-25, anim-27..30,
anim-31a-n, anim-32 (anim-09 — в mesh, anim-11/24/26 слиты); mesh-60..62; view-15,
view-17, view-18; ui-28; fmt-23 (fmt-25 ушёл в фазу 2 вместе с читателем
FBX); pro-eng-02; syn-03.

**Выполнено, когда:** *клип, правленный в таймлайне, играет одинаково тремя
путями — `Pose.sampleClip`, `AnimationPlayer.seek`, `BakedPoses` — и после
round-trip через GLB треки равны побайтно; кисть весов красит в согнутой позе и
оставляет ≤ n влияний из профиля с суммой 1; ретаргет клипа на скелет вдвое
выше держит стопу в сантиметре от пола; авториг RobotExpressive по восьми
маркерам даёт скелет ≤ 64 костей с первичными весами за секунды в изоляте;
экран 19 показывает треугольники, кости и текстуры против профиля тем же
рендерером, что игра; агент проходит «авториг → веса → ключи → GLB» в CI.*

**Решения до старта:** пакет `flutter3d_rig` (В2); четыре влияния как
жёсткий предел (З1); IK всегда запекается молча (З3); секунды как временная
база (З5); объём ретаргета v1 (З6).

### 5.5 Фаза 4 — профессиональные режимы

Оговорка: самая неточная фаза. Скульптинг на 1,2 млн, XPBD-ткань, LSCM и
запекание лучами — численные алгоритмы, чьи размеры L могут удвоиться; порядок
внутри фазы задаёт pro-sc-01 и pro-rn-01, а не этот список.

**Входит:** pro-eng-03..07, pro-uv-01..07, pro-sc-01..09, pro-lod-01..04,
pro-rt-01..07, pro-sim-01..06, pro-rn-01..04, pro-pt-01..05, pro-doc-01,
pro-test-01, pro-after-01; view-19..21 (⇢ pro), ui-29; mat-17; fmt-27, fmt-28;
mesh-70..73 (⇢ pro).

**Выполнено, когда:** *куб подразбит до 1,2 млн треугольников и мазок пера
меняет только затронутые чанки за бюджет кадра на десктопе (на вебе — в
пределах лимита профиля); ретопология даёт ≥ 70 % квадов на поверхности
исходника, а запечённая карта нормалей показывает мазок как рельеф на
low-меше в GLB; куб развёрнут LSCM в острова без наложений с растяжением в
списке; ткань 20×20 висит на двух углах и экспортируется восемью морф-целями;
снимок 4К собран тайлами с прогрессом, а правка bloom пересчитывает только
post; покраска через шов ложится на оба острова и сводится в
`baseColorTexture`; проект фазы 1 открывается после восьми новых секций;
восемь кадров и сквозной MCP-сценарий зелёные в CI.*

**Решения до старта:** экспорт симуляции (И2); второй UV-набор (Д10);
тайминг правок контракта `renderPost`/`overwriteTexture` (И3). Закрыты
2026-09-09: ткань — отдельный солвер `flutter3d_cloth` в фазе 4 (В3/И1);
скульптинг — `SculptMesh` с мультиразрешением, экран 08 получает кнопку
«Подразбить» вместо «плотности» (Б8/Б9); «Рендер» экрана 12 — снимок тем же
рендерером с суперсэмплингом и проходами frame graph, трассировщик вне плана,
«сэмплы» из макета уходят (pro-rn-02).

---

## 6. Правки движка

Все пункты с `engineChange = true` после слияния дубликатов — 46. Каждая нужна
и играм; каждая проходит конформанс, эталонный кадр или round-trip, как любая
правка движка. Пометка «контракт» — правка `GraphicsDevice`, то есть все четыре
бэкенда, `testing_fake_backend.dart` и минорный bump полки (§7, п. 13).

| # | id | что | пакет | ф. | проверка |
|---|---|---|---|---|---|
| 1 | doc-01 (+ mesh-03) | два чистых пакета словаря (решение 2026-09-09): `geometry` — geometry/*, `Ray`, `TriangleBvh`; `formats` — документ, `lighting_model`, синхронная половина `model_loader`, f3d/gltf/obj/fmat, animation; `flutter3d` реэкспортирует оба | engine → geometry + formats | 0 | 4322 теста без правки импортов; сканер; `bench_geometry.dart` AOT отдельным main |
| 2 | fmt-01 | `compareModelDocuments` в lib | formats | 1 | тест на категорию через поломку |
| 3 | fmt-02 | `PlainModelDocument`, `sniffImageMimeType` | formats | 1 | тесты переведены |
| 4 | fmt-03 | `authoredAttributes` + секция 17 | formats | 1 | старые `.f3d` читаются как «все» |
| 5 | fmt-04 | `meshName`, `asset`, `sourceUri` + секции 18–20 | formats | 1 | round-trip; старые с null |
| 6 | fmt-05 | `TextureSampling.mipLinear` | formats | 1 | golden не меняется |
| 7 | fmt-06 | `GltfWriter` (GLB, `.gltf`+`.bin`) — в `formats`, чтобы MCP экспортировал без Flutter | formats | 1 | round-trip 8 моделей; fmt-10/11; `dart test` без SDK |
| 8 | fmt-07 (+ anim-26) | скины, анимации, морфы в `GltfWriter` | formats | 1 | 7 риггированных round-trip; поза t=0.5 |
| 9 | fmt-08 | `ObjWriter` + `.mtl` | formats | 1 | round-trip по множеству треугольников |
| 10 | fmt-09 | `StlLoader`, `ModelFormat.stl` | formats | 1 | пять фикстур; снифф; sendable |
| 11 | fmt-11 (+ qa-09) | glTF-Validator в тестах/CI | engine + tool | 1 | сломанный min/max → ошибка |
| 12 | fmt-12 | `warnings` писателей, `ExportReport` | formats | 1 | OBJ теряет скин → предупреждение |
| 13 | fmt-13 | `encodeModelInIsolate` (обёртка с `kIsWeb`) | engine | 1 | байты = синхронные |
| 14 | fmt-14 | `convert_asset -f` | engine | 1 | GLB из `.f3d` проходит валидатор |
| 15 | fmt-15 | Draco/meshopt — громкий пропуск | formats | 1 | 0 surfaces + предупреждение |
| 16 | fmt-16 | документы и `boundaryEnumExempt` | engine + docs | 1 | сканер |
| 17 | view-03 | орто-зум, `frameBounds` для орто, `animateTo` в `OrbitController` | engine | 1 | тест орто-зума |
| 18 | view-05 (+ qa-10) | `MeshOverlay`, сцена `mesh-overlay` 43 → 44 | engine | 1 | четыре набора, 0 пикселей |
| 19 | view-06 | стейдж `OverlayVertex` (условно по view-01) | shaders + 4 бэкенда | 1 | `mesh-overlay` в допуске; `manifest_test` |
| 20 | view-09 (+ mesh-20, p0-10) | `TriangleBvh` в `geometry`; `Raycaster` по дереву | geometry + engine | 1 | 10k лучей = перебор |
| 21 | view-14 (+ pro-eng-01, qa-11, p0-06) | **контракт** `overwriteGeometry`; `DeviceMesh.overwrite`; конформанс 33 → 34 | hw + 4 бэкенда + engine + conformance | 2 (1 по p0-06) | конформанс на четырёх; Impeller вручную с датой |
| 22 | ui-18 | `BinaryStorage`/IndexedDB в `flutter3d_screens` | screens | 1 | тест на Storage в памяти |
| 23 | ui-20 | resize `WebGlDevice` или пересоздание устройства | webgl / backend | 1 | конформанс-проверка resize, если правка |
| 24 | ui-27 | новый пакет `flutter3d_editor_widgets` | новый пакет | 2 | тесты редактора уровней после переноса |
| 25 | view-07 | `MeshData.edgeIndices`, стейдж `MeshWireVertex`, каркас на всех бэкендах | engine + shaders + бэкенды | 2 | сцена `wireframe-edges`; `wireframeDeclined` не бывает |
| 26 | view-15 | `SceneSurface.views:` | session | 3 | CPU-тест двух видов |
| 27 | view-17 (+ anim-24) | `FrameResult.triangles`/`instances` | engine | 3 | куб + инстансы = формула |
| 28 | fmt-19 | `extras`, `KHR_texture_transform` сквозным проходом, секция 21 | engine | 2 | побайтные JSON-фрагменты |
| 29 | fmt-20 | `StlWriter` | engine | 2 | `84 + 50·count` |
| 30 | fmt-21 | KTX2 сквозь `GltfWriter` (`KHR_texture_basisu`) | engine | 2 | лоадер читает |
| 31 | fmt-22 (+ mat-30) | `Ktx2Writer` + BC1/BC3/ETC2 (пункт ROADMAP) | engine | 2 | PSNR ≥ 30 dB; конформанс |
| 32 | fmt-23 | Basis ETC1S: решение и спайк | engine | 3 | транскод существующим читателем |
| 33 | anim-01 | `Pose` и FK без сцены | engine | 3 | = `Skeleton.matrices` (1e-5) |
| 34 | anim-02 | `SkinBlend` | engine | 3 | = `MeshSkinnedVertexShader` (1e-4) |
| 35 | anim-14 | `TwoBoneIk`, `FabrikIk` | engine | 3 | цель 1e-4; pole |
| 36 | anim-16 | `AnimationPlayer.rootMotionDelta` | engine | 3 | сумма за цикл |
| 37 | anim-27 | имя формы в `F3dRecord.morphTarget` | engine | 3 | round-trip имён |
| 38 | pro-eng-02 | **контракт** `overwriteTexture` | hw + 4 бэкенда | 3 | readback региона |
| 39 | pro-eng-03 | `Renderer.renderPost` с внешним HDR | engine | 4 | сцена `post-only` |
| 40 | pro-eng-04 | `TiledProjection` | engine | 4 | 2×2 тайла = кадр |
| 41 | pro-eng-05 | `FrameResult.passes` | engine | 4 | bloom отсутствует при выключенном |
| 42 | pro-eng-06 | LOD в `ModelDocument`, `.f3d`, `ModelAsset`, `MSFT_lod` | engine | 4 | сцена `lod-asset` |
| 43 | pro-eng-07 | ленты заданной толщины в оверлее | engine | 4 | сцена `overlay-ribbon` |
| 44 | mat-17 | `.hdr` и float-окружение | engine + conformance | 4 | конформанс float-куба; `ibl-hdr` |
| 45 | fmt-27 | `UsdzWriter` (по спросу) | engine | 4 | Quick Look на устройстве |
| 46 | fmt-28 | свет и камеры в словаре, `KHR_lights_punctual` | engine | 4 | round-trip |

Столбец «пакет» после решения 2026-09-09 читается так: `geometry` и
`formats` — два чистых пакета словаря, `engine` — то, что остаётся в
`flutter3d` (изолятная обёртка, `convert_asset`, рендер, оверлеи, `Pose`),
`hw` — контракт `GraphicsDevice` и четыре бэкенда. Писатели форматов
(fmt-01..09/12/15) все живут в `formats`; в engine из форматов остаются только
fmt-13 и fmt-14.

Кроме них: doc-25 (публичный кодек `SurfaceMaterial ↔ Map` в fmat.dart, S) —
входит в doc-10; rel-13 (`make_templates.py` через `dart run
flutter3d_model_core:export`) — правка инструментов, не движка; ui-29 — потребитель
№ 21. Читатель FBX (fmt-24/25, пакет `flutter3d_fbx` над `formats`, fmt-29d)
правкой движка не является и в таблицу не входит: `flutter3d` его не
реэкспортирует, декодер регистрируется редактором.

---

## 7. Конфликты с ROADMAP и ARCHITECTURE

Один список, каждый с предложенным решением. Правки текста ROADMAP делаются на
дате ревизии (28 сентября), как он сам требует; решения владельца 2026-09-09
закрыли № 34 и № 36 и сдвинули формулировки № 3, 5, 11, 12, 24, 28, 31, 37.

| # | С чем | Кто задел | Решение |
|---|---|---|---|
| 1 | ROADMAP, приёмка редактора уровней: «zero changes inside the engine's own sources made for the editor's sake» | mesh-03, doc-01, view-05/07/09/14/17, mat-03/17, ui-18/20, pro-eng-*, qa, rel-12 | rel-12 заводит отдельный трек редактора моделей со своей Acceptance; формулировка трека уровней не распространяется на него; каждая из 46 правок §6 названа возможностью движка с вызывающим вне редактора (игры: коллизии по треугольникам, деформируемые меши, HDR-небо, экспорт ассетов) |
| 2 | ROADMAP: «every edit is a command object with apply and revert» | doc-05, doc-08, ui-11, qa-18 | doc-29: ROADMAP переписывается на то, что делает код (снимки у уровня, прежнее значение у модели, обратных команд нет нигде); ARCHITECTURE §8.7 объясняет три модели отмены |
| 3 | ROADMAP «Not doing: Node-graph materials» | mat-10..13, pro-rn-03, ui-27, pro-eng-03 | дописать в «Not doing»: «a fixed set of nodes that bakes into texture slots is not that»; в дизайне «граф нод» → «компоновщик текстур», «граф композитинга» → «граф из фиксированных проходов»; доказательство — эталонные кадры движка не меняются, `LightingModel.builtIn` не растёт. Решение владельца 2026-09-09 (Ж1 закрыт): компоновщик текстур с фиксированным набором нод; формулировка ROADMAP о графе нод меняется на ревизии 28 сентября |
| 4 | ROADMAP §Rendering: «eight lights is a ceiling on the scene today» | mat-23 | `LightBuffer.gatherNear` / `gatherNearFrom` уже отбирает восемь на объект (light_lists_test) — текст отстал от кода; поправить на ревизии, план считает «8 на объект» |
| 5 | ROADMAP: soft bodies «the solver and its collisions are the committed part», но в Committed их нет | pro-sim-01 | владелец решает, идёт ли `flutter3d_cloth` в ROADMAP как тот самый солвер (тогда позже переезжает в `flutter3d_physics`) или остаётся редакторским; решение 2026-09-09 (В3/И1): ткань — отдельный плоский солвер `flutter3d_cloth` в фазе 4 с API только на `CollisionShape`; в ROADMAP он не претендует на строку Committed о soft bodies, переезд в `flutter3d_physics` — отдельное решение после фазы 4 |
| 6 | ROADMAP «Not doing: rigid bodies with rotation and joints» | pro-sim-02 | чип «Твёрдое тело» без вращения с подписью в панели; вращение — только как порт солвера после фазы 4 |
| 7 | ROADMAP относит экспорт анимации к фазе 3 | fmt-07 | делать в фазе 1: писатель без скинов теряет данные импорта молча; anim-26 слит |
| 8 | ROADMAP: читатели Draco/meshopt в конце квартала | fmt-15 | не конфликт: честный отказ до них, потом читатели заменяют пропуск |
| 9 | ROADMAP: `KHR_lights_punctual` в рендер-треке | fmt-28, mat-23 | словарь (`ModelLight`/`ModelCamera`) добавляет fmt-28, рендер-трек его использует; согласовать, чтобы не сделать дважды |
| 10 | ROADMAP «Two tiers, and only two», восемь committed-треков (green main, editor, strategy, rendering, terrain, backends, measurement, games) | rel-12 | девятый трек входит с переносом чего-то вниз на ту же дату ревизии; кандидаты — хвост рендер-трека (декали) или измерение; решает владелец |
| 11 | ROADMAP «A level editor in the browser — after this quarter» против веб-редактора моделей в фазе 1 | rel-10, ui-14 | записать в ROADMAP: веб-редактор моделей появляется раньше, потому что задача записи файлов решается там впервые; решение 2026-09-09 (Е1): веб — равноправная платформа фазы 1, p0-02/p0-08 — ворота качества, а не выбор |
| 12 | ROADMAP «exporter from a modelling tool» после квартала; FBX не значится | fmt-24/25, fmt-29d | писатель glTF появляется здесь, экспортёр из Blender остаётся отдельным; FBX — свой читатель на Dart в `flutter3d_fbx` над `formats` (Д7 закрыт 2026-09-09), fmt-26 снят; в ROADMAP FBX по-прежнему не значится — это пакет редактора, не движка |
| 13 | ARCHITECTURE §7.1: «changing any of these breaks a backend, and that is the bar»; §16: `^0.6.0` не покрывает 0.7 | view-14, pro-eng-02, qa-11 | одна правка контракта на фазу; PR на четыре бэкенда + fake + конформанс; семантика «видно со следующего прохода» записана в контракте; версии полки поднимаются одним коммитом «полка 0.7.0»; Impeller-прогон `conformance.sh` с датой в HANDOFF |
| 14 | ARCHITECTURE §3.2/§13/§16 и README: число пакетов, тестов, порядок публикации, сцен, проверок | mesh-00, doc-02, qa-02/10/11/16, rel-03/07, view-05/22, fmt-16 | в том же коммите, что и каталог/тест/сцена; списки числительных в rules.dart расширяются заранее |
| 15 | ARCHITECTURE §4 и `render_settings.dart`: семантика `RenderSettings.wireframe` / `wireframeDeclined` | view-07 | документ правится в том же PR; конформанс-проверка «wireframe drawn as edges or refused» не трогается |
| 16 | ARCHITECTURE §6.3, environment_map.dart: окружение 8 бит по решению | mat-16, mat-17 | mat-16 остаётся внутри решения (LDR-панорама с подписью); mat-17 оформляется как возможность движка для игр (HDR-небо), фаза 4 |
| 17 | ARCHITECTURE §14: отказ от FFI в рантайме | fmt-23 | для офлайн-конвертера не сказано; явное решение владельца при fmt-23; на вебе и в редакторе FFI нет в любом случае |
| 18 | ARCHITECTURE §1: «desktop only, не упущение»; веб на `--wasm`; пример движка без Android | ui-00, p0-08, p0-01 | модельер выбирает бэкенд через `flutter3d_backend`; если `file_selector_web` не собирается под wasm — JS-сборка как записанное исключение §1; Android-раннер примера — строка в таблице платформ §1 |
| 19 | ARCHITECTURE §8.1 обещает `ModelDocument` без Flutter, но пакет объявляет Flutter SDK | doc-00/01, qa-03 | обещание становится проверяемым пакетом (doc-01) и правилом сканера на транзитивную SDK-зависимость (qa-03) |
| 20 | ARCHITECTURE §15: нет аддитивной позы | anim-20 | не конфликт: аддитивны веса морфов, что §15 допускает |
| 21 | CONTRIBUTING «Generated files are generated» + история libm | rel-13, doc-21, qa (риск) | писатели квантуют координаты, канонический JSON, сравнение геометрии с допуском вместо байтов; фикстуры записываются на двух ОС |
| 22 | Правило сканера «an enum in a published package is machinery or is not an enum» | mesh-19, fmt-09, qa-06 | `ElementLevel`/`IssueSeverity` — enum с экземпцией и причиной; `ModelFormat.stl` меняет текст экземпции и «Three decoders» в прозе; содержимое — sealed |
| 23 | Правило «a step reaches for no clock», «asks no machine» | mesh-00, qa-02 | три пакета в `notARepeatableStep` с причиной «редактор, а не шаг симуляции» |
| 24 | doc/model-editor.md §5.1: `flutter3d_model_core → flutter3d` | все | заменяется на `→ flutter3d_formats → flutter3d_geometry` (В1 закрыт 2026-09-09: два пакета); §5.1 проработки переписан 2026-09-09, ARCHITECTURE — вместе с doc-29 |
| 25 | doc §5.2: параметрические объекты «через существующие Shape»; «чанками по 1024» | mesh-28, p0-05 | квадовую топологию строит `ParametricShape`, `Shape` — эталон parity; чанк — гипотеза до p0-05 |
| 26 | doc §5.5: «Renderer в Texture.asImage()» | ui-06 | как в редакторе уровней — `SceneSurface → device.present` |
| 27 | doc §4.3: неизменяемые значения | p0-11 | при GC-паузах >16 мс допускается изменяемый рабочий режим внутри транзакции — уточнение, не отмена |
| 28 | doc §5.1: три пакета | anim-09/17/21, pro-sim-01, ui-27, doc-01, fmt-29d | до девяти: `geometry`, `formats`, `rig`, `cloth`, `fbx`, `editor_widgets`; `geometry`/`formats` (В1), `cloth` (В3) и `fbx` (Д7) решены 2026-09-09, `rig` и `editor_widgets` — по вопросам §8 |
| 29 | README передачи: `ColorScheme.fromSeed` и точные hex одновременно | ui-02 | явная схема, seed только для неназванных ролей |
| 30 | README передачи: `selection`/`history` внутри `document` | doc-04 | в сессии `Modeling`, чтобы значение проекта было тем, что сериализуется |
| 31 | README передачи: «тяжёлые операции в изоляте» на всех платформах | doc-24, p0-07, pro-job-01 | на вебе — порции с уступкой кадру; формулировку README уточнить по исходу p0-07; решение 2026-09-09 (Е11): заморозка с прогрессом на неделимой операции допустима, web worker (ui-34d) — условный пункт фазы 1 при заморозке дольше 1 с |
| 32 | Дизайн экрана 12: «256 / 256 сэмплов» | pro-rn-02 | «тайлы N / M» и «суперсэмплинг»; трассировщик вне плана |
| 33 | Дизайн: лимит влияний из профиля произвольный | anim-32 | ≤ 4 (формат вершины) и ≤ 64 (бандл); больше — новая раскладка вне фазы 3 |
| 34 | План дизайна §7: планшет второй волной, но экраны 03/04 в фазе 1 | ui-05, ui-21 | **Закрыт 2026-09-09 (решение владельца):** раскладки и раннеры Android/iOS — фаза 1 (ui-21 перенесён, §2.12 ⁴); фаза 1 выходит на четырёх платформах, iPad и аккаунт — rel-19d; план дизайна §7 правится под это |
| 35 | Сандбокс macOS выключен у редактора уровней («Under the sandbox that is `PathAccessException`» — из-за записи через rename) | ui-14, ui-20, p0-13n | у модельера включён, но способ записи выбирает спайк p0-13n в фазе 0 (`saveFile` + прямая запись, или security-scoped каталог); два entitlement-файла (Debug без, Release с) — вопрос Е4 |
| 36 | План дизайна §1: третье отличие продукта — «Сцена и композиция без переключения инструмента. Ассеты собираются в сцену прямо здесь, а не только в движке»; план сводит режим «Сцена» к свету/окружению/теням/пост (Ж4), doc-11 создаёт проект из документа заново, слияния и расстановки ассетов нет | Ж4, mat-24, doc-11 | **Закрыт 2026-09-09 (решение владельца):** композиция остаётся — doc-11a-n (`ImportInto`) безусловно в фазе 2, mat-24 расширен расстановкой ассетов с гизмо и экспортом сцены одним GLB; третье отличие продукта из плана дизайна §1 сохраняется |
| 37 | README передачи (точность hi-fi): вьюпорт — `radial-gradient(120% 100% at 50% 0%, #1A1E1F 0%, #0E1112 70%)`; Ж7 выбирает плоский `#0E1112` | view-02, Ж7 | градиент реализуем — `SkySettings` (view-02) или полноэкранный unlit-квад под сценой на всех бэкендах; решение владельца: плоский в v1 с записью расхождения или градиент через `SkySettings` с эталонным кадром. Остаётся открытым (Ж7); из расхождений с README передачи по визуалу 2026-09-09 закрыт соседний вопрос об иконках (Е12n: `Icons` из SDK с таблицей соответствия в ui-02), градиента решение не касается |

---

## 8. Открытые вопросы

Дубликаты из одиннадцати аспектов слиты, вопросы сгруппированы; на каждый
дана рекомендация там, где она следует из проработки или из кода. Буква и
номер — те, на которые ссылаются вехи §5. Из 87 строк 24 закрыты: В1, Ж2 и
Г4 — по критике 2026-09-09, ещё 21 (А2, Б1, Б3, Б8, Б9, В3, В5, В8, Г2, Г9,
Д7, Е1, Е2, Е5, Е8, Е11, Е12n, Ж1, Ж4, И1, К2) — решениями владельца
2026-09-09, В1 при этом переписан на два пакета; строка закрытого вопроса
начинается с «Закрыт …» в столбце ответа. Открытых — 63.

### А. Сроки и стенд

| # | Вопрос | Рекомендация |
|---|---|---|
| А1 | Дата начала фазы 1: ответы критического пути (p0-04/05/09) к 2026-09-25, остальные к 2026-10-05 — подтвердить или сдвинуть; фаза 0 конкурирует со сроками ROADMAP (28 сентября, 26 октября) | принять 2026-10-05 как старт фазы 1, если В1 решён к 25 сентября |
| А2 | Устройство «планшет с пером» для p0-03: iPad (физического нет) или Android-планшет | **Закрыт 2026-09-09 (решение владельца):** физический iPad с Pencil и аккаунт Apple Developer покупаются до середины фазы 1 (rel-19d, S, владелец); до покупки строка iPad в p0-03 (и в таблице фазы 0 doc §6) остаётся незамеренной и записывается так, p0-03 дозамеряется после rel-19d |
| А3 | Стресс-сцена p0-01 — та же «stress scene on the software backend» из ROADMAP «Measurement»? | да, одна сцена и одна базовая линия draw call (view-22) |
| А4 | Порог бюджета веб-профиля: 16,6 мс на 1 млн или 33 мс, раз вьюпорт не единственное, что рисует Flutter | выбрать до замера; ≤16,6 → бюджет 1 млн, 16,6–33 → ≤300k (p0-02); равноправие веба от порога не зависит (Е1) |

### Б. Структура данных ядра

| # | Вопрос | Рекомендация |
|---|---|---|
| Б1 | Неманифолдный вход: расщеплять рёбра с ≥3 гранями при импорте и показывать как проблему, или радиальная структура по образцу BMesh | **Закрыт 2026-09-09 (решение владельца):** расщеплять при импорте и помечать как проблему (mesh-13, mesh-27); радиальной структуры нет |
| Б2 | Стабильность id элементов: надгробия + `compact()` с `IdRemap` или плотные id с перенумерацией | надгробия — нужны карточке переприменения, журналу и `Selection` в MCP (doc-07) |
| Б3 | Критерий 0.3 «≤10 % полной копии»: на смежном 1 % или на случайном; чанки или журнал прежних значений | **Закрыт 2026-09-09 (решение владельца):** отмена для мешей — персистентные значения со структурным разделением (mesh-10/11, doc-08); разбивку на чанки и патчи, а с ней и то, на каком распределении держится ≤10 %, меряет p0-05/mesh-02 — это уже замер, не вопрос |
| Б4 | Параметрические объекты строят квады сами, `Shape` — эталон parity (расходится с §5.2) | подтвердить (mesh-28/29) |
| Б5 | Какие атрибуты по углу, какие по вершине | UV и цвет по углу, позиция/joints/weights/shape keys по вершине (mesh-12) |
| Б6 | `materialSlot` по грани в фазе 1 | да: GLB с несколькими материалами требует `MeshData` на слот (mesh-14, doc-12) |
| Б7 | Enum против sealed для уровня выделения, severity, режима | `ElementLevel`/`IssueSeverity` — enum с экземпцией; содержимое (геометрия, модификаторы, команды) — sealed (qa-06, mesh-19) |
| Б8 | Скульптинг: `SculptMesh` отдельной плоской структурой (pro-sc-02) или патч-слой над `EditMesh` (mesh-72) | **Закрыт 2026-09-09 (решение владельца):** `SculptMesh` с мультиразрешением (pro-sc-02/07); грязный чанк = непрерывный диапазон буфера; pro-sc-01 меряет, не выбирает |
| Б9 | Мультиразрешение или динамическая топология | **Закрыт 2026-09-09 (решение владельца):** мультиразрешение (pro-sc-07); экран 08 получает кнопку «Подразбить» вместо «плотности кисти» (ui-29) |

### В. Пакеты и публикация

| # | Вопрос | Рекомендация |
|---|---|---|
| В1 | **Закрыт 2026-09-09 (по критике, переписан решением владельца).** Пакет словаря: имя и состав | **Закрыт 2026-09-09 (решение владельца):** два пакета вместо одного, срок фазы 0 — 2026-09-25. `flutter3d_geometry` — `MeshData`, `VertexLayout`, `Shape`/`LatheShape` и производные, тангенсы, `morph_target`, `CpuMesh`, `math/intersections`, `Ray`, `TriangleBvh`; `flutter3d_formats` — `ModelDocument`, `SurfaceMaterial`, `MaterialDocument`/`MaterialHint`, `lighting_model`, синхронная половина `model_loader`, декодеры gltf/obj/f3d/ktx2/stl, писатели `F3dWriter`/`GltfWriter`/`ObjWriter` (fmt-01..09/12/15; в engine остаются только fmt-13/14 — иначе `flutter3d_model_mcp` не экспортирует GLB (doc-21) и не стартует без Flutter (rel-04)). `formats → geometry`, `mesh → geometry`, `model_core → оба`, `flutter3d` реэкспортирует оба; порядок публикации §16: geometry → formats → flutter3d; 33 пакета к концу фазы 0 |
| В2 | Четвёртый пакет `flutter3d_rig` (ретаргет, авториг) или всё в core, или в движок | `rig` — алгоритмы над `Pose`/`ModelDocument`, играм не нужны; веса — в `flutter3d_mesh/skin/`; `Pose` и IK — в движок |
| В3 | `flutter3d_cloth` отдельно или подпапка `flutter3d_physics` | **Закрыт 2026-09-09 (решение владельца):** отдельный солвер `flutter3d_cloth` в фазе 4 — плоский пакет с зависимостью только на `CollisionShape` (pro-sim-01); И1 закрыт тем же ответом |
| В4 | Ворота `.fmat` (mat-03): в `flutter3d_editor_core` с зависимостью модельера на него ради одной библиотеки, или дублировать | в `editor_core` (одни ворота на два редактора), но только после doc-01: библиотека принимает `MaterialDocument`/`MaterialHint`, а `editor_core` — плоский пакет, которому нельзя тянуть Flutter SDK; `editor_core` получает зависимость на `flutter3d_formats`, ярус в §16 сдвигается (rel-03); альтернатива — библиотека в model_core, редактор уровней импортирует оттуда. В фазе 2 — вместе с `FieldRow` в `flutter3d_editor_widgets` (ui-27) |
| В5 | Имена: mesh / model_core / model_mcp / modeler или единый корень; резервировать ли на pub.dev; где живёт код | **Закрыт 2026-09-09 (решение владельца):** код живёт в этом монорепозитории — пакеты входят в workspace, сканер структуры, CI и порядок публикации §16 (qa-02/03/04, rel-02/03); имена — mesh / model_core / model_mcp / geometry / formats и `flutter3d_modeler`; не резервировать заглушкой, перепроверять перед rel-06 (rel-01) |
| В6 | `bin/` утилиты: `flutter3d_mesh:check`, `flutter3d_model_core:export` | `core:export` — да (нужен rel-13); `mesh:check` — нет, лишняя публичная поверхность |
| В7 | Версии новых пакетов: 0.1.0 или номер полки (0.7.0 после правки HAL) | номер полки (§16: одна цифра — одно дерево) |
| В8 | Первая публикация: набор 27 декабря или первый набор 2027 | **Закрыт 2026-09-09 (решение владельца):** первая публикация и релиз — только когда фаза 1 в руках у первых пользователей (rel-16 → rel-06); 27 декабря целью не является, до того — «в порядке, но не наружу», как strategy |

### Г. Документ, история, формат, MCP

| # | Вопрос | Рекомендация |
|---|---|---|
| Г1 | Магия файла проекта и место автосохранения (рядом с файлом или в каталоге приложения); расширение `.f3dproj` закрыто решением 2026-09-09 (Г2) | магия `F3DP`; автосохранение в каталоге приложения через `Storage` (ui-18) |
| Г2 | Хранить ли историю в файле проекта (README передачи) | **Закрыт 2026-09-09 (решение владельца):** да — свой `.f3dproj` с историей: секция `history` в контейнере (doc-09, doc-31d), шаг = `says` + команда + ссылка на прежнее значение через чанки, уже лежащие в файле как блобы; лимит Г5 применяется к файлу; «сохранить без истории» — опция (ui-33d); журнал doc-16 остаётся. Приёмка round-trip: сохранить → открыть → отменить три шага |
| Г3 | `Selection` в аргументах мешевых команд и `select` как verb — не два ли пути для UI | оба, как предложено (doc-04/07): объектные команды несут id, мешевые — `Selection` |
| Г4 | Язык `says` и описаний инструментов; тип подсказок параметров — **закрыт 2026-09-09**: свой sealed `ParamHint` в core | **Закрыт 2026-09-09 (по критике, язык подтверждён решением владельца):** английский в ядре, MCP и `says`, локализация в app (ui-22, русский и английский с первой версии — Е2); подсказки — свой `ParamHint` (Int / Double / Bool / Enum / Vector3, `step`, `unit`, диапазон), потому что у `MaterialHint` есть только `RangeHint(double, step)`, `ColorHint`, `TextureHint`, `EnumHint` — ни целых, ни флагов, ни единиц — и `material_hint.dart` тянет `LightingModel`; `MaterialHint` остаётся панели материала (syn-01) |
| Г5 | Глубина истории: 64 шага или лимит по байтам | оба (doc-08); число байт — из p0-05 |
| Г6 | PNG с deflate: свой кодировщик, `package:archive` в core, или сырые RGBA в проекте и PNG только в app; и декодирование (нода Image графа, mat-09n) — в репозитории нет ни одного чистого декодера PNG/JPEG (golden читает через `dart:ui`, `cpu_png.dart` только пишет) | сырые RGBA в проекте всегда; для экспорта из MCP без Flutter — `package:archive` в core (mat-12); декодер — `package:image` в core или свой inflate + baseline JPEG (mat-09n); если ни то ни другое — граф без пикселей в core и запекание через `dart:ui` в app, тогда `bakeTextureGraph` из mat-32 невозможен и это записывается |
| Г7 | `json_write_through.dart` из `flutter3d_sim`: копия в core или общий пакет | копия (~100 строк), обратная зависимость на sim недопустима |
| Г8 | MCP создаёт новый проект по несуществующему пути; профиль по умолчанию | да (doc-19); профиль `desktop` |
| Г9 | Экспорт при `Issue` уровня error: отказывать или предупреждать | **Закрыт 2026-09-09 (решение владельца):** предупредить и экспортировать с явным подтверждением; отказ только при пустой геометрии (doc-14, ui-17; приёмка §5.2) |
| Г10 | Хранить ли исходный импортированный файл вербатим в проекте | нет в v1 (удваивает размер); опция позже (fmt-18) |

### Д. Форматы

| # | Вопрос | Рекомендация |
|---|---|---|
| Д1 | STL как встроенный `ModelFormat.stl` (правка экземпции) или внешний декодер | встроенный (fmt-09) |
| Д2 | `authoredAttributes` на `ModelSurface` или на `MeshData` | `ModelSurface` (fmt-03) |
| Д3 | `extras` и `asset` в словаре и в `.f3d` или только у glTF-писателя | в словаре («open, and without a registry»), по секции `.f3d` на поле (fmt-04/19) |
| Д4 | Скины/анимации/морфы в `GltfWriter` в фазе 1 или 3 | фаза 1 (fmt-07) |
| Д5 | Пакет `gltf` (Khronos-валидатор) резолвится под SDK ^3.12? | спайк полдня; иначе `npx` в CI или свой чекер (fmt-11) |
| Д6 | Семейства сжатия по профилям (ETC2/ASTC/BC/ETC1S) и допустим ли FFI к libbasisu в офлайн-конвертере | fmt-22 на Dart для `.f3d`; Basis — решение fmt-23 до фазы 3; на вебе и в редакторе FFI нет |
| Д7 | FBX: свой читатель (fmt-24/25, два L) или только сервер (fmt-26); где хостится | **Закрыт 2026-09-09 (решение владельца):** свой читатель на Dart — fmt-24/25 (два L) в фазе 2 отдельной дорожкой после того, как фаза 1 в руках (rel-16); пакет `flutter3d_fbx`, плоский, зависит от `formats` (fmt-29d); серверная конвертация fmt-26 снята — не делаем |
| Д8 | USDZ: есть ли спрос; принимает ли Quick Look usda | спайк на устройстве до любой оценки (fmt-27) |
| Д9 | Свет и камеры в `ModelDocument`: кто добавляет — рендер-трек или fmt-28 | fmt-28, рендер-трек потребляет |
| Д10 | Второй UV-набор (`texcoord1`) для AO/лайтмапов | нет в фазе 4; AO на основной UV |
| Д11 | `tool/make_models.py` заменить Dart-`GltfWriter` | да, после rel-13, одной перегенерацией |

### Е. Оболочка, платформы, веб

| # | Вопрос | Рекомендация |
|---|---|---|
| Е1 | Веб на старте — равный или просмотр; JS-сборка допустима, если `file_selector_web` не собирается под wasm | **Закрыт 2026-09-09 (решение владельца):** веб — равноправная платформа с первой версии, не «решают замеры»; p0-02/p0-08 остаются воротами качества: непройденный порог становится пунктом фазы 1 (JS-сборка как записанное исключение ARCHITECTURE §1, порции вместо изолята, worker ui-34d при необходимости) |
| Е2 | Английский с первой версии | **Закрыт 2026-09-09 (решение владельца):** русский и английский с первой версии — ru шаблон + en (ui-22); ядро, MCP и `says` — английский (Г4) |
| Е3 | Режимы фаз 2–4 в переключателе: выключенные или скрытые | выключенные — README требует пять сегментов постоянно |
| Е4 | Сандбокс macOS: два entitlement-файла (Debug без, Release с) или один; и как писать файл под `user-selected.read-write`, если `writeFileAtomically` делает rename в каталог, куда доступа нет (причина, по которой редактор уровней сандбокс выключил) | два; относительные пути `--dart-define` живут только в Debug; способ записи — по p0-13n в фазе 0 (`saveFile` + прямая запись или security-scoped каталог), после него ui-14 переписывает native-ветку |
| Е5 | Набор горячих клавиш | **Закрыт 2026-09-09 (решение владельца):** Blender-подобные (G/R/S/E/I, 1/2/3, Tab) там, где не конфликтуют с платформой; перечислены в справке (ui-32n) |
| Е6 | Автосохранение на вебе: localStorage через `Storage` или IndexedDB-расширение | `BinaryStorage` в `flutter3d_screens` (ui-18), правка пакета репозитория — нужно согласие |
| Е7 | Открытие файлов из системы (Finder, intent, DocumentBrowser) | фаза 2 |
| Е8 | Подпись и нотаризация macOS на фазу 1 | **Закрыт 2026-09-09 (решение владельца):** «правый клик → Open» в фазе 1; аккаунт Apple Developer и iPad нужны до середины фазы 1 (rel-19d), потому что iOS — платформа фазы 1 |
| Е9 | Канал обратной связи: только Issues с меткой или ещё Discussions | Issues + кнопка в приложении (rel-15); Discussions — по спросу |
| Е10 | Ассет туториала: модель Khronos или «купленный ассет» | Khronos из `flutter3d_samples` (лицензия уже есть) |
| Е11 | Допустима ли заморозка интерфейса на вебе при неделимой операции до фазы 2 | **Закрыт 2026-09-09 (решение владельца):** да, с прогрессом на месте кнопки; web worker — условный пункт фазы 1 (ui-34d), если p0-07/p0-08 покажут заморозку дольше 1 с |
| Е12n *(добавлено по критике)* | Набор иконок: README передачи требует Material Symbols Outlined (вес 400), во Flutter это внешний пакет `material_symbols_icons` (Apache 2.0, несколько МБ шрифта в бандле); `Icons` из SDK — без зависимости, но часть глифов другая | **Закрыт 2026-09-09 (решение владельца):** `Icons` из SDK с таблицей соответствия в ui-02; `material_symbols_icons` не берём |

### Ж. Рендер, материалы, модификаторы

| # | Вопрос | Рекомендация |
|---|---|---|
| Ж1 | «Граф нод» → «компоновщик текстур», состав нод mat-10; запись в ROADMAP | **Закрыт 2026-09-09 (решение владельца):** компоновщик текстур с фиксированным набором нод (mat-10); формулировка ROADMAP о графе нод меняется на ревизии 28 сентября (§7 № 3) |
| Ж2 | Подсказки параметров нод и модификаторов: `MaterialHint` как есть или общий `ControlHint` в движке — **закрыт 2026-09-09** | `ParamHint` из core (Г4) для нод, модификаторов и команд; `MaterialHint` — только панель материала; движок не правится |
| Ж3 | Модификатор: один флаг `enabled` или `enabled` + `showInViewport` | один в v1 |
| Ж4 | Режим «Сцена» v1: только свет/окружение/тени/пост или расстановка ассетов и пробы отражений; план дизайна §1 называет композицию ассетов третьим отличием продукта (§7 № 36) | **Закрыт 2026-09-09 (решение владельца):** свет/окружение/тени/пост плюс расстановка нескольких ассетов — doc-11a-n (`ImportInto`) безусловно в фазе 2, mat-24 расширен расстановкой и экспортом сцены одним GLB; §7 № 36 закрыт; пробы отражений не входят |
| Ж5 | Цифры бюджета текстур по пресетам и разрешение запекания по умолчанию | десктоп 2048/256 МБ, мобильный 1024/64 МБ, веб 2048/128 МБ; запекание 1024 по умолчанию — согласовать |
| Ж6 | HDRI: LDR-панорама в фазе 2 или `.hdr` с float-окружением | LDR (mat-16) в фазе 2 с подписью; mat-17 в фазе 4 |
| Ж7 | Фон вьюпорта: плоский `#0E1112`, небо `SkySettings` или радиальный градиент из README передачи (hi-fi) | плоский в v1; градиент реализуем на всех бэкендах — `SkySettings` (как и предлагает view-02) или полноэкранный unlit-квад, а не «невозможен»; расхождение с README — §7 № 37 |
| Ж8 | Точки-вершины: квады везде или `PrimitiveType.point` где есть | квады везде — одна картинка, один golden-путь |
| Ж9 | Смещение глубины оверлеев: CPU или стейдж `OverlayVertex` | по view-01(в), порог 2 мс |
| Ж10 | `overwriteGeometry` и кадры в полёте на Impeller: двойной буфер в `DeviceMesh` или обязанность бэкенда | бэкенд буферизует; контракт — «видно со следующего прохода» (view-14) |
| Ж11 | Каркас скиннированных мешей в позе: второй стейдж или только бинд-поза | бинд-поза в фазе 2 |
| Ж12 | Hover по граням на каждое движение мыши на телефоне | hover подэлементов только на десктопе; на тач — по клику |
| Ж13 | Меш предпросмотра материала по умолчанию; пол с тенью | сфера; пол — да |
| Ж14 | Ждать энкодер из ROADMAP или показывать расчёт | расчёт (mat-28) сразу; mat-30 после fmt-22 |

### З. Анимация

| # | Вопрос | Рекомендация |
|---|---|---|
| З1 | Четыре влияния как жёсткий предел или раскладка на 8 в фазе 4 | жёсткие 4 (anim-32); убрать из дизайна намёк на произвольное число |
| З2 | 64 кости: «разделить меш по скелетам» как операция или только ошибка | только ошибка в v1 |
| З3 | IK при экспорте: запекать молча или спрашивать; нужен ли runtime-IK в плеере | запекать молча с записью в `ExportReport`; runtime-IK — вне этой итерации |
| З4 | Ключ корневого движения в extras и `rootMotionDelta` — согласовать с треком «animation that adds» | согласовать на ревизии ROADMAP, один API |
| З5 | Временная база: секунды (glTF, `AnimationTrack`) или кадры | секунды; fps профиля только для показа и привязки (syn-03) |
| З6 | Ретаргет v1: только гуманоид или четвероногое тоже | гуманоид |
| З7 | Источник mocap для экрана 14: только glTF/GLB | да (BVH и FBX вне плана до fmt-25) |
| З8 | Лицевые наборы: стандартная номенклатура (52 ARKit) как шаблон или только пользовательские группы | пользовательские в v1 |
| З9 | Драйверы форм: только в проекте с запеканием или секция `.f3d` для рантайма | запекание в v1 (anim-20) |
| З10 | Аддитивный слой из ROADMAP до фазы 3 или после | после; reference-поза — кадр 0 клипа |

### И. Фаза 4

| # | Вопрос | Рекомендация |
|---|---|---|
| И1 | Чей солвер ткани: тот самый из ROADMAP (потом в physics) или редакторский навсегда | **Закрыт 2026-09-09 (решение владельца):** отдельный солвер `flutter3d_cloth` в фазе 4 (В3); на строку Committed о soft bodies не претендует, переезд в `flutter3d_physics` — отдельное решение после фазы 4 (§7 № 5) |
| И2 | Экспорт симуляции: ≤8 морф-целей, секция вершинной анимации `.f3d` + узел, или только предпросмотр | морф-цели в фазе 4, секция — по спросу |
| И3 | Три правки контракта (`overwriteGeometry`, `overwriteTexture`, `renderPost`): в фазах 2–3 или к старту фазы 4 | по одной на фазу: 2 / 3 / 4 |
| И4 | «Твёрдое тело» без вращения приемлемо для фазы 4 | да, с подписью (pro-sim-02) |

### К. Качество и публикация

| # | Вопрос | Рекомендация |
|---|---|---|
| К1 | Кто записывает Impeller/WebGL/WebGPU-наборы новых сцен и гоняет Impeller-конформанс | нужна ночная macOS-машина из ROADMAP; до неё сцены живут в `_provisional`, что acceptance view-05 запрещает к мержу |
| К2 | Внешняя проверка экспорта сверх валидатора: headless Godot в CI или ручной чек-лист | **Закрыт 2026-09-09 (решение владельца):** headless Godot в CI — qa-19n (S), как требует план дизайна («открывается в Godot и Unity» автотестом); Unity и Blender — ручной чек-лист в HANDOFF перед релизом фазы 1 |
| К3 | `tool/structure.dart --recount`, переписывающий числа в документах | нет: сканер печатает число, человек правит |
| К4 | Где живут GPU-числа фазы 0: HANDOFF (вне git) или doc §6 | doc §6 (единственная копия в git), HANDOFF дублирует |
| К5 | Что в ROADMAP двигается вниз ради девятого трека | владелец; кандидаты — декали, измерение |

---

## 9. Риски

Слиты из одиннадцати списков; оставлено снимающее действие с id.

| # | Риск | Снимающее действие |
|---|---|---|
| 1 | Красный `main` и три пакета под тридцатью правилами: числа тестов и пакетов, порядок публикации, enum, «публичный член без вызова», `dashed`/`reload`/`spike` в lib, `DateTime.now()` и `math.sin` под правилами шага | qa-01 первым; qa-02/03/04/05/06 до первой строки кода; `dart run tool/structure.dart` перед каждым коммитом; числа — в том же коммите, что тест (qa-16) |
| 2 | Чистое ядро не резолвится без Flutter SDK (сканер не видит транзитивную зависимость) — обнаружится у первого хоста MCP | doc-00 → doc-01 в фазе 0; правило qa-03; контейнерная проверка rel-04 |
| 3 | Снимок персистентного меша при разбросанных правках трогает почти все чанки — §4.3 не выполняется; GC-паузы от новых значений на каждый кадр | p0-05 (чанки против журнала, два распределения) и p0-11 (сквозной конвейер) до mesh-10; `toMeshData(into:)`, снимок на транзакцию, при провале — рабочий режим внутри транзакции |
| 4 | Half-edge ломается тихо: картинка верна, следующая операция падает через десять шагов; loop cut/ring/Catmull-Clark молчат на триангулированном импорте | `validate()` после каждой операции в тестах (mesh-11), фазз с сидом (mesh-32), обходы останавливаются на не-квадах с `report`, `dissolveEdge` восстанавливает квады (mesh-25), квады у параметрических (mesh-28), parity-тест (mesh-29) |
| 5 | Экспорт сходится с собственным лоадером, но не с Godot/Unity/Blender; сгенерированные атрибуты делают round-trip недостижимым | fmt-03 до писателя; fmt-10 (кадр против кадра), fmt-11 (валидатор), headless Godot в CI (qa-19n), ручной чек-лист Unity/Blender перед релизом (К2 закрыт 2026-09-09); `compareModelDocuments` с категориями и мутациями |
| 6 | Байтовая недетерминированность (libm, порядок ключей, форматирование double) ломает дифф фикстур на двух ОС | квантование координат, канонический JSON, Float32 в блобах, сравнение геометрии с допуском; фикстуры записаны на двух ОС (doc-21, rel-13) |
| 7 | Правка контракта `GraphicsDevice` ломает четыре бэкенда и fake; асинхронный submit на Impeller читает уже перезаписанный буфер | одна правка контракта на фазу; PR на все бэкенды с конформанс-проверкой; семантика «видно со следующего прохода» и буферизация на стороне бэкенда (Ж10); Impeller через `conformance.sh` с датой (view-14) |
| 8 | Пересоздание `DeviceMesh` на каждую правку и оверлей на 200 тыс. рёбер каждый кадр не укладываются в кадр на телефоне и в WebGL | p0-06 и view-01(б,в) до реализации; `MeshLayoutPlan`/`fillVertices` (mesh-14); линии в постоянном буфере по версии, ленты только для выделенного; прореживание точек (view-13) |
| 9 | Новый шейдер требует `glslangValidator`, `naga`, `impellerc` и Dart-стадию; забытая стадия падает на одном бэкенде | не более двух вершинных стейджей и ни одного фрагментного; `ci.sh` регенерирует таблицы; `manifest_test` пиннит `kRequiredShaders` (view-06/07) |
| 10 | Голден-сцены пишутся только на macOS с GPU и в Chrome; между записью наборов сцена в `_provisional` не ловит регрессию | CPU-набор первым как эталон согласия; по одной сцене на PR; `_provisional` пуст к мержу (view-05); машина К1 |
| 11 | BSP-булевы взрываются по полигонам и времени на копланарных мешах, переполняют стек или вешают интерфейс | явный стек, eps по bounds, бюджет полигонов с отказом, детектор копланарности, `Isolate.run` (mesh-47, mesh-30); кэш по версиям и порог живого пересчёта в стеке (mat-18/20) |
| 12 | На вебе нет изолятов: импорт 100 МБ, булевы, запекание, авториг замораживают вкладку; «в изоляте» из README невыполнимо буквально | один раннер (doc-24/ui-25) с порциями и уступкой кадру; p0-07 решает форму операций; веб равноправен (Е1, решение 2026-09-09): при заморозке дольше 1 с на эталонной операции — ui-34d в фазе 1; лимит импорта на вебе в диалоге |
| 13 | Веб-стек файлов (`file_selector_web`, `package:web`, wasm, COOP/COEP) работает в Chrome и не работает в Safari/Firefox; фиксированный размер вьюпорта (`kFixedResolution`) — мыло на 5K | p0-08 с таблицей браузер × действие; rel-10 проверяет тем же компилятором, что шипит сайт; ui-20 — пересоздание устройства или resize `WebGlDevice` |
| 14 | Веса и морфы портятся первой топологической операцией; CPU-скиннинг расходится с шейдером; редактор красит «не там» | слои с правилами наследования в одном месте (mesh-12/60), полные слои позиций вместо дельт (mesh-61), паритет `SkinBlend`/`Pose` против транскрипции шейдера и `Skeleton.update` (anim-01/02/28) |
| 15 | Лимиты 4 влияния / 64 кости выглядят в дизайне настройкой профиля, а в движке — константы бандла | anim-32: профиль не принимает больше, текст отказа называет причину; `RigReadiness` показывает превышение до экспорта |
| 16 | Первичные веса авторига (оболочки) и ретаргет (скольжение стоп) разочаровывают | тест видимости и сглаживание (anim-22), честная подпись «первичные веса», прижим стоп через IK с тестом «≤1 см при росте ×2» (anim-17); heat diffusion — кандидат фазы 4 |
| 17 | Граф-компоновщик прочитается как «node-graph materials» из «Not doing», и mat-10..13 отвергнут целиком; запекание 2048² на CPU занимает секунды/десятки секунд | переименование и запись в ROADMAP до старта (Ж1); доказательство — эталоны движка не меняются; предпросмотр 256² с кэшем по ветке, полное разрешение по кнопке в изоляте (mat-11) |
| 18 | Формат проекта меняется вместе с `EditMesh` на каждом шаге фазы 1 и ломает автосохранения первых пользователей; PNG без сжатия делает проект в 80 МБ | миграции с первого дня, фикстуры каждой версии навсегда, неизвестные секции и ключи переживают round-trip (doc-28, pro-doc-01); сырые RGBA с разделением блобов, PNG на экспорт (mat-12) |
| 19 | Три раскладки расходятся по составу инструментов; `documents.dart` тянет `dart:io` в веб-сборку; compact-плотность не проходит контраст и textScaler | таблица инструментов с тестом множества id (ui-07); conditional export с первого коммита и веб-сборка в CI с фазы 0 (ui-14); guideline-тесты (ui-23) |
| 20 | Локализация введена поздно: русский интерфейс и английские `says` ядра в одной строке статуса | ui-22 до первых панелей; язык `says` решён до model_core (Г4) |
| 21 | Восемь источников на объект и шесть теневых — режим «Сцена» позволит больше, и свет молча отбросится | статус читает `lightsDropped`/`shadowsDenied` каждый кадр (mat-24); `ExportReadiness` дублирует как Issue |
| 22 | Скульптинг на 1,2 млн не укладывается в кадр на Dart; программный растеризатор на 4К считает минуты | pro-sc-01 и pro-rn-01 до структуры и UI; фиксированная топология + чанки + локальные нормали + overwrite; лимит плотности на вебе (pro-sc-09); тайлы с прогрессом (pro-eng-04), SSAA ×1 по умолчанию |
| 23 | Ткань зависит от `flutter3d_physics` ради форм столкновений, а мягкие тела движка придут с другим API | зависимость только на `CollisionShape`; детерминизм и фиксированный шаг по правилам sim, чтобы перенос был копированием (pro-sim-01, И1) |
| 24 | Время job `check` растёт на три `dart test`, браузерный прогон, бенч, wasm-сборку и тесты приложения при 60-минутном timeout | время каждого шага записано в `ci.yml` (qa-17); браузерный прогон только для mesh; бенч — артефакт, не assert; выше 30 минут — отдельный job `modeler` |
| 25 | Спайки под `tool/` разрастаются в третий движок геометрии, который никто не переносит в пакет | mesh-01/02 сразу в `packages/flutter3d_mesh`; веб-спайк p0-08 — один вопрос, README «The answer», после переноса «superseded by» (p0-12) |
| 26 | Правки engine ради редактора застревают в согласовании (выделение словаря, HAL) и блокируют критический путь | mesh-01/02 не зависят от решения; фолбэк `TriangleBuffers` описан в mesh-03 (~50 строк адаптера); срок В1 — 2026-09-25; трек в ROADMAP (rel-12) |
| 27 | Первых пользователей нет или отзывы не доходят; «пятнадцать минут на любом устройстве» остаётся обещанием | rel-09 делает туториал тестом в CI с измеренным временем; rel-15 кнопка в приложении; rel-16 когорта набирается лично, итог в ROADMAP числами |
| 28 | `MorphTexture` пакует одну колонку на вершину — ширина текстуры ограничивает число вершин морфящегося меша (проверено: `geometry/morph_texture.dart` — «width the mesh's vertex count, height three rows per target») | правило в `ExportReadiness` уже в фазе 1 (doc-14: «вершин с морфами > `maxTextureSize` профиля»), потому что импорт с морф-целями приходит в фазе 1; `rigIssues` (anim-13) и экспорт симуляции (pro-sim-05) читают тот же лимит |


---

## 10. История правок

### 2026-09-09 — правки по критике

Двадцать пять находок и двенадцать «недостающих аспектов»; каждая проверена по
дереву на `239ccf8e` и по архиву передачи дизайна до внесения. Одна строка на
находку.

- В1 закрыт: писатели fmt-01..09/12/15 переведены в чистый пакет словаря (тогда один, под рабочим именем; с решением владельца ниже — `formats`), в engine остались fmt-13/14; fmt-06/08/09 зависят от doc-01; §3.1, §4.2, §5.1, §5.2, §6 и «Коротко» согласованы (pubspec `flutter: sdk`, `flatDartPackages`).
- Фаза 1 получила панель материала mat-04a-n; `SetTexture`/`AddImage` перенесены из doc-25 в mat-01; приёмка §5.2 требует цвет и текстуру в GLB (план дизайна: «Базовые материалы» в фазе 1).
- rel-04 больше не зависит от doc-19: заглушка `bin/model_mcp.dart --help` заводится в rel-02, `tools/list` в контейнере — приёмка doc-19.
- anim-31 сужен до FK `Skeleton.update` (код есть); мазок/`SkinBlend`/`bindWeights` — anim-31a-n на старте фазы 3.
- Дописаны зависимости doc-03 ← mesh-11, doc-07 ← mesh-22..26, ui-09 ← doc-07/syn-01, ui-26 ← doc-07, mat-01 ← doc-03/05; §4.1 пересчитан строго по ним (см. ниже).
- `TriangleBvh` получил владельца: view-09 (в пакете словаря — после решения владельца `geometry`, зависит от doc-01 и p0-10), mesh-20 — `MeshBvh` поверх, зависит от view-09.
- Г4/Ж2 закрыты в пользу своего `ParamHint` в core; `MaterialHint` — только панель материала (у `RangeHint` шаг есть, но нет целых, флагов, единиц; файл тянет `LightingModel`).
- Счёт пакетов: qa-02 расширяет числительные до forty; §5.1, qa-16, rel-06 — 32 пакета; doc-01, ui-27, anim-17, pro-sim-01, fmt-24 несут сдвиг числа в приёмке.
- doc-01 переносит `render/lighting_model.dart` и синхронную половину `model_loader.dart` (`ModelFormat`, `ModelDecoder`, `sniffModelFormat`, `decodeModel`), `kIsWeb` → `bool.fromEnvironment`; путь экземпции `ModelFormat` обновляется.
- mat-03 зависит от doc-01; `editor_core` получает зависимость на пакет словаря (теперь `formats`), ярус в §16 — rel-03; В4 переписан.
- Спайк сандбокса p0-13n в фазе 0; ui-14 native-ветка и ui-20 зависят от него; Е4 и §7 № 35 дополнены (`Release.entitlements`, `atomic_write.dart`).
- §7 № 36: композиция ассетов из плана дизайна §1 против Ж4; условный doc-11a-n `ImportInto` в фазе 2; Ж4 помечен как расхождение.
- mat-09n: чистый декодер PNG/JPEG для ноды Image (в дереве только `dart:ui` и писатель `cpu_png.dart`); mat-11 зависит от него; Г6 дополнен.
- mesh-28 строит UV по углам как `Shape.build()`, mesh-29 сравнивает texcoord (1e-6), mesh-23 проверяет UV боковых квадов тестом; mesh-12 получил правило заполнения `uv0`.
- §7 № 4: `LightBuffer.packFor` → `gatherNear`/`gatherNearFrom`.
- §7 № 10 и К5: восемь committed-треков, девятый входит.
- doc-29 → ARCHITECTURE §8.7, fmt-16 — §8.6 Writers; §7 № 2 согласован.
- ui-15: `defaultStorage('flutter3d_modeler')` вместо `Storage(appName:)`.
- Путь бенча — `packages/flutter3d/tool/bench`; приёмка mesh-03 и §6 № 1 — `bench_geometry.dart` AOT отдельным main.
- ui-13: сегменты-кривые Безье с уплощением в полилинию для `LatheShape`, `AddLathe` хранит кривую, чипы «Точка / Кривая / Ось».
- Ж7 без «невозможен»: градиент — `SkySettings` или unlit-квад; расхождение с README — §7 № 37.
- Риск 28: пометка «не проверено» снята (`morph_texture.dart`), правило переехало в doc-14 (фаза 1).
- qa-08: провенанс — `assets/ATTRIBUTION.md` пакета samples (критик назвал README; README на него ссылается, `LICENSES.md` только в apps).
- view-06: размер S помечен условным с оценкой M по риску 9, если пункт срабатывает.
- pro-eng-06: секция `LODS` = kind 24.
- Недостающие аспекты: единицы и ось вверх при импорте (doc-11 `ImportOptions`, ui-16); иконки (ui-02, Е12n); необработанные исключения (ui-30n); пивот и `ApplyTransform` (doc-06, ui-17); drag-and-drop (ui-31n); лимиты входа (ui-16); совместная работа (pro-after-01); справка и клавиши (ui-32n); headless Godot в CI (qa-19n, К2).

Критический путь после пересчёта: `qa-01 → qa-02 → mesh-01 → mesh-02 →
mesh-10 → mesh-11 → mesh-12 → mesh-13 → mesh-25 → doc-07 → doc-20 → rel-09 →
rel-16`, 4 S + 8 M + 1 L ≈ 29 недель — число прежнее, состав другой (см. §4.1).
Счётчики: 317 + 3 + 9 пунктов, 37 расхождений, 84 открытых вопроса, 32 пакета
к концу фазы 0 (числа на момент этой ревизии; после решений владельца ниже —
другие).

### 2026-09-09 — решения владельца

Двадцать ответов Дмитрия на вопросы §8; каждое внесено как факт с пометкой
«решение 2026-09-09». Одна строка на решение и что оно изменило в плане.

- Код живёт в этом монорепозитории (В5 закрыт): пакеты входят в workspace, сканер, CI и порядок публикации §16; §5.1 «Решения до старта: нет».
- Веб — равноправная платформа с первой версии (Е1 закрыт): p0-02/p0-08 переписаны как ворота качества, непройденный порог становится пунктом фазы 1; §1 п. 3, §5.1, §7 № 11 согласованы. Заморозка с прогрессом допустима (Е11 закрыт), web worker — условный пункт фазы 1 ui-34d (сноска ⁸), §7 № 31 дополнен.
- Фаза 1 выходит на macOS, вебе, Android и iOS: ui-21 перенесён из фазы 2 в 1 (сноска ⁴), §7 № 34 закрыт; iPad и аккаунт Apple Developer — rel-19d до середины фазы 1 (А2, Е8 закрыты); подпись macOS — «правый клик → Open».
- Русский и английский с первой версии (Е2 закрыт), ядро/MCP/`says` — английский (Г4 подтверждён); ui-22 и приёмка §5.2 дополнены.
- Отмена для мешей — персистентные значения со структурным разделением (Б3 закрыт); разбивку меряет p0-05.
- Неманифолдный вход расщепляется при импорте и помечается как проблема (Б1 закрыт; mesh-13/27).
- Скульптинг — `SculptMesh` с мультиразрешением (Б8/Б9 закрыты); экран 08 получает «Подразбить» вместо «плотности» (§3.1, §5.5).
- Формат проекта — `.f3dproj` с историей (Г2 изменён): doc-31d (секция `history`, шаг = `says` + команда + ссылка на чанки-блобы, лимит Г5 на файл), ui-33d («сохранить без истории»); журнал doc-16 остаётся; приёмка §5.2 — сохранить → открыть → отменить три шага.
- Граф нод — компоновщик текстур с фиксированным набором нод (Ж1 закрыт); ROADMAP переформулируется на ревизии 28 сентября (§7 № 3, §5.1).
- Режим «Сцена» фазы 2 = свет/окружение/тени/пост плюс расстановка ассетов (Ж4 и §7 № 36 закрыты): doc-11a-n безусловно (сноска ⁶), mat-24 расширен расстановкой и экспортом сцены одним GLB; приёмка §5.3 дополнена.
- «Рендер» экрана 12 — снимок тем же рендерером с суперсэмплингом и проходами frame graph (pro-rn-02); трассировщик вне плана; §5.5.
- Иконки — `Icons` из SDK с таблицей соответствия (Е12n закрыт); §7 № 37 помечен, градиент Ж7 открыт.
- Словарь — два пакета вместо одного: `flutter3d_geometry` и `flutter3d_formats` (В1 переписан): §1 п. 1, обозначения, §3.1, §5.1, §6 № 1/2–10/12/15/20 и столбцы «пакет», §7 № 24/28, В4; 33 пакета к концу фазы 0, порядок публикации geometry → formats → flutter3d; прежнего рабочего имени в файле не осталось.
- Первая публикация — когда фаза 1 в руках у первых пользователей (В8 закрыт); 27 декабря целью не является; rel-06 после rel-16, §4.3.
- Состав — один человек с агентами (§4.3 переписан): календарь фазы 1 = сумма размеров (S = 1, M = 2,5, L = 5 недель) — 73 S + 44 M + 3 L ≈ 198 недель; с агентами на дорожках форматов, оверлеев, платформ и локализации ≈ 172 (предположение, проверяется первой дорожкой); таблица «1 / 2 / 3 человека» снята; §1 п. 2.
- Экспорт при ошибке проверки — предупредить и экспортировать с подтверждением, отказ только при пустой геометрии (Г9 закрыт); приёмка §5.2.
- Горячие клавиши — Blender-подобные (Е5 закрыт); приёмка §5.2, ui-32n.
- FBX — свой читатель на Dart (Д7 изменён): fmt-24/25 в фазе 2 отдельной дорожкой после rel-16 (fmt-25 из фазы 3 — сноска ⁵), fmt-26 снят (сноска ⁷), пакет `flutter3d_fbx` — fmt-29d; §6 говорит, что это не правка движка; §7 № 12/28.
- Ткань — отдельный солвер `flutter3d_cloth` в фазе 4 (В3/И1 закрыты); §7 № 5.
- Проверка экспорта во внешнем движке — headless Godot в CI (qa-19n) плюс ручной чек-лист Unity/Blender перед релизом (К2 закрыт).

Первый прогон внесения этих решений упал на лимите после 57 правок (§1–§5
и таблицы §2 были готовы); §6, §7, §8, §10, хвосты прежнего имени пакета и
проработка doc/model-editor.md доделаны вторым прогоном в тот же день.

Счётчики после решений: 317 + 3 + 9 + 5 пунктов (`-d`: doc-31d, ui-33d,
ui-34d, rel-19d, fmt-29d), 37 расхождений (№ 34 и № 36 закрыты), 63 открытых
вопроса из 87, 33 пакета к концу фазы 0, фаза 1 — ≈ 198 недель одного
человека или ≈ 172 с агентами.

Сверка после второго прогона (тот же день): пятнадцать хвостов, где текст
ещё держал прежние развилки; каждый проверен по файлу до правки. Одна строка
на находку.

- Счёт фазы 1 пересчитан по таблицам §2 теми же правилами §4.3: 73 S, а не 72 — итого 120 пунктов, ≈ 198 недель (≈ 202 с условными), с агентами ≈ 172; §1 п. 2, §4.3 и счётчики здесь поправлены.
- Кто закрыл Г4: §1 п. 8 приведён к §8 (В1, Ж2 и Г4 — по критике, ещё 21 — решениями владельца); в §5.2 Г4 вынесен из «решениями владельца» в «по критике, подтверждён владельцем»; счётчик ревизии по критике — 84 открытых, не 85.
- Риск 12 больше не говорит «веб как просмотр допустим планом дизайна»: веб равноправен (Е1), при заморозке дольше 1 с — ui-34d в фазе 1.
- Риск 5: headless Godot в CI (qa-19n) отделён от ручного чек-листа Unity/Blender, как записано в К2.
- rel-05: место в поезде считается до набора, в котором выходит rel-06 (после rel-16), а не до 27 декабря (В8); пакетов пять, с geometry/formats.
- Г1 больше не держит расширение файла проекта открытым: `.f3dproj` закрыт Г2, в Г1 остались магия и место автосохранения; doc-09 и §5.2 «Решения до старта» согласованы.
- А4 переформулирован: порог выбирает бюджет веб-профиля (1 млн или ≤300k, p0-02), а не статус платформы — равноправие веба от порога не зависит (Е1).
- §2.11: в списке свободных имён на pub.dev вместо снятых `flutter3d_model`/`flutter3d_asset_core` — принятые `flutter3d_formats`, `flutter3d_fbx`, `flutter3d_cloth` (все пять отвечают 404 на `pub.dev/api/packages`, проверено 2026-09-09).
- А2 ссылался на «строку §7 проработки для iPad», которой нет: замер iPad живёт в p0-03 и в таблице фазы 0 doc §6.
- rel-11: подпись и нотаризация не в фазе 1, релиз открывается «правый клик → Open» (Е8); приёмка говорит то же.
- Проработка doc §6, фаза 0: строка 0.5 и абзац после таблицы не оставляют вебу выход в «просмотр» — непройденный порог становится пунктом фазы 1 (§7).
- Проработка doc §6, конец фазы 1: «работа для второго человека» заменена на дорожки для агентов при одном исполнителе (решение 15, план §4.2–4.3).
- Проработка doc §6: 1.9 (писатели и `StlLoader`) стоит в `formats` и зависит от doc-01, 0.4 называет пять новых пакетов, заголовок §5.4 — «Что добавить в движок и словарь».
- Проработка doc §2, экран 08: «динамическая плотность» заменена мультиразрешением с кнопкой «Подразбить» (Б9).
- Проработка doc §1 и §4: у §4.1 и §4.2 появились абзацы «Решение принято 2026-09-09» по образцу §4.3, §1 говорит «все три решены», а не «с рекомендацией».

### 2026-09-09 — что решила фаза 0

Замеры сняты, числа и способ их получения — в проработке `doc/model-editor.md`
§6. Ниже только то, что они изменили в этом плане; строки таблиц §2 при
следующей ревизии приводятся к этому.

- **p0-05 отменяет чанки.** Copy-on-write по чанкам проходит только кластерную
  правку (1–2 % копии) и проваливает рассеянную (92–100 %); журнал прежних
  значений стоит 2 % в обоих. `mesh-10` — плоские `Float32List` плюс журнал
  `(индексы, прежние значения)`, а не `PersistentFloat32Vector`; `mesh-02`
  закрыт этим замером. Приёмка `doc-31d` про «`identical` нетронутых чанков»
  переписывается на журнал: у него нет версий-значений, старое состояние
  существует через откат.
- **p0-06 выносит `view-14` из фазы 1 в фазу 4.** `DeviceMesh.upload` целого
  меша в кадр стоит 1,24 мс на 200 тыс. треугольников и 5,39 мс на миллионе —
  порог был 16,6. Частичная перезапись буфера (`overwriteGeometry`, четыре
  бэкенда, конформанс-проверка `qa-11`) не нужна для интерактивности фазы 1.
- **p0-10 оставляет пикинг на CPU.** Луч через `TriangleBvh` — 2,2–3,8 мкс
  против 1,2–23 мс перебором; build 200 тыс. — 61 мс. Ни id-прохода граней, ни
  поиска по окрестности half-edge в фазе 2 не потребуется. Реализация уже
  лежит в `flutter3d_geometry` (`view-09` получил её из p0-10, как и
  планировалось), с тестом против перебора.
- **p0-11 подтверждает API на значениях до 200 тыс. треугольников** (весь путь
  правка → пересборка → загрузка — 1,8 мс, ноль медленных кадров) и включает
  `toMeshData(into:)` из `mesh-14` для миллиона (12 % кадров опаздывают).
- **p0-07 разрешает обе стратегии**: изолят на native не стоит ничего
  измеримого, нарезка на 32 порции даёт худший кусок 2,1 мс. Операции пишутся
  пошаговыми с первого дня; `ui-34d` остаётся условным.
- **p0-02 переводит веб фазы 1 на dart2js.** Под `--wasm` приложение не
  стартует, тот же код в JS работает — это записанное исключение
  ARCHITECTURE §1, предусмотренное порогом. Причина отказа wasm заводится
  отдельным пунктом фазы 1; кадровые числа в браузере снимаются
  `profile_web.py` и в этом плане пока отсутствуют.
- **p0-13n: контейнер macOS годится полностью** — и прямая запись, и
  «временный файл + rename». Автосохранение (`ui-18`) пишет туда. Запись в
  файл, выбранный в панели, остаётся ручной проверкой в одну минуту.
- **anim-31: FK — 17,5 мкс на позу из 64 костей**, снято тестом, а не
  AOT-бенчем: `Skeleton` тянет `Scene` → `flutter3d_hardware` → Flutter SDK.
  Сравнимым с §14 `ARCHITECTURE.md` это станет только после `anim-02`.
- **Не снято и остаётся за фазой 0**: p0-03 (Galaxy A55 и iPad — нужны
  устройства), кадровые числа в браузере, ручная запись через панель macOS и
  `syn-02` (два макета экранов — работа дизайна).

