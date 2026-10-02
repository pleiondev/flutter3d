/// The service, started.
///
/// **One process, pages and API together.** Every page is a jaspr component
/// rendered on the server and handed to shelf as a response, so a form handler
/// and the page it redirects to run in the same isolate against the same pool,
/// with no second service to keep in step.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:jaspr/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'main.server.options.dart';
import 'src/config.dart';
import 'src/content/learn_content.dart';
import 'src/db/database.dart';
import 'src/http/app.dart';
import 'src/mail/mailer.dart';
import 'src/services.dart';
import 'src/storage/blob_store.dart';
import 'src/telemetry/telemetry_service.dart';

Future<void> main(List<String> arguments) async {
  Jaspr.initializeApp(options: defaultServerOptions);

  final Config config;
  try {
    config = readConfig();
  } on ConfigError catch (error) {
    stderr.writeln(error);
    exitCode = 78; // EX_CONFIG
    return;
  }

  // Not a reason to stop: see [learnDirectoryProblem].
  if (learnDirectoryProblem(config.learnDirectory) case final problem?) {
    stderr.writeln(problem);
  }

  // N7. Not a reason to stop either: a broken level costs its own runs.
  final (
    telemetryLevels,
    levelProblems,
  ) = switch (config.telemetryLevelsDirectory) {
    final directory? => readTelemetryLevels(directory),
    null => (<String, Level>{}, <String>[]),
  };
  levelProblems.forEach(stderr.writeln);

  final db = await Database.open(config.databaseUrl);
  final services = Services(
    config: config,
    db: db,
    mailer: switch (config.resendApiKey) {
      final key? => ResendMailer(apiKey: key, from: config.mailFrom),
      null => ConsoleMailer(),
    },
    blobs: FileBlobStore(config.blobDirectory),
    // No games: every genre in the repository needs Flutter, which a server
    // started with `dart run` does not have. A deploy that plays one builds
    // its own entry point and names it here.
    telemetryLevels: telemetryLevels,
  );
  Services.instance = services;

  final server = await shelf_io.serve(
    buildHandler(services),
    InternetAddress.loopbackIPv4,
    config.port,
  );
  server.autoCompress = true;

  // Expired sessions, spent letters and old attempts. Hourly, because nothing
  // reads an expired row as valid — every query checks the time — so the sweep
  // is housekeeping and not a security boundary.
  final sweeper = Timer.periodic(const Duration(hours: 1), (_) async {
    try {
      await services.sessions.sweep();
      await services.tokens.sweep();
      await services.limiter.sweep();
    } catch (error) {
      stderr.writeln('sweep failed: $error');
    }
  });

  final sharing = services.shares.takesShares
      ? 'sharing in ${config.shareModeration.name} mode'
      : 'sharing off: review mode with no moderator token';
  stdout.writeln(
    'models on http://${server.address.host}:${server.port} '
    '(${config.sendsMail ? 'sending mail' : 'printing mail to the log'}; '
    '$sharing)',
  );

  // systemd stops a unit with SIGTERM; answering it lets requests in flight
  // finish instead of being cut off mid-upload.
  await ProcessSignal.sigterm.watch().first;
  sweeper.cancel();
  await server.close();
  await db.close();
}
