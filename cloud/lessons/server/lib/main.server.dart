/// The service, started.
///
/// No database, no mailer, no sweeper — this is `cloud/server`'s
/// `main.server.dart` with everything an account needs removed, because
/// nothing here has one.
library;

import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'src/config.dart';
import 'src/http/app.dart';

Future<void> main(List<String> arguments) async {
  final Config config;
  try {
    config = readConfig();
  } on ConfigError catch (error) {
    stderr.writeln(error);
    exitCode = 78; // EX_CONFIG
    return;
  }

  final server = await shelf_io.serve(buildHandler(config), InternetAddress.loopbackIPv4, config.port);
  server.autoCompress = true;

  stdout.writeln('lessons on http://${server.address.host}:${server.port}');

  // systemd stops a unit with SIGTERM; answering it lets requests in flight
  // finish instead of being cut off mid-response.
  await ProcessSignal.sigterm.watch().first;
  await server.close();
}
