# Меньше пакетов — план слияний

Свод от 2026-09-13. Основание — вопрос владельца о сорока пяти пакетах как
избыточном абстрагировании и разбор каждого по pubspec, графу зависимостей,
ARCHITECTURE.md §3 и ответам pub.dev в тот же день, на ветке `modeler`.

Обозначения — как в [tooling-plan.md](tooling-plan.md): **р.** — размер для
одного человека (S — до дня, M — два–три дня); **pub** — пакет опубликован на
pub.dev и слияние требует bump и записи в CHANGELOG обоих участников.
Строки считаны по `lib/`, без тестов.

## 1. Что является границей пакета, а что нет

В этом репозитории пакет оправдан, если его отделяет одна из шести вещей:

1. **Flutter SDK.** Сервер, MCP-сервер, CLI и build hook не могут импортировать
   Flutter. Граница проверяется правилом `the simulation names no Flutter` по
   списку `flatDartPackages` в `tool/structure/repository.dart`.
2. **Нативный код или плагин.** Папки платформ, `flutter_gpu`, `flutter_soloud`,
   `flutter_webrtc`. Влить плагин в не-плагин нельзя, не сделав плагином его.
3. **Сторонняя зависимость, которую потребитель не должен наследовать.**
   `dart_mcp`, `flutter_bloc`, `flutter_test`, `web`.
4. **Вес ассетов.** 4,7 МБ образцов Khronos, GLSL-исходники, шейдерный бандл.
5. **Правило жанров.** `no package names a genre` и `a genre package reaches no
   other genre` — оба в `tool/structure.dart`.
6. **Независимая публикация.** 27 пакетов на pub.dev, 18 нет. Неопубликованные
   сливаются без последствий для чужих `pubspec.yaml`.

Границей **не** является: «написан после того, как набор 0.6.0 был решён»
(CHANGELOG `flutter3d_cloth`, `flutter3d_rig`), «удобно импортировать одной
строкой» (`flutter3d_app`), «на будущее» (`flutter3d_fbx`) и «пока никто не
использует» (`flutter3d_render_job`, `flutter3d_stereo`).

## 2. Итог разбора

Из 45 пакетов 38 держатся на одной из причин выше и остаются.
Семь держатся на истории, и их можно свернуть в шесть слияний (одно из
семи — спорное, §4). Результат: **45 → 39**, при спорном — 38.

Седьмая причина, добавленная владельцем 2026-09-13 при чтении первого
варианта: **узкая предметная область**. `flutter3d_lab` (маятник `edu-04`)
строится на `sim`, но образовательная симуляция — это вертикаль, а не часть
движка, так же как жанровый пакет — не часть `flutter3d_game`. Она остаётся
отдельным пакетом по тому же основанию, что и четыре жанра.

Полная таблица по всем пакетам с причиной выделения — в §6.

## 3. Слияния

Порядок — от бесплатных к дорогим: сначала неопубликованные, потом пары с
pub.dev. Каждое слияние — отдельный коммит, чтобы откатывалось по одному.

### 3.1 `flutter3d_cloth` → `flutter3d_physics` — р. S, pub (physics)

Ткань зависит только от `physics` и сталкивается с его же фигурами. Единственная
причина отдельного пакета, по его CHANGELOG, — время написания. Идёт в
`packages/flutter3d_physics/lib/src/cloth/`, экспорт через
`flutter3d_physics.dart`. Потребители: `flutter3d_model_core`, `apps/flutter3d_modeler`.

### 3.2 `flutter3d_rig` → `flutter3d_model_core` — р. S, не pub

Описание обещает «no Flutter, no renderer», а pubspec зависит от
`flutter3d_model_core`, то есть это операция моделлера, а не библиотека.
Единственный потребитель — `flutter3d_model_mcp`. Идёт в
`packages/flutter3d_model_core/lib/src/rig/`. Цикла нет: `model_core` от `rig` не
зависит.

### 3.3 `flutter3d_fbx` → `flutter3d_formats` — р. S, не pub

73 строки: `handles()` узнаёт файл, `decode()` отказывает с `FormatException`.
Рядом с glTF, OBJ, STL и USDZ в `formats` ему и место. Выделять обратно —
только если ридер `fmt-24`/`fmt-25` принесёт зависимость, которую `formats` не
должен носить. Строку `flutter3d_fbx` из `flatDartPackages` убрать: `formats` в
списке уже есть.

