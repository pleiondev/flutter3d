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
| `server/web/assets/` | The stylesheet and three scripts: uploading, converting, and opening a model in 3D. The tutorial's pictures are under `learn/modeler/` here |
| `server/lib/src/convert/` | Online conversion: the one adapter to `flutter3d_build`'s converters, the archive reader that guards against zip bombs, the confinement, and the short-lived store results wait in. Also "Download as…": the exporter over the core's writers and the isolate runner both share |
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
| `MODELS_EDITOR` | `on` or `off` (default). Whether a model opened at `/app/` can be saved back. See [Editing is switched off](#editing-is-switched-off). Anything else stops the start |

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

`convert_routes_test.dart` and `convert_test.dart` cover converting without a
database: signed out, unconfirmed and forged requests are refused, a result is
nobody else's, a bomb stops at its budget, a path outside the upload reads as
missing, and a conversion past its deadline is stopped. A model comes back
as one bundled `.f3d` per input, and only the `model` target asks for the
bundle. They also check that
`MODELS_EDITOR=off` answers a source save with 410, that "Save to my
models" keeps an uploaded `.glb` byte for byte, and that a zipped `.gltf`
with its `.bin` is kept as a `.glb`. `export_test.dart` covers "Download
as…" without a database: each writer through the isolate, the `.gltf` taken
apart from a GLB, a second request that is a read, two at once that write
once, and an export of a replaced source that is not kept. The journey test
walks the same against Postgres: a private model's exports 404 for anybody
else, a published one's are anybody's, each format's type and name, and the
rows and blobs gone after a source save and after a delete.

## Editing is switched off

As deployed, `MODELS_EDITOR=off`. Models are stored, rendered and inspected as
before, but nobody edits them on the site:

- `/app/` is the modeller built with
  `--dart-define=FLUTTER3D_MODELER_MODE=viewer`. It draws the model, orbits
  it, switches between material, normals and wireframe display, and still
  captures the owner's preview picture (`POST /api/v1/models/<id>/preview`).
  It has no tools, panels or keys that edit, no autosave, and no "Save to
  cabinet".
- `POST /api/v1/models/<id>/source` answers **410** with
  `{"error": "Editing models on this site is switched off; …"}`. It is 410
  rather than 404 because the route was retired on purpose, and 404 is what
  this service answers for a model that is not yours. It is answered before
  the model is looked up, so it is the same for every id.
- A model's page says "View in 3D" and notes that no new revisions are made.
  Old revisions stay downloadable.

To turn editing back on, change both halves together:

1. On bob, set `Environment=MODELS_EDITOR=on` in
   `/etc/systemd/system/flutter3d-models.service` and run
   `systemctl daemon-reload`.
2. Run `cloud/tool/deploy.sh`. It reads `MODELS_EDITOR` from the unit and
   passes it to `tool/build_viewer.sh`, which builds the viewer in editor mode
   (`FLUTTER3D_MODELER_MODE=editor`) for `on` and in viewer mode for `off`.
   A unit without the setting stops the deploy before anything is built.

To build the viewer by hand, run `MODELS_EDITOR=on cloud/tool/build_viewer.sh`
(or `off`). Keep the setting in the unit and not in the environment file. The
file overrides the unit, and `deploy.sh` only reads the unit, so a value in the
file would leave the viewer and the server disagreeing.

## Converting

`/convert` turns a source file into the engine's formats online. It accepts
one file, or a `.zip` of a folder: a Unity project folder with its `.meta`
files, a Godot project, or a USD stage with its references and textures. It
reads what `flutter3d convert` reads without outside programs: glTF/GLB,
OBJ+MTL, STL, PLY, USDA/USDZ, MaterialX, Unity `.prefab`/`.unity`/`.mat`, and
Godot `.tscn`/`.tres`. It calls `convertFiles` from
`package:flutter3d_build/convert.dart` through one adapter,
`server/lib/src/convert/converter.dart`.

What comes back depends on the target. **`model`** asks for `convertFiles`'
default, one `.f3d` bundle per input: the model with its lights and cameras,
its materials, its `.f3dmat` programs, a scene's level documents as prefabs
and every file a scene names, all in the `programs`, `prefabs` and `files`
sections of that one file. **`material`** and **`level`** call
`convertFiles(..., bundle: false)` and get the sidecar layout of `flutter3d
convert --split` (`<name>.f3d`, `materials/*.fmat`, `*.f3dmat`, `textures/*`,
`<name>.level.json`), because what they offer are those files: in bundle mode
they would be inside the `.f3d`, and a material result would come back empty.

| | |
|---|---|
| `GET /convert` | The form. Signed out or unconfirmed, it says what is needed instead |
| `POST /api/v1/conversions` | The file as the body, `X-Filename`, `X-Target: model \| material \| level`, `X-CSRF`. `201 {id, path}`, or `{error}` with 401, 403, 413 or 422 |
| `GET /convert/<id>` | The result: its files, and the converter's report of what it mapped, approximated and left behind |
| `GET /convert/<id>/file?path=<path>` | One file. The path is looked up among the result's own files, never joined onto a directory |
| `GET /convert/<id>/all.zip` | Every file, when there is more than one |
| `GET /convert/<id>/as/<format>?path=<path>` | One `.f3d` of the result in another format. See [Downloading in other formats](#downloading-in-other-formats). Written on the first request and kept beside the result for as long as the result is |
| `POST /convert/<id>/save` | Form, `file=<path>` of an `.f3d`. Saves a new model through the same `inspectUpload`, blob store and `models.create` an upload goes through, then redirects to the model's page, which opens in the view-only viewer. What it saves is described below |

Who may convert: any signed-in account with a confirmed address, the same
`canUpload` as uploading. Both POSTs check CSRF the way every other mutating
route does (`X-CSRF`, or the form's `csrf` field).

**There is no rate limit, by decision.** What the server guards against is a
hostile input, not frequent use:

- The upload limit applies as it does to uploads (`MODELS_UPLOAD_LIMIT`).
- Each conversion runs in its own isolate, which is killed after two
  minutes. The person is told it took too long and nothing is kept.
  The isolate is killed rather than abandoned (`Isolate.run` with a timeout
  would leave it running).
- A `.zip` is unpacked by `zip_guard.dart`, which counts inflated bytes as they
  come out and stops at 512 MB for the whole archive, whatever its headers
  claim. A `.usdz`, alone or inside the archive, is measured against the same
  budget before the converter opens it. Entries named `../…`, absolute paths,
  encrypted entries and ZIP64 archives are refused.
- The converters follow the paths a source file names. Here they run under
  `IOOverrides` that answer any path outside the upload as a missing file, so
  a reference to `/etc/passwd` or to another account's blob becomes a "could
  not read" line in the report, not a texture in the download.
- No outside program runs. FBX, `.blend` and binary USD are reported as not
  available online, and the rest of the upload converts.

The isolate shares the process's memory. A file built to exhaust memory
inside the budget, such as an enormous texture, is limited by the deadline and
by the unit's limits, not by the converter.

What can be kept: only models can be saved to My models, because a row in
`models` is a model. Materials (`.fmat`, `.f3dmat`) and levels
(`.level.json` with their prefabs, models and textures) are download-only.
Storing them would need new tables, and the smaller change was chosen.

What "Save to my models" keeps depends on what was sent:

- An upload that is already a format the service stores (`.glb`, `.gltf`,
  `.obj`, `.f3d`, `.f3dproj`, the `SourceFormat` list) is kept as the bytes
  that were sent, not as the converted `.f3d`. A glTF extension the engine
  does not read survives that way. The `.f3d` stays a download.
- A `.gltf` or `.obj` inside a `.zip` that refers to a `.bin`, a `.mtl` or
  textures beside it cannot be stored as one file. It is read with the
  archive around it and kept as a GLB the engine's writer makes of it. A
  self-contained `.gltf` (data URIs) is kept as it is.
- Everything else (Unity, Godot, USD, MaterialX, PLY, STL) keeps the `.f3d`.

The original is used only when the result has exactly one `.f3d` and the
converter's report says that file came from that upload. An archive with a
prefab and an `.obj` beside it keeps the `.f3d`. The decision is made inside
the conversion's isolate, under its deadline. The result page says, under
the button, which file it will keep. The original waits beside the result
(`original` in its directory) and goes when the result does.

Where results live: in memory (the index) and in the system's temporary
directory (the files), which under systemd is the unit's private `/tmp`. They
are kept for one hour for the account that made them and swept every ten
minutes. Another account, or a signed-out request, gets the same 404 an id
that never existed gets. A restart drops them all.

## Downloading in other formats

Every model page and every model in a conversion result has a "Download as…"
menu. It is a `<details>` list of links, so it needs no script (pages allow
only `script-src 'self'`).

| | |
|---|---|
| `GET /files/<id>/as/<format>` | The model's current source in `<format>`. Same access rule as `/files/<id>/source`: `canView`, so anyone for a published model and the owner for a private one. Everyone else, and an unknown format, gets 404. Same `etag` and `cache-control` as the source download (`public, max-age=300` or `private, no-cache`) |
| `GET /convert/<id>/as/<format>?path=<path>` | The same for an `.f3d` in a held result. Only the account that made the result can fetch it, and the answer is never cached (`private, no-store`) |

| `<format>` | What comes back |
|---|---|
| `original` | The stored file, byte for byte |
| `f3d` | `.f3d`, `application/octet-stream` |
| `glb` | `.glb`, `model/gltf-binary` |
| `gltf` | `<name>-gltf.zip`: the `.gltf`, its `.bin`, and `textures/<n>.png` (or `.jpg`) for each image. Written from the GLB by `convert/gltf_files.dart`, because the core has no `.gltf` writer |
| `obj` | `.obj` (`model/obj`), or `<name>-obj.zip` with its `.mtl` and the textures the `.mtl` names when the writer makes more than one file |
| `stl` | Binary `.stl`, `model/stl` |
| `usdz` | `.usdz`, `model/vnd.usdz+zip`. Geometry only, as the core's writer says |

When the stored file already is the format asked for (a `.glb` asked for as
`glb`, an `.f3d` as `f3d`, a self-contained `.gltf` as `gltf`), the stored
file is served and nothing is written, so nothing is lost to a rewrite. The
menu leaves those formats out, since "Original" already offers them. A
modeller project (`.f3dproj`) flattens through `toModelDocument`, the same
function the modeller's own export uses, so it offers every format.

The menu also has **For Blender**, which is the `.glb`, with a line saying
how to open it: File → Import → glTF 2.0. The `.usdz` opens there too,
through File → Import → Universal Scene Description. There is no `.blend`,
because nothing here runs Blender or any other outside program.

How a file is written: the stored source is decoded by the same readers
`inspectUpload` uses (`decodeStoredModel` in `storage/inspect.dart`) and
written by `flutter3d_core`'s `ModelWriter`s. This happens in an isolate of
its own, killed at the same two-minute deadline as `/convert`
(`convert/killable.dart` is the runner both use). If the reader or a writer
refuses, the answer is 422 with its reason. Nobody is rate limited, by the
same decision as converting, but the deadline still applies. Two requests
for the same file in the same format at the same moment wait on one write,
through an in-process in-flight map (`ExportRuns`).

How it is kept: the written file is a blob like any other, recorded in
`model_exports` (migration `006`) under the source's SHA-256, the format,
and `exportWriterVersion` (in `convert/exporter.dart`). The second request
for that key reads the blob, and so does a request from a different model
that holds the same file. A row belongs to its model and is deleted by
cascade with it. `POST /m/<id>/delete` frees the export blobs along with the
source, preview and revisions. A new source (`/api/v1/models/<id>/source`)
drops the rows written from the old one (`dropStaleExports`). In each case
the blobs are freed only when `isReferenced`, which now also checks
`model_exports`, says nothing else points at them. Deleting an account
collects export and revision blobs too. An export finished after its source
was replaced is sent once from memory and not kept. When a writer in
`flutter3d_core` changes what it writes, raise `exportWriterVersion`. The
next request then writes a fresh export, and the old rows go with the next
source change or delete.

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
   `systemctl daemon-reload` is run. The script checks the two settings it
   depends on, `MODELS_EDITOR` (before building) and `MODELS_LEARN_DIR`
   (before it replaces anything). When the unit does not have one of them,
   the script stops and its message lists these two steps.

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

Preview pictures and editing from the cabinet, with revisions, are both
built, though editing is off as deployed (see
[Editing is switched off](#editing-is-switched-off)). The server has no GPU to
render a frame, so a preview is captured in the viewer's own browser
(`canvas.toBlob`) and POSTed to `/api/v1/models/<id>/preview`. With
`MODELS_EDITOR=on`, a save-back goes to `/api/v1/models/<id>/source`, which
keeps the file it replaces as a revision in `model_revisions`, downloadable by
the owner at `/files/<id>/revisions/<revisionId>`. Both endpoints check
ownership and CSRF the same way every other mutating route here does.

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
