import 'lti_platform_config.dart';
import 'random_token.dart';

/// The redirect this tool sends back for a platform's third-party login
/// initiation request, and the two values the caller must keep to check
/// against the launch that follows.
final class OidcLoginRedirect {
  const OidcLoginRedirect({
    required this.uri,
    required this.state,
    required this.nonce,
  });

  /// Where to redirect the browser — the platform's authorization endpoint.
  final Uri uri;

  /// Carry this in a signed cookie or a server-side session keyed by it, not
  /// in anything the browser could replay unchanged. `LtiLaunchValidator`
  /// checks the launch's returned `state` against it.
  final String state;

  /// Checked against the `id_token`'s own `nonce` claim by
  /// `LtiLaunchValidator` — the two checks together are what stops a
  /// captured `id_token` from being replayed against a fresh launch.
  final String nonce;
}

/// Builds the redirect for LTI 1.3's OIDC third-party login initiation
/// (IMS Security Framework §5.1.1): a platform GETs or POSTs this tool's
/// `/login` with `iss`/`login_hint`/`target_link_uri` (and usually
/// `lti_message_hint`), and this tool answers not with content but with a
/// redirect back to the platform's own authorization endpoint, carrying a
/// fresh `state` and `nonce`.
///
/// This class only builds that redirect — it does not read the incoming
/// request or decide the request looks legitimate (that is a route's job in
/// `cloud/lti`, not this package's), and it does not store `state`/`nonce`:
/// the caller does, and hands them back to `LtiLaunchValidator.verify` when
/// the launch (the `id_token` POST to `/launch`) arrives.
final class OidcLoginInitiation {
  const OidcLoginInitiation({
    required this.platform,
    required this.toolLaunchUri,
  });

  final LtiPlatformConfig platform;

  /// This tool's own launch endpoint — where the platform's authorization
  /// server redirects the `id_token` back to (`redirect_uri`).
  final Uri toolLaunchUri;

  /// [loginHint] and [ltiMessageHint] come straight from the platform's
  /// login initiation request, unexamined.
  OidcLoginRedirect buildRedirect({
    required String loginHint,
    String? ltiMessageHint,
  }) {
    final state = randomToken();
    final nonce = randomToken();
    final uri = platform.authLoginUrl.replace(
      queryParameters: <String, String>{
        'scope': 'openid',
        'response_type': 'id_token',
        'response_mode': 'form_post',
        'prompt': 'none',
        'client_id': platform.clientId,
        'redirect_uri': toolLaunchUri.toString(),
        'login_hint': loginHint,
        'state': state,
        'nonce': nonce,
        'lti_message_hint': ?ltiMessageHint,
      },
    );
    return OidcLoginRedirect(uri: uri, state: state, nonce: nonce);
  }
}
