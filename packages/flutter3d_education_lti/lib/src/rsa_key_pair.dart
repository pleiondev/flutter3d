import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// A real 2048-bit RSA key pair — this tool's own signing identity
/// (`LtiToolCredentials`) when nothing in the environment supplies one, and
/// the same generator a test's fake platform already used privately before
/// this was promoted out of `test/support/` for that second, real caller.
RsaKeyPair generateRsaKeyPair() {
  final keyGen = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        _seededSecureRandom(),
      ),
    );
  final pair = keyGen.generateKeyPair();
  return RsaKeyPair(publicKey: pair.publicKey, privateKey: pair.privateKey);
}

/// An RSA key pair, as [generateRsaKeyPair] makes one: the half a platform
/// verifies with and the half this tool signs with.
final class RsaKeyPair {
  /// The pair of [publicKey] and the [privateKey] that matches it.
  const RsaKeyPair({required this.publicKey, required this.privateKey});

  /// The half that verifies, published as a JWK.
  final pc.RSAPublicKey publicKey;

  /// The half that signs, kept secret.
  final pc.RSAPrivateKey privateKey;

  @override
  bool operator ==(Object other) =>
      other is RsaKeyPair &&
      other.publicKey == publicKey &&
      other.privateKey == privateKey;

  @override
  int get hashCode => Object.hash(publicKey, privateKey);

  @override
  String toString() => 'RsaKeyPair(${publicKey.modulus?.bitLength} bits)';
}

/// A `pointycastle` `SecureRandom` seeded from `dart:math`'s
/// `Random.secure()` — key generation needs one and none of
/// `pointycastle`'s own registered generators self-seeds.
pc.SecureRandom _seededSecureRandom() {
  final secureRandom = pc.FortunaRandom();
  final seedSource = math.Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
  return secureRandom;
}
