# cloud/lessons

The service at **https://lessons.pleion.dev/**: a public page and an
embeddable iframe for an `edu-00` lesson document, played back by
`apps/flutter3d_lesson_viewer`.

Its own subdomain and its own service on `bob`, deliberately separate from
`models.pleion.dev` (`cloud/server`) — a different audience (a lesson embedded
in someone else's course page, not a person's own model cabinet), and a
different security posture: the whole reason `/e/<slug>` exists is so a
third-party page *can* frame it, the opposite of what `cloud/server` allows
for its own pages.

## What is here

| | |
|---|---|
| `server/` | One Dart process: shelf routes, plain HTML strings — no jaspr, no database, no accounts |
| `server/lib/src/lessons_registry.dart` | The lessons this service knows about, as Dart data — not a file on disk or a table, because nobody uploads a lesson here (yet; see "What is not here yet") |
| `tool/` | Building the executable, building the viewer, deploying both |
| `deploy/` | The systemd units, the nginx vhost, the tunnel config and an example environment |

## Running it

```bash
cd cloud/lessons/server
dart pub get

LESSONS_BASE_URL=http://localhost:8796 \
dart run lib/main.server.dart
```

Open `http://localhost:8796/l/engine-tour`. Without `LESSONS_VIEWER_DIR` set,
`/app/` answers 404 — build the viewer first (`cloud/lessons/tool/build_viewer.sh`,
needs Flutter) and set `LESSONS_VIEWER_DIR=build/app` to see the lesson itself
run, rather than just the page around it.

| Variable | |
|---|---|
| `LESSONS_BASE_URL` | What the embed snippet on `/l/<slug>` tells people to point their `<iframe>` at |
| `LESSONS_PORT` | Default 8796 |
| `LESSONS_VIEWER_DIR` | Optional; serves the lesson viewer at `/app/` when set |

Every setting is read once at start, and a missing required one stops the
start with the names of everything that is missing.

## Tests

```bash
dart test
```

Routes only — there is no database, so there is no `-t db`/`-x db` split
`cloud/server` needs.

## Adding a lesson

Add a `Lesson` to `lessons` in `lib/src/lessons_registry.dart`, and bundle its
level JSON as an asset of `apps/flutter3d_lesson_viewer` (see that app's own
`assets/levels/`). There is no upload path and no database migration — this is
as far as the "public page for one lesson" acceptance goes today.

## Deploying

```bash
cloud/lessons/tool/deploy.sh
```

Builds the executable in a `linux/amd64` Dart container, builds the viewer,
rsyncs both to `bob:/opt/flutter3d-lessons` and restarts the unit. Nothing
else changes on a redeploy.

### The first time

Done once, by hand, same reasoning as `cloud/README.md`'s own "first time"
section — each of these steps creates something outside this repository, and
a script that repeats them is a script somebody runs twice by accident.

1. **Environment** — `deploy/flutter3d-lessons.env.example` to
   `/etc/flutter3d-lessons.env`, mode 600, with the real base URL.

2. **Service** — `deploy/flutter3d-lessons.service` to
   `/etc/systemd/system/`, `systemctl enable flutter3d-lessons`, then run
   `tool/deploy.sh`.

3. **nginx** — `deploy/nginx-lessons.pleion.dev.conf` to `sites-available`,
   linked into `sites-enabled`, `nginx -t && systemctl reload nginx`.

4. **Tunnel** — its own, not an ingress rule added to the models tunnel:

   ```bash
   cloudflared tunnel create flutter3d-lessons
   ```

   the printed ID into `deploy/cloudflared-lessons.yml` copied to
   `/etc/cloudflared/lessons.yml`, then the DNS route **with the config and
   the tunnel ID named explicitly** — `cloud/README.md` already documents
   the exact mistake this flag avoids (a bare `tunnel route dns` picks up
   bob's default config and points the record at the wrong tunnel):

   ```bash
   cloudflared --config /etc/cloudflared/lessons.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> lessons.pleion.dev
   ```

   Then enable `deploy/cloudflared-lessons.service`.

### Where it runs

- **Executable** — `bob:/opt/flutter3d-lessons/lessons`, run by
  `flutter3d-lessons.service` as a dynamic user
- **nginx** — `127.0.0.1:8795`, serving `/app/` from disk and proxying
  everything else to the service on `127.0.0.1:8796`
- **Tunnel** — `cloudflared-lessons.service`

Ports chosen as the next free pair after `models.pleion.dev`'s `8793`/`8794`
— confirm nothing else on `bob` already holds `8795`/`8796` before the first
deploy; this repository only tracks what it put there itself.

**Why `/e/` needs its own nginx `location`, not just its own route in the
Dart service.** `dart:io`'s `HttpServer` adds `X-Frame-Options: SAMEORIGIN`
to every response by default, at the transport layer — `shelf` (and this
service's own `_securityHeaders`) has no way to remove a header `dart:io`
pre-populated outside `shelf`'s own header map, so omitting it from the
`Response` this service builds is not the same as it being absent on the
wire. Found by curling the deployed service, not by reading this service's
code. The fix lives in `deploy/nginx-lessons.pleion.dev.conf`'s `location
/e/` (`proxy_hide_header X-Frame-Options`) — removing that block "as
redundant" because the Dart route already omits the header would silently
break every embed.

## What is not here yet

- **`prep-00`/`prep-01`/`prep-02`** (`doc/lesson-scenarios-plan.md`) — a real
  object to tear down, real lesson text, real questions. The one lesson this
  service ships today is the camera tour already proved by `tpl-04`'s
  `viewer.json`, plus one placeholder `check` question added to prove that
  mechanic against real content — not a real course.
- **Everything `apps/flutter3d_lesson_viewer` itself does not play back**:
  `offsets` (layered teardown), `edu_clip_plane` rendering, `bindings`/
  `edu_data_source` (live data). See that app's own `lib/main.dart` doc
  comment and `packages/flutter3d_bridge/lib/src/lesson_player.dart`.
- ~~**`check` (the quiz question)** left out of `edu_sequence.steps`~~ — fixed.
  `LessonView` did not wrap itself in a `Material`, which is why a real
  browser run hit Flutter's default red error screen on that step where
  `flutter test` did not; see `doc/tooling-plan.md`'s `edu-02` entry for the
  found cause and the fix. `tour.json` carries `quiz-steps` in
  `edu_sequence.steps` again.
- **`edu-03`** (LTI 1.3/xAPI) — planned in `doc/edu-03-lti-plan.md`, not
  started in code yet. This service has no notion of a student identity or a
  grade to report; the plan puts that in a new `cloud/lti`, built on a new
  `flutter3d_lti` package this one does not depend on.
- **Uploading a lesson.** The registry is Dart code because nobody has asked
  to publish their own lesson here yet — the same gap `cloud/server`'s own
  README names for its "public catalogue".
