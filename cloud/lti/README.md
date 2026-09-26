# cloud/lti

`edu-03` (`doc/edu-03-lti-plan.md`): LTI 1.3 launch and grade/xAPI
passback, on top of the `packages/flutter3d_lti` client library
(`lti-00` to `lti-02`, closed). It is its own service on its own subdomain,
for the same reasons `cloud/lessons/README.md` gives for sitting apart from
`cloud/server`. The audience is different: an LMS launching this tool with a
student's identity, not a person opening their own model cabinet. So is the
protocol: LTI's OIDC launch, not this repository's own accounts.

## What is here

| | |
|---|---|
| `server/` | One Dart process (`lti-03`): `/login` (OIDC third-party login initiation), `/launch` (verifies the `id_token`, opens the lesson viewer), `/app/` |
| `docker-compose.yml` | A throwaway Moodle (`lti-06`) to develop and launch against locally: `bitnamilegacy/moodle` + `bitnamilegacy/mariadb`, brought up and verified booting in this session |
| `moodle-sandbox-setup.md` | Registering this tool as a Moodle external LTI 1.3 tool. Every field name and generated URL in it was read out of the sandbox's own Moodle 5.0.2 source, not recalled from memory |

## Running the sandbox

```bash
docker-compose -f cloud/lti/docker-compose.yml up -d
docker logs -f lti-moodle-1   # until it prints "Moodle setup finished!"
```

<http://localhost:8798>, `admin` / `flutter3d-lti-sandbox`. First boot takes
about a minute; Moodle's own installer does that work, not this compose file.
Then follow
`moodle-sandbox-setup.md`.

Canvas is not here yet. `doc/edu-03-lti-plan.md` §5 treats it as a separate,
heavier step so that this one does not wait on it.

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

Every setting is read once at start. If any required one is missing, the
service refuses to start and names everything that is missing. Without
`LTI_VIEWER_DIR` set, `/app/` answers 404, the same as in `cloud/lessons`. To
see a launch actually land on a lesson instead of only redirecting toward one,
build the viewer first (`apps/flutter3d_lesson_viewer`) and point
`LTI_VIEWER_DIR` at it.

| Variable | |
|---|---|
| `LTI_BASE_URL` | This service's own address. `OidcLoginInitiation`'s `redirect_uri` and the redirect into `/app/` are both built from it |
| `LTI_PORT` | Default 8799 (8798 is this repository's own Moodle sandbox above, on the same machine) |
| `LTI_PLATFORM_ISSUER` / `_CLIENT_ID` / `_DEPLOYMENT_ID` / `_AUTH_LOGIN_URL` / `_JWKS_URL` | One platform's registration. Per `doc/edu-03-lti-plan.md` §4 there is no organisation model yet, so the environment holds one set of these |
| `LTI_PLATFORM_AUTH_TOKEN_URL` | Optional; the AGS half of `lti-04` needs it |
| `LTI_TOOL_KEY_FILE` | Optional. This tool's own signing identity for AGS, from `dart run tool/generate_tool_key.dart <path>`. Without it no line item ever gets a score |
| `LTI_LRS_STATEMENTS_ENDPOINT` / `_AUTHORIZATION` | Optional, both or neither; the xAPI half of `lti-04` |
| `LTI_VIEWER_DIR` | Optional; serves the lesson viewer at `/app/` when set |

### Tests

```bash
cd cloud/lti/server && dart test
```

`test/support/fake_platform.dart` generates a real RSA key pair and signs
real `id_token`s. That is the same check `flutter3d_lti`'s own tests make,
applied here to this service's routes instead of the library underneath them.

### What was actually run against the sandbox above (2026-09-15)

No browser was available in this session to click through Moodle's admin UI
and register the tool for real, so the full loop (course link → `/login` →
platform login → `/launch` → lesson) is not proven end to end; see
`doc/edu-03-lti-plan.md` §7. Two things are proven. The real sandbox's
`/mod/lti/certs.php` JWKS parses through `flutter3d_lti`'s own JWK code
unmodified. And a real `cloud/lti/server` process's `/login` reached the real
sandbox's `/mod/lti/auth.php` and got back an HTTP 200, not a connection
failure.

## Deploying

```bash
cloud/lti/tool/deploy.sh
```

The script builds the executable in a `linux/amd64` Dart container, builds the
viewer, rsyncs both to `bob:/opt/flutter3d-lti` and restarts the unit. The
container gets `packages/flutter3d_lti` copied in alongside `cloud/lti/server`,
because this service depends on it by path; `cloud/lessons` depends on no
engine package and does not need that.

### The first time

As in the "first time" section of `cloud/lessons/README.md`, each step below
creates something outside this repository.

1. **Environment**: copy `deploy/flutter3d-lti.env.example` to
   `/etc/flutter3d-lti.env`, mode 600, and fill in the real platform
   registration (`LTI_PLATFORM_ISSUER` and the rest) once a real LMS has
   registered this tool. `moodle-sandbox-setup.md` shows where those five
   values come from for a Moodle.

2. **Service**: copy `deploy/flutter3d-lti.service` to `/etc/systemd/system/`,
   run `systemctl enable flutter3d-lti`, then run `tool/deploy.sh`.

3. **nginx**: copy `deploy/nginx-lti.pleion.dev.conf` to `sites-available`,
   link it into `sites-enabled`, then `nginx -t && systemctl reload nginx`.
   Every location strips `X-Frame-Options`. That file's own comment explains
   why an LTI tool needs the opposite of `models.pleion.dev`'s framing policy,
   and what the proper fix (per-platform `frame-ancestors`) would need.

4. **Tunnel**: this service gets a tunnel of its own, not an ingress rule
   added to another service's:

   ```bash
   cloudflared tunnel create flutter3d-lti
   ```

   Put the printed ID into `deploy/cloudflared-lti.yml`, copy that to
   `/etc/cloudflared/lti.yml`, then add the DNS route with the config and the
   tunnel ID named explicitly (`cloud/README.md` documents the mistake this
   avoids):

   ```bash
   cloudflared --config /etc/cloudflared/lti.yml \
     tunnel route dns --overwrite-dns <TUNNEL_ID> lti.pleion.dev
   ```

   Then enable `deploy/cloudflared-lti.service`.

### Where it runs

- Executable: `bob:/opt/flutter3d-lti/lti`, run by `flutter3d-lti.service` as
  a dynamic user
- nginx: `127.0.0.1:8797`, serving `/app/` from disk and proxying everything
  else to the service on `127.0.0.1:8798`
- Tunnel: `cloudflared-lti.service`

The ports are the next free pair after `cloud/lessons`'s `8795`/`8796`. Before
the first deploy, confirm nothing else on `bob` already holds `8797`/`8798`.

## What is not here yet

- `lti-04`: wiring a launch's `check` result to `AgsClient`/`XapiClient`.
- A real platform registration. The fields in
  `deploy/flutter3d-lti.env.example` stay empty until an actual LMS (not this
  sandbox) registers this tool.
- Canvas in `docker-compose.yml`, which is a separate, heavier step of
  `lti-06`.
