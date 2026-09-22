# Registering `cloud/lti` as an external tool in the Moodle sandbox

For `lti-06` (`doc/edu-03-lti-plan.md`), against the Moodle brought up by
`docker-compose.yml`. Every label and URL below is read out of Moodle
5.0.2's own source (`mod/lti/edit_form.php`, `mod/lti/locallib.php`,
`mod/lti/lang/en/lti.php`) inside the running sandbox container, not
recalled from memory or an older Moodle version — a click-through in a
browser has not confirmed the *navigation path* reads exactly this in the
rendered UI (this session had no browser to drive), so treat the menu
labels as very likely right and the field names/URLs as exact.

## 1. Sign in

<http://localhost:8798>, `admin` / `flutter3d-lti-sandbox` (from
`docker-compose.yml`'s `MOODLE_PASSWORD`).

## 2. Open "Manage preconfigured tools"

Site administration → Plugins → Activity modules → **External tool** →
**Manage preconfigured tools** (`/mod/lti/toolconfigure.php`) → **Add
preconfigured tool**.

## 3. Fill in the form

| Field | Value |
|---|---|
| Tool name | `flutter3d-lti (sandbox)` |
| Tool URL | `cloud/lti`'s own base URL, e.g. `http://host.docker.internal:8797/` — a placeholder until `lti-03` exists; Moodle stores it but does not call it during registration |
| LTI version | **LTI 1.3** |
| Public key type | **Keyset URL** (Moodle's default; the alternative, pasting a raw RSA key, is not what `cloud/lti` will use) |
| Public keyset URL | `cloud/lti`'s own JWKS endpoint — `lti-01`'s risk note already expects this at `/.well-known/jwks.json`, e.g. `http://host.docker.internal:8797/.well-known/jwks.json` |
| Initiate login URL | `cloud/lti`'s `/login` route — `OidcLoginInitiation`'s counterpart, e.g. `http://host.docker.internal:8797/login` |
| Redirection URI(s) | `cloud/lti`'s `/launch` route — one per line if there is ever more than one, e.g. `http://host.docker.internal:8797/launch` |

`host.docker.internal` rather than `localhost`: the Moodle *container* is
what resolves these URLs (to build the launch's `id_token` and to fetch the
JWKS), and `localhost` inside that container is the container itself, not
the host machine `cloud/lti` runs on. Docker Desktop resolves
`host.docker.internal` to the host from inside a container; this matters
once `lti-03` is a real service to launch against; today the values just
need to be *present* for Moodle to accept the form.

## 4. Save, then read the generated values

Saving opens **"Tool configuration details"** (`get_string`s of the same
names, `mod/lti/lang/en/lti.php`):

| Label shown | Where it comes from | For a Moodle at `http://localhost:8798` |
|---|---|---|
| Platform ID | `$CFG->wwwroot` — the site's own base URL | `http://localhost:8798` |
| Client ID | `registration_helper::get()->new_clientid()` — a fresh random string per tool | shown in the modal; copy it |
| Deployment ID | `$type->id` — the tool type's own row id, a plain integer | usually `1` for the first tool registered on a fresh site |
| Public keyset URL | fixed path | `http://localhost:8798/mod/lti/certs.php` |
| Access token URL | fixed path | `http://localhost:8798/mod/lti/token.php` |
| Authentication request URL | fixed path | `http://localhost:8798/mod/lti/auth.php` |

These five feed `LtiPlatformConfig` directly:

```dart
LtiPlatformConfig(
  issuer: 'http://localhost:8798',               // Platform ID
  clientId: '<copied from the modal>',            // Client ID
  deploymentId: '<copied from the modal>',         // Deployment ID, as a string
  authLoginUrl: Uri.parse('http://localhost:8798/mod/lti/auth.php'),
  jwksUrl: Uri.parse('http://localhost:8798/mod/lti/certs.php'),
  authTokenUrl: Uri.parse('http://localhost:8798/mod/lti/token.php'),
)
```

## 5. Add it to a course

A registered tool type is not itself a launchable link — a course activity
of type "External tool" pointed at it is. Create a course (or use Moodle's
default "Test course 1" if one exists), add an activity, choose **External
tool**, and pick this tool from **Preconfigured tool**. Opening that
activity as a student (or as admin, which Moodle lets through with a
warning) is the LTI 1.3 launch `lti-03`/`lti-07` need to answer.

## 6. Canvas

Not here — `doc/edu-03-lti-plan.md` §5 takes it as its own step. Canvas's
own external-app registration screen asks for the same five values in the
other direction (Moodle above is the *platform*; a Canvas launch would work
the same way once Canvas is in `docker-compose.yml`), so nothing about
`LtiPlatformConfig` or `LtiLaunchValidator` changes for it — only which
platform's issuer/URLs are configured.
