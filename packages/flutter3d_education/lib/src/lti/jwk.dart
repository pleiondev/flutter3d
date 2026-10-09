import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as djwt;
import 'package:pointycastle/export.dart' as pc;

/// Turns one RSA entry of a platform's JWKS (RFC 7517 — a `kty: "RSA"`
/// key with base64url `n`/`e`) into a key `dart_jsonwebtoken` can verify an
/// RS256 signature with.
///
/// `dart_jsonwebtoken`'s own `RSAPublicKey` only parses PEM — a JWKS gives
/// the modulus and exponent as bare base64url integers instead, so this is
/// the one piece of key-format plumbing this package writes itself, and it
/// stops at parsing: `RSAPublicKey.raw` does the rest with the same
/// `pointycastle` type PEM parsing itself builds.
djwt.RSAPublicKey rsaPublicKeyFromJwk(Map<String, dynamic> jwk) {
  final kty = jwk['kty'] as String?;
  if (kty != 'RSA') {
    throw ArgumentError('jwk.kty is "$kty", expected "RSA"');
  }
  final n = jwk['n'] as String?;
  final e = jwk['e'] as String?;
  if (n == null || e == null) {
    throw ArgumentError('jwk is missing "n" or "e"');
  }
  final modulus = _bigIntFromBase64Url(n);
  final exponent = _bigIntFromBase64Url(e);
  return djwt.RSAPublicKey.raw(pc.RSAPublicKey(modulus, exponent));
}

BigInt _bigIntFromBase64Url(String value) {
  final bytes = base64Url.decode(base64Url.normalize(value));
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// The inverse of [rsaPublicKeyFromJwk]: this tool's own public key, as the
/// one JWKS entry `cloud/lti`'s `/.well-known/jwks.json` serves so a
/// platform that registered this tool can verify the client assertion
/// `AgsClient` signs for a client-credentials grant (`lti-01`'s own doc
/// comment on [LtiToolCredentials]).
Map<String, Object?> rsaPublicKeyToJwk(
  pc.RSAPublicKey key, {
  required String kid,
}) {
  return {
    'kty': 'RSA',
    'kid': kid,
    'use': 'sig',
    'alg': 'RS256',
    'n': _base64UrlFromBigInt(key.modulus!),
    'e': _base64UrlFromBigInt(key.exponent!),
  };
}

String _base64UrlFromBigInt(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// This tool's own private half, in the RFC 7518 §6.3.2 private-RSA-key
/// shape (`n`/`e`/`d`/`p`/`q`) — `tool/generate_tool_key.dart` writes one of
/// these to a file once, and `Config.fromEnvironment` reads it back with
/// [rsaPrivateKeyFromJwk]. Not PEM: this package already had a JWK
/// reader/writer for the public half ([rsaPublicKeyFromJwk]/[rsaPublicKeyToJwk]),
/// and PEM's ASN.1 framing buys this tool's own key file nothing that a
/// second JWK does not already give for free.
Map<String, Object?> rsaPrivateKeyToJwk(
  pc.RSAPrivateKey key, {
  required String kid,
}) {
  return {
    'kty': 'RSA',
    'kid': kid,
    'use': 'sig',
    'alg': 'RS256',
    'n': _base64UrlFromBigInt(key.n!),
    'e': _base64UrlFromBigInt(key.publicExponent!),
    'd': _base64UrlFromBigInt(key.privateExponent!),
    'p': _base64UrlFromBigInt(key.p!),
    'q': _base64UrlFromBigInt(key.q!),
  };
}

/// The inverse of [rsaPrivateKeyToJwk].
pc.RSAPrivateKey rsaPrivateKeyFromJwk(Map<String, dynamic> jwk) {
  final kty = jwk['kty'] as String?;
  if (kty != 'RSA') {
    throw ArgumentError('jwk.kty is "$kty", expected "RSA"');
  }
  final n = jwk['n'] as String?;
  final d = jwk['d'] as String?;
  final p = jwk['p'] as String?;
  final q = jwk['q'] as String?;
  if (n == null || d == null || p == null || q == null) {
    throw ArgumentError('jwk is missing one of "n", "d", "p", "q"');
  }
  return pc.RSAPrivateKey(
    _bigIntFromBase64Url(n),
    _bigIntFromBase64Url(d),
    _bigIntFromBase64Url(p),
    _bigIntFromBase64Url(q),
  );
}
