/// One LMS registration this tool can be launched from.
///
/// Set once from environment variables when a service starts — the same
/// pattern `LESSONS_BASE_URL`/`MODELS_SECRET` already read once at start in
/// `cloud/lessons`/`cloud/server` — not a row in a database. `doc/
/// edu-03-lti-plan.md` §4 explains why: LTI's own idea of an "organization"
/// waits for the cloud track's team projects, and until then one platform is
/// one set of these fields, not a tenant.
final class LtiPlatformConfig {
  const LtiPlatformConfig({
    required this.issuer,
    required this.clientId,
    required this.deploymentId,
    required this.authLoginUrl,
    required this.jwksUrl,
    this.authTokenUrl,
  });

  /// The platform's `iss` — what a launch's `id_token` must claim, and what
  /// the third-party login initiation request names itself.
  final String issuer;

  /// This tool's client ID at the platform, checked against the `id_token`'s
  /// `aud`.
  final String clientId;

  /// The one deployment of this tool at the platform, checked against the
  /// `id_token`'s `https://purl.imsglobal.org/spec/lti/claim/deployment_id`.
  ///
  /// A platform can deploy the same tool more than once (different course,
  /// different contract); a single [LtiPlatformConfig] names exactly one of
  /// those, the same way `LtiPlatformConfig` names exactly one platform.
  final String deploymentId;

  /// Where the OIDC third-party login initiation redirects to — the
  /// platform's authorization endpoint.
  final Uri authLoginUrl;

  /// Where this tool fetches the platform's public keys to verify an
  /// `id_token`'s signature.
  final Uri jwksUrl;

  /// The platform's OAuth2 token endpoint, for the client-credentials grant
  /// `AgsClient` (`lti-01`) uses to get a Bearer token before posting a
  /// score. Null for a platform this tool only ever launches from without
  /// grading — `LtiLaunchValidator` never reads this field.
  final Uri? authTokenUrl;
}
