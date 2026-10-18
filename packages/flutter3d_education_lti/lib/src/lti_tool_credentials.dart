import 'package:pointycastle/export.dart' as pc;

/// This tool's own signing identity — the half of LTI Advantage nobody
/// verifying an `id_token` needs, and exactly what `AgsClient` needs to ask
/// a platform for a Bearer token.
///
/// A client-credentials grant (IMS Security Framework §5.4) authenticates
/// this tool to the platform with a JWT *this tool* signs and hands over as
/// `client_assertion` — the mirror image of `LtiLaunchValidator` verifying a
/// JWT the *platform* signed. `cloud/lti` is expected to serve [publicKey]
/// at its own `/.well-known/jwks.json` under [kid], so a platform that
/// registered this tool can check the assertion the same way this package
/// checks the platform's `id_token`.
final class LtiToolCredentials {
  /// This tool's identity at one platform: [clientId] and the key pair
  /// published under [kid].
  const LtiToolCredentials({
    required this.clientId,
    required this.kid,
    required this.privateKey,
    required this.publicKey,
  });

  /// This tool's client ID at the platform — also the assertion's `iss` and
  /// `sub` (IMS Security Framework §5.4.1: both name the client, there is
  /// no separate "user" a client-credentials grant is signing in as).
  final String clientId;

  /// The key id the assertion's header carries, and the one [publicKey] is
  /// served under in this tool's JWKS, so the platform picks the right key.
  final String kid;

  /// The half that signs each client assertion with RS256; kept secret.
  final pc.RSAPrivateKey privateKey;

  /// The half the platform verifies the assertion with, published under
  /// [kid].
  final pc.RSAPublicKey publicKey;
}
