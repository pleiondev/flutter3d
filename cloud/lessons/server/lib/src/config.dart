/// Everything the service needs to know that is not in its code.
///
/// Smaller than `cloud/server`'s `Config` on purpose: there is no account, no
/// database, no mail, nothing a person signs into — so there is nothing here
/// to hold a secret. Read once, at start, and never again, the same
/// discipline `cloud/server` uses for the same reason: a setting that could
/// change mid-run is a setting two requests could disagree about.
library;

import 'dart:io';

/// Where the service listens, what it calls itself, and where the built
/// lesson viewer lives.
class Config {
  const Config({
    required this.port,
    required this.baseUrl,
    this.viewerDirectory,
  });

  /// Reads the configuration from the process environment.
  ///
  /// Throws [ConfigError] naming every variable that is missing, rather than
  /// the first one — `cloud/server`'s own reasoning: a deploy three
  /// variables short should say so once.
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

    final config = Config(
      // 8796: on bob, 8793/8794 are the models service and its nginx, 8795
      // is this service's own nginx.
      port: int.tryParse(env['LESSONS_PORT'] ?? '') ?? 8796,
      baseUrl: _withoutTrailingSlash(required('LESSONS_BASE_URL')),
      viewerDirectory: env['LESSONS_VIEWER_DIR'],
    );

    if (missing.isNotEmpty) throw ConfigError(missing);
    return config;
  }

  /// The loopback port nginx proxies to.
  final int port;

  /// What the service calls itself in the embed snippet a lesson page shows
  /// (`<iframe src="$baseUrl/e/<slug>">`) — built from a request's own host
  /// header would be `127.0.0.1` behind the tunnel, the same problem
  /// `cloud/server`'s `baseUrl` solves for its letters.
  final String baseUrl;

  /// The web build of `flutter3d_lesson_viewer`, served under `/app/` — or
  /// null, when nginx serves it and this process should not (production;
  /// see `cloud/lessons/deploy/nginx-lessons.pleion.dev.conf`).
  final String? viewerDirectory;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// What is missing from the environment.
class ConfigError implements Exception {
  const ConfigError(this.missing);

  final List<String> missing;

  @override
  String toString() =>
      'Configuration incomplete. Set: ${missing.join(', ')}.\n'
      'See cloud/lessons/README.md for what each one is.';
}

/// The environment this process was started with.
Config readConfig() => Config.fromEnvironment(Platform.environment);
