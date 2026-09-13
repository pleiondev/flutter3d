/// The web half of `mcp-13n`'s `--mcp-port`: a no-op. `flutter3d_model_mcp`
/// reaches `dart:io`'s `HttpServer`, which does not exist in a browser, and
/// `--mcp-port` naming a socket nothing outside the tab could connect to
/// anyway is not a flag a web build has any use offering.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

Future<void> startMcpServer({
  required ModelHistory history,
  required int port,
}) async {}

Future<void> stopMcpServer() async {}