### 3.4 `flutter3d_render_job` — не слияние, а потребитель — р. S, не pub

`RenderSnapshotJob` не импортирует ни один пакет и ни одно приложение, и в
первом варианте плана стоял на удаление. Разбор 2026-09-13 показал, что он
от редактора не зависит: на входе `ModelProject`, который `model_core`
собирает и из любого документа `formats` через `fromModelDocument`, на выходе
PNG. Своего в нём три вещи, которых нет больше нигде: `sceneFromProject`
(второй конвертер документа в `Scene`; первый — `scene_sync.dart` в
моделлере), тайловый рендер со сшивкой и SSAA ×2, и выбор между
`Isolate.run` и покадровой уступкой на web.

Запускается только внутри Flutter-процесса: `flutter3d` называет Flutter, так
что `dart run` и `flutter3d_model_mcp` отпадают. Значит его дом — пакет над
чистым `model_core`, по той же схеме, что `particles` над `particles_core`.

**Решение владельца (2026-09-13): оставить пакетом и дать ему потребителя.**
Самое дешёвое — кнопка «Render» в `apps/flutter3d_modeler` и thumbnail в
списке проектов. Заодно свести два конвертера документа в сцену к одному:
`scene_sync.dart` моделлера и `sceneFromProject` строят одну и ту же сцену
по-разному, и второй из них уже лежит в пакете, который моделлер сможет
импортировать. В `flutter3d_testing` не сливать: `testing` получил бы
`model_core` и `mesh` в закрытие ради одного сценария.

### 3.5 `flutter3d_sim_mcp` + `flutter3d_render_mcp` → `flutter3d_sim_mcp` — р. M, не pub

Оба Flutter-пакеты, оба на `dart_mcp`, у обоих закрытие `bridge` + `cpu` +
`sim` + `flutter3d`; `sim_mcp` сверху тянет `game_shooter`. Один процесс с
двумя наборами инструментов: агент, который играет уровень вслепую (`ai-00`),
и агент, который спрашивает «почему кадр неверен» (`par-02`), — это один и тот
же агент в одной сессии, и сейчас ему нужны два stdio-сервера.

Имя остаётся `flutter3d_sim_mcp`; инструменты `render_mcp` идут отдельным
файлом `lib/src/render_tools.dart`, оба `bin/` сохраняются, пока есть
конфигурации агентов, которые их называют. Проверить `tool/skills` — там могут
лежать описания серверов по именам.

### 3.6 `flutter3d_backend` → `flutter3d_app` — р. S, pub (оба)

`app` — barrel из пяти `export`, `backend` — 188 строк условного импорта
«какой бэкенд открыть» и `openDevice`. Вместе это один пакет «сборка
приложения». `app` уже re-экспортирует `backend`, поэтому семь приложений,
которые импортируют `flutter3d_app`, не заметят ничего. Прямой импорт
`flutter3d_backend` остался только в `apps/flutter3d_demo_strategy/pubspec.yaml`
— убрать строку.

Правило `the engine names no backend` читает только `packages/flutter3d`, так
что `app`, назвавший четыре бэкенда, его не нарушает.

### 3.7 `flutter3d_session` → `flutter3d_screens` — р. M, pub (оба)

`session` зависит от `screens` (берёт `RenderSettings`), значит закрытие
зависимостей любого потребителя от слияния не меняется — включая
`flutter3d_bridge`, которому нужен `RunSession`. Имя оставить `flutter3d_screens`?
Нет: слитый пакет — это «приложение вокруг игры»: surface, прогон и экраны.
Предлагаемое имя — **`flutter3d_session`** (оно шире), `screens` уходит в
`lib/src/screens/`.

Доклад в `flutter3d_app/lib/flutter3d_app.dart` «пять пакетов, никто из
которых не знает о другом» и так неверен: `session` знает о `screens`.
После 3.6 и 3.7 barrel будет re-экспортировать три пакета: `session`,
`pad_input`, `pointer_lock`, плюс собственный код выбора бэкенда.

## 4. Спорное: `flutter3d_particles` → `flutter3d`

488 строк контрибьютора прохода. Если влить в движок, `flutter3d` начнёт
зависеть от `flutter3d_particles_core` (чистый Dart, безвредно), а пакет
`flutter3d_particles` на pub.dev останется с последней версией и пометкой
discontinued. Переименовать `particles_core` в `particles` нельзя, пока имя
занято. Выигрыш — один пакет; цена — discontinued-запись и переезд четырёх
потребителей (`bridge` и три демо). **Отложить**; вернуться, когда следующая
мажорная версия всё равно заставит трогать потребителей.

