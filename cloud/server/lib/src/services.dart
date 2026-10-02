/// Everything a request handler or a page reaches for, built once at start.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show HeadlessGame, Level;

import 'auth/accounts.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/email_tokens_repository.dart';
import 'db/metrics_repository.dart';
import 'db/models_repository.dart';
import 'db/projects_repository.dart';
import 'db/rate_limit.dart';
import 'db/sessions_repository.dart';
import 'db/shares_repository.dart';
import 'db/telemetry_repository.dart';
import 'db/users_repository.dart';
import 'http/cookies.dart';
import 'http/gallery_catalogue.dart';
import 'mail/mailer.dart';
import 'shares/share_service.dart';
import 'storage/blob_store.dart';
import 'telemetry/telemetry_service.dart';

class Services {
  Services({
    required this.config,
    required this.db,
    required this.mailer,
    required this.blobs,
    GalleryCatalogue? gallery,
    Map<String, HeadlessGame> telemetryGames = const <String, HeadlessGame>{},
    Map<String, Level> telemetryLevels = const <String, Level>{},
  }) : gallery = gallery ?? const FixedCatalogue(),
       telemetry = TelemetryService(
         games: telemetryGames,
         levels: telemetryLevels,
         store: TelemetryRepository(db),
       ),
       shares = ShareService(
         store: SharesRepository(db),
         moderation: config.shareModeration,
         moderatorToken: config.shareModeratorToken,
         reportsToHide: config.shareReportsToHide,
       ),
       users = UsersRepository(db),
       sessions = SessionsRepository(db),
       tokens = EmailTokensRepository(db),
       models = ModelsRepository(db),
       projects = ProjectsRepository(db),
       metrics = MetricsRepository(db),
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

  /// `gal-07`: what `/gallery/` answers from.
  ///
  /// **Empty by default, and that is a working server rather than a broken
  /// one.** A deploy with no keys configured offers nothing it cannot
  /// reach and says nothing it cannot verify; the modeller falls back to
  /// the sixteen models it builds itself, which is why its gallery works
  /// on a laptop with no network at all.
  final GalleryCatalogue gallery;
  final Mailer mailer;
  final BlobStore blobs;

  /// N7: runs sent with a player's consent, played again and binned.
  ///
  /// **Empty unless a deploy hands it games and levels**, and an empty one
  /// answers every run with why it took none. The games are [HeadlessGame]s
  /// this process can step, so they are chosen in code where the server is
  /// built; the levels come from `MODELS_TELEMETRY_LEVELS_DIR`.
  final TelemetryService telemetry;

  /// N10: levels shared behind short codes.
  ///
  /// **Refuses every share until somebody can moderate them**, unless the
  /// deploy chose `MODELS_SHARES_MODERATION=open`: in review, a level nobody
  /// could ever publish is a level kept for nothing.
  final ShareService shares;

  final UsersRepository users;
  final SessionsRepository sessions;
  final EmailTokensRepository tokens;
  final ModelsRepository models;
  final ProjectsRepository projects;
  final MetricsRepository metrics;
  final RateLimiter limiter;
  final CookiePolicy cookies;
  late final Accounts accounts;
}
