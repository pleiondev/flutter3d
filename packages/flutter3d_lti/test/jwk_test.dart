/// `lti-04`: this tool's own key round-trips through the same JWK shape
/// [rsaPublicKeyFromJwk] already reads off a platform — proven both ways,
/// since this file is now the writer as well as the reader.
library;

import 'package:flutter3d_lti/src/jwk.dart';
import 'package:test/test.dart';

import 'support/test_rsa_key_pair.dart';

void main() {
  final pair = generateTestRsaKeyPair();

  group('rsaPublicKeyToJwk / rsaPublicKeyFromJwk', () {
    test('round-trips a public key through the JWK shape a JWKS carries', () {
      final jwk = rsaPublicKeyToJwk(pair.publicKey, kid: 'tool-key-1');

      expect(jwk['kty'], 'RSA');
      expect(jwk['kid'], 'tool-key-1');
      expect(jwk['alg'], 'RS256');

      final parsed = rsaPublicKeyFromJwk(jwk);
      expect(parsed.key.modulus, pair.publicKey.modulus);
      expect(parsed.key.exponent, pair.publicKey.exponent);
    });
  });

  group('rsaPrivateKeyToJwk / rsaPrivateKeyFromJwk', () {
    test('round-trips a private key through RFC 7518 §6.3.2 fields', () {
      final jwk = rsaPrivateKeyToJwk(pair.privateKey, kid: 'tool-key-1');

      expect(jwk['kty'], 'RSA');
      expect(jwk.keys, containsAll(<String>['n', 'e', 'd', 'p', 'q']));

      final parsed = rsaPrivateKeyFromJwk(jwk);
      expect(parsed.n, pair.privateKey.n);
      expect(parsed.privateExponent, pair.privateKey.privateExponent);
      expect(parsed.p, pair.privateKey.p);
      expect(parsed.q, pair.privateKey.q);
    });

    test('rejects a jwk missing a required field', () {
      expect(
        () => rsaPrivateKeyFromJwk(const {'kty': 'RSA', 'n': 'x'}),
        throwsArgumentError,
      );
    });

    test('rejects a jwk that is not an RSA key', () {
      expect(
        () => rsaPrivateKeyFromJwk(const {'kty': 'oct'}),
        throwsArgumentError,
      );
    });
  });
}
