# flutter3d 1.0: путь внедрения и опыт разработчика (product review, 2026-10-09)

Ветка `1.0.0`, рабочее дерево. Вопрос обзора: что обещает «целевое состояние» 1.0 первому пользователю с pub.dev, и доставляет ли это план rc.1. Источники: `tasks/1.0-readiness-review.md` §3 и §6, `tasks/1.0-rc1-plan.md`, `tasks/1.0-publish.md`, `tasks/1.0-stability.md`, `site/content/reference/migrating-to-1.0.md`, текущая поверхность (quickstart, first-project, packages.md, README, SUPPORT, `flutter3d_build`), аудиты 02, 08 и 16. Пометки: **[есть]** в дереве сейчас, **[rc.1]** / **[rc.2]** по плану, **[нет в плане]**, **[не проверено]** там, где я не запускал код.

Сводка в одном абзаце. План действительно переносит «первый час» в rc.1 (D54, D58, 2F, 5.4, 5.6), и это правильный ход. Но «две команды и сорок строк» в rc.1 получаются только для кубика из шаблона: витрина товара с GLB из сети, орбитой, тапом и AR-кнопкой (то, «за чем Flutter-разработчик приходит первым», review:794) остаётся `ModelViewer3D` в волне 4.5, то есть rc.2; модель из `assets_src/` требует хука, `flutter3d_build:init`, строк `assets:` и `flutter clean`, ни одно из которых план не убирает, только учит `doctor` их проверять. Кулинарная книга на 20 рецептов втиснута в один пункт 5.4 вместе с переписыванием ~20 документов и правкой `doctor`, размером L на одного агента, и половина рецептов зависит от API, которого в rc.1 ещё нет. Обещание версий (строгий semver, LTS 18 месяцев, «патч не меняет кадр») для 57 пакетов, одного мейнтейнера и бэкенда на `flutter_gpu: sdk: flutter` держится на инструментах, которые есть (снимки API, правила, `dart_apitool`), и на проверках, которых нет нигде, кроме одного Mac (голдены Impeller/WebGPU руками, ночной прогон «пока машина включена»). Миграция с 0.8 инструментально лучше, чем у большинства Dart-пакетов, но 721 из 1538 записей «руками», а 0.6/0.7 не имеют пути вовсе. Редактор в rc.1 получает dmg/zip/tar.gz и веб-сборку по URL, но Windows-сборка выходит раньше, чем кто-либо её запускал, Linux рисует через CPU, а нотаризация упирается в сертификат одного человека.

---

## 1. Поверхность установки

### 1.1. Сколько пакетов ставит пользователь

| Сценарий | Сегодня [есть] | rc.1 по плану | rc.2 |
|---|---|---|---|
| (a) витрина модели | `flutter3d` + `flutter3d_app` (+ `vector_math`) — `site/content/quickstart.md:119-122`, `packages/flutter3d_build/lib/src/project_template.dart:36-38`. Модель из `assets_src/` добавляет `flutter3d_build` в `dev_dependencies` и хук (`site/content/reference/asset-pipeline.md:18-28`). Модель из сети: ни одного пакета не хватает, нужны четыре вызова и ручной `dispose` (`tasks/1.0-audits/16-reader-beginner.md:31`) | то же; `OrbitCamera3D`, `Mesh3D.onTap`, `Light3D.sun()/lamp()` в 2F (`tasks/1.0-rc1-plan.md:122`) | `ModelViewer3D` с сетью, постером, хотспотами, AR (D47, `1.0-rc1-plan.md:225`, review:1524 «4.5») |
| (b) казуальная игра | шаблон редактора: `flutter3d`, `flutter3d_game`, `flutter3d_sim`, `flutter3d_game_ui`, `flutter3d_app`, `flutter3d_audio` = 6 (`packages/flutter3d_editor_core/lib/src/scaffold_templates.dart:40-53`); пример `flutter3d_game/example` — 8 с `plugin_api` и `cpu` (`packages/flutter3d_game/example/pubspec.yaml:17-52`). Flame-путь: `flame_flutter3d` + `flame` (+ `_audio`), в quickstart не упомянут (16:49) | `create project --kind arcade` (5.6, `1.0-rc1-plan.md:256`) | демо arcade само переезжает на `Flutter3dView` только в 4G (`1.0-rc1-plan.md:204`, rc.2) |
| (c) лаборатория | `flutter3d_education` + `flutter3d_app` + `flutter3d_sim` (+ физика); `apps/flutter3d_lab_pendulum` — 342 строки императивного кода (16:95) | пример «laboratory-shaped» в 4K, перенесён в rc.1 (`1.0-rc1-plan.md:208`); `TimeSource.manual` (3G), `SimulationProfile.accurate` (3C) | документ `f3d.experiment` — 4E в шаге 4.1 (rc.1 по таблице, `1.0-rc1-plan.md:192`), но лаборатории на нём — 4J в 4.2 (rc.2, `:207`) |

