/// Everything the service needs to know that is not in its code.
///
/// **Read once, at start, and never again.** A setting that can change while
/// the process runs is a setting two requests can disagree about, and the
/// service has nothing that would benefit from it. A missing setting stops the
/// start rather than the first request that needs it: a mail key that is only
/// found to be absent when somebody registers has already cost a registration.
library;

import 'dart:io';

/// Where the service listens, what it calls itself, and the secrets it holds.
class Config {
  const Config({
    required this.port,
    required this.baseUrl,
    required this.databaseUrl,
    required this.blobDirectory,
    required this.mailFrom,
    required this.resendApiKey,
    required this.sessionSecret,
    required this.uploadLimitBytes,
    this.assetsDirectory = 'web/assets',
    this.viewerDirectory,
    this.learnDirectory = 'content/learn/modeler',
  });

  /// Reads the configuration from the process environment.
  ///
  /// Throws [ConfigError] naming every variable that is missing, rather than
  /// the first one: a deploy that is three variables short should say so once.
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

    // The mail key is the one secret with a legitimate absence: without it the
    // service prints letters to the log instead of sending them, which is what
    // development wants and what a test can read.
    final resendApiKey = env['MODELS_RESEND_API_KEY'];

    final config = Config(
      // 8794: on bob, 8790–8792 are the documentation site, tooth and its API,
      // and 8793 is the nginx that sits in front of this.
      port: int.tryParse(env['MODELS_PORT'] ?? '') ?? 8794,
      baseUrl: _withoutTrailingSlash(required('MODELS_BASE_URL')),
      databaseUrl: required('MODELS_DATABASE_URL'),
      blobDirectory: required('MODELS_BLOB_DIR'),
      mailFrom: env['MODELS_MAIL_FROM'] ?? 'models@pleion.dev',
      resendApiKey: resendApiKey?.isEmpty ?? true ? null : resendApiKey,
      sessionSecret: required('MODELS_SECRET'),
      uploadLimitBytes:
          int.tryParse(env['MODELS_UPLOAD_LIMIT'] ?? '') ?? 100 * 1024 * 1024,
      // The directory whose files answer `/assets/<name>` — the mount strips
      // the prefix, so this is `web/assets`, not `web`.
      assetsDirectory: env['MODELS_ASSETS_DIR'] ?? 'web/assets',
      viewerDirectory: env['MODELS_VIEWER_DIR'],
      learnDirectory: env['MODELS_LEARN_DIR'] ?? 'content/learn/modeler',
    );

    if (missing.isNotEmpty) throw ConfigError(missing);
    return config;
  }

  /// The loopback port nginx proxies to.
  final int port;

  /// What the service calls itself in links it puts into letters.
  ///
  /// Behind a tunnel the request's own host header is the loopback address, so
  /// a verification link built from it would point at `127.0.0.1`.
  final String baseUrl;

  final String databaseUrl;

  /// Where uploaded files live, addressed by their own SHA-256.
  final String blobDirectory;

  final String mailFrom;

  /// Absent in development: letters go to the log instead.
  final String? resendApiKey;

  /// Signs the short-lived download links the viewer is handed.
  final String sessionSecret;

  /// The largest upload accepted, in bytes.
  ///
  /// A hundred megabytes by default, because that is what a free Cloudflare
  /// tunnel passes: accepting more here would only move the failure to a place
  /// with no error message in it.
  final int uploadLimitBytes;

  /// The stylesheet and the two small scripts, served under `/assets/`.
  ///
  /// A directory rather than bytes in the binary, because nginx serves the same
  /// directory in production and the service only has to in development.
  final String assetsDirectory;

  /// The web build of the modeller, served under `/app/` — or null, when nginx
  /// serves it and this process should not.
  final String? viewerDirectory;

  /// The tutorial's Markdown, one file a case, served under `/learn/modeler/`.
  ///
  /// **A setting, because the default only works from a checkout.** It is a
  /// path relative to the working directory, which is `cloud/server` when
  /// somebody runs the service by hand and `/opt/flutter3d-models` under
  /// systemd, where there is no `content/` at all. The pages were read from the
  /// relative path with nothing to override it, the deploy copied no Markdown
  /// anywhere, and an absent directory reads as an empty tutorial by design —
  /// so production would have served the index with nothing on it and said
  /// nothing.
  final String learnDirectory;

  /// Whether letters are actually sent.
  bool get sendsMail => resendApiKey != null;

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
      'See cloud/README.md for what each one is.';
}

/// The environment this process was started with.
Config readConfig() => Config.fromEnvironment(Platform.environment);
