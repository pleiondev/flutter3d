import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

/// Why `XapiClient.send` could not deliver a statement to the LRS.
final class XapiException extends ResourceException {
  const XapiException(this.message);

  @override
  final String message;

  @override
  String toString() => 'XapiException: $message';
}
