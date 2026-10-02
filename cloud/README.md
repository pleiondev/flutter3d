# cloud

The service at https://models.pleion.dev/: an account with a confirmed
address, the models a person keeps in it, and the modeller's web build to open
them in.

It lives in this repository because it reads models with the engine's own
packages. An upload that `flutter3d_formats` cannot decode is refused before it
reaches the disk. It lives outside the pub workspace because it is a service
and is never published, and the counts the README and `tool/structure.dart`
keep are counts of packages.

## What is here

| | |
|---|---|
| `server/` | One Dart process: shelf for the routes, jaspr to render every page on the server |
| `server/lib/src/db/migrations/` | The schema, as numbered SQL. `tool/embed_migrations.dart` turns it into the Dart file the binary carries |
| `server/web/assets/` | The stylesheet and two scripts: uploading, and opening a model in 3D. The tutorial's pictures are under `learn/modeler/` here |
| `server/content/learn/modeler/` | The modeller's tutorial, one Markdown file a case, served at `/learn/modeler/`. Read from disk at start, so it is deployed beside the executable and not inside it |
| `tool/` | Building the executable, building the viewer, deploying both |
| `deploy/` | The systemd units, the nginx vhost, the tunnel config and an example environment |
| `docker-compose.yml` | Postgres for development and the integration test |
| `monitoring/` | Prometheus and Grafana for the service's own numbers (accounts, models, disk). [README](monitoring/README.md) |