Минимум для (a) не меняется между rc.1 и rc.2: два пакета плюс `vector_math`, потому что `Vector3` в сигнатурах виджетов (`project_template.dart:40`).

### 1.2. Версии и `flutter pub add`

- Ограничение `^1.0.0-rc.1`, потому что `^1.0.0` не допускает пререлиз (`tasks/1.0-publish.md:7-10`). pub.dev держит 0.8.x по умолчанию (`:14-15`), поэтому `flutter pub add flutter3d` без явного ограничения приведёт 0.8.5, а не кандидата **[не проверено: поведение `pub add` с пререлизами, но так работает резолвер по умолчанию]**. Правильная форма — `flutter pub add 'flutter3d:^1.0.0-rc.1' 'flutter3d_app:^1.0.0-rc.1'`; ни quickstart, ни README её не пишут, оба дают только YAML (`quickstart.md:104-123`, `README.md:21-24`).
- Приёмка волны 5 требует, чтобы 52 пакета резолвились «с `^1.0.0-rc.1` в свежем `flutter create`» (`1.0-rc1-plan.md:261-263`) — это проверка резолва, не первого часа.
- Пакеты со своими линиями: `pad_input`, `pointer_lock` 0.5.0, `flame_multiplayer` 0.3.0, `flame_multiplayer_dashwire` 0.2.0 (02:5). D10/5.5 переводят два последних на `1.0.0-rc.1` (`1.0-rc1-plan.md:255`), иначе `pub publish` предупреждает о зависимости от пререлиза (08:67). README.md:31-33 и SUPPORT.md:162 называют старые числа (02:9-11).

### 1.3. Каждый ручной шаг целевого состояния

| Шаг | Где описан | Убирает ли план | Документирует ли план |
|---|---|---|---|
| `flutter create` или `flutter3d create project`, потом `flutter create --platforms=macos .` поверх (две команды создания) | `first-project.md:42-49`, `project_template.dart:148-152` | нет | 5.4 quickstart «`flutter create`, two dependencies» (`1.0-rc1-plan.md:254`) |
| `FLTEnableFlutterGPU` + `FLTEnableImpeller` в `Info.plist`; `io.flutter.embedding.android.EnableFlutterGPU` в манифесте | `quickstart.md:83`, `first-project.md:52`, `pitfalls.md:15-16` | нет и не может: per-app настройка Flutter | да: quickstart 5.4 «the two platform keys»; `doctor` проверяет (5.4); баннер вместо тихого CPU (2F, `:122`) |
| Тихий fallback на `flutter3d_cpu` с одной строкой в консоли | `first-project.md:53`; строка `Impeller would not start` в `packages/flutter3d_app/lib/src/backend_native.dart` | да, 2F: баннер `DidNotStart`-стиля (виджет есть: `packages/flutter3d_app/lib/src/surface/did_not_start.dart:18`) | — |
| `dart run flutter3d_build:init` → `hook/build.dart`, `dev_dependencies`, `assets:` по подкаталогам, `.gitignore` | `asset-pipeline.md:18-30`; `flutter3d create project` делает это сам (`project_template.dart:142-145` через `planInit`), `flutter create` — нет | нет | `doctor` проверяет хук и строки `assets:` (5.4) |
| `flutter clean` после добавления `flutter3d_build` (кэш «нет хуков») | `asset-pipeline.md:37, :264` | нет | нигде, кроме asset-pipeline; в quickstart и README `flutter3d_app` ни слова (16:21) **[нет в плане]** |
| Строка `assets:` на каждый подкаталог (`listSync` без `recursive`) | `asset-pipeline.md:33` | нет | `doctor` (5.4) |
| Шейдерный бандл после `flutter upgrade` | hosted-архив несёт бандл, собранный SDK публикатора (`packages/flutter3d_impeller/.pubignore`, `shader_bundle_build.dart:60-66` «keeping the bundle already at … inside the pub cache»); ответ пользователю — «upgrade `flutter3d_impeller`» (`site/content/core/tutorial.md:82`) | частично: D15 (4C) переносит сборку бандла в хук проекта (`1.0-rc1-plan.md:190`); если хук компилирует `impellerc` пользователя, привязка к SDK исчезает **[не проверено: план не говорит, где компилируется проектный бандл]** | SUPPORT:214-222 говорит только про патч `flutter3d_impeller` |
| `impellerc` (`flutter precache`), `glslangValidator`, `naga` для материалов | `doctor.dart:164-201` | нет | уже есть в `doctor` |
| Ключи в `Scene3D` как условие сохранения узла | `packages/flutter3d_app/README.md:17,45-47`; 16:45 | нет | **[нет в плане]** |
| Hot reload: `onCreated` не перестраивается | 16:41 | нет | **[нет в плане]** |

