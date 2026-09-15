/// Everything a request handler or a page reaches for, built once at start.
library;

import 'auth/accounts.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/email_tokens_repository.dart';
import 'db/models_repository.dart';
import 'db/projects_repository.dart';
import 'db/rate_limit.dart';
import 'db/sessions_repository.dart';
import 'db/users_repository.dart';
import 'http/cookies.dart';
import 'mail/mailer.dart';
import 'storage/blob_store.dart';

class Services {
  Services({
    required this.config,
    required this.db,
    required this.mailer,
    required this.blobs,
  }) : users = UsersRepository(db),
       sessions = SessionsRepository(db),
       tokens = EmailTokensRepository(db),
       models = ModelsRepository(db),
       projects = ProjectsRepository(db),
       limiter = RateLimiter(db),
       cookies = CookiePolicy.forBaseUrl(config.baseUrl) {
    accounts = Accounts(
      users: users,
      sessions: sessions,
      tokens: tokens,
      models: models,
      limiter: limiter,
      mailer: mailer,
      blobs: blobs,
      baseUrl: config.baseUrl,
    );
  }

  /// **The one global, and why it is one.** A jaspr component is built by the
  /// framework, not by this code, so there is no constructor to hand it a
  /// database through; an inherited component would carry the same object
  /// through every level of every page to reach the three that need it. The
  /// process holds exactly one of these, set before the server listens.
  static late Services instance;

  final Config config;
  final Database db;
  final Mailer mailer;
  final BlobStore blobs;

  final UsersRepository users;
  final SessionsRepository sessions;
  final EmailTokensRepository tokens;
  final ModelsRepository models;
  final ProjectsRepository projects;
  final RateLimiter limiter;
  final CookiePolicy cookies;
  late final Accounts accounts;
}
