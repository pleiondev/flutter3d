import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart' as pc;

/// A fake LTI platform for this service's own tests — duplicated from
/// `packages/flutter3d_lti/test/support/test_platform.dart` rather than
/// imported: a package's `test/` directory is not something another
/// package can depend on. Kept to only what `app_test.dart` needs.
final class FakePlatform {
  factory FakePlatform({
    required String issuer,
    required String clientId,
    required String deploymentId,
    String kid = 'fake-platform-key',
  }) {
    final keyGen = pc.RSAKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          _seededSecureRandom(),
        ),
      );
    final pair = keyGen.generateKeyPair();
    return FakePlatform._(
      issuer: issuer,
      clientId: clientId,
      deploymentId: deploymentId,
      kid: kid,
      publicKey: pair.publicKey,
      privateKey: pair.privateKey,
    );
  }

  FakePlatform._({
    required this.issuer,
    required this.clientId,
    required this.deploymentId,
    required this.kid,
    required this.publicKey,
    required this.privateKey,
  });

  final String issuer;
  final String clientId;
  final String deploymentId;
  final String kid;
  final pc.RSAPublicKey publicKey;
  final pc.RSAPrivateKey privateKey;

  Uri get jwksUrl => Uri.parse('$issuer/.well-known/jwks.json');
  Uri get authLoginUrl => Uri.parse('$issuer/auth');

  /// Where `AgsClient`'s client-credentials grant goes (`lti-04`) — null in
  /// [config] until a test that needs AGS asks for [configWithAgsToken],
  /// the same "not every launch has a line item" honest absence
  /// `LtiPlatformConfig.authTokenUrl` itself keeps.
  Uri get authTokenUrl => Uri.parse('$issuer/token');

  LtiPlatformConfig get config => LtiPlatformConfig(
    issuer: issuer,
    clientId: clientId,
    deploymentId: deploymentId,
    authLoginUrl: authLoginUrl,
    jwksUrl: jwksUrl,
  );

  LtiPlatformConfig get configWithAgsToken => LtiPlatformConfig(
    issuer: issuer,
    clientId: clientId,
    deploymentId: deploymentId,
    authLoginUrl: authLoginUrl,
    jwksUrl: jwksUrl,
    authTokenUrl: authTokenUrl,
  );

  /// An `LtiLaunchValidator` for [config] whose HTTP client answers only
  /// this platform's own JWKS URL — the injection point
  /// `cloud/lti/server/lib/src/http/app.dart`'s `buildHandler` exists for.
  LtiLaunchValidator buildValidator() => LtiLaunchValidator(
    platform: config,
    httpClient: MockClient((request) async {
      if (request.url == jwksUrl) {
        return http.Response(jsonEncode(_jwks), 200);
      }
      return http.Response('not found', 404);
    }),
  );

  Map<String, dynamic> get _jwks => {
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

  String signLaunch({
    required String nonce,
    String subject = 'student-42',
    Duration expiresIn = const Duration(minutes: 5),
    Map<String, dynamic> extraClaims = const {},
  }) {
    final jwt = JWT(
      {
        'nonce': nonce,
        'https://purl.imsglobal.org/spec/lti/claim/message_type':
            'LtiResourceLinkRequest',
        'https://purl.imsglobal.org/spec/lti/claim/version': '1.3.0',
        'https://purl.imsglobal.org/spec/lti/claim/deployment_id': deploymentId,
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
      issuer: issuer,
      subject: subject,
      audience: Audience([clientId]),
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

pc.SecureRandom _seededSecureRandom() {
  final secureRandom = pc.FortunaRandom();
  final seedSource = Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
  return secureRandom;
}
