# cloud/lessons

The service at https://lessons.pleion.dev/ serves a public page and an
embeddable iframe for an `edu-00` lesson document, played back by
`apps/flutter3d_lesson_viewer`.

It has its own subdomain and its own service on `bob`, separate from
`models.pleion.dev` (`cloud/server`). The audience is different: a lesson
embedded in someone else's course page, where `cloud/server` hosts a person's
own model cabinet. So is the security posture. `/e/<slug>` exists so that a
third-party page *can* frame it, and `cloud/server` forbids exactly that for
its own pages.

## What is here

| | |
|---|---|
| `server/` | One Dart process: shelf routes and plain HTML strings. No jaspr, no database, no accounts |
| `server/lib/src/lessons_registry.dart` | The lessons this service knows about, as Dart data. It is not a file on disk or a table, because nobody uploads a lesson here (yet; see "What is not here yet") |
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
`/app/` answers 404. To see the lesson itself run, and not just the page
around it, build the viewer first (`cloud/lessons/tool/build_viewer.sh`, which
needs Flutter) and set `LESSONS_VIEWER_DIR=build/app`.

| Variable | |
|---|---|
| `LESSONS_BASE_URL` | What the embed snippet on `/l/<slug>` tells people to point their `<iframe>` at |
| `LESSONS_PORT` | Default 8796 |
| `LESSONS_VIEWER_DIR` | Optional; serves the lesson viewer at `/app/` when set |

Every setting is read once at start. If a required one is missing, the start
stops and names everything that is missing.

## Tests

```bash
dart test
```

The tests cover routes only. There is no database, so there is no
`-t db`/`-x db` split of the kind `cloud/server` needs.

## Adding a lesson

Add a `Lesson` to `lessons` in `lib/src/lessons_registry.dart`, and bundle its
level JSON as an asset of `apps/flutter3d_lesson_viewer` (see that app's own
`assets/levels/`). There is no upload path and no database migration. This is
as far as the "public page for one lesson" acceptance goes today.

## Deploying

```bash
cloud/lessons/tool/deploy.sh
```

The script builds the executable in a `linux/amd64` Dart container, builds the
viewer, rsyncs both to `bob:/opt/flutter3d-lessons` and restarts the unit.
Nothing else changes on a redeploy.

### The first time

These steps are done once, by hand, for the same reason as the "first time"
section of `cloud/README.md`: each one creates something outside this
repository, and a script that repeats them is a script somebody runs twice by
accident.

1. Environment: copy `deploy/flutter3d-lessons.env.example` to
   `/etc/flutter3d-lessons.env`, mode 600, with the real base URL.

2. Service: copy `deploy/flutter3d-lessons.service` to
   `/etc/systemd/system/`, run `systemctl enable flutter3d-lessons`, then run
   `tool/deploy.sh`.

3. nginx: copy `deploy/nginx-lessons.pleion.dev.conf` to `sites-available`,
   link it into `sites-enabled`, then `nginx -t && systemctl reload nginx`.

4. Tunnel: create a separate tunnel for this service instead of adding an
   ingress rule to the models tunnel:

   ```bash
   cloudflared tunnel create flutter3d-lessons
   ```

   Put the printed ID into `deploy/cloudflared-lessons.yml`, copy that to
   `/etc/cloudflared/lessons.yml`, then add the DNS route with the config and
   the tunnel ID named explicitly. `cloud/README.md` already documents the
   mistake this flag avoids: a bare `tunnel route dns` picks up bob's default
   config and points the record at the wrong tunnel.

   ```bash
   cloudflared --config /etc/cloudflared/lessons.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> lessons.pleion.dev
   ```

   Then enable `deploy/cloudflared-lessons.service`.

### Where it runs

- Executable: `bob:/opt/flutter3d-lessons/lessons`, run by
  `flutter3d-lessons.service` as a dynamic user
- nginx: `127.0.0.1:8795`, serving `/app/` from disk and proxying
  everything else to the service on `127.0.0.1:8796`
- Tunnel: `cloudflared-lessons.service`

The ports are the next free pair after the `8793`/`8794` used by
`models.pleion.dev`. Before the first deploy, confirm nothing else on `bob`
already holds `8795`/`8796`; this repository only tracks what it put there
itself.

**Why `/e/` needs its own nginx `location`, not just its own route in the
Dart service.** `dart:io`'s `HttpServer` adds `X-Frame-Options: SAMEORIGIN`
to every response by default, at the transport layer. `shelf` (and this
service's own `_securityHeaders`) cannot remove a header that `dart:io`
pre-populated outside `shelf`'s own header map, so leaving it out of the
`Response` this service builds does not mean it is absent on the wire. This
was found by curling the deployed service, not by reading the code. The fix
is in the `location /e/` block of `deploy/nginx-lessons.pleion.dev.conf`
(`proxy_hide_header X-Frame-Options`). Removing that block as redundant,
on the grounds that the Dart route already omits the header, would silently
break every embed.

## What is not here yet

- **`prep-00`/`prep-01`/`prep-02`** (`doc/lesson-scenarios-plan.md`): a real
  object to tear down, real lesson text, real questions. The one lesson this
  service ships today is the camera tour already proved by `tpl-04`'s
  `viewer.json`, plus one placeholder `check` question added to prove that
  mechanic against real content. It is not a real course.
- **Everything `apps/flutter3d_lesson_viewer` itself does not play back**:
  `offsets` (layered teardown), `edu_clip_plane` rendering, `bindings`/
  `edu_data_source` (live data). See that app's own `lib/main.dart` doc
  comment and `apps/flutter3d_lesson_viewer/lib/src/lesson_player.dart`.
- **`check` (the quiz question)**: `check_prompt.dart` implements and
  unit-tests it, and the shipped `tour.json` still carries a `quiz-steps`
  entity with a real question, but the step is deliberately left OUT of
  `edu_sequence.steps`. A real-browser run (not `flutter test`) hit Flutter's
  default red error screen on that step, and the root cause is not yet found;
  see the `edu-02` entry in `doc/tooling-plan.md`. Re-add it to `steps` only
  after someone with a working browser reproduces and fixes the crash.
- **`edu-03`** (LTI/xAPI): this service has no notion of a student identity
  or a grade to report. `edu-03` depends on this service but has not started.
- **Uploading a lesson.** The registry is Dart code because nobody has asked
  to publish their own lesson here yet. `cloud/server`'s own README names the
  same gap for its "public catalogue".
