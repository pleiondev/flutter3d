/// The modeller's server started over stdin and stdout, offering a project's
/// plugin tools: what `bin/model_mcp.dart` runs, and what a project's own
/// `bin/` runs with the tools its plugins brought.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_mcp/kit.dart';

import 'model_server.dart';
import 'model_session.dart';

/// Opens the project [arguments] names and serves it over stdio, offering
/// [projectTools] beside the modeller's own.
///
/// **The registry rather than the plugins.** Installing a plugin takes a
/// plugin host, which belongs to `flutter3d_sim`'s `EngineLoop`, and this
/// package depends on no simulation. So a project that wants its plugins'
/// tools offered installs them where it already does — a loop handed the
/// registry among its `registries` — and starts the server from a `bin/` of
/// its own with that registry:
///
/// ```dart
/// void main(List<String> arguments) {
///   final tools = McpTools();
///   EngineLoop(input: InputState(), registries: [tools],
///       plugins: installedPlugins);
///   serveModelMcp(arguments, projectTools: tools);
/// }
/// ```
///
/// `dart run flutter3d_mcp:model_mcp` hands it an empty one, which
/// lists nothing beside the modeller's tools until something is added.
///
/// `--help` prints the usage and returns null; a wrong argument count or a
/// project that will not parse is written to stderr and ends the process
/// non-zero, before the protocol starts, for the reason `bin/model_mcp.dart`
/// gives.
ModelMcpServer? serveModelMcp(
  List<String> arguments, {
  McpTools? projectTools,
}) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stderr.writeln(modelMcpUsage);
    return null;
  }
  if (arguments.length != 1) {
    stderr.writeln(modelMcpUsage);
    // The usage code of the `flutter3d` command's contract (`CliExit.usage`
    // in flutter3d_build), so a script reads every flutter3d tool alike.
    exit(2);
  }

  final ModelSession session;
  try {
    session = ModelSession.open(arguments.first);
  } catch (error) {
    stderr.writeln('could not open ${arguments.first}: $error');
    // The failure code of the `flutter3d` command's contract
    // (`CliExit.failure`): a file it could not read.
    exit(1);
  }

  return ModelMcpServer(
    stdioChannel(input: stdin, output: stdout),
    session: session,
    projectTools: projectTools ?? McpTools(),
  );
}

/// What `model_mcp` prints for `--help` and for a wrong argument count.
const String modelMcpUsage = '''
A model editor an agent can drive, over MCP on stdin and stdout.

  dart run flutter3d_mcp:model_mcp <project.f3dproj>

One project, opened for the life of the process — or started fresh, if the
path does not exist yet. A host that wants two starts two processes.
''';
