/// Everything the service needs to know that is not in its code.
///
/// One [LtiPlatformConfig], not a list: `doc/edu-03-lti-plan.md` §4 defers
/// multi-platform organisation to the cloud track's team projects and takes
/// "one platform's fields in the environment" as the whole of `edu-03`'s
/// answer until then, the same discipline `cloud/lessons`/`cloud/server`
/// already apply to their own settings — read once, at start, never again.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_lti/flutter3d_lti.dart';
import 'package:pointycastle/export.dart' as pc;

class Config {
  const Config({
    required this.port,
    required this.baseUrl,
    required this.platform,
    this.viewerDirectory,
    this.toolCredentials,
    this.lrs,
  });

  /// Reads the configuration from the process environment.
  ///
  /// Throws [ConfigError] naming every variable that is missing, rather than
  /// the first one — `cloud/lessons`'s own reasoning.
  factory Config.fromEnvironment(Map<String, String> env) {
    final missing = <String>[];

    String required(String name) {
      final value = env[name];
      if (value == null || value.isEmpty) {
        missing.add(name);
        return '';
      }
      return value;
    }

    Uri requiredUri(String name) {
      final value = required(name);
      // `Uri.parse('')` does not throw — an empty placeholder is fine here,
      // it is never read: `missing` being non-empty throws below before
      // this `Config` reaches anything that would dereference it.
      return Uri.parse(value);
    }

    final platform = LtiPlatformConfig(
      issuer: required('LTI_PLATFORM_ISSUER'),
      clientId: required('LTI_PLATFORM_CLIENT_ID'),
      deploymentId: required('LTI_PLATFORM_DEPLOYMENT_ID'),
      authLoginUrl: requiredUri('LTI_PLATFORM_AUTH_LOGIN_URL'),
      jwksUrl: requiredUri('LTI_PLATFORM_JWKS_URL'),
      authTokenUrl: switch (env['LTI_PLATFORM_AUTH_TOKEN_URL']) {
        final String url when url.isNotEmpty => Uri.parse(url),
        _ => null,
      },
    );

    final config = Config(
      // 8798 is this repository's own Moodle sandbox (`cloud/lti/docker-
      // compose.yml`) on a developer's machine — this default is for
      // running this service *alongside* that sandbox locally, so it picks
      // the next port instead. On bob, `lti-05` gives this service 8797/8798
      // (nginx/dart), the pair after `cloud/lessons`'s 8795/8796 — no
      // clash there, a sandbox never runs on bob.
      port: int.tryParse(env['LTI_PORT'] ?? '') ?? 8799,
      baseUrl: _withoutTrailingSlash(required('LTI_BASE_URL')),
      platform: platform,
      viewerDirectory: env['LTI_VIEWER_DIR'],
      toolCredentials: _readToolCredentials(env, platform, missing),
      lrs: _readLrsConfig(env, missing),
    );

    if (missing.isNotEmpty) throw ConfigError(missing);
    return config;
  }

  /// `lti-04`'s AGS half — null exactly when `LTI_TOOL_KEY_FILE` is unset,
  /// the same "an LTI launch with no AGS claim" honest-absence
  /// `LtiLaunchClaims.agsLineItemUrl` already keeps: a deployment that has
  /// not run `tool/generate_tool_key.dart` and registered the result simply
  /// skips score passback rather than failing every launch over it.
  static LtiToolCredentials? _readToolCredentials(
    Map<String, String> env,
    LtiPlatformConfig platform,
    List<String> missing,
  ) {
    final path = env['LTI_TOOL_KEY_FILE'];
    if (path == null || path.isEmpty) return null;

    final Map<String, dynamic> jwk;
    try {
      jwk = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    } on IOException {
      missing.add('LTI_TOOL_KEY_FILE (cannot read "$path")');
      return null;
    }

    final privateKey = rsaPrivateKeyFromJwk(jwk);
    return LtiToolCredentials(
      // IMS Security Framework §5.4.1: a client-credentials grant
      // authenticates with the same `client_id` the platform already
      // registered this tool's launch under — no second identity to keep in
      // step with the first.
      clientId: platform.clientId,
      kid: jwk['kid'] as String? ?? 'flutter3d-lti-1',
      privateKey: privateKey,
      // Derived rather than read a second time: an RSA private key already
      // carries everything its own public half needs (`n`, and `d`/`p`/`q`
      // give `publicExponent` for free via `RSAPrivateKey`'s own
      // constructor) — a separate public-key file would be a second copy of
      // a fact this one already states.
      publicKey: pc.RSAPublicKey(privateKey.n!, privateKey.publicExponent!),
    );
  }

  /// `lti-04`'s xAPI half — null exactly when no LRS is configured, the
  /// second of the two paths `doc/edu-00-interactive-format.md` §10 leaves
  /// to the host and neither of which this service requires.
  static XapiLrsConfig? _readLrsConfig(
    Map<String, String> env,
    List<String> missing,
  ) {
    final endpoint = env['LTI_LRS_STATEMENTS_ENDPOINT'];
    if (endpoint == null || endpoint.isEmpty) return null;

    final auth = env['LTI_LRS_AUTHORIZATION'];
    if (auth == null || auth.isEmpty) {
      missing.add('LTI_LRS_AUTHORIZATION');
      return null;
    }
    return XapiLrsConfig(
      statementsEndpoint: Uri.parse(endpoint),
      authorizationHeader: auth,
    );
  }

  final int port;

  /// This service's own address — `OidcLoginInitiation`'s `toolLaunchUri`
  /// (`$baseUrl/launch`) and the redirect target after a launch verifies
  /// (`$baseUrl/app/?...`) are both built from it, the same problem
  /// `cloud/lessons`'s own `baseUrl` solves for its embed snippet.
  final String baseUrl;

  final LtiPlatformConfig platform;

  /// The web build of `flutter3d_lesson_viewer`, served under `/app/` — or
  /// null, when nginx serves it and this process should not.
  final String? viewerDirectory;

  /// This tool's own signing identity for AGS score passback (`lti-04`) —
  /// null when this deployment has not run `tool/generate_tool_key.dart`
  /// and pointed `LTI_TOOL_KEY_FILE` at the result, in which case a check
  /// result still reaches the LRS (if [lrs] is configured) but never the
  /// platform's own gradebook.
  final LtiToolCredentials? toolCredentials;

  /// Where a `check` result's xAPI statement goes (`lti-04`) — null when no
  /// Learning Record Store is configured, `doc/edu-00-interactive-format.md`
  /// §10's own "a result need not go anywhere in particular" left open.
  final XapiLrsConfig? lrs;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

class ConfigError implements Exception {
  const ConfigError(this.missing);

  final List<String> missing;

  @override
  String toString() =>
      'Configuration incomplete. Set: ${missing.join(', ')}.\n'
      'See cloud/lti/README.md for what each one is.';
}

Config readConfig() => Config.fromEnvironment(Platform.environment);