Two more services live beside it, each with its own README: `lessons/`
(a lesson page and its embed) and `lti/` (LTI 1.3 launch and grade passback).
Shared levels and opt-in telemetry are part of this server; see
[Sharing](#sharing) and [Telemetry](#telemetry).

## Running it

```bash
docker compose -f cloud/docker-compose.yml up -d

cd cloud/server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # jaspr's generated options

MODELS_BASE_URL=http://localhost:8794 \
MODELS_DATABASE_URL=postgres://models:models@localhost:55432/models \
MODELS_BLOB_DIR=/tmp/models-blobs \
MODELS_SECRET=dev \
dart run lib/main.server.dart
```

With no `MODELS_RESEND_API_KEY`, letters are printed to the terminal instead of
sent, so after registering you will find the confirmation link in the log. To
open models in 3D locally, build the viewer (`cloud/tool/build_viewer.sh`) and
add `MODELS_VIEWER_DIR=build/app`.

Every setting is read once at start. If any are missing, the start stops and
names all of them.

| Variable | |
|---|---|
| `MODELS_BASE_URL` | What links in letters point at |
| `MODELS_DATABASE_URL` | `postgres://user:password@host:port/database` |
| `MODELS_BLOB_DIR` | Where uploaded files are kept, by SHA-256 |
| `MODELS_SECRET` | Signing secret |
| `MODELS_RESEND_API_KEY` | Optional; without it letters go to the log |
| `MODELS_MAIL_FROM` | Default `models@pleion.dev` |
| `MODELS_PORT` | Default 8794 |
| `MODELS_UPLOAD_LIMIT` | Bytes; default 100 MB, which is what a free Cloudflare tunnel passes |
| `MODELS_ASSETS_DIR` | Default `web/assets` |
| `MODELS_VIEWER_DIR` | Optional; serves the viewer at `/app/` when set |
| `MODELS_LEARN_DIR` | Default `content/learn/modeler`, which is right in a checkout and nowhere else. A directory with no case in it gives an empty tutorial and one line in the log; the start does not fail |
| `MODELS_TELEMETRY_LEVELS_DIR` | Optional; the levels telemetry runs are played again in. See [Telemetry](#telemetry) |
| `MODELS_SHARES_MODERATION` | `review` (default) or `open`. See [Sharing](#sharing) |
| `MODELS_SHARES_MODERATOR_TOKEN` | Optional, 24 characters or more; without it moderation is off |
| `MODELS_SHARES_REPORTS_TO_HIDE` | How many reports send a published level back to review. Default 3 |

## Tests

```bash
dart test -x db     # the rules: passwords, tokens, CSRF, uploads, access, letters
dart test -t db     # the whole journey against Postgres, through the real handler
```

The journey test registers, confirms, uploads, checks that nobody else can see
the model, signs out and back in, resets the password from another browser and
checks that the first one was signed out, and deletes the model and its file.

After editing a migration, run `dart run tool/embed_migrations.dart`. With
`--check` it fails when the generated file is stale.

## Telemetry

The reference server for runs that players agreed to send (N7 in
`tasks/0.9-engine-roadmap.md`). Under `/api/telemetry/`:

| | |
|---|---|
| `POST runs` | A `TelemetryUpload` from `flutter3d_sim`. Refused without the consent it was sent under. The run is played again through `resimulate`; one that diverges, or names a game or a level this server lacks, is refused and nothing is kept. An accepted run keeps its trail, outcome, length and the consent record, not its input, and answers `201 {run, eraseKey}` |
| `DELETE runs/<run>?key=<eraseKey>` | Deletes the run. Only the key's hash is stored |
| `GET heatmap?level=<digest>&cell=<metres>` | The newest 2000 runs of that level, binned. The JSON is the playtest report's, which the editor's report screen draws |

`MODELS_TELEMETRY_LEVELS_DIR` names a directory of level documents, keyed by
their digest; a file that does not parse is named in the log and skipped.
The games are `HeadlessGame`s handed to `Services(telemetryGames:)` in code.
`main.server.dart` hands none, because every genre in the repository needs
Flutter and this process runs under `dart run`, so as shipped the endpoint
answers 503 and says why.

## Sharing

The reference server for shared levels (N10 in `tasks/0.9-engine-roadmap.md`).
A player shares a level, or a level with a run through it, and gets a short
code back. The client and the format are `RunService` and `ShareBundle` in
`flutter3d_sim`; a game points `RunService` at `https://<host>/api/`. Every
answer is JSON, and every refusal is `{"message": …}`, which `RunService` hands
to the game as the reason. No account is involved. Under `/api/v1/`:

| | |
|---|---|
| `POST shares` | A `ShareBundle`, at most 4 MB. A run recorded in another version of the level is refused. `201 {code, address, status}`, or `200` with the same code when these bytes were shared before |
| `GET shares/<code>` | `200 {bundle}` when published, `202` while pending, `410` with the moderator's reason when removed, `404` |
| `POST shares/<code>/reports` | `{reason}`, answered `202 {message}` |
| `GET moderation/queue` | Token. Pending levels and anything reported |
| `GET moderation/shares/<code>` | Token. One level with its record, whatever its status |
| `POST moderation/shares/<code>` | Token, `{decision: publish \| remove, reason}`. A removal needs a reason; publishing again drops the reports |

A level is filed under the SHA-256 of the bytes the server writes for it, not
the bytes it was sent, so the same level shared twice gets the same code. Those
bytes are kept as `text` in `shares`, since `jsonb` would not keep them. The
code is the first seven characters of the hash in Crockford's base 32, and gets
longer only if a different level already holds it. People can type it in lower
case, with dashes, and with O for 0 or L for 1.

In `review` mode nothing opens until a moderator publishes it, so without a
token `POST shares` answers 503 instead of keeping levels nobody could ever
publish. In `open` mode a level opens at once, and
`MODELS_SHARES_REPORTS_TO_HIDE` reports send it back to review. The moderation
routes take `Authorization: Bearer <MODELS_SHARES_MODERATOR_TOKEN>` and answer
503 when no token is set.

Not deployed: the production environment sets none of these, so models.pleion.dev
shares nothing yet.

## Deploying

```bash
cloud/tool/deploy.sh
```

Builds the executable in a `linux/amd64` Dart container, builds the viewer,
rsyncs both to `bob:/opt/flutter3d-models` and restarts the unit. Nothing else
changes on a redeploy.

### The first time

These steps are done once, by hand, because each one creates something outside
this repository.

1. Database. It gets its own container, on a loopback port the other two
   Postgres containers on bob do not use:

   ```bash
   docker run -d --name models-postgres --restart unless-stopped \
     -e POSTGRES_USER=models -e POSTGRES_PASSWORD=… -e POSTGRES_DB=models \
     -v models-postgres:/var/lib/postgresql/data \
     -p 127.0.0.1:5434:5432 postgres:17-alpine
   ```

2. Environment. Copy `deploy/flutter3d-models.env.example` to
   `/etc/flutter3d-models.env`, mode 600, with the real values.

3. Mail. Add `pleion.dev` in Resend, put the SPF, DKIM and DMARC records it
   lists into Cloudflare DNS, wait for it to show verified, and put the API key
   in the environment file.

4. Service. Copy `deploy/flutter3d-models.service` to `/etc/systemd/system/`,
   run `systemctl enable flutter3d-models`, then run `tool/deploy.sh`.

   The unit is copied by hand and `tool/deploy.sh` does not touch it, so a
   setting added to it later is not on the server until it is copied again and
   `systemctl daemon-reload` is run. The script checks the one setting it
   depends on, `MODELS_LEARN_DIR`, before it replaces anything. When the unit
   does not have it, the script stops and its message lists these two steps.

5. nginx. Copy `deploy/nginx-models.pleion.dev.conf` to `sites-available`,
   link it into `sites-enabled`, and run `nginx -t && systemctl reload nginx`.

6. Tunnel. Run `cloudflared tunnel create flutter3d-models`, put the ID into
   `deploy/cloudflared-models.yml` and copy that to
   `/etc/cloudflared/models.yml`. Then add the DNS route, naming the config and
   the UUID explicitly:

   ```bash
   cloudflared --config /etc/cloudflared/models.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> models.pleion.dev
   ```

   Without `--config`, the command picked up bob's default `config.yml` and
   pointed the record at a different tunnel than the one it was given by name.
   That happened on the first setup, and the line it printed named the wrong
   ID, so read that line. Then enable `deploy/cloudflared-models.service`.

### Where it runs

- Executable: `bob:/opt/flutter3d-models/models`, run by
  `flutter3d-models.service` as a dynamic user
- Files people uploaded: `/var/lib/flutter3d-models/blobs`
- Database: the `models-postgres` container, `127.0.0.1:5434`
- nginx: `127.0.0.1:8793`, serving `/assets/` and `/app/` from disk and
  proxying everything else to the service on `127.0.0.1:8794`
- Tunnel: `cloudflared-models.service`

## What is not here yet

- Author pages, and attribution written into exported files. A published
  model's own page already names its owner, its licence and its category. A
  page listing everything one account has published, and a downloaded file
  carrying that licence in its own metadata, are not built yet.

Preview pictures and editing from the cabinet, with revisions, both work. The
server has no GPU to render a frame, so a preview is captured in the viewer's
own browser (`canvas.toBlob`) and POSTed to `/api/v1/models/<id>/preview`. A
save-back goes to `/api/v1/models/<id>/source`, which keeps the file it
replaces as a revision in `model_revisions`, downloadable by the owner at
`/files/<id>/revisions/<revisionId>`. Both endpoints check ownership and CSRF
the same way every other mutating route here does.

Projects, publishing and the public showcase also work. A model can live
inside a project or stand alone. `models.project_id` is nullable, and the
database itself sets it to `null` when the project is deleted; no code walks
the models to detach them. `POST /m/<id>/publish` records a licence and a
category, each chosen from a fixed enum server-side, so a client-supplied
string never reaches the `check` constraint that backstops them. `/explore`
lists every published model, filterable by category and searchable by title
and description through `websearch_to_tsquery` (never raw `to_tsquery` on
what somebody typed).

Every mutating route added for this (project create, describe, delete, move,
publish, unpublish) checks ownership and CSRF like the other routes here. A
cross-account project id gets the same 404 a cross-account model id already
got, never a 403 that would confirm the other account's project exists. An
adversarial review of all of it found one real gap: project creation had no
rate limit, unlike every other row-creating action here. It now carries
`RateRule.projectCreatePerAccount`, in the same shape publishing already had.