### 1.4. «Две команды и сорок строк» — rc.1 или rc.2?

Целевой текст: «the first hour in two commands and forty lines» (`1.0-readiness-review.md:879-880`), у flutter_scene «two commands and 45 lines» (`:847`). В rc.1 (5.4 + 4K + 2F) честный счёт для витрины с собственной GLB:

```
flutter3d create project shop          # 1
cd shop && flutter create --platforms=macos .   # 2
<править Info.plist>                   # 3, руками
flutter pub get && flutter clean       # 4 (clean — asset-pipeline.md:37)
flutter run -d macos                   # 5
```

Строк — около 30 в шаблоне (`project_template.dart:56-85`), это держится. Но модель с CDN, орбита жестами с ограничениями, хотспот и AR — rc.2 (приёмка 4.5: «a networked GLB in `ModelViewer3D` with orbit, a hotspot and an AR button in under twenty lines», `1.0-rc1-plan.md:236-238`). В rc.1 орбита есть (`OrbitCamera3D`, 2F), сети нет. Вывод: «две команды» в rc.1 — для сферы из шаблона; для сценария (a) из §1.1 — rc.2. План это не скрывает, но README/quickstart 5.4 должны прямо сказать «витрина — в rc.2».

Отдельно: 4K обещает примеры «twin-shaped» и «laboratory-shaped» (`:208`), а не viewer-shaped; шаблон `--kind viewer` в 5.6 будет написан на API без `ModelViewer3D`, то есть либо на `Model3D(source: 'assets_src/…')` с хуком, либо его придётся переписать в rc.2.

---

## 2. План документации 5.4 против десяти просьб новичка

Десять просьб — §3 аудита 16 (пункты 23–32; 33–34 там же, итого двенадцать). Сопоставление:

| # | Просьба (16:§3) | Пункт плана | Волна |
|---|---|---|---|
| 23 | quickstart для pub-пользователя в начале, checkout в конце | 5.4 «rewritten from the pub user's side first … and the checkout last» (`1.0-rc1-plan.md:254`) | rc.1 |
| 24 | поднять `ModelViewer3D` | D47 остаётся в 4.5 (`:225`) | **rc.2** |
| 25 | `Mesh3D.onTap` / `Model3D.onTap(part)` | 2F (`:122`) | rc.1 |
| 26 | `OrbitCamera3D` | 2F | rc.1 |
| 27 | `doctor` проверяет plist/манифест, хук, `assets:` | 5.4 (`:254`), D19 (`:190`) | rc.1 |
| 28 | баннер вместо тихого fallback | 2F | rc.1 |
| 29 | один тип материала в quickstart и README | 5.4 | rc.1 |
| 30 | `Light3D.sun()`/`lamp()` | 2F | rc.1 |
| 31 | cookbook, 20 рецептов ≤40 строк | 5.4 | rc.1 |
| 32 | playground «вставил код, увидел картинку» | 5.6 — но «renders a level or prefab document», не Dart-код (`:256`) | rc.1, иной смысл |
| 33 | `create --kind viewer|arcade` | 5.6 | rc.1 |
| 34 | счётчики держит правило | 5.4 «rule-held counts» | rc.1 |

Остальные замечания аудита 16, у которых **нет пункта плана**: hot reload для `onCreated` (16:41); ключи как условие корректности (16:45); `Material3D` как родитель меша против свойства (16:43); анимация свойств узла (16:35); `flutter clean` и хук в README `flutter3d_app` (16:21; `doctor` проверит, но README не назван); «что делать pub-пользователю после `flutter upgrade`» (16:19); Flame-путь в quickstart (16:49; есть только шаблон `arcade`); сообщество и где искать ответы (16:91; review:849-850 «community size, which no plan addresses»). Туториал `core/tutorial.md` (16:51, сейчас на `flutter3d_impeller`/`GpuRenderBackend`/`Material(Vector4)`, `tutorial.md:33,118,227`) — в 5.4 есть («`core/tutorial.md` on the 1.0 API»). Ссылка на глоссарий из quickstart — в 5.4 есть (сейчас в quickstart слова «glossary» нет).

