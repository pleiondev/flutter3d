import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// A real 2048-bit RSA key pair — this tool's own signing identity
/// (`LtiToolCredentials`) when nothing in the environment supplies one, and
/// the same generator a test's fake platform already used privately before
/// this was promoted out of `test/support/` for that second, real caller.
({pc.RSAPublicKey publicKey, pc.RSAPrivateKey privateKey})
generateRsaKeyPair() {
  final keyGen = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        _seededSecureRandom(),
      ),
    );
  final pair = keyGen.generateKeyPair();
  return (publicKey: pair.publicKey, privateKey: pair.privateKey);
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
