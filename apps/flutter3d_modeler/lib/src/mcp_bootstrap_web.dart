/// The web half of `mcp-13n`'s `--mcp-port`: a no-op. `flutter3d_mcp/model.dart`
/// reaches `dart:io`'s `HttpServer`, which does not exist in a browser, and
/// `--mcp-port` naming a socket nothing outside the tab could connect to
/// anyway is not a flag a web build has any use offering.
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'mcp_ui_actions.dart';

/// Does nothing: a browser has no socket to listen on. Every argument is
/// the native half's, taken so the call site reads the same on both.
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

/// Does nothing, there being no server to stop.
Future<void> stopMcpServer() async {}

/// Does nothing, there being no server holding a history.
void rebindMcpHistory(ModelHistory history) {}
