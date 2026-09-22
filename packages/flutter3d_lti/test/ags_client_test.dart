import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/test_platform.dart';
import 'support/test_rsa_key_pair.dart';

void main() {
  late TestPlatform platform;
  late LtiToolCredentials credentials;

  setUp(() {
    platform = TestPlatform();
    final pair = generateTestRsaKeyPair();
    credentials = LtiToolCredentials(
      clientId: platform.config.clientId,
      kid: 'tool-key-1',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
    );
  });

  test('rejects a platform with no auth token URL', () {
    final noTokenUrl = LtiPlatformConfig(
      issuer: platform.config.issuer,
      clientId: platform.config.clientId,
      deploymentId: platform.config.deploymentId,
      authLoginUrl: platform.config.authLoginUrl,
      jwksUrl: platform.config.jwksUrl,
    );

    expect(
      () => AgsClient(platform: noTokenUrl, credentials: credentials),
      throwsArgumentError,
    );
  });

  test('gets a token then posts a score to <lineitem>/scores', () async {
    Uri? tokenRequestUri;
    Map<String, String>? tokenRequestBody;
    Uri? scoreRequestUri;
    Map<String, String>? scoreRequestHeaders;
    Map<String, dynamic>? scoreRequestBody;

    final client = AgsClient(
      platform: platform.config,
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url == platform.config.authTokenUrl) {
          tokenRequestUri = request.url;
          tokenRequestBody = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({'access_token': 'a-token', 'expires_in': 3600}),
            200,
          );
        }
        if (request.url.toString() ==
            'https://platform.example.test/lineitems/1/scores') {
          scoreRequestUri = request.url;
          scoreRequestHeaders = request.headers;
          scoreRequestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );

    await client.submitScore(
      AgsScore(
        userId: 'student-42',
        scoreGiven: 8,
        scoreMaximum: 10,
        timestamp: DateTime.utc(2026, 9, 15),
      ),
      lineItemUrl: 'https://platform.example.test/lineitems/1',
    );

    expect(tokenRequestUri, platform.config.authTokenUrl);
    expect(tokenRequestBody!['grant_type'], 'client_credentials');
    expect(
      tokenRequestBody!['scope'],
      'https://purl.imsglobal.org/spec/lti-ags/scope/score',
    );

    // The assertion this client signed itself, verified as the platform
    // would verify it: against the *tool's* public key, not the platform's.
    final assertion = JWT.verify(
      tokenRequestBody!['client_assertion']!,
      RSAPublicKey.raw(credentials.publicKey),
    );
    expect(assertion.issuer, credentials.clientId);
    expect(assertion.subject, credentials.clientId);
    expect(assertion.audience?.first, platform.config.authTokenUrl.toString());

    expect(
      scoreRequestUri.toString(),
      'https://platform.example.test/lineitems/1/scores',
    );
    expect(scoreRequestHeaders!['authorization'], 'Bearer a-token');
    expect(
      scoreRequestHeaders!['content-type'],
      'application/vnd.ims.lis.v1.score+json',
    );
    expect(scoreRequestBody, {
      'userId': 'student-42',
      'scoreGiven': 8,
      'scoreMaximum': 10,
      'activityProgress': 'Completed',
      'gradingProgress': 'FullyGraded',
      'timestamp': '2026-09-15T00:00:00.000Z',
    });
  });

  test(
    'reuses the access token across submissions instead of refetching it',
    () async {
      var tokenRequests = 0;
      final client = AgsClient(
        platform: platform.config,
        credentials: credentials,
        httpClient: MockClient((request) async {
          if (request.url == platform.config.authTokenUrl) {
            tokenRequests++;
            return http.Response(
              jsonEncode({'access_token': 'a-token', 'expires_in': 3600}),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );

      for (var i = 0; i < 3; i++) {
        await client.submitScore(
          AgsScore(userId: 'student-42', scoreGiven: i, scoreMaximum: 10),
          lineItemUrl: 'https://platform.example.test/lineitems/1',
        );
      }

      expect(tokenRequests, 1);
    },
  );

  test(
    'throws AgsException when the score endpoint refuses the POST',
    () async {
      final client = AgsClient(
        platform: platform.config,
        credentials: credentials,
        httpClient: MockClient((request) async {
          if (request.url == platform.config.authTokenUrl) {
            return http.Response(
              jsonEncode({'access_token': 'a-token', 'expires_in': 3600}),
              200,
            );
          }
          return http.Response('scope not granted', 403);
        }),
      );

      await expectLater(
        client.submitScore(
          AgsScore(userId: 'student-42', scoreGiven: 1, scoreMaximum: 1),
          lineItemUrl: 'https://platform.example.test/lineitems/1',
        ),
        throwsA(isA<AgsException>()),
      );
    },
  );

  test('throws AgsException when the client-credentials grant fails', () async {
    final client = AgsClient(
      platform: platform.config,
      credentials: credentials,
      httpClient: MockClient((request) async {
        return http.Response('invalid_client', 401);
      }),
    );

    await expectLater(
      client.submitScore(
        AgsScore(userId: 'student-42', scoreGiven: 1, scoreMaximum: 1),
        lineItemUrl: 'https://platform.example.test/lineitems/1',
      ),
      throwsA(isA<AgsException>()),
    );
  });
}
