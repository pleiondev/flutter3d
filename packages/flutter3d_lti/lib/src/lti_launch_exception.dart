/// Why `LtiLaunchValidator.verify` refused a launch. A sealed hierarchy, not
/// one class with a message: a caller (a `cloud/lti` route, deciding what to
/// tell a browser) can `switch` on which check failed rather than parsing a
/// string, and `dart_jsonwebtoken`'s own exceptions never leak past this
/// package's boundary — nothing outside `lti_launch_validator.dart` needs to
/// import it to catch what it throws.
sealed class LtiLaunchException implements Exception {
  const LtiLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The `state` this launch returned does not match the one its login
/// initiation handed out — either a forged launch, or a launch replayed
/// against the wrong session.
final class LtiStateMismatchException extends LtiLaunchException {
  const LtiStateMismatchException()
    : super('state does not match the one this login started with');
}

/// The `id_token`'s signature, issuer, audience, expiry or structure failed
/// verification — wraps whatever `dart_jsonwebtoken` or the JWKS fetch found
/// wrong, named in [message].
final class LtiTokenInvalidException extends LtiLaunchException {
  const LtiTokenInvalidException(super.message);
}

/// The `id_token`'s signature and every OIDC check passed, but its `exp` is
/// in the past. Split from [LtiTokenInvalidException] because an expired
/// launch usually means "the browser sat on this page too long, try again",
/// not "something is misconfigured" — the two want different messages to a
/// student.
final class LtiTokenExpiredException extends LtiLaunchException {
  const LtiTokenExpiredException() : super('id_token has expired');
}

/// The `id_token`'s `nonce` does not match the one this login started with.
final class LtiNonceMismatchException extends LtiLaunchException {
  const LtiNonceMismatchException()
    : super('nonce does not match the one this login started with');
}

/// The `id_token`'s `deployment_id` claim does not name the deployment
/// [LtiPlatformConfig] registered — either a different placement of the same
/// tool at the platform, or a platform sending a deployment this tool was
/// never told about.
final class LtiDeploymentMismatchException extends LtiLaunchException {
  const LtiDeploymentMismatchException(String claimed, String expected)
    : super(
        'deployment_id "$claimed" does not match the registered '
        '"$expected"',
      );
}
