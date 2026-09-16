/// The web half of `mcp-13n`'s `--mcp-port`: a no-op. `flutter3d_model_mcp`
/// reaches `dart:io`'s `HttpServer`, which does not exist in a browser, and
/// `--mcp-port` naming a socket nothing outside the tab could connect to
/// anyway is not a flag a web build has any use offering.
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'mcp_ui_actions.dart';

Future<void> startMcpServer({
  required ModelHistory history,
  required int port,
  UiActions? uiActions,
  String? sessionPath,
  void Function(
    String toolName,
    Map<String, Object?> arguments,
    ({bool did, String says, Uint8List? png}) answer,
    Duration elapsed,
  )?
  onToolCall,
  void Function(String clientName)? onInitialize,
  String? Function()? pausedBecause,
}) async {}

Future<void> stopMcpServer() async {}