**Размер 5.4.** Один пункт, один агент, размер L («a week»). Содержимое: quickstart (переписать); tutorial (переписать на новый API); один тип материала во всех README (57 README); глоссарий; **20 рецептов**; **код** `doctor` (три новые проверки с тестами, CONTRIBUTING требует красный тест сперва, `1.0-rc1-plan.md:70-71`); счётчики через правила в README, SUPPORT, index, packages.md, AGENTS; таблица README и packages.md (10 и 4 пропуска, 02:31); SECURITY, AGENTS, ROADMAP заново (ROADMAP просрочен по своим правилам, 02:46); comparison.md; LICENSES; `/showcase/learn/`; CONTRACTS с расширением правила и шестью правками; SUPPORT; три плана; ARCHITECTURE с четырьмя новыми типами. Это около двадцати документов плюс код плюс двадцать компилируемых примеров. Для сравнения, 5.6 (два шаблона и страница) — M. Нереалистично в L; cookbook стоит выделить в отдельный пункт с собственной приёмкой («каждый рецепт — файл в `examples/cookbook/`, собирается в CI»), иначе рецепты будут текстом без компиляции.

**Содержательный риск cookbook.** Три названных рецепта (`:254`): «a GLB with a buy button» — без `ModelViewer3D` это `Model3D` из `assets_src/` с хуком; «a runner at 60 fps on a phone» — Flame-мост, чьё демо переезжает на `Flutter3dView` в 4G (rc.2), плюс цифра «60 fps» должна подтверждаться pacing-отчётом 5.0; «a pendulum with a length slider» — `TimeSource.manual` (3G), `accurate` (3C) — есть к 5.4, а `f3d.experiment` (4E) без лабораторий на нём (4J, rc.2). Волна 5 «runs twice» (`:246`), так что cookbook rc.1 частично переписывается для rc.2 — это надо заложить.

---

## 3. Обещание версий

### 3.1. Что обещано

- Строгий semver с 1.0.0, ни одного `@experimental` (`tasks/1.0-stability.md:37-40, :57-58`; `SUPPORT.md:157-160`).
- Один номер на полку из ~53 пакетов; интерфейсные пакеты своими линиями (`SUPPORT.md:162-181`; `1.0-stability.md:41-45`).
- Фиксы: новейший минор — всё; предыдущий — крэши/данные/безопасность три месяца; **один минор в год LTS на 18 месяцев, «None is named yet»** (`SUPPORT.md:183-192`).
- Депрекация до следующего мажора и не менее 6 месяцев (`SUPPORT.md:194-197`); при этом D14 — «No `@Deprecated` in 1.0.0», правило «a major release deprecates nothing» (`1.0-readiness-review.md:1167-1169`). Это согласуется (депрекация в минорах, снятие в мажоре), но `migrating-to-1.0.md:89-90` пишет «`GameLoop` still works in 1.0 and is deprecated until 2.0», тогда как `GameLoop` в `flutter3d_sim/lib` отсутствует (аудит 02:38; `rg GameLoop packages/flutter3d_sim/lib` пусто). В `packages/*/lib` сейчас 8 `@Deprecated` (D12 их удаляет).
- «A patch does not change the frame» (`1.0-stability.md:100-104`).
- Снимки `api/<package>.api` (56 файлов), правила классификации и метка `**Breaking:` (`tool/structure/api.dart:222,972`), `dart_apitool` против pub перед публикацией (`1.0-publish.md:113-121`); MCP/VM-схемы в снимках (`1.0-stability.md:156-162`).

### 3.2. Что это стоит на один релиз (по текущим документам)

