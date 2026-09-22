import 'dart:convert';
import 'dart:math' as math;

final math.Random _secureRandom = math.Random.secure();

/// A URL-safe random token with 256 bits of entropy — `state` and `nonce`
/// are both this, per the OIDC third-party login initiation this package
/// builds (`OidcLoginInitiation`). No `uuid` dependency: a UUID's 122 random
/// bits are already more than the ones below, and this repository does not
/// take a package for what nine lines of `dart:math`/`dart:convert` do.
String randomToken() {
  final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