## 5. Что остаётся и почему это стоит записать

- **`flutter3d_stereo`** (914 строк, Android-плагин, v0.1.0) и
  **`flutter3d_net_webrtc`** (174 строки, `flutter_webrtc`) никто не
  импортирует. Слить некуда: нативный код. Вопрос не «куда», а «нужны ли»;
  решает владелец, план их не трогает.
- **`flutter3d_shaders`** (66 строк + GLSL) — три потребителя: `impeller`,
  `cpu`, `conformance`. В `hardware` не идёт, потому что «hardware names no
  graphics API», а GLSL — это API. Остаётся.
- **`flutter3d_build`** — `tool/init` (чистый Dart) импортирует его для
  конвертации на этапе сборки; в `flutter3d` его нельзя.
- **Четыре MCP-пакета** после 3.5 станут тремя: `editor_mcp` (Dart, `sim`),
  `model_mcp` (Dart, моделлер), `sim_mcp` (Flutter, игра + кадр). Сливать
  дальше нельзя: закрытия разные, и потребитель `editor_mcp` получил бы
  моделлер.

## 6. Что обновить при каждом слиянии

Список, потому что половина из этого проверяется сканом, а половина — нет.

1. `pubspec.yaml` корня: убрать пакет из `workspace:`.
2. `pubspec.yaml` потребителей: заменить зависимость, `flutter pub get`.
3. Импорты `package:<старое>/` → `package:<новое>/` (`rg -l` по `packages/`,
   `apps/`, `tool/`).
4. ARCHITECTURE.md: таблица §3.2, список **The order, used on the day**
   (правило `the publishing order names every package` падает, если пакет в
   дереве, но не в списке — и наоборот), число «Thirty-five packages» в §3
   (сейчас в дереве 45, документ уже врёт; после плана — 39).
5. README.md: строка «holds thirty-five» (строка 14).
6. `tool/structure/repository.dart`: `flatDartPackages` (3.3),
   `genrePackages` не трогается.
7. Число тестов в README, ARCHITECTURE.md и на сайте — `tool/structure.dart`
   считает «says N tests»; слияние тестов число не меняет, новый тест на
   кнопку «Render» (3.4) — меняет.
8. CHANGELOG.md принимающего пакета: жирный тезис «принял `X`, потому что…»;
   CHANGELOG.md уходящего — последняя запись «слит в `Y`».
9. Для pub-пакетов (3.1, 3.6, 3.7): версия `0.7.0` у принимающего, у
   уходящего — `flutter pub publish` последней версии с `discontinued`
   через pub.dev admin, поле `replaced_by`.
10. `doc/plan-status.json` — если слитый пакет назван в статусе пункта
    (`pro-rn-02`, `fmt-29d`, `ai-00`, `par-02`), обновить причину.
11. `tool/skills` — описания MCP-серверов по именам (3.5).
12. CI `.github/workflows/ci.yml` — пакеты в явных шагах: `flutter3d_mesh`
    (bench), `flutter3d_impeller` (bundle). Ни один из сливаемых там не
    назван; проверить после 3.5.

## 7. Порядок и оценка

| Шаг | Слияние | р. | pub | Блокирует |
|---|---|---|---|---|
| 1 | 3.3 `fbx` → `formats` | S | нет | — |
| 2 | 3.2 `rig` → `model_core` | S | нет | — |
| 3 | 3.4 `render_job`: кнопка «Render» в моделлере | S | нет | — |
| 4 | 3.5 `render_mcp` → `sim_mcp` | M | нет | — |
| 5 | 3.1 `cloth` → `physics` | S | да | bump physics |
| 6 | 3.6 `backend` → `app` | S | да | bump app |
| 7 | 3.7 `screens` → `session` | M | да | bump session, bridge |

Шаги 1–4 — один-два дня без публикаций. Шаги 5–7 — вместе с выпуском 0.7.0,
потому что три discontinued-пакета за один релиз объяснить проще, чем по
одному за три.

## 8. Полная таблица

