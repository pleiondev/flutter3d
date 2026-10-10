/// The editor's server started over stdin and stdout, with a project's
/// plugins installed: what `bin/editor_mcp.dart` runs, and what a project's
/// own `bin/` runs with the plugins it has.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show EditorPieces, Editing;
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'editor_server.dart';
import 'editor_session.dart';

/// Opens the level [arguments] names and serves it over stdio, offering the
/// MCP tools [plugins] bring beside the editor's own.
///
/// **The plugins are installed here, in a loop that never steps.** A plugin's
/// tools go into an [McpTools] through the plugin host, and the host belongs
/// to an [EngineLoop]; this one is built only to install them and is never
/// run, since the server edits a document and plays nothing. The registry is
/// handed to the server as `projectTools`, so each tool is listed as
/// `<plugin id>.<tool>` and withdrawn if its plugin is switched off.
///
/// **This package compiles in no plugins of its own.** `dart run
/// flutter3d_mcp:editor_mcp` installs none, because which plugins a
/// project has is the project's: a project that wants its plugins' tools
/// offered starts the server from a `bin/` of its own —
///
/// ```dart
/// import 'package:flutter3d_mcp/editor.dart';
/// import 'package:my_game/plugins.g.dart';
///
/// void main(List<String> arguments) =>
///     serveEditorMcp(arguments, plugins: installedPlugins);
/// ```
///
/// — which works for plugins that start under `dart run`, without Flutter.
///
/// A missing argument and an unreadable document are written to stderr and
/// end the process non-zero, before the protocol starts, for the reason
/// `bin/editor_mcp.dart` gives.
EditorMcpServer serveEditorMcp(
  List<String> arguments, {
  List<Flutter3dPlugin> plugins = const <Flutter3dPlugin>[],
}) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run flutter3d_mcp:editor_mcp <level.json>\n'
      'One level document, opened for the life of this process.',
    );
    // The usage code of the `flutter3d` command's contract (`CliExit.usage`
    // in flutter3d_build), so a script reads every flutter3d tool alike.
    exit(2);
  }

  // The plugins' commands as well as their tools: `command.run` reads a
  // plugin's command through the same pieces the editor application fills.
  final tools = McpTools();
  final pieces = EditorPieces();
  EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[tools, pieces],
    plugins: plugins,
  );

  final EditorSession session;
  try {
    final path = arguments.first;
    session = EditorSession(
      Editing.parse(File(path).readAsStringSync(), path: path),
      pieces: pieces,
    );
  } catch (error) {
    stderr.writeln('could not open ${arguments.first}: $error');
    // The failure code of the `flutter3d` command's contract
    // (`CliExit.failure`): a file it could not read.
    exit(1);
  }
  return EditorMcpServer(
    stdioChannel(input: stdin, output: stdout),
    session: session,
    projectTools: tools,
  );
}
