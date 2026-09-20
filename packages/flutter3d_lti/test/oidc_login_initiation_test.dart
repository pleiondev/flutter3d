import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:test/test.dart';

void main() {
  final platform = LtiPlatformConfig(
    issuer: 'https://platform.example.test',
    clientId: 'tool-client-id',
    deploymentId: 'deployment-1',
    authLoginUrl: Uri.parse('https://platform.example.test/auth'),
    jwksUrl: Uri.parse('https://platform.example.test/.well-known/jwks.json'),
  );
  final initiation = OidcLoginInitiation(
    platform: platform,
    toolLaunchUri: Uri.parse('https://tool.example.test/launch'),
  );

  test('redirects to the platform auth endpoint with the OIDC parameters', () {
    final redirect = initiation.buildRedirect(loginHint: 'student-42');

    expect(redirect.uri.origin, platform.authLoginUrl.origin);
    expect(redirect.uri.path, platform.authLoginUrl.path);
    final params = redirect.uri.queryParameters;
    expect(params['scope'], 'openid');
    expect(params['response_type'], 'id_token');
    expect(params['response_mode'], 'form_post');
    expect(params['prompt'], 'none');
    expect(params['client_id'], platform.clientId);
    expect(params['redirect_uri'], 'https://tool.example.test/launch');
    expect(params['login_hint'], 'student-42');
    expect(params['state'], redirect.state);
    expect(params['nonce'], redirect.nonce);
  });

  test('carries lti_message_hint through when the platform sent one', () {
    final redirect = initiation.buildRedirect(
      loginHint: 'student-42',
      ltiMessageHint: 'opaque-hint',
    );

    expect(redirect.uri.queryParameters['lti_message_hint'], 'opaque-hint');
  });

  test('omits lti_message_hint when the platform sent none', () {
    final redirect = initiation.buildRedirect(loginHint: 'student-42');

    expect(
      redirect.uri.queryParameters.containsKey('lti_message_hint'),
      isFalse,
    );
  });

  test(
    'state and nonce are fresh, unguessable and different from each other',
    () {
      final a = initiation.buildRedirect(loginHint: 'student-42');
      final b = initiation.buildRedirect(loginHint: 'student-42');

      expect(a.state, isNot(equals(a.nonce)));
      expect(a.state, isNot(equals(b.state)));
      expect(a.nonce, isNot(equals(b.nonce)));
      expect(a.state.length, greaterThanOrEqualTo(32));
    },
  );
}
