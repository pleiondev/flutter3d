# 05. Экосистема, go-to-market и эксплуатация релиза 1.0 (продуктовое ревью, 2026-10-09)

Ветка `1.0.0`, репозиторий `github.com/pleiondev/flutter3d`. Это не аудит кода: вопрос в том, что вокруг кода решает, «приземлится» ли релиз. Живые цифры сняты 2026-10-09 через `gh` и API pub.dev. Где оценка не проверена, так и написано.

## 0. Сводка цифр (живые, 2026-10-09)

| | flutter3d | flutter_scene (bdero) | Источник |
|---|---|---|---|
| GitHub stars / forks / watchers | **32 / 2 / 0** | 912 / 95 / 17 | `gh repo view`, GraphQL |
| Issues open / closed всего | 2 / 0 (всего 2) | 23 / 109 (всего 132) | GraphQL |
| Discussions | **выключены** (`hasDiscussionsEnabled: false`) | 0 | `gh repo view` |
| Открытых PR | 7 (6 рабочих веток + draft #82 «1.0.0») | 6 | `gh pr list` |
| GitHub Releases | **0** (`latestRelease: null`); git-тегов 17 (v0.4.0…v0.8.5) | editor 0.24.0 с dmg/zip/tar.gz | `gh release list`, `git tag` |
| Контрибьюторы | **1** (4399 коммитов Dmitrii + 1 алиас `dzolotov` + dependabot) | 24 | `git shortlog -sn --all` |
| pub.dev `flutter3d`: версия / лайки / загрузки 30 дн / баллы | 0.8.3+1 (2026-10-01) / **8 / 783 / 160/160** | 0.24.3 (2026-10-09) / 350 / 21 182 / 160/160 | `/api/packages/*/score` |
| pub.dev `flutter3d_core` | 0.8.3+1 / 0 лайков / 587 / **140/160** | — | то же |
| Репо создан | 2026-08-08 (2 месяца) | 2024-02-01 | `gh repo view` |
| Дата push | 2026-10-09 15:07Z | 2026-10-09 05:54Z | |

Соотношение по загрузкам ≈ 27×, по звёздам ≈ 28×, по контрибьюторам 24:1. Это те же цифры, что в `tasks/1.0-audits/18-flutter-scene.md:13` и `:61` («32★, 2 форка, 783 загрузки/мес») — за сутки ничего не изменилось, кроме того, что Scene выпустил 0.24.3.

---

## 1. Операция публикации

### Что есть

- **Листок дня**: `tasks/1.0-publish.md`. Порядок слоями, «ждать, пока слой появится на pub.dev, прежде чем следующий» (`:129–133`), 5 пакетов пометить discontinued вручную через admin-страницу pub.dev (`:166–179`), «ошибки: опубликованную версию можно только retract в 7 дней» (`:16`).
- **Dry-run**: `tool/publish_check.sh` (127 строк) делает `dart pub publish --dry-run` по каждому пакету, снимает/возвращает `publish_to: none` через `mktemp` + `trap`, allowlist предупреждений (`:74`), затем `tool/api_against_pub.sh` через `dart_apitool` (пропускается, если инструмент не установлен или pub.dev недоступен, `api_against_pub.sh:34–44`).
- **Структурное правило** «the publishing order names every package» выводит слои из pubspec'ов и падает при расхождении (`ARCHITECTURE.md:4683–4689`).
- **Publisher** `pleion.dev` подтверждён у всех опубликованных пакетов (`/api/packages/*/publisher`).

### Что может пойти не так в день релиза (с доказательствами)

1. **Два разных порядка публикации в двух документах.** `tasks/1.0-publish.md:134–146` — 9 слоёв L0–L8, `flutter3d_plugin_api` в L0, `flutter3d_foundation` и `flutter3d_matter` **отсутствуют вовсе**. `ARCHITECTURE.md:4659–4681` — 10 слоёв L0–L9, `foundation` в L0, `plugin_api` в L1, `matter` в L2, всего **56** пакетов. Правило структуры проверяет ARCHITECTURE, а «листок дня» — publish.md. Если Дмитрий пойдёт по листку, `flutter3d_foundation` (от которого зависят sim, particles, plugin_api) не будет опубликован до них → `pub publish` упадёт на резолве в L1–L2. Листок надо перегенерировать из правила, а не править руками.
2. **Число пакетов не сходится нигде.** README `:12` «fifty-two packages», `:18` «forty-eight … the 1.0.0 set»; README `:209` «fifty-seven packages»; SUPPORT.md `:162` «forty-nine packages of the shelf»; `site/content/index.md:31` «all 45 packages … Forty-two carry the release candidate»; `:93` «Forty-five packages in all»; `AGENTS.md:8` «36 packages and 8 applications»; `tasks/1.0-publish.md:148` «52 packages are published»; факт — 57 pubspec в `packages/`, 1 `publish_to: none`, **56 публикуемых**, 52 на `1.0.0-rc.1` + 4 на своих линиях. Живой сайт говорит «Thirty-eight packages» (см. §4). Шесть разных чисел в документах, которые читатель откроет первыми. Rc1-plan 5.4 обещает «hand-written counts replaced by rule-held ones» — не сделано.
3. **`flame_multiplayer`/`dashwire`: четыре версии в четырёх местах.** Pubspec: `0.3.0` и `0.2.0`. README `:32–33` и SUPPORT `:181`, publish.md `:72–73`: `0.2.0` и `0.1.1`. Решение D10 (`1.0-readiness-review.md:1486`): «→ `1.0.0-rc.1` with a CHANGELOG note on the jump». Rc1-plan 5.5 повторяет D10. Ни одно не выполнено. При этом `pub publish` **отказывает** релизной версии, зависящей от pre-release (`publish.md:62–64`, `08-tests-ci-publish.md:67`): `flame_multiplayer 0.3.0` → `flutter3d_net ^1.0.0-rc.1` = ERROR в L6, и `dashwire` следом в L7. Это известный блокер без закрытия.
4. **Dry-run не проверяет то, что сломается.** `publish_check.sh` гоняет dry-run **внутри workspace**, где сиблинги резолвятся по path. Что `^1.0.0-rc.1` реально резолвится с pub.dev, первый раз проверится на самом релизе, слой за слоем. `api_against_pub.sh` закрывает только API-diff, не резолв. Acceptance rc1-plan (`:261–263`) — «52 packages resolve from pub.dev … in a fresh `flutter create` project» — проверяется только после публикации, т.е. это не gate, а post-mortem.
5. **Отката нет, есть retract.** `publish.md:16` честно: только retract в 7 дней. Не написано, что делать, если пакет в L3 ушёл с неверным constraint и L4+ не резолвятся. Рабочий приём, которого в листке нет: `^1.0.0-rc.1` допускает `1.0.0-rc.1+1` и `1.0.0-rc.2`, так что «сломанный» пакет можно перевыпустить с build-метаданными, не трогая 55 сиблингов. Это стоит записать в листок как план Б.
6. **Семь (по publish.md `:152`) или одиннадцать (по ARCHITECTURE `:4692`) dev-зависимостей публикуются после пакета**, который их называет, — pana будет показывать «missing dependency» и срезать баллы на часы/дни, пока слой не дойдёт. Документы расходятся и в этом числе.
7. **Discontinue вручную.** 5 пакетов (`flutter3d_editor_mcp` 0.8.0, `flutter3d_model_mcp` 0.8.1, `flutter3d_mcp_kit` 0.8.0, `flutter3d_lab` 0.8.0, `flutter3d_lti` 0.8.0) сейчас **не** помечены (`isDiscontinued: null`, проверено API). Это 5 заходов в admin UI pub.dev после того, как заменяющие пакеты появятся. Пропустить легко; тогда `pub.dev/publishers/pleion.dev` показывает 61 пакет, из которых 5 мёртвые без указателя.
8. **Описания >180 символов** у 13 пакетов (`08-tests-ci-publish.md:71`; rc1-plan 5.5 «descriptions under 180 characters») — pana режет баллы; `flutter3d_core` уже 140/160. Не сделано.
9. **`dart_apitool` не установлен** на машине (`08-tests-ci-publish.md:70`); publish.md `:113` говорит, что прогон был 2026-10-08 с 0.23.2 — значит, установлен был. Противоречие; на день надо убедиться, иначе скрипт молча «skipped».
10. **Один мейнтейнер, один аккаунт pub.dev, одна машина.** Нет второго uploader'а в publisher'е (не проверено через API, publisher members не публичны — **unverified**), нет описанного bus-factor для 2FA/признаков.

### Сколько займёт полная публикация (оценка, не проверена)

56 пакетов × (`flutter pub publish` с подтверждением и загрузкой ≈ 1–2 мин) + 10 слоёв × ожидание индексации pub.dev (обычно 1–5 мин, иногда 10+) + 5 discontinue через UI + деплой сайта (`site/tool/deploy.sh`, rsync на `bob`) ≈ **3–5 часов внимательной ручной работы** для rc.1, и столько же для 1.0.0 и для rc.2. Каждый обрыв (сбой сети, ошибка constraint) добавляет цикл «понять, перевыпустить +1, ждать». Нет скрипта, который публикует слой и ждёт появления версии через `/api/packages/<p>` — всё руками, по `pub publish` из каждой из 56 директорий (`publish.md:127–128`).

---

## 2. CI и nightly как зависимость продукта

### Факты

- В `.github/workflows/` **только `ci.yml`** (762 строки). `nightly.yml` (D16), `editor_release.yml` (D55) — нет. `rg 'schedule:|cron'` пусто (`08-tests-ci-publish.md:38`).
- `ci.yml:8–11`: триггер `push: branches: [main]` и `pull_request`. Ветка `1.0.0` получает CI только через draft PR #82. Значок в README `:9` — статус **`main`**, то есть сейчас 0.8.5-эпохи кода, не кандидата.
- Нигде нет `runs-on: [self-hosted, impeller]`. HANDOFF.md `:13375–13376`: «Left for Dmitrii … a self-hosted macOS runner if the Impeller goldens are ever to be recorded nightly». Rc1-plan 0.5 (`:84`): «set up the self-hosted macOS runner … Dmitrii, S» — не сделано. ROADMAP `:88–94` обещает это с сентября («Alongside it, an Impeller machine of my own runs the golden and conformance suites nightly»).
- Решение 18 (`readiness-review:1188–1191`): «SUPPORT says it runs only while the machine is on». В SUPPORT.md такой фразы нет (`rg nightly SUPPORT.md` пусто).
- GPU-половина голденов записывается руками: `SUPPORT.md:47–52` «by hand, on a Mac with a GPU»; `pacing` job на `macos-latest` с `continue-on-error: true` (`ci.yml:605–608`) — «reported, not yet required».
- Голдены Impeller (96) и WebGPU (96, **0 перезаписаны**) старше шейдеров от 10-09 (`08-tests-ci-publish.md:52–60`). Для rc.1 нужна перезапись всех четырёх наборов на машине Дмитрия (rc1-plan 5.2).

### Что это значит для продукта

- **Что обещает значок**: «ci passing» на `main` = CPU-голдены, анализ, структура, билды, браузерные тесты, Windows MSVC. Он **не** обещает: что Impeller рисует правильно, что WebGPU-голдены актуальны, что на телефоне 60 fps. Читатель README этого не знает; SUPPORT не говорит «nightly есть / нет».
- **Единая точка отказа**: все GPU-доказательства (4 golden-набора, конформанс Impeller через `conformance.sh`, pacing на A55 — D51, условие тега) живут на одном Mac и одном телефоне в руках одного человека. Когда Mac выключен — nightly нет, но его и так нет. Когда Mac выключен в день релиза — голдены не перезаписать, тег не поставить по условию D51.
- **Условие тега D51** (пять пунктов на железе: pacing на A55 и iPhone, 2-часовой soak, таблица паритета C-ядра, rollback на 8 телефонах, размеры APK/IPA/web — `rc1-plan:37–51`) — rc1-plan 5.0 назначает «Dmitrii with an agent on the Impeller machine». Восемь телефонов в реальном Wi-Fi — у одного человека. **Unverified**, есть ли 8 устройств; если нет, условие тега не выполнимо и его надо смягчить письменно.
- **Что произойдёт после 1.0**: PR от внешнего контрибьютора, меняющий шейдер, пройдёт зелёный CI (CPU-голдены) и может сломать Impeller — узнают пользователи. Без nightly «strict semver» и «патч чинит» (SUPPORT `:157–160`) опираются на ручную дисциплину.

---

## 3. Сообщество и поддержка

### Каналы (что есть / чего нет)

| Канал | Состояние | Источник |
|---|---|---|
| GitHub Issues | включены; 3 шаблона (`bug_report.yml`, `feature_request.yml`, `modeler_report.yml`) + `config.yml` с blank issues | `.github/ISSUE_TEMPLATE/` |
| GitHub Discussions | **выключены**; HANDOFF `:13374` просит Дмитрия создать категории через UI — не сделано | `gh repo view` |
| Discord / Slack / Matrix / Telegram / рассылка | **нет** ни одного упоминания в README, SUPPORT, CONTRIBUTING, site index, comparison | `rg -i discord\|slack\|…` по документам: 0 совпадений |
| Обещание времени ответа | только SECURITY.md `:12` «acknowledgement within a week» для уязвимостей. SUPPORT.md — целиком о платформах и версиях, **ни слова о том, куда писать и когда ждать ответ** | SUPPORT.md 1–227 |
| Контакт CoC | «private GitHub security advisory» (`CODE_OF_CONDUCT.md:39–40`) — канал для уязвимостей используется как канал жалоб на поведение; нет e-mail | |
| Sponsors / funding | `fundingLinks: []` | `gh repo view` |
| Releases page | 0 релизов; «What's new» читать негде, кроме 56 CHANGELOG'ов | `gh release list` |

### Единственные два внешних сигнала — и оба без ответа

- **#80** (2026-10-06, `kevinkobori`): `pointer_lock` объявляет только macOS в `flutter.plugin.platforms`, просит объявить остальные. 0 комментариев за 3 дня.
- **#81** (2026-10-08, `helgoboss`): автор оригинального `pointer_lock` (GitHub, упомянут в README как prior art) пишет: «Was a bit baffled that the package name is now taken … would have been nice to either contact me before … or giving your package another name». **0 комментариев.** Это первое, что увидит читатель Reddit/HN, открыв Issues: репутационный риск «занял чужое имя и молчит». Сам факт, что обе первые внешние issue открыты про `pointer_lock` (а не про движок), говорит, что именно он сейчас находится поиском.

### Шаблоны issue устарели

- `feature_request.yml:33` «a backend (impeller, webgl, cpu)» — три, а их четыре; `:32` «one genre (shooter, platformer, racing)» — без strategy. `bug_report.yml:31` правильно говорит «Four exist».

### План по сообществу

**Нет.** `readiness-review.md:842` прямо: «community size, which no plan addresses». `18-flutter-scene.md:61`: «Сообщество … **нет** плана». `vision.md:17` называет «Adoption: pub.dev likes, stars, packages that depend on ours, and contributors» третьей метрикой «first» — и ни один пункт rc1-plan, publish.md, ROADMAP не двигает её. Единственное действие, направленное наружу — «videos and posts through the humanizer» (5.7) и один LinkedIn-пост про каустику (`publish.md:185–189`).

---

## 4. Сайт и витрина

### Что обещает исходник `site/content/index.md`

- `:7` «Five games, one engine» в заголовке; `:9` «six games built on them»; `:2` description «five games … four genres and a Flame hybrid». Три числа на одной странице.
- `:31` «all 45 packages are on pub.dev. Forty-two carry the release candidate 1.0.0-rc.1» — на pub.dev нет ни одного rc.1 (проверено: `flutter3d` 0.8.3+1), а 14 пакетов из дерева **вообще не на pub.dev** (`flutter3d_effects`, `_elements`, `_foundation`, `_matter`, `_mcp`, `_post`, `_voxel`, `_physics_native`, `_plugin_api`, `_plugin_runtime`, `_editor_play`, `_game_kit/_physics/_ui`, `_camera`, `_level_scene`, `_lints`, `_build_hooks` — API-проверка выше).
- `:32` «Stability: Pre-1.0. The graphics HAL carries a written compatibility promise; nothing else does» — противоречит README/SUPPORT («strict semver from 1.0.0», «the candidate already does»).
- `:156–169` «One HAL, four backends» — ок; но `:165` «WebGPU … You get it by asking for it, not by default» и `:171–173` «WebGPU is not the browser default» — противоречит README `:174–175` и SUPPORT `:70` («the default backend of a browser build since 1.0.0»). Та же неувязка отмечена в `18-flutter-scene.md:88` для ARCHITECTURE §15.
- `:89` «All six run in a browser on the WebGL2 backend».
- `:53` карточка Modeler «Tool · in progress».

### Что показывает **живой** сайт (curl 2026-10-09)

- `https://flutter3d.pleion.dev/`: «Thirty-eight packages», «all 38 packages», версия `0.8.0` (и `0.4.2`), «four backends». Это деплой **эпохи 0.8.0**; исходник ушёл вперёд на две итерации.
- `/reference/comparison/` живой — против Scene **0.23.0** и flutter3d 0.8.1/0.8.2. Исходник — против 0.24.1; факт — 0.24.3 вышел сегодня.
- `/reference/migrating-to-1.0/` — **404** (страница есть в исходнике, не задеплоена).
- `/download/`, `/editor/` — 404; **страницы загрузки редактора нет ни в исходнике, ни на сайте**. Единственный способ получить редактор — `flutter run -d macos` из `apps/flutter3d_editor` (`gallery.md:48–50`). `modeler/demo.md:29`: «The build is not signed or notarised yet … right-click, Open. The plan records that as a decision; nobody forgot». D55 (`readiness-review:1532`) обещает `editor_release.yml` + download page в rc.1 — не начато, сертификат «Dmitrii (the certificate)».
- `/showcase/` живой — 1660 байт (оболочка приложения); `/changelog/` живой — 76 KB, есть.
- `https://models.pleion.dev/` и `/learn/modeler/` — **200**, модельер живой. Это сильнейший публичный актив: Scene не имеет web-редактора (`18-flutter-scene.md:69`).
- Деплой: `site/tool/deploy.sh` → rsync на `bob:/opt/flutter3d`, cloudflared-туннель (`site/README.md:22–29, 83`). **Нет CI-деплоя**; сайт устаревает, пока кто-то не запустит скрипт руками. `publish.md:180` шаг 4 «Deploy the site» — ручной.

### Changelog-страница для 1.0

`site/content/changelog.md` генерируется из каталога showcase (`site/tool/showcase.mjs:93–104`, группировка по `since`), «every line quotes the package CHANGELOG it came from». `publish.md:33–34`: витрина помечает 1.0-страницы `since: '1.0.0-rc.1'`. Значит страница **будет** нести rc.1 — но только как список showcase-фич с их CHANGELOG-строками, **без нарратива** «что такое 1.0 и зачем мигрировать». Текущие CHANGELOG'и пакетов — списки `**Breaking:**` (`packages/flutter3d/CHANGELOG.md:1–40` — сплошные переносы экспортов). Это changelog для мигрирующего, не для покупателя.

### Галерея

`gallery.md` — 4 игры в iframe (shooter, platformer, racing, strategy), «The four games below» (`:7`), а index обещает шесть. Strategy без sample-run (`:37–39, 67–74`).

---

## 5. Агент/MCP как дифференциатор

`vision.md:28–32`: «The agent as a first-class user. **This is the main difference.**» Проверим, что в целевом состоянии реально отдаётся и как это узнаёт покупатель.

### Инвентарь (целевое состояние rc.1)

| Сервер / артефакт | Где | Запуск | Schema-версия |
|---|---|---|---|
| Редактор уровней | `flutter3d_mcp` `bin/editor_mcp.dart` | `dart run flutter3d_mcp:editor_mcp <level.json>`, stdio, без GPU | `editorMcpSchemaVersion` |
| Модельер (147 инструментов + `render`) | `flutter3d_mcp` `bin/model_mcp.dart` | `dart run flutter3d_mcp:model_mcp <project>` | `modelMcpSchemaVersion` |
| Проектный сервер (инструменты плагинов) | `flutter3d_mcp` `bin/project_mcp.dart` | `dart run flutter3d_mcp:project_mcp` | `projectMcpSchemaVersion` |
| Симуляция «играть вслепую» + render-диагностика | `flutter3d_sim_mcp` (две библиотеки, **без `bin/`**, MCP по сокету, не stdio — `README:21–24`) | из `flutter test`/приложения; нужен Flutter | `simMcpSchemaVersion`, `renderMcpSchemaVersion` |
| Plugin-author сервер | `flutter3d_build` `bin/plugin_mcp.dart` | `dart run flutter3d_build:plugin_mcp` (предположительно) | `pluginAuthorMcpSchemaVersion` |
| Loopback внутри запущенного модельера/редактора | `LoopbackMcpServer` в `kit.dart`; `modeler/demo.md:33` «Started with `--mcp-port`» | `rg -- '--mcp-port' apps/*/lib/main.dart` — **0 совпадений**; флаг в тексте есть, в main.dart не найден (**unverified**, может быть глубже) | — |
| VM-service extensions (`ext.flutter3d.*`) | `flutter3d_app` | автоматически в debug | `vmSchemaVersion` |
| Agent skills | 29 каталогов `skills/` по пакетам (`fd -t d '^skills$' packages apps`) | `dart run skills@ get` — **сторонний** CLI `skills` 1.0.3 (README `:280–288`) | не версионируются отдельно |

`flutter3d:skills` как команда **не существует**: в `packages/flutter3d_build/bin/` — `convert, create, flutter3d, init, lights, migrate, plugin_mcp, plugins`. `tool/skills` — внутренний генератор (`publish_to: none`), «writes agent skills for people building a game on flutter3d» — но его выход куда идёт, не проверено.

### Версионирование схем

**Сделано на бумаге и в правилах**: `CONTRIBUTING.md:371–394` — каждый сервер объявляет `schemaVersion` в `serverInfo`, «every server starts at 1.0.0 with the first stable release», алиасы для переименований до следующего мажора, `outputSchema` и `ToolHints` на каждом инструменте, два правила структуры (`every MCP tool and VM extension is the snapshot its package commits`, `a break in a tool or an extension is labelled and versioned`). `tasks/1.0-stability.md:89–93`. Снапшоты `api/*.mcp|vm|cli`. Это сильнее, чем у Scene. Но `readiness-review` 1F (`rc1-plan:102`) — 28 падающих тестов mcp, «`flutter3d.schema` в списке лишний», `broken_asset.glb` отсутствует — состояние на 10-09, не на тег.

### Где об этом прочитает покупатель

- README `:75` — одна строка таблицы для `flutter3d_mcp`, `:79` для `sim_mcp`, `:273–288` раздел «Skills for whatever is writing the code». Нет раздела «агент как пользователь» с примером конфигурации хоста (пример `mcpServers` есть только в `packages/flutter3d_mcp/README.md:60+`).
- `site/content/index.md` — слово MCP **не встречается**; «an agent can drive through the same doors a person uses» только в карточке модельера `:55`. В «What is in the box» (`:181–194`) строки про агента нет.
- `comparison.md:96–99` — три строки «yes/yes» (editor with MCP, render stats over MCP, skills) — **как паритет**, а не как отличие. `18-flutter-scene.md:32` формулирует отличие («агенту доступна симуляция, не только документ») — на сайт это не попало.
- Что ставить пользователю: Dart SDK (без Flutter) для трёх серверов `flutter3d_mcp`; Flutter — для `sim_mcp`; `skills` CLI — для скиллов; и до публикации rc.1 **ничего из этого нет на pub.dev** (`flutter3d_mcp` 404; на pub лежат старые `flutter3d_editor_mcp` 0.8.0 / `flutter3d_model_mcp` 0.8.1).

Вывод: «главное отличие» по vision — на титульной странице отсутствует, в сравнении показано как равенство, а инструкция «как подключить к Claude/Cursor за 2 минуты» есть только внутри README пакета, которого пока нет на pub.dev.

---

## 6. Сравнительные утверждения, которые оспорят

Проверено против `site/content/reference/comparison.md` (исходник) и живых данных Scene (0.24.3, 2026-10-09).

| Строка | Что написано | Что оспорят | Кто |
|---|---|---|---|
| `comparison.md:9`, `:16` | «read against `flutter_scene` 0.24.1 … 2026-10-07»; «Commits … after 0.24.1 are not counted» | 0.24.2 (10-08) и 0.24.3 (10-09) уже вышли; релиз-страница датирована днём, когда сравнение уже устарело | любой читатель с pub.dev |
| `:16` | «Core package version 1.0.0-rc.1» | на pub.dev 0.8.3+1; rc.1 не опубликован | скептик: «сравнивает ветку с релизом» |
| `:26` | «`flutter3d_mcp` on pub.dev» | 404 | то же |
| `:112` | «`flutter3d_editor_mcp` is on pub.dev» | противоречит `:26` (там `flutter3d_mcp`); две строки одной страницы называют разные пакеты | |
| `:41` EVSM «Scene: no», `:42` caustics «no», `:48` volumetric fog «no», `:49` OIT «no», `:50` motion blur «no», `:51` local exposure/HDR «no», `:57` GPU splat sort «no», `:58` impostors «no», `:59` Hi-Z «no», `:66` anim graph «no», `:68` animation pointers «no», `:69` retargeting «no`, `:81–83` ragdoll/cloth/liquids «no», `:88–94` «no» ×7, `:102` «no» | «red dot … means none of the three [README, CHANGELOG, source up to 0.24.1] names it» (`:30`) | 0.24.2–0.24.3 не прочитаны; `18-flutter-scene.md:19` перечисляет, что они принесли (Scene.dispose, TAA objectMotion, GPU-pacing, lean lit-shader). `:82` «Cloth in the engine's packages: Scene no» — у Scene есть `example_cloth.dart` (`18:86`), формулировка «in the engine's packages» спасает, но `:122` «Scene's README names none of those» — спорно. Каждый «no» — приглашение к опровержению в комментариях автором Scene, у которого 912★ аудитории | bdero и его Discord |
| `:63` | «Debug views of material channels: Scene yes» | с 0.24.1 — только за `debug_views: true` (`18:81`); не ошибка, но неточно | |
| `:7` | «Scene's render tests are where Flutter GPU regressions get caught» | это пересказ слов автора Scene, подано как факт (`18:87`) | |
| `:110` | «flutter3d's physics core in C … was started on 2026-10-04, and nobody outside this repository has run it yet» | честно — и это аргумент **против**, который сравнение само даёт; хорошо, но надо понимать, что цитировать будут именно это | |
| `:117` | «More than two and a half years … against flutter3d's two months» | честно | |
| Community row | **отсутствует** в Quick facts (`:13–26`) | 912★/21k загрузок vs 32★/783 — скептик добавит сам; `18:61` называет это «Б» (блокер для risk-averse команд) | |
| `:20` | «Windows: … nobody has played them there yet. Linux: … Impeller does not draw» | D56 обещает Supported в rc.1; если сделают — строку надо переписать; если нет — она верна и это минус | |
| README `:4` «four games of different genres», `:209` «13267 tests across fifty-seven packages» | число тестов держится правилом (ok); «fifty-seven» vs «fifty-two» в `:12` | внутренняя неувязка | |
| README `:12–37` первый абзац | 26 строк про номера версий (0.6.0, 0.7.0, rc.1, 0.5.0, 0.2.0, 0.1.1) до того, как сказано, что движок умеет | новичок (см. `16-reader-beginner.md`) | |

Что должна исправить перечитка D58 (`readiness-review:1536`): версия и дата (→ 0.24.3, 2026-10-09), `flutter3d_mcp` на pub (→ «после rc.1»), debug views за define, строки про `ExternalTexture` и billboards/sprites (у Scene есть, у flutter3d до rc.2 нет — сейчас этих строк в таблице **нет вообще**, что выглядит как умолчание), оговорки Windows/Linux с номерами issue Scene (#475/#474/#388/#391), пункты 0.24.2–0.24.3, cloth-пример, «unpublished candidate», ARCHITECTURE §15 про дефолтный web-бэкенд. Плюс четыре «to verify» (ETC1S-кодер, `ShadowCatcherMaterial`, `PointLight.radius`, tvOS/visionOS) — rc1-plan 5.6'. И добавить строку community (хотя бы stars/downloads с датой) — её отсутствие заметнее, чем цифры.

---

## 7. План запуска

### Что есть

- `tasks/1.0-publish.md:183–189`: «Shoot the videos, last of all (MP4 and APNG). Put every public post through the humanizer and the platform notes in the global CLAUDE.md»; один **LinkedIn-пост про каустику** с черновиком в scratchpad сессии (`caustics_post_simple.txt`) и видео «Reef wreck reel» (`reel_main.dart`).
- `rc1-plan 5.7`: «the videos and the posts through the humanizer».
- `0.9-release.md:142, 174`: «The videos, shot last» — та же фраза, перенесённая из 0.9.
- `ROADMAP.md:317–328` «The games, in front of people»: web-демо на сайте, два релиза «26 October and 27 December» (сроки из квартального плана 0.7/0.8).
- `site/content/reference/migrating-to-1.0.md` — гид миграции 0.8 → 1.0 есть в исходнике (на сайте 404).

### Чего нет

1. **Чек-листа запуска**: какие каналы (Reddit r/FlutterDev, HN Show, Mastodon, X, flutter-community Medium, Discord-серверы Flutter, Flame-Discord для `flame_flutter3d`), кто и когда постит, какой URL ведёт (сайт? pub.dev? GitHub?), что в первом комментарии. Единственный названный канал — LinkedIn.
2. **GitHub Release для `v1.0.0-rc.1`** с release notes — релизов 0; тег `v0.8.5` без release-страницы. Читатель с GitHub «What's new» не найдёт.
3. **Страницы «What's new since 0.8» / нарратива 1.0** — changelog-страница сайта соберёт список showcase-фич (§4), а CHANGELOG'и пакетов — списки breaking. Нет текста «1.0 — это: строгий semver, четыре бэкенда, детерминизм, агент; вот почему мигрировать; вот `migrate` в одну команду».
4. **Демо-видео**: ни одного готового; «shoot last» два релиза подряд. `18-flutter-scene.md:72` предлагает «2-минутный ролик: баг пришёл файлом, тест воспроизвёл, rollback на 8 телефонах» — в плане нет.
5. **Цифры с телефона в README до тега** (D51, `18:68` пункт 1 «что проверит переходящий первым») — ещё нет (`doc/pacing/` только macos-ci).
6. **Статьи**: `docs/articles/README.md` существует (не читал — **unverified**, что это), Medium/dev.to не упомянуты.
7. **Ответ на #81** (`pointer_lock`) до любого поста — иначе это первый комментарий в треде.
8. **Store-листинги демо** (`vision.md:15` «The demos in the stores») — никаких следов TestFlight/Play Console; Android-keystore «left for Dmitrii» (HANDOFF `:13376`).
9. **Кто отвечает в первые 72 часа** после поста — при одном мейнтейнере, который одновременно публикует 56 пакетов руками (§1).
10. **Второй релиз (1.0.0 после rc.1)**: «Collect feedback. Then 1.0.0» (`publish.md:43`) — без критерия, сколько фидбэка/времени; без даты.

---

## 8. Топ-8 рисков экосистемы/эксплуатации

| # | Риск | Вероятность / удар | Митигация есть? | Чего не хватает |
|---|---|---|---|---|
| 1 | **День публикации срывается посередине**: листок (`1.0-publish.md`) не содержит `foundation`/`matter`, `flame_multiplayer` 0.3.0 → ERROR на pre-release, 56 ручных `pub publish`, 10 слоёв ожидания | высокая / высокий (полдня-день, полупубликованный набор на pub.dev, который не резолвится) | частично: `publish_check.sh`, правило порядка в структуре, `^rc.1` допускает `+1` | перегенерировать листок из правила; решить D10 по факту (pubspec'ы); скрипт «опубликовать слой и дождаться API»; записать план Б (`+1`), отрепетировать на `--dry-run` вне workspace |
| 2 | **GPU-доказательства на одной машине и одном телефоне, nightly нет**: значок обещает меньше, чем читают; условие тега D51 (8 телефонов) может быть невыполнимо | высокая / средний (регрессии Impeller после 1.0 ловят пользователи) | нет (`nightly.yml` отсутствует, runner не поднят, SUPPORT молчит) | поднять runner (rc1-plan 0.5) или честно написать в SUPPORT/README «GPU-голдены записываются вручную перед релизом»; второй значок «nightly»; смягчить D51 до «2 телефона» письменно |
| 3 | **Сообщество = 0 при 27× отставании, плана нет, два внешних issue без ответа, одна из них — претензия на имя `pointer_lock`** | высокая / высокий (первый пост в Reddit — «он занял чужое имя и не отвечает») | нет | ответить на #81 и #80 до любого анонса; включить Discussions; назвать один чат-канал; написать в SUPPORT «куда писать и когда ждать ответ»; добавить community-строку в comparison |
| 4 | **Сайт устарел на две версии и деплоится вручную**: живой index говорит «38 пакетов, 0.8.0», migrating-to-1.0 → 404, comparison против 0.23 | высокая / средний (первое впечатление — «проект заброшен или врёт») | скрипт `deploy.sh` есть | деплой сайта в CI по тегу; проверка живого сайта в чек-листе (curl 5 URL); правило «hand-written counts replaced by rule-held ones» (5.4) |
| 5 | **Редактор нераздаваемый, D55 не начат**: нет dmg/zip/tar.gz, нет download page, сертификат у Дмитрия | средняя / высокий (единственный «Б»-гэп против Scene в `18:47`) | web-модельер жив на models.pleion.dev (сильно) | минимум — web-редактор по URL (18:69 пункт 3, «Scene не может дать ноль установки») и страница /download с «пока только web + build from source»; dmg — после |
| 6 | **Сравнение будет оспорено автором Scene**: ~20 «Scene: no», версия 0.24.1 вместо 0.24.3, «rc.1 на pub.dev», два разных имени MCP-пакета | средняя / высокий (репутация честности, которой страница гордится) | D58 запланирован в 5.6' | выполнить D58 до поста; каждую «no»-строку сопроводить «as of 0.24.3, from README/CHANGELOG/source»; добавить строки ExternalTexture/billboards с «flutter3d: rc.2» |
| 7 | **Дифференциатор «агент» не виден покупателю**: index без MCP, comparison показывает паритет, инструкция подключения только в README пакета, которого нет на pub.dev; `--mcp-port` в тексте, в main.dart не найден (unverified) | средняя / средний | контракт схем (CONTRIBUTING) сильный | раздел «Подключить агента за 2 минуты» на index и в README с `mcpServers`-сниппетом; строка в comparison «агент играет симуляцию без GPU: yes/no»; проверить `--mcp-port` |
| 8 | **Нет нарратива релиза и чек-листа запуска**: 0 GitHub Releases, changelog = список breaking, видео «shoot last» второй релиз подряд, один LinkedIn-пост, «collect feedback, then 1.0.0» без критерия | высокая / средний (релиз «пройдёт тихо», а это единственный момент, когда 27× можно сократить) | humanizer-скилл; migrating-to-1.0.md | чек-лист каналов с датами; GitHub Release с текстом «что такое 1.0»; одно 2-минутное видео детерминизма до поста; цифры с A55 в README (D51); критерий и дата 1.0.0 |

### Что поправимо за день и даёт больше всего

1. Ответить на #81 (и #80). 2. Перегенерировать `1.0-publish.md` из правила порядка и решить D10 в pubspec'ах. 3. Задеплоить сайт из ветки (или хотя бы `migrating-to-1.0`) и поставить деплой в CI. 4. Добавить в SUPPORT абзац «куда писать, когда ждать, nightly пока вручную». 5. Строка community и версия 0.24.3 в comparison.

**Unverified в этом отчёте**: оценка времени публикации (§1); наличие второго uploader'а в publisher `pleion.dev`; существование 8 телефонов для D51; флаг `--mcp-port` в приложениях; что внутри `docs/articles/`; авторство черновика LinkedIn-поста.
