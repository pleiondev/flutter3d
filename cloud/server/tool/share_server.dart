/// The sharing half of the reference server on its own: the `v1/shares`
/// routes over a store in memory, with no database and no pages — what a
/// game's test shares a run through, and what somebody trying sharing on
/// their own machine runs.
///
///     dart run tool/share_server.dart [port]
///
/// Port nought, the default, takes a free one; the first line printed is
/// `listening on <port>`, which is what a test waits for. Moderation is
/// `open`, so a code opens as soon as it is filed: nobody is here to
/// publish it.
library;

import 'dart:io';

import 'package:flutter3d_models/src/config.dart' show ShareModeration;
import 'package:flutter3d_models/src/http/share_routes.dart';
import 'package:flutter3d_models/src/shares/share_service.dart';
import 'package:flutter3d_models/src/shares/share_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> arguments) async {
  final service = ShareService(
    store: MemoryShareStore(),
    moderation: ShareModeration.open,
  );
  final handler = const Pipeline().addHandler(
    (Router()..mount('/api/', shareRoutes(service).call)).call,
  );
  final server = await shelf_io.serve(
    handler.call,
    InternetAddress.loopbackIPv4,
    arguments.isEmpty ? 0 : int.parse(arguments.first),
  );
  stdout.writeln('listening on ${server.port}');
}
