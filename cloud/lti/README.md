# cloud/lti

`edu-03` (`doc/edu-03-lti-plan.md`): LTI 1.3 launch and grade/xAPI
passback, on top of the `packages/flutter3d_lti` client library
(`lti-00`–`lti-02`, closed). Its own service, its own subdomain, the same
reasoning `cloud/lessons/README.md` gives for sitting apart from
`cloud/server` — a different audience (an LMS launching this tool with a
student's identity, not a person's own model cabinet) and a different
protocol (LTI's OIDC launch, not this repository's own accounts).

## What is here

| | |
|---|---|
| `server/` | One Dart process (`lti-03`): `/login` (OIDC third-party login initiation), `/launch` (verifies the `id_token`, opens the lesson viewer), `/app/` |
| `docker-compose.yml` | A throwaway Moodle (`lti-06`) to develop and launch against locally — `bitnamilegacy/moodle` + `bitnamilegacy/mariadb`, brought up and verified booting in this session |
| `moodle-sandbox-setup.md` | Registering this tool as a Moodle external LTI 1.3 tool — every field name and generated URL read out of the sandbox's own Moodle 5.0.2 source, not recalled from memory |

## Running the sandbox

```bash
docker-compose -f cloud/lti/docker-compose.yml up -d
docker logs -f lti-moodle-1   # until it prints "Moodle setup finished!"
```

<http://localhost:8798>, `admin` / `flutter3d-lti-sandbox`. First boot takes
about a minute (Moodle's own installer, not this compose file, does the
work). Then `moodle-sandbox-setup.md`.

Canvas is not here yet — `doc/edu-03-lti-plan.md` §5 takes it as its own,
heavier step rather than blocking this one on it.

## Running the service

```bash
cd cloud/lti/server
dart pub get

LTI_BASE_URL=http://localhost:8799 \
LTI_PLATFORM_ISSUER=<Platform ID from moodle-sandbox-setup.md> \
LTI_PLATFORM_CLIENT_ID=<Client ID from the same> \
LTI_PLATFORM_DEPLOYMENT_ID=<Deployment ID from the same> \
LTI_PLATFORM_AUTH_LOGIN_URL=http://localhost:8798/mod/lti/auth.php \
LTI_PLATFORM_JWKS_URL=http://localhost:8798/mod/lti/certs.php \
dart run lib/main.server.dart
```

Every setting is read once at start; a missing required one stops the start
naming everything that is missing. Without `LTI_VIEWER_DIR` set, `/app/`
answers 404 — same as `cloud/lessons`, build the viewer first
(`apps/flutter3d_lesson_viewer`) and point it there to see a launch actually
land on a lesson rather than just redirect toward one.

| Variable | |
|---|---|
| `LTI_BASE_URL` | This service's own address — `OidcLoginInitiation`'s `redirect_uri` and the redirect into `/app/` are both built from it |
| `LTI_PORT` | Default 8799 (8798 is this repository's own Moodle sandbox above, on the same machine) |
| `LTI_PLATFORM_ISSUER` / `_CLIENT_ID` / `_DEPLOYMENT_ID` / `_AUTH_LOGIN_URL` / `_JWKS_URL` | One platform's registration — `doc/edu-03-lti-plan.md` §4: no organisation model yet, one set of these in the environment |
| `LTI_PLATFORM_AUTH_TOKEN_URL` | Optional — `lti-04`'s AGS half needs it |
| `LTI_TOOL_KEY_FILE` | Optional — this tool's own signing identity for AGS, from `dart run tool/generate_tool_key.dart <path>`. No line item ever gets a score without it |
| `LTI_LRS_STATEMENTS_ENDPOINT` / `_AUTHORIZATION` | Optional, both or neither — `lti-04`'s xAPI half |
| `LTI_VIEWER_DIR` | Optional; serves the lesson viewer at `/app/` when set |

### Tests

```bash
cd cloud/lti/server && dart test
```

`test/support/fake_platform.dart` generates a real RSA key pair and signs
real `id_token`s — the same proof `flutter3d_lti`'s own tests give, applied
to this service's routes rather than the library underneath them.

### What was actually run against the sandbox above (2026-09-15)

No browser was available this session to click through Moodle's admin UI
and register the tool for real, so the full loop (course link → `/login` →
platform login → `/launch` → lesson) is not proven end to end — see `doc/
edu-03-lti-plan.md` §7. What is proven: the real sandbox's `/mod/lti/
certs.php` JWKS parses through `flutter3d_lti`'s own JWK code unmodified,
and a real `cloud/lti/server` process's `/login` reached the real sandbox's
`/mod/lti/auth.php` and got back an HTTP 200, not a connection failure.

## Deploying

```bash
cloud/lti/tool/deploy.sh
```

Builds the executable in a `linux/amd64` Dart container (`packages/
flutter3d_lti` copied in alongside `cloud/lti/server`, since this service
depends on it by path — unlike `cloud/lessons`, which depends on no engine
package), builds the viewer, rsyncs both to `bob:/opt/flutter3d-lti` and
restarts the unit.

### The first time

Same reasoning as `cloud/lessons/README.md`'s own "first time" section —
each step below creates something outside this repository.

1. **Environment** — `deploy/flutter3d-lti.env.example` to
   `/etc/flutter3d-lti.env`, mode 600, with the real platform registration
   (`LTI_PLATFORM_ISSUER` and the rest) once a real LMS has registered this
   tool — `moodle-sandbox-setup.md` shows where those five values come from
   for a Moodle.

2. **Service** — `deploy/flutter3d-lti.service` to `/etc/systemd/system/`,
   `systemctl enable flutter3d-lti`, then run `tool/deploy.sh`.

3. **nginx** — `deploy/nginx-lti.pleion.dev.conf` to `sites-available`,
   linked into `sites-enabled`, `nginx -t && systemctl reload nginx`. Every
   location strips `X-Frame-Options` — see that file's own comment for why
   an LTI tool needs the opposite of `models.pleion.dev`'s framing policy,
   and what the honest (per-platform `frame-ancestors`) fix would need.

4. **Tunnel** — its own, not an ingress rule added to another service's:

   ```bash
   cloudflared tunnel create flutter3d-lti
   ```

   the printed ID into `deploy/cloudflared-lti.yml` copied to
   `/etc/cloudflared/lti.yml`, then the DNS route **with the config and the
   tunnel ID named explicitly** (`cloud/README.md` documents the exact
   mistake this flag avoids):

   ```bash
   cloudflared --config /etc/cloudflared/lti.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> lti.pleion.dev
   ```

   Then enable `deploy/cloudflared-lti.service`.

### Where it runs

- **Executable** — `bob:/opt/flutter3d-lti/lti`, run by
  `flutter3d-lti.service` as a dynamic user
- **nginx** — `127.0.0.1:8797`, serving `/app/` from disk and proxying
  everything else to the service on `127.0.0.1:8798`
- **Tunnel** — `cloudflared-lti.service`

Ports chosen as the next free pair after `cloud/lessons`'s `8795`/`8796` —
confirm nothing else on `bob` already holds `8797`/`8798` before the first
deploy.

## What is not here yet

- **`lti-04`** — wiring a launch's `check` result to `AgsClient`/`XapiClient`.
- **A real platform registration** — `deploy/flutter3d-lti.env.example`'s
  fields are empty until an actual LMS (not this sandbox) registers this
  tool for real.
- **Canvas** in `docker-compose.yml` — its own, heavier step of `lti-06`.
