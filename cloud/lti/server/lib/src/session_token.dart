import 'dart:convert';
import 'dart:math';

final Random _secureRandom = Random.secure();

/// A URL-safe random token with 256 bits of entropy — the same shape
/// `flutter3d_lti`'s own `state`/`nonce` use, but this package does not
/// depend on that package's private `random_token.dart` for it: a session
/// token identifies this service's own record, not an OIDC value the LTI
/// spec gives a name to.
String generateSessionToken() {
  final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
