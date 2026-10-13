import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

/// Why `AgsClient` could not get a score to the platform's gradebook —
/// the client-credentials grant failed, or the scores endpoint refused the
/// POST. Carries the platform's own response text in [message] rather than
/// swallowing it: an AGS failure is usually a scope the platform never
/// granted this deployment, and that only shows up in the response body.
final class AgsException extends ResourceException {
  const AgsException(this.message);

  @override
  final String message;

  @override
  String toString() => 'AgsException: $message';
}