1. Снимки: `dart run api_snapshot` по 56 пакетам, `schema_snapshot`, `migration_seed --append`, `generate_migrations --check` (`CONTRIBUTING.md:154-157, :228-240`).
2. Корпус миграции: 21 приложение из тега через `git archive`, `migrate`, `analyze` (`1.0-publish.md:102-105`).
3. `tool/publish_check.sh` (переписывает pubspec'ы, 08:5), `tool/api_against_pub.sh` (скачивает 52 пакета через `dart-apitool`, `tool/api_against_pub.sh:102`).
4. Перезапись четырёх наборов голденов (96 сцен × 4) и тейпов **руками на Mac с GPU** (`SUPPORT.md:47-48`, WebGPU «by hand in Chrome», `:70-74`); с августа голдены перезаписаны 478 раз (`1.0-stability.md:32-33`); ночной Impeller-прогон на Mac Дмитрия «runs only while the machine is on» (`1.0-readiness-review.md:1192`).
5. Публикация слоями L0–L8 с ожиданием появления каждого слоя на pub.dev (`1.0-publish.md:128-146`): 52 интерактивных `flutter pub publish`, девять ожиданий.
6. Пометка discontinued руками в админке pub.dev (`:166-177`).

Это «день» для rc.1 (`1.0-publish.md:1` «the day's sheet») при условии, что ничего не падает. Для патча 1.0.1 остаётся открытым главный вопрос: **патч одного пакета — это 53 публикации или одна?** SUPPORT:162 «one number», но SUPPORT:218-219 «the repair is a patch of `flutter3d_impeller`, and no other package's API changes». Если патчится один пакет, «один номер» перестаёт быть правдой после первого патча (и структура правил `sibling carets` должна это допускать); если все 53, каждый фикс `flutter_gpu` — полдня публикаций. Документы не решают; продукт-обещание повисает.

### 3.3. Что реально увидит пользователь между 1.0 и 1.1

- `flutter_gpu` приходит как `sdk: flutter` (`packages/flutter3d_impeller/pubspec.yaml:37-39`), то есть каждый stable Flutter может сломать Impeller-бэкенд без участия автора. Обещание: «Supported is the Flutter stable CI runs and every stable release after it within the same Flutter major» (`SUPPORT.md:208-210`), ремонт — патч `flutter3d_impeller`, при необходимости с поднятием его Flutter-пола (`:218-222`). Для пользователя: после `flutter upgrade` до нового stable — пока патча нет, либо стейл-бандл (`ShaderBundleRefused.stale`, `1.0-stability.md:143-145`), либо падение `flutter_gpu` → **тихий (до 2F) или баннерный (после) откат на CPU**. После патча с поднятым полом — пользователь на старом Flutter патч не возьмёт. «Its breaks are repaired in patches … and our API does not change» (`1.0-stability.md:111-113`) — верно про API, но не про опыт: окно без работающего Impeller зависит от скорости одного человека.
- Бандл из hosted-архива собран SDK публикатора (`.pubignore`, `shader_bundle_build.dart:60-66`), поэтому «версия пакета ↔ версия Flutter» — скрытая матрица, которую SUPPORT не ведёт. D15 (хук выбирает стадии per project) может это снять, если компиляция пойдёт у пользователя; тогда `impellerc` становится обязательным у каждого пользователя (сейчас `doctor` помечает его «needed only to build shader bundles from a checkout», `doctor.dart:173`).
- Тейпы: «Patches never change the simulation; a minor that changes it bumps the version» (`1.0-stability.md:80-81`); минор с изменением симуляции делает сохранения-тейпы игроков «refused honestly» (`:83`). Для казуальной игры с сохранениями это означает: каждый минор движка — потенциальная потеря реплеев, хотя позы сохраняются.
- Голдены: «in a minor the picture may change … the old look comes back through a settings flag» (`:103-104`) — флаг на каждое визуальное изменение в каждом миноре; для одного мейнтейнера это растущее множество флагов без плана их снятия.

### 3.4. Оценка

Как **инструментарий** обещание выше среднего для pub.dev: снимки API с классификацией, миграционная таблица, `dart_apitool`, правила в CI. Как **продуктовое обещание** — не покрыто: LTS без названного релиза и без второго человека; «патч не меняет кадр» проверяется на одном Mac; `flutter_gpu` вне контроля; один номер против патча одного пакета не решён. Честнее было бы в SUPPORT: «LTS начинается с первого минора, у которого есть ночной прогон на хостед-раннере», и явно описать, что происходит у пользователя в день выхода нового Flutter stable.

---

## 4. Миграция с 0.8

**Что есть [есть].** `dart pub global activate flutter3d_build 1.0.0-rc.1` + `flutter3d_lints`, `migrate --dry-run`, семь шагов (`migrating-to-1.0.md:27-61`; `packages/flutter3d_build/bin/migrate.dart:1-38`). Одна таблица `0.8_to_1.0.yaml` (18 991 строка) порождает `fix_data.yaml` (40 файлов), правила lint-плагина и гайд. Переименования пакетов `flutter3d_editor_mcp/_mcp_kit → flutter3d_mcp`, `_lab/_lti → flutter3d_education` переписываются в импортах (`0.8_to_1.0.yaml:84-87`, `migrate/table.dart:191-192`). Пять имён помечаются discontinued после публикации (`1.0-publish.md:166-179`). Корпус из 21 приложения 0.8.5 мигрировал чисто 10-08 (`:102-105`).

**Что настораживает.**

1. **Доля ручной работы.** 1538 записей: 97 `migrate`, 455 `dart fix`, 265 «nothing to do», **721 by hand** (`migrating-to-1.0.md:127`) — 47 %. «About two hundred places» в README:125 и `migrating:8` противоречит 1538 записям таблицы; читатель не поймёт, сколько у него работы.
2. **Таблица не финальна.** «Every wave appends its own entries … Once wave 4 has landed» (`1.0-publish.md:93-95`). D36 (`StepSystems` уходит), D39 (`MaterialParameters`), D9 (34 параметра `Flutter3dView` в группы), D12 (восемь депрекаций удаляются), A9 (`LinearColor` везде) — всё это новые by-hand записи для 0.8-пользователя, которых в текущем гайде нет. Гайд сейчас ещё описывает `GameLoop` как «deprecated until 2.0» (`:89-90`), чего не будет (D14).
3. **Инструмент сам красный.** 34 падения в `flutter3d_build`, среди них `migrate_test` («`flame: ^1.38.2` пропал из pubspec»), `migrate_fixture_test`, `init_test` (аудит 08:21); 1E чинит в волне 1.
4. **Между rc.1 и rc.2 «a break is allowed»** (`1.0-rc1-plan.md:31`). CONTRIBUTING:245-247 говорит, что после тега разломы идут в новую таблицу с `from:` этого релиза, так что путь rc.1 → rc.2 инструментально возможен **[не проверено: план не называет таблицу `1.0.0-rc.1_to_rc.2`]**. Ранний пользователь rc.1 рискует второй миграцией.
5. **0.7.0 и 0.6.0 — без пути.** quickstart:101 «Skip 0.7.0», README:33-34 отсылает к `doc/boundary-0.7.0.md` для 0.6; `migrate --from 0.8` — «the default and the only source version for now» (`migrating:62`). Пользователь 0.6/0.7 поднимается до 0.8 руками по документу, потом инструментом. Таких пользователей, судя по «0.7.0 is prepared and not published» в ROADMAP (02:47), мало, но публичный текст «skip 0.7.0» в quickstart 1.0 — сигнал нестабильности для нового читателя, и 5.4 его убирает («quickstart's stale lines»).
6. **Lint-плагин** требует `analysis_server_plugin` и Dart ≥3.12 (`SUPPORT.md:201`); квик-фиксы применяются по одному (`migrating:83-85`), поэтому шаг 5 — отдельный бинарь `flutter3d_lints:migrate` (есть: `packages/flutter3d_lints/bin/migrate.dart`).

**Оценка.** Для проекта на 0.8.5: инструменты и отчёт с TODO — 4/5 по замыслу, 3/5 по состоянию (красные тесты, таблица не финальна, гайд расходится с кодом). Для 0.6/0.7: 1/5, ручной путь через два документа. Главный продуктовый риск — число «200 мест» против 1538 записей: ожидание и реальность разойдутся в первый же `--dry-run`.

---

## 5. Редактор и модельер

**Сегодня [есть].** Редактор запускается из checkout: `cd apps/flutter3d_editor && flutter run -d macos --dart-define=level=…` (`first-project.md:25-27`, причём workspace и бандл должны быть собраны, `:19`). CI собирает редактор для Linux и Windows (`.github/workflows/ci.yml:366-388`), но артефактов не публикует; релизного воркфлоу нет (`ls .github/workflows` → только `ci.yml`). Веб-сборка существует «with less» (`apps/flutter3d_editor/README.md:351-358`: документы живут в странице, проект скачивается zip), но `site/content/gallery.md:54` утверждает «The editor is desktop-only by design … it has no web build» — противоречие в публичных текстах. Модельер развёрнут на models.pleion.dev (`README.md:40-42`); CI билдит `flutter3d_modeler` и `flutter3d_showcase` (`ci.yml:318`).

**rc.1 (D55, 5.6').** `editor_release.yml`: нотаризованный macOS dmg, Windows zip, Linux tar.gz, `SHA256SUMS` по тегу; веб-редактор на сайте рядом с модельером; страница загрузки (`1.0-rc1-plan.md:257`; review:1448-1451). Владелец: «agent, Dmitrii (the certificate)».

**rc.2.** Редактор в контракте плагинов — D32. Здесь план противоречит сам себе: «Two candidates» относит D32 к rc.2 (`1.0-rc1-plan.md:27`, review:1419), а агент 4I с D32 стоит в таблице шага 4.1, который rc.1 (`:194`). Надо решить, иначе владелец `apps/flutter3d_editor` в 4.1 и в 4.5 неясен.

**Что пользователь реально получит в rc.1.**

- macOS: dmg, если сертификат Apple Developer и `notarytool` попадут в CI как секреты. Это единственный пункт плана, завязанный на документ одного человека; при истечении сертификата релиз редактора встаёт. Запасного пути (unsigned dmg с инструкцией `xattr`) план не называет.
- Windows: zip без подписи (SmartScreen предупредит), притом «Nobody has played a game on Windows yet» (`SUPPORT.md:60`); D56 требует одну сыгранную сессию игры, не редактора. Редактор на Windows выходит раньше, чем его кто-либо открыл.
- Linux: tar.gz, но Impeller на Linux не рисует до 4C (`gl_VertexID`, `SUPPORT.md:63-66`); до тех пор редактор рисует через CPU-растеризатор.
- Web: редактор по URL — то, чего «Scene cannot offer» (review:880). Это реальное преимущество, и оно почти бесплатно (сборка есть). Ограничение: уровень открывается «without its game's textures» (`apps/flutter3d_editor/README.md:355`).

**Вывод.** По URL — сильный ход, и его стоит поставить первым в 5.6'. Нативные сборки трёх платформ в rc.1 — обещание, которое проверено только на macOS; для Windows и Linux честнее помечать «Best effort» прямо на странице загрузки, как SUPPORT уже делает для игр.

---

## 6. Шаблоны и playground (5.6)

- `flutter3d create project <dir>` существует (`packages/flutter3d_build/bin/flutter3d.dart:_createProject`, `project_template.dart`) — один шаблон, без `--kind`, со сферой на `Scene3D` и хуком через `planInit`. Четыре жанровых шаблона — у редактора (`first-project.md:32`). `create plugin --kind` есть (`bin/create.dart`).
- `--kind viewer` и `--kind arcade` — 5.6, rc.1, M (`1.0-rc1-plan.md:256`). Замечания: `viewer` в rc.1 без `ModelViewer3D` (см. §1.4); `arcade` на Flame-мосту, чьё демо само на старом входе до 4G (rc.2), то есть шаблон опередит демо, с которого его обычно списывают.
- Playground — страницы нет (`ls site/content` → `arcade core education modeler platformer racing reference river shooter showcase strategy changelog first-project gallery index quickstart`). План: «renders a level or prefab document through the web backend as the user edits it» (`:256`). Это редактор документа в браузере, не «вставил `Scene3D`-код» (16:73); для Flutter-разработчика второе ценнее, первое — ещё один взгляд на веб-редактор из 5.6'. Риск дублирования: веб-редактор по URL и playground уровня — одна и та же вещь с двух страниц.
- Оба пункта rc.1, но стоят в волне 5 после 4.1, вместе с документами и релизом; при сдвиге 5.0 (железо) они первыми уйдут в rc.2.

---

## 7. Первый час целевого состояния, шаг за шагом

Сценарий: Flutter-разработчик, macOS, хочет показать GLB товара. Статусы: **есть** / **rc.1** / **rc.2** / **нет в плане**.

| # | Шаг | Что происходит | Статус | Источник |
|---|---|---|---|---|
| 1 | Открыть сайт, найти quickstart | quickstart начинается с checkout 57 пакетов | **rc.1** (5.4 переворачивает порядок) | `quickstart.md:26-34`; `1.0-rc1-plan.md:254` |
| 2 | `flutter3d doctor` | проверяет Dart/Flutter/impellerc/glslang/naga | есть; ключи, хук, `assets:` — **rc.1** | `doctor.dart:105-216`; план `:254` |
| 3 | `flutter3d create project shop` | pubspec с двумя пакетами, `main.dart` на `Scene3D`, хук и `assets:` через `planInit` | есть | `project_template.dart:34-38,142-145` |
| 4 | `flutter create --platforms=macos .` | платформенные папки | есть, ручной | `project_template.dart:150` |
| 5 | Два ключа в `Info.plist` | без них тихий CPU | есть (ручной); баннер — **rc.1** (2F); `doctor` — **rc.1** | `first-project.md:52-53`; `:122` |
| 6 | `flutter pub get` с `^1.0.0-rc.1` | 52 пакета резолвятся | **rc.1** (приёмка волны 5) | `1.0-rc1-plan.md:261-263` |
| 7 | `flutter run -d macos` | сфера; bundle из hosted-архива | есть | `.pubignore` impeller |
| 8 | Положить `robot.glb` в `assets_src/`, `Model3D(source: …)` | хук конвертирует; нужен `flutter clean`, если `flutter3d_build` добавлен после сборки | есть; `flutter clean` — **нет в плане** как шаг quickstart | `asset-pipeline.md:37,264` |
| 9 | Орбита жестами | `Camera3D` только `position/target` | **rc.1** `OrbitCamera3D` (2F) | `:122` |
| 10 | Тап по детали | `Raycaster` + переиспользуемый `HitResult` | **rc.1** `Mesh3D.onTap`/`Model3D.onTap(part)` (2F) | `:122`; 16:33 |
| 11 | Свет «просто светит» | `intensity: 92650.0` в шаблоне | **rc.1** `Light3D.sun()/lamp()` (2F) | `project_template.dart:66-72`; `:122` |
| 12 | GLB с CDN | четыре вызова, ручной `dispose` | **rc.2** `ModelViewer3D` (D47, 4.5) | `:225`; 16:31 |
| 13 | Постер, прогресс, хотспоты, AR-кнопка | нет | **rc.2** | `:225,236-238` |
| 14 | Понять `RenderMaterial` vs `Material3D` vs ещё три | пять «материалов» | **rc.1** (5.4 один тип + глоссарий) | `:254`; 16:13 |
| 15 | Рецепт «GLB с кнопкой купить» | нет cookbook | **rc.1** по плану, но на API без `ModelViewer3D` → **rc.2** по сути | `:254` |
| 16 | Попробовать в браузере без установки | демо и модельер есть; playground уровня — **rc.1** (5.6); «вставил код» — **нет в плане** | `:256`; 16:73 |
| 17 | Собрать на телефон, узнать размер APK | размеров нет | **rc.1** (5.0 п.5, условие тега) | `:49-50` |
| 18 | `flutter upgrade` через месяц | стейл-бандл или падение `flutter_gpu` → CPU | **нет в плане** как сценарий для pub-пользователя; механизм D15 — **rc.1** | `tutorial.md:82`; `SUPPORT.md:218-222` |
| 19 | Hot reload после правки `onCreated` | нужен hot restart | **нет в плане** | 16:41 |
| 20 | Спросить, где-нибудь | SO пуст; skills для агента | **нет в плане** | 16:91; review:849-850 |

Итог таблицы: из двадцати шагов восемь есть сегодня, восемь закрывает rc.1, два — только rc.2, и четыре не планируются (из них два — `flutter clean` и `flutter upgrade` — ровно те «вечер отладки» случаи, о которых аудит 16 предупреждал).

---

## 8. Рекомендации в порядке отдачи

1. **Разделить 5.4.** Cookbook — отдельный пункт с приёмкой «20 файлов в `examples/cookbook/`, собираются в `tool/ci.sh`»; `doctor` — в 2E или 4C (код, не документы); остальные документы — 5.4 как есть. Иначе L на одного агента превратится в «рецепты текстом».
2. **Сказать в README и quickstart rc.1 прямо:** «витрина с `ModelViewer3D` — rc.2; в rc.1 — `Model3D` из `assets_src/` с хуком». Иначе первый читатель rc.1 найдёт в плане то, чего нет в пакете, и придёт за flutter_scene (16:103).
3. **`flutter clean` и `flutter upgrade` — в quickstart** как два абзаца-предупреждения; это дешевле любого пункта плана и закрывает два «нет в плане».
4. **Решить «один номер против патча одного пакета»** до тега и записать в SUPPORT; то же для «патч не меняет кадр»: кто и где это проверяет, когда Mac выключен.
5. **Снять противоречие D32** (4I в 4.1 против «rc.2») и **gallery.md против README редактора** о веб-сборке.
6. **Страница загрузки редактора** со статусами по платформам из SUPPORT и с unsigned-fallback на случай сертификата.
7. **В гайд миграции** — честное «1538 записей, 721 руками» вместо «около двухсот мест», и убрать `GameLoop` «deprecated until 2.0».
8. **`flutter pub add` с явным ограничением** в quickstart одной строкой, потому что по умолчанию придёт 0.8.5.
