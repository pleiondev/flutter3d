# cloud

The service at **https://models.pleion.dev/**: an account with a confirmed
address, the models a person keeps in it, and the modeller's web build to open
them in.

It lives in this repository because it reads models with the engine's own
packages — an upload that `flutter3d_formats` cannot decode is refused before it
reaches the disk — and it lives outside the pub workspace because it is a
service rather than a package: it is never published, and the counts the README
and `tool/structure.dart` keep are counts of packages.

## What is here

| | |
|---|---|
| `server/` | One Dart process: shelf for the routes, jaspr to render every page on the server |
| `server/lib/src/db/migrations/` | The schema, as numbered SQL. `tool/embed_migrations.dart` turns it into the Dart file the binary carries |
| `server/web/assets/` | The stylesheet and two scripts: uploading, and opening a model in 3D |
| `tool/` | Building the executable, building the viewer, deploying both |
| `deploy/` | The systemd units, the nginx vhost, the tunnel config and an example environment |
| `docker-compose.yml` | Postgres for development and the integration test |

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
sent — register, and the confirmation link is in the log. To open models in 3D
locally, build the viewer (`cloud/tool/build_viewer.sh`) and add
`MODELS_VIEWER_DIR=build/app`.

Every setting is read once at start, and a missing one stops the start with the
names of everything that is missing.

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

## Tests

```bash
dart test -x db     # the rules: passwords, tokens, CSRF, uploads, access, letters
dart test -t db     # the whole journey against Postgres, through the real handler
```

The journey test registers, confirms, uploads, checks that nobody else can see
the model, signs out and back in, resets the password from another browser and
checks that the first one was signed out, and deletes the model and its file.

After editing a migration: `dart run tool/embed_migrations.dart`. With `--check`
it fails when the generated file is stale.

## Deploying

```bash
cloud/tool/deploy.sh
```

Builds the executable in a `linux/amd64` Dart container, builds the viewer,
rsyncs both to `bob:/opt/flutter3d-models` and restarts the unit. Nothing else
changes on a redeploy.

### The first time

Done once, by hand, because each step creates something outside this repository.

1. **Database** — its own container, on a loopback port the other two Postgres
   containers on bob do not use:

   ```bash
   docker run -d --name models-postgres --restart unless-stopped \
     -e POSTGRES_USER=models -e POSTGRES_PASSWORD=… -e POSTGRES_DB=models \
     -v models-postgres:/var/lib/postgresql/data \
     -p 127.0.0.1:5434:5432 postgres:17-alpine
   ```

2. **Environment** — `deploy/flutter3d-models.env.example` to
   `/etc/flutter3d-models.env`, mode 600, with the real values.

3. **Mail** — add `pleion.dev` in Resend, put the SPF, DKIM and DMARC records it
   lists into Cloudflare DNS, wait for it to show verified, and put the API key
   in the environment file.

4. **Service** — `deploy/flutter3d-models.service` to `/etc/systemd/system/`,
   `systemctl enable flutter3d-models`, then run `tool/deploy.sh`.

5. **nginx** — `deploy/nginx-models.pleion.dev.conf` to `sites-available`,
   linked into `sites-enabled`, `nginx -t && systemctl reload nginx`.

6. **Tunnel** — `cloudflared tunnel create flutter3d-models`, the ID into
   `deploy/cloudflared-models.yml` copied to `/etc/cloudflared/models.yml`, then
   the DNS route **with the config and the UUID named explicitly**:

   ```bash
   cloudflared --config /etc/cloudflared/models.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> models.pleion.dev
   ```

   Run without `--config`, it picked up bob's default `config.yml` and pointed
   the record at a different tunnel than the one it was given by name — the
   first setup did exactly that, and the line it printed named the wrong ID.
   Read that line. Then enable `deploy/cloudflared-models.service`.

### Where it runs

- **Executable** — `bob:/opt/flutter3d-models/models`, run by
  `flutter3d-models.service` as a dynamic user
- **Files people uploaded** — `/var/lib/flutter3d-models/blobs`
- **Database** — the `models-postgres` container, `127.0.0.1:5434`
- **nginx** — `127.0.0.1:8793`, serving `/assets/` and `/app/` from disk and
  proxying everything else to the service on `127.0.0.1:8794`
- **Tunnel** — `cloudflared-models.service`

## What is not here yet

- **The public catalogue.** Models can be private only. Publishing with a
  licence, author pages and attribution written into exported files are the stage
  after that; the licences and the `published()` query exist already.

Preview pictures and editing from the cabinet, with revisions, are both real
now: the server has no GPU to render a frame, so a preview is captured in the
viewer's own browser (`canvas.toBlob`) and POSTed to
`/api/v1/models/<id>/preview`; a save-back goes to
`/api/v1/models/<id>/source`, which keeps the file it replaces as a revision
in `model_revisions`, downloadable by the owner at
`/files/<id>/revisions/<revisionId>`. Both endpoints check ownership and CSRF
the same way every other mutating route here does.