| Пакет | Строк | pub | Держится на | Вердикт |
|---|---|---|---|---|
| `flutter3d` | 23 894 | да | ядро | остаётся |
| `flutter3d_hardware` | 4 422 | да | HAL, §1.5 «engine names no backend» | остаётся |
| `flutter3d_impeller` | 2 753 | да | §1.2 `flutter_gpu`, hook, бандл | остаётся |
| `flutter3d_webgl` | 15 131 | да | §1.3 `web`, условный импорт | остаётся |
| `flutter3d_webgpu` | 20 293 | да | бэкенд, WGSL | остаётся |
| `flutter3d_cpu` | 6 443 | да | софтверный бэкенд, 19 зависимых | остаётся |
| `flutter3d_backend` | 188 | да | история | → `app` (3.6) |
| `flutter3d_app` | 35 | да | barrel | принимает `backend` |
| `flutter3d_session` | 1 737 | да | история | принимает `screens` (3.7) |
| `flutter3d_screens` | 2 664 | да | §1.3 `flutter_bloc`, но `session` уже зависит | → `session` (3.7) |
| `flutter3d_conformance` | 4 598 | да | §1.3 `flutter_test` | остаётся |
| `flutter3d_testing` | 328 | да | §1.3 `flutter_test` | остаётся |
| `flutter3d_shaders` | 66 + GLSL | да | §1.4, три потребителя | остаётся |
| `flutter3d_samples` | 33 + 4,7 МБ | да | §1.4 | остаётся |
| `flutter3d_particles` | 488 | да | Flutter-половина | спорно (§4), отложено |
| `flutter3d_particles_core` | 1 826 | нет | §1.1, нужен `model_core` | остаётся |
| `flutter3d_physics` | 5 099 | да | §1.1, 7 зависимых | принимает `cloth` (3.1) |
| `flutter3d_cloth` | 579 | нет | история | → `physics` (3.1) |
| `flutter3d_rig` | 1 722 | нет | история | → `model_core` (3.2) |
| `flutter3d_fbx` | 73 | нет | «на будущее» | → `formats` (3.3) |
| `flutter3d_lab` | 249 | нет | §2, вертикаль `edu-04` | остаётся |
| `flutter3d_render_job` | 535 | нет | Flutter-половина над `model_core`; потребителя пока нет | остаётся, подключить (3.4) |
| `flutter3d_stereo` | 914 | нет | §1.2 Android-плагин; нет потребителей | остаётся, вопрос §5 |
| `flutter3d_sim` | 15 937 | да | §1.1 | остаётся |
| `flutter3d_game` | 1 893 | да | Flutter-половина игры, 15 зависимых | остаётся |
| `flutter3d_game_shooter` | 4 968 | да | §1.5 | остаётся |
| `flutter3d_game_platformer` | 4 415 | да | §1.5 | остаётся |
| `flutter3d_game_racing` | 4 805 | да | §1.5 | остаётся |
| `flutter3d_game_strategy` | 4 133 | нет | §1.5 | остаётся |
| `flutter3d_bridge` | 2 377 | да | единственный пакет по обе стороны | остаётся |
| `flutter3d_audio` | 1 469 | да | §1.2 `flutter_soloud` | остаётся |
| `flutter3d_net` | 608 | нет | §1.1 | остаётся |
| `flutter3d_net_webrtc` | 174 | нет | §1.2 `flutter_webrtc`; нет потребителей | остаётся, вопрос §5 |
| `flutter3d_editor_core` | 2 796 | да | §1.1, `tool/init` | остаётся |
| `flutter3d_editor_mcp` | 720 | да | §1.3 `dart_mcp` | остаётся |
| `flutter3d_model_core` | 21 265 | нет | §1.1 | принимает `rig` |
| `flutter3d_model_mcp` | 4 277 | нет | §1.3 `dart_mcp`; modeler поднимает in-process | остаётся |
| `flutter3d_mesh` | 15 875 | нет | `cpu` и bench берут без `model_core` | остаётся |
| `flutter3d_geometry` | 3 141 | нет | `mesh` берёт без декодеров | остаётся |
| `flutter3d_formats` | 14 046 | нет | §1.1, `tool/convert_asset` | принимает `fbx` |
| `flutter3d_build` | 1 026 | нет | §1.1, `tool/init` | остаётся |
| `flutter3d_sim_mcp` | 927 | нет | §1.3 `dart_mcp` | принимает `render_mcp` (3.5) |
| `flutter3d_render_mcp` | 589 | нет | то же закрытие, что у `sim_mcp` | → `sim_mcp` (3.5) |
| `pad_input` | 1 407 | да | §1.2, самостоятельное имя | остаётся |
| `pointer_lock` | 499 | да | §1.2 macOS-код | остаётся |
