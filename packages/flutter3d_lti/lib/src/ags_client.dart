import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'ags_exception.dart';
import 'ags_score.dart';
import 'lti_platform_config.dart';
import 'lti_tool_credentials.dart';
import 'random_token.dart';

/// The score-passback half of LTI Assignment and Grade Services (IMS
/// AGS §A): gets a Bearer token from the platform via a client-credentials
/// grant, then POSTs a score to a line item's `/scores` endpoint.
///
/// One instance per [platform] is meant to live for the process, the same
/// reasoning `LtiLaunchValidator` caches its JWKS for: the access token this
/// gets is reused across scores until it is close to expiring, not
/// refetched per submission.
final class AgsClient {
  AgsClient({
    required this.platform,
    required this.credentials,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null {
    if (platform.authTokenUrl == null) {
      throw ArgumentError(
        'platform.authTokenUrl is null; AgsClient needs it for the '
        'client-credentials grant',
      );
    }
  }

  static const _scoreScope =
      'https://purl.imsglobal.org/spec/lti-ags/scope/score';

  final LtiPlatformConfig platform;
  final LtiToolCredentials credentials;

  final http.Client _http;
  final bool _ownsHttpClient;

  String? _cachedToken;
  DateTime? _cachedTokenExpiry;

  /// POSTs [score] to [lineItemUrl]'s `/scores` endpoint — the URL
  /// `LtiLaunchClaims.agsLineItemUrl` carried on the launch this score
  /// answers.
  Future<void> submitScore(
    AgsScore score, {
    required String lineItemUrl,
  }) async {
    final token = await _accessToken();
    final uri = Uri.parse('$lineItemUrl/scores');
    final response = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/vnd.ims.lis.v1.score+json',
      },
      body: jsonEncode(score.toJson()),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw AgsException(
        'POST $uri failed with HTTP ${response.statusCode}: '
        '${response.body}',
      );
    }
  }

  /// Frees the HTTP client this client created, when it created one itself.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  Future<String> _accessToken() async {
    final token = _cachedToken;
    final expiry = _cachedTokenExpiry;
    if (token != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return token;
    }

    final response = await _http.post(
      platform.authTokenUrl!,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_assertion_type':
            'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
        'client_assertion': _clientAssertion(),
        'scope': _scoreScope,
      },
    );
    if (response.statusCode != 200) {
      throw AgsException(
        'client-credentials grant at ${platform.authTokenUrl} failed with '
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AgsException(
        'client-credentials response from ${platform.authTokenUrl} is not '
        'valid JSON',
      );
    }
    final accessToken = body['access_token'] as String?;
    if (accessToken == null) {
      throw const AgsException(
        'client-credentials response has no "access_token"',
      );
    }
    final expiresInSeconds = body['expires_in'] as int? ?? 3600;
    _cachedToken = accessToken;
    // A minute of slack so a token does not expire mid-request on a score
    // this client is about to submit with it.
    _cachedTokenExpiry = DateTime.now().add(
      Duration(seconds: expiresInSeconds - 60),
    );
    return accessToken;
  }

  /// The JWT this tool signs to authenticate itself to the platform (IMS
  /// Security Framework §5.4.1): `iss`/`sub` both name this tool's client
  /// ID, `aud` names the token endpoint being asked, and it lives for
  /// minutes, not the hour an access token gets.
  String _clientAssertion() {
    final jwt = JWT(
      {'jti': randomToken()},
      issuer: credentials.clientId,
      subject: credentials.clientId,
      audience: Audience([platform.authTokenUrl.toString()]),
      header: {'kid': credentials.kid},
    );
    return jwt.sign(
      RSAPrivateKey.raw(credentials.privateKey),
      algorithm: JWTAlgorithm.RS256,
      expiresIn: const Duration(minutes: 5),
    );
  }
}
