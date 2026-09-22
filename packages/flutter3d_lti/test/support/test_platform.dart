import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart' as pc;

import 'test_rsa_key_pair.dart';

/// A whole fake LTI platform for a test: an RSA key pair, a JWKS response
/// carrying its public half, and a way to mint `id_token`s signed with the
/// private half — so `LtiLaunchValidator` is proven against a real RS256
/// signature and a real JWKS document, not a mock of either.
final class TestPlatform {
  factory TestPlatform({
    String issuer = 'https://platform.example.test',
    String clientId = 'tool-client-id',
    String deploymentId = 'deployment-1',
    String kid = 'test-key-1',
  }) {
    final pair = generateTestRsaKeyPair();

    return TestPlatform._(
      config: LtiPlatformConfig(
        issuer: issuer,
        clientId: clientId,
        deploymentId: deploymentId,
        authLoginUrl: Uri.parse('$issuer/auth'),
        jwksUrl: Uri.parse('$issuer/.well-known/jwks.json'),
        authTokenUrl: Uri.parse('$issuer/token'),
      ),
      kid: kid,
      publicKey: pair.publicKey,
      privateKey: pair.privateKey,
    );
  }

  TestPlatform._({
    required this.config,
    required this.kid,
    required this.publicKey,
    required this.privateKey,
  });

  final LtiPlatformConfig config;
  final String kid;
  final pc.RSAPublicKey publicKey;
  final pc.RSAPrivateKey privateKey;

  /// A JWKS document a real platform's `jwksUrl` would answer with.
  Map<String, dynamic> get jwks => {
    'keys': [
      {
        'kty': 'RSA',
        'kid': kid,
        'use': 'sig',
        'alg': 'RS256',
        'n': _base64UrlBigInt(publicKey.modulus!),
        'e': _base64UrlBigInt(publicKey.exponent!),
      },
    ],
  };

  /// A `MockClient` (`package:http/testing.dart`) that answers this
  /// platform's JWKS URL and nothing else — a launch validator given this
  /// client reaches no real network.
  http.Client get httpClient => MockClient((request) async {
    if (request.url == config.jwksUrl) {
      return http.Response(jsonEncode(jwks), 200);
    }
    return http.Response('not found', 404);
  });

  /// Signs an `id_token` as this platform would for a resource link launch,
  /// with sensible LTI claims a test can override piecemeal.
  String signLaunch({
    required String nonce,
    String subject = 'student-42',
    String? audience,
    Duration expiresIn = const Duration(minutes: 5),
    Map<String, dynamic> extraClaims = const {},
  }) {
    final jwt = JWT(
      {
        'nonce': nonce,
        'https://purl.imsglobal.org/spec/lti/claim/message_type':
            'LtiResourceLinkRequest',
        'https://purl.imsglobal.org/spec/lti/claim/version': '1.3.0',
        'https://purl.imsglobal.org/spec/lti/claim/deployment_id':
            config.deploymentId,
        'https://purl.imsglobal.org/spec/lti/claim/target_link_uri':
            'https://tool.example.test/launch',
        'https://purl.imsglobal.org/spec/lti/claim/roles': [
          'http://purl.imsglobal.org/vocab/lis/v2/membership#Learner',
        ],
        'https://purl.imsglobal.org/spec/lti/claim/resource_link': {
          'id': 'resource-link-1',
        },
        ...extraClaims,
      },
      issuer: config.issuer,
      subject: subject,
      audience: Audience([audience ?? config.clientId]),
      header: {'kid': kid},
    );
    return jwt.sign(
      RSAPrivateKey.raw(privateKey),
      algorithm: JWTAlgorithm.RS256,
      expiresIn: expiresIn,
    );
  }
}

String _base64UrlBigInt(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64Url.encode(bytes).replaceAll('=', '');
}
