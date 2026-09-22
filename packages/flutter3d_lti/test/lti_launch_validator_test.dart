import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_platform.dart';

void main() {
  late TestPlatform platform;
  late LtiLaunchValidator validator;

  setUp(() {
    platform = TestPlatform();
    validator = LtiLaunchValidator(
      platform: platform.config,
      httpClient: platform.httpClient,
    );
  });

  test('verifies a well-formed launch and parses its claims', () async {
    final idToken = platform.signLaunch(nonce: 'nonce-1');

    final claims = await validator.verify(
      idToken,
      expectedState: 'state-1',
      receivedState: 'state-1',
      expectedNonce: 'nonce-1',
    );

    expect(claims.subject, 'student-42');
    expect(claims.deploymentId, platform.config.deploymentId);
    expect(claims.messageType, LtiMessageType.resourceLinkRequest);
    expect(claims.resourceLinkId, 'resource-link-1');
    expect(claims.roles, contains(contains('Learner')));
  });

  test('parses the AGS endpoint claim when the platform grants it', () async {
    final idToken = platform.signLaunch(
      nonce: 'nonce-1',
      extraClaims: {
        'https://purl.imsglobal.org/spec/lti-ags/claim/endpoint': {
          'scope': ['https://purl.imsglobal.org/spec/lti-ags/scope/score'],
          'lineitem': 'https://platform.example.test/lineitems/1',
        },
      },
    );

    final claims = await validator.verify(
      idToken,
      expectedState: 's',
      receivedState: 's',
      expectedNonce: 'nonce-1',
    );

    expect(claims.agsLineItemUrl, 'https://platform.example.test/lineitems/1');
    expect(
      claims.agsScopes,
      contains('https://purl.imsglobal.org/spec/lti-ags/scope/score'),
    );
  });

  test('rejects a launch whose state does not match the login', () async {
    final idToken = platform.signLaunch(nonce: 'nonce-1');

    await expectLater(
      validator.verify(
        idToken,
        expectedState: 'expected',
        receivedState: 'forged',
        expectedNonce: 'nonce-1',
      ),
      throwsA(isA<LtiStateMismatchException>()),
    );
  });

  test('rejects a launch whose nonce does not match the login', () async {
    final idToken = platform.signLaunch(nonce: 'actual-nonce');

    await expectLater(
      validator.verify(
        idToken,
        expectedState: 's',
        receivedState: 's',
        expectedNonce: 'a-different-nonce',
      ),
      throwsA(isA<LtiNonceMismatchException>()),
    );
  });

  test('rejects an expired id_token', () async {
    final idToken = platform.signLaunch(
      nonce: 'nonce-1',
      expiresIn: const Duration(seconds: -10),
    );

    await expectLater(
      validator.verify(
        idToken,
        expectedState: 's',
        receivedState: 's',
        expectedNonce: 'nonce-1',
      ),
      throwsA(isA<LtiTokenExpiredException>()),
    );
  });

  test('rejects an id_token for a different audience', () async {
    final idToken = platform.signLaunch(
      nonce: 'nonce-1',
      audience: 'someone-elses-client-id',
    );

    await expectLater(
      validator.verify(
        idToken,
        expectedState: 's',
        receivedState: 's',
        expectedNonce: 'nonce-1',
      ),
      throwsA(isA<LtiTokenInvalidException>()),
    );
  });

  test(
    'rejects an id_token naming a deployment this tool does not know',
    () async {
      final idToken = platform.signLaunch(
        nonce: 'nonce-1',
        extraClaims: {
          'https://purl.imsglobal.org/spec/lti/claim/deployment_id':
              'some-other-deployment',
        },
      );

      await expectLater(
        validator.verify(
          idToken,
          expectedState: 's',
          receivedState: 's',
          expectedNonce: 'nonce-1',
        ),
        throwsA(isA<LtiDeploymentMismatchException>()),
      );
    },
  );

  test(
    'rejects an id_token signed by a key the platform never published',
    () async {
      final impostor = TestPlatform(
        issuer: platform.config.issuer,
        clientId: platform.config.clientId,
        deploymentId: platform.config.deploymentId,
        kid: 'a-key-id-not-in-the-real-jwks',
      );
      final idToken = impostor.signLaunch(nonce: 'nonce-1');

      await expectLater(
        validator.verify(
          idToken,
          expectedState: 's',
          receivedState: 's',
          expectedNonce: 'nonce-1',
        ),
        throwsA(isA<LtiTokenInvalidException>()),
      );
    },
  );

  test('caches JWKS keys instead of fetching them on every launch', () async {
    var requests = 0;
    final countingValidator = LtiLaunchValidator(
      platform: platform.config,
      httpClient: _CountingClient(platform.httpClient, () => requests++),
    );

    for (var i = 0; i < 3; i++) {
      final idToken = platform.signLaunch(nonce: 'nonce-$i');
      await countingValidator.verify(
        idToken,
        expectedState: 's',
        receivedState: 's',
        expectedNonce: 'nonce-$i',
      );
    }

    expect(requests, 1);
  });
}

/// Wraps another client and counts every request that passes through it —
/// enough to prove `LtiLaunchValidator` reuses its JWKS cache rather than
/// fetching it once per launch.
final class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner, this._onRequest);

  final http.Client _inner;
  final void Function() _onRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    _onRequest();
    return _inner.send(request);
  }
}
