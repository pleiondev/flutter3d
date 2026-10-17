# flutter3d_education_lti

LTI 1.3 launch, grade passback and xAPI reporting for flutter3d's lessons and laboratories, in plain Dart. `cloud/lti` serves a lesson viewer over it once a launch verifies.

*Until 1.0.0-rc.1, `flutter3d_lti`, and for a while the `lti.dart` library of [`flutter3d_education`](https://pub.dev/packages/flutter3d_education).* It is a package of its own so that what reads an experiment (the editor, a lesson, the build tool) does not resolve `pointycastle`, `dart_jsonwebtoken` and `http`; it depends on `flutter3d_education` for the experiment a `CheckReporter` reports on.

LTI 1.3 launch and xAPI reporting, for the `edu-03` line of `doc/tooling-plan.md`
(`doc/edu-03-lti-plan.md` has the full plan). It is plain Dart, without `shelf`,
`jaspr` or Flutter, so a service that only needs to verify a launch or file a
grade does not have to carry any of them.

## What is here

- `LtiPlatformSettings` holds one LMS registration (issuer, client ID, deployment
  ID, JWKS URL, auth-login URL), read once from environment variables the
  same way `cloud/lessons`/`cloud/server` already read theirs.
- `OidcLoginInitiation` builds the redirect for LTI's OIDC third-party login
  initiation, with a fresh `state`/`nonce` per login.
- `LtiLaunchValidator` verifies an incoming `id_token`'s signature against the
  platform's JWKS (cached by `kid`), its issuer/audience/expiry, and the
  `state`/`nonce` from the login that started it, then parses the result into
  `LtiLaunchClaims`.
- `AgsClient` gets a Bearer token from the platform through a
  client-credentials grant this tool signs itself (`LtiToolCredentials`),
  then posts an `AgsScore` to a line item's `/scores` endpoint. It caches the
  access token until the token is close to expiring.
- `XapiClient` PUTs an `XapiStatement` (actor/verb/object/result) to a
  Learning Record Store, keyed by the statement's own UUID so a retried
  submission cannot double a student's record.

- `CheckReporter` is the wire from a lesson's `check` questions to both
  clients: each answer becomes an xAPI statement, and each question settled
  updates the score in the platform's gradebook.

## Tests

```bash
dart test
```

`test/support/test_platform.dart` generates a real RSA key pair per test run
and signs real `id_token`s with it, so `LtiLaunchValidator` is tested against an
actual RS256 signature and an actual JWKS document rather than mocks.
