## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

**The first publication, at the shelf's number rather than a first of its
own.** The 0.1.0 below is the number this package carried on the `edu-track`
branch, where it was written; it never reached pub.dev. The whole workspace
goes out on one number so that one number names one tree, and `^0.7.0` on any
`flutter3d_*` package resolves against every other — a package joining at 0.1.0
would be the one line in the graph nobody could write that constraint against.

Nothing in it changed on the way across: it names no sibling at all, only
`dart_jsonwebtoken`, which is why it could come over on its own while the rest
of that branch waits.

## 0.1.0

* **OIDC login and `id_token` verification (`lti-00`).**
  `LtiPlatformConfig`, `OidcLoginInitiation`, `LtiLaunchValidator` and
  `LtiLaunchClaims`.
* **AGS score passback (`lti-01`).** `AgsClient` gets a Bearer token from the
  platform via a client-credentials grant this tool signs itself
  (`LtiToolCredentials`), then posts an `AgsScore` to a line item's
  `/scores` endpoint. The access token is cached until it is close to
  expiring.
* **xAPI reporting (`lti-02`).** `XapiClient` PUTs an `XapiStatement`
  (actor/verb/object/result, built from `XapiActor.fromLtiSubject` and a
  handful of common `XapiVerb`s) to a Learning Record Store.
* `cloud/lti`, the service that wires a launch's `check` result to both of
  the above, is not here yet — see `doc/edu-03-lti-plan.md` (`lti-03`,
  `lti-04`).
