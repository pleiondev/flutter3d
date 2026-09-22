import 'dart:convert';

import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:flutter3d_lti_service/src/config.dart';
import 'package:flutter3d_lti_service/src/http/app.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/fake_platform.dart';

void main() {
  late FakePlatform platform;
  late Config config;
  late Handler handler;

  setUp(() {
    platform = FakePlatform(
      issuer: 'https://platform.example.test',
      clientId: 'tool-client-id',
      deploymentId: 'deployment-1',
    );
    config = Config(
      port: 0,
      baseUrl: 'https://lti.example.test',
      platform: platform.config,
    );
    handler = buildHandler(config, validator: platform.buildValidator());
  });

  Future<Response> get(String path) => Future.sync(
    () => handler(Request('GET', Uri.parse('https://lti.example.test$path'))),
  );

  Future<Response> post(String path, Map<String, String> form) => Future.sync(
    () => handler(
      Request(
        'POST',
        Uri.parse('https://lti.example.test$path'),
        body: form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    ),
  );

  group('/health', () {
    test('answers ok', () async {
      final response = await get('/health');
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });
  });

  group('/login', () {
    test('redirects to the platform with a fresh state and nonce', () async {
      final response = await get(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );

      expect(response.statusCode, 302);
      final location = Uri.parse(response.headers['location']!);
      expect(location.origin, 'https://platform.example.test');
      expect(location.queryParameters['response_type'], 'id_token');
      expect(location.queryParameters['client_id'], 'tool-client-id');
      expect(
        location.queryParameters['redirect_uri'],
        'https://lti.example.test/launch',
      );
      expect(location.queryParameters['login_hint'], 'student-42');
      expect(location.queryParameters['state'], isNotEmpty);
      expect(location.queryParameters['nonce'], isNotEmpty);
    });

    test('rejects a login initiation naming a different platform', () async {
      final response = await get(
        '/login?iss=https://someone-elses-platform.test&login_hint=x',
      );

      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('Unknown platform'));
    });
  });

  group('/launch', () {
    test('rejects a request with neither id_token nor state', () async {
      final response = await post('/launch', {});
      expect(response.statusCode, 400);
    });

    test('rejects a state this service never issued', () async {
      final idToken = platform.signLaunch(nonce: 'whatever');
      final response = await post('/launch', {
        'id_token': idToken,
        'state': 'never-issued',
      });

      expect(response.statusCode, 400);
      expect(
        await response.readAsString(),
        contains('expired or never started'),
      );
    });

    test('rejects an id_token that fails verification', () async {
      final loginResponse = await get(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );
      final state = Uri.parse(
        loginResponse.headers['location']!,
      ).queryParameters['state']!;

      final impostor = FakePlatform(
        issuer: platform.issuer,
        clientId: platform.clientId,
        deploymentId: platform.deploymentId,
        kid: 'an-unregistered-key',
      );
      final idToken = impostor.signLaunch(nonce: 'does-not-matter');

      final response = await post('/launch', {
        'id_token': idToken,
        'state': state,
      });

      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('Launch not verified'));
    });

    test('a verified launch redirects into the lesson viewer', () async {
      final loginResponse = await get(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );
      final location = Uri.parse(loginResponse.headers['location']!);
      final state = location.queryParameters['state']!;
      final nonce = location.queryParameters['nonce']!;

      final idToken = platform.signLaunch(nonce: nonce);
      final response = await post('/launch', {
        'id_token': idToken,
        'state': state,
      });

      expect(response.statusCode, 302);
      final viewerUrl = Uri.parse(response.headers['location']!);
      expect(viewerUrl.path, '/app/');
      expect(viewerUrl.queryParameters['level'], 'assets/levels/tour.json');
      expect(viewerUrl.queryParameters['launch'], isNotEmpty);
    });

    test('the same state cannot be redeemed twice', () async {
      final loginResponse = await get(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );
      final location = Uri.parse(loginResponse.headers['location']!);
      final state = location.queryParameters['state']!;
      final nonce = location.queryParameters['nonce']!;
      final idToken = platform.signLaunch(nonce: nonce);

      final first = await post('/launch', {
        'id_token': idToken,
        'state': state,
      });
      expect(first.statusCode, 302);

      final second = await post('/launch', {
        'id_token': idToken,
        'state': state,
      });
      expect(second.statusCode, 400);
      expect(await second.readAsString(), contains('expired or never started'));
    });
  });

  group('unmatched routes', () {
    test('answer 404', () async {
      final response = await get('/nothing-here');
      expect(response.statusCode, 404);
    });
  });

  group('/.well-known/jwks.json', () {
    test('answers an empty key set when no tool key is configured', () async {
      final response = await get('/.well-known/jwks.json');
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {'keys': []});
    });

    test(
      'serves this tool\'s own public key once one is configured — what a '
      "platform fetches to verify AgsClient's client-credentials assertion",
      () async {
        final toolPair = generateRsaKeyPair();
        final localConfig = Config(
          port: 0,
          baseUrl: 'https://lti.example.test',
          platform: platform.config,
          toolCredentials: LtiToolCredentials(
            clientId: platform.clientId,
            kid: 'tool-key-1',
            privateKey: toolPair.privateKey,
            publicKey: toolPair.publicKey,
          ),
        );
        final localHandler = buildHandler(
          localConfig,
          validator: platform.buildValidator(),
        );

        final response = await Future.sync(
          () => localHandler(
            Request(
              'GET',
              Uri.parse('https://lti.example.test/.well-known/jwks.json'),
            ),
          ),
        );

        expect(response.statusCode, 200);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final keys = body['keys'] as List;
        expect(keys, hasLength(1));
        final key = keys.single as Map<String, dynamic>;
        expect(key['kid'], 'tool-key-1');
        expect(key['kty'], 'RSA');
        expect(
          rsaPublicKeyFromJwk(key).key.modulus,
          toolPair.publicKey.modulus,
        );
      },
    );
  });

  group('/launch/<token>/check-result', () {
    /// Runs `/login` then `/launch` through [handler] and returns the
    /// `launch` token the redirect names — the same round trip a real
    /// browser makes, reused here so `check-result` is exercised against a
    /// launch this service actually verified rather than one poked into
    /// its store directly.
    Future<String> launch({Map<String, dynamic> extraClaims = const {}}) async {
      final loginResponse = await get(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );
      final location = Uri.parse(loginResponse.headers['location']!);
      final state = location.queryParameters['state']!;
      final nonce = location.queryParameters['nonce']!;
      final idToken = platform.signLaunch(
        nonce: nonce,
        extraClaims: extraClaims,
      );
      final launchResponse = await post('/launch', {
        'id_token': idToken,
        'state': state,
      });
      final viewerUrl = Uri.parse(launchResponse.headers['location']!);
      return viewerUrl.queryParameters['launch']!;
    }

    Future<Response> postCheckResult(String token, Map<String, Object?> body) =>
        Future.sync(
          () => handler(
            Request(
              'POST',
              Uri.parse('https://lti.example.test/launch/$token/check-result'),
              body: jsonEncode(body),
              headers: {'content-type': 'application/json'},
            ),
          ),
        );

    test('an unknown or expired token is a 404, not a crash', () async {
      final response = await postCheckResult('never-issued', {
        'step': 'quiz-1',
        'correct': true,
      });
      expect(response.statusCode, 404);
    });

    test('a malformed body is a 400', () async {
      final token = await launch();
      final response = await postCheckResult(token, {'step': 'quiz-1'});
      expect(response.statusCode, 400);
    });

    test('a launch with no AGS claim and no LRS configured reports neither, '
        'rather than failing', () async {
      final token = await launch();
      final response = await postCheckResult(token, {
        'step': 'quiz-1',
        'correct': true,
      });
      expect(response.statusCode, 200);
      final result = jsonDecode(await response.readAsString());
      expect(result, {'ags': false, 'xapi': false});
    });

    test('both AGS and xAPI fire at once, when a launch has both — '
        'neither path chosen over the other', () async {
      final toolPair = generateRsaKeyPair();
      final agsPlatform = platform.configWithAgsToken;
      final lineItemUrl = 'https://platform.example.test/lineitems/1';

      Map<String, dynamic>? tokenRequestBody;
      Map<String, dynamic>? scoreBody;
      Map<String, dynamic>? xapiStatement;
      String? xapiAuthHeader;

      final mockClient = MockClient((request) async {
        if (request.url == agsPlatform.authTokenUrl) {
          tokenRequestBody = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({
              'access_token': 'fake-access-token',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url == Uri.parse('$lineItemUrl/scores')) {
          expect(request.headers['authorization'], 'Bearer fake-access-token');
          scoreBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 200);
        }
        if (request.url.origin == 'https://lrs.example.test' &&
            request.url.path == '/statements') {
          xapiAuthHeader = request.headers['authorization'];
          xapiStatement = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204);
        }
        return http.Response('unexpected request: ${request.url}', 500);
      });

      final localConfig = Config(
        port: 0,
        baseUrl: 'https://lti.example.test',
        platform: agsPlatform,
        toolCredentials: LtiToolCredentials(
          clientId: agsPlatform.clientId,
          kid: 'tool-key-1',
          privateKey: toolPair.privateKey,
          publicKey: toolPair.publicKey,
        ),
        lrs: XapiLrsConfig(
          statementsEndpoint: Uri.parse('https://lrs.example.test/statements'),
          authorizationHeader: 'Basic dGVzdDp0ZXN0',
        ),
      );
      final localHandler = buildHandler(
        localConfig,
        validator: platform.buildValidator(),
        httpClient: mockClient,
      );

      Future<Response> localGet(String path) => Future.sync(
        () => localHandler(
          Request('GET', Uri.parse('https://lti.example.test$path')),
        ),
      );
      Future<Response> localPost(
        String path,
        Map<String, String> form,
      ) => Future.sync(
        () => localHandler(
          Request(
            'POST',
            Uri.parse('https://lti.example.test$path'),
            body: form.entries
                .map(
                  (e) =>
                      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
                )
                .join('&'),
            headers: {'content-type': 'application/x-www-form-urlencoded'},
          ),
        ),
      );

      final loginResponse = await localGet(
        '/login?iss=https://platform.example.test&login_hint=student-42',
      );
      final location = Uri.parse(loginResponse.headers['location']!);
      final state = location.queryParameters['state']!;
      final nonce = location.queryParameters['nonce']!;
      final idToken = platform.signLaunch(
        nonce: nonce,
        extraClaims: {
          'https://purl.imsglobal.org/spec/lti-ags/claim/endpoint': {
            'lineitem': lineItemUrl,
            'scope': ['https://purl.imsglobal.org/spec/lti-ags/scope/score'],
          },
        },
      );
      final launchResponse = await localPost('/launch', {
        'id_token': idToken,
        'state': state,
      });
      final token = Uri.parse(
        launchResponse.headers['location']!,
      ).queryParameters['launch']!;

      final response = await Future.sync(
        () => localHandler(
          Request(
            'POST',
            Uri.parse('https://lti.example.test/launch/$token/check-result'),
            body: jsonEncode({'step': 'quiz-1', 'correct': true}),
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {
        'ags': true,
        'xapi': true,
      });
      expect(tokenRequestBody?['grant_type'], 'client_credentials');
      expect(scoreBody?['userId'], 'student-42');
      expect(scoreBody?['scoreGiven'], 1);
      expect(scoreBody?['scoreMaximum'], 1);
      expect(xapiAuthHeader, 'Basic dGVzdDp0ZXN0');
      final actor = xapiStatement?['actor'] as Map<String, dynamic>?;
      final account = actor?['account'] as Map<String, dynamic>?;
      expect(account?['name'], 'student-42');
      final result = xapiStatement?['result'] as Map<String, dynamic>?;
      expect(result?['success'], true);
    });
  });
}
