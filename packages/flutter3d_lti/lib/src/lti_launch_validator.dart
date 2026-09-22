import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'jwk.dart';
import 'lti_launch_claims.dart';
import 'lti_launch_exception.dart';
import 'lti_platform_config.dart';

/// Verifies an LTI 1.3 launch's `id_token` against its platform, and turns
/// the result into [LtiLaunchClaims] or an [LtiLaunchException].
///
/// One instance per [platform] is meant to live for the process, not per
/// request: it caches the platform's JWKS keys by `kid` for [jwksCacheTtl]
/// so a launch does not fetch the keyset every time, the same reasoning
/// `flutter3d_lti`'s only network dependency (`http`) exists for at all.
final class LtiLaunchValidator {
  LtiLaunchValidator({
    required this.platform,
    http.Client? httpClient,
    this.jwksCacheTtl = const Duration(hours: 1),
  }) : _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final LtiPlatformConfig platform;
  final Duration jwksCacheTtl;

  final http.Client _http;
  final bool _ownsHttpClient;

  Map<String, RSAPublicKey>? _cachedKeys;
  DateTime? _cachedAt;

  /// Verifies [idToken] against [platform] and the `state`/`nonce` an
  /// earlier `OidcLoginInitiation.buildRedirect` call handed out.
  ///
  /// [receivedState] and [receivedNonce] come from the launch itself (the
  /// `state` form field, and the `id_token`'s own `nonce` claim once
  /// decoded); [expectedState] and [expectedNonce] are what the caller kept
  /// from the login initiation this launch claims to complete. Checking
  /// both — not just the token's signature — is what stops a captured
  /// `id_token` from a previous, unrelated login from being replayed here.
  Future<LtiLaunchClaims> verify(
    String idToken, {
    required String expectedState,
    required String receivedState,
    required String expectedNonce,
  }) async {
    if (receivedState != expectedState) {
      throw const LtiStateMismatchException();
    }

    final unverified = _decodeUnverified(idToken);
    final kid = unverified.header?['kid'] as String?;
    if (kid == null) {
      throw const LtiTokenInvalidException(
        'id_token header has no "kid"; cannot select a JWKS key',
      );
    }

    final key = await _keyFor(kid);
    final Map<String, dynamic> payload;
    try {
      final verified = JWT.verify(
        idToken,
        key,
        issuer: platform.issuer,
        audience: Audience(<String>[platform.clientId]),
      );
      payload = (verified.payload as Map).cast<String, dynamic>();
    } on JWTExpiredException {
      throw const LtiTokenExpiredException();
    } on JWTException catch (e) {
      throw LtiTokenInvalidException(e.message);
    }

    if (payload['nonce'] != expectedNonce) {
      throw const LtiNonceMismatchException();
    }

    final claims = LtiLaunchClaims.fromPayload(payload);
    if (claims.deploymentId != platform.deploymentId) {
      throw LtiDeploymentMismatchException(
        claims.deploymentId,
        platform.deploymentId,
      );
    }
    return claims;
  }

  /// Frees the HTTP client this validator created, when it created one
  /// itself rather than being handed one to share.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  JWT _decodeUnverified(String idToken) {
    try {
      return JWT.decode(idToken);
    } on JWTException catch (e) {
      throw LtiTokenInvalidException(e.message);
    }
  }

  Future<RSAPublicKey> _keyFor(String kid) async {
    final cachedAt = _cachedAt;
    final cached = _cachedKeys;
    final isFresh =
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < jwksCacheTtl;
    if (isFresh && cached.containsKey(kid)) {
      return cached[kid]!;
    }

    final response = await _http.get(platform.jwksUrl);
    if (response.statusCode != 200) {
      throw LtiTokenInvalidException(
        'fetching JWKS from ${platform.jwksUrl} failed with '
        'HTTP ${response.statusCode}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw LtiTokenInvalidException(
        'JWKS from ${platform.jwksUrl} is not valid JSON',
      );
    }

    final keys = <String, RSAPublicKey>{};
    for (final entry in (body['keys'] as List? ?? const [])) {
      final jwk = (entry as Map).cast<String, dynamic>();
      if (jwk['kty'] != 'RSA') continue;
      final entryKid = jwk['kid'] as String?;
      if (entryKid == null) continue;
      keys[entryKid] = rsaPublicKeyFromJwk(jwk);
    }
    _cachedKeys = keys;
    _cachedAt = DateTime.now();

    final key = keys[kid];
    if (key == null) {
      throw LtiTokenInvalidException(
        'JWKS from ${platform.jwksUrl} has no RSA key with kid "$kid"',
      );
    }
    return key;
  }
}
