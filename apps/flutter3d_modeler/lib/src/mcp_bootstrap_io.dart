/// The real half of `mcp-13n`'s `--mcp-port`: binds a [ModelHttpServer] to
/// the GUI's own live [ModelHistory] and writes the session file an agent
/// reads to find it.
library;

import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:path_provider/path_provider.dart';

import 'mcp_ui_actions.dart';
import 'mcp_ui_tools.dart';

/// The one server this process ever runs — `ModelSession`'s own "one per
/// process, because the project is the state" applies here too: there is
/// nothing for a second [startMcpServer] call to bind to that the first one
/// is not already answering for.
ModelHttpServer? _server;

/// Where [_server]'s own session file was written — held beside it so
/// [stopMcpServer] removes the same file [startMcpServer] wrote, whatever
/// directory that call was given.
File? _sessionFile;

/// Starts listening on `127.0.0.1:$port` (`0` picks any free port) over
/// [history] — the same document a person already has open — and writes
/// the port and token an agent needs into the session file, named
/// `mcp-session.json` inside [sessionDirectory]. A second call while one is
/// already running does nothing, rather than leaking a socket nothing can
/// reach any more.
///
/// [sessionDirectory] defaults to [getApplicationSupportDirectory] — the
/// same directory family `AutosaveController`'s own storage resolves,
/// though this file is its own, independent of that one's format. A test
/// gives a temp directory instead, since `path_provider`'s platform channel
/// has nothing to answer it in a plain `flutter test` run.
///
/// [uiActions] is `mcp-16d`'s own door: null starts the plain document
/// server every headless caller already gets, and a live [UiActions] adds
/// the seven `ui.*` tools beside it — [uiToolsFor] is what turns one into
/// the other.
Future<void> startMcpServer({
  required ModelHistory history,
  required int port,
  UiActions? uiActions,
  Directory? sessionDirectory,
}) async {
  if (_server != null) return;
  final session = ModelSession(history);
  final server = await ModelHttpServer.start(
    session: session,
    port: port,
    extraTools: uiActions == null
        ? const <ModelPictureTool>[]
        : uiToolsFor(uiActions),
  );
  _server = server;
  final dir = sessionDirectory ?? await getApplicationSupportDirectory();
  final file = File('${dir.path}/mcp-session.json');
  _sessionFile = file;
  writeMcpSessionFile(file, port: server.port, token: server.token);
}

/// Closes the server [startMcpServer] opened, if one is running, and
/// removes the session file so nothing reads a port that has gone stale.
Future<void> stopMcpServer() async {
  final server = _server;
  if (server == null) return;
  _server = null;
  await server.close();
  final file = _sessionFile;
  _sessionFile = null;
  if (file != null) deleteMcpSessionFile(file);
}
