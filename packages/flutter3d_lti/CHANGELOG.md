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
