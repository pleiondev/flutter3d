/// The project server over stdin and stdout: the tools a project's plugins
/// bring, and nothing else.
///
///     dart run flutter3d_mcp:project_mcp
///
/// **Started from here, it offers nothing until something is added**, and
/// that is the honest answer for a package that compiles in no plugins. It is
/// here so the shape is one command away and a host can check it connects;
/// a project that wants its plugins' tools offered starts the same server
/// from a `bin/` of its own, over the [McpTools] its engine filled:
///
/// ```dart
/// void main() {
///   final tools = McpTools();
///   EngineLoop(input: InputState(), registries: [tools],
///       plugins: installedPlugins);
///   ProjectMcpServer(stdioChannel(input: stdin, output: stdout),
///       tools: tools);
/// }
/// ```
///
/// Nothing is written to stdout that is not a protocol message — stdout *is*
/// the channel. Registered as `bin/` rather than as an `executables:` entry,
/// matching every other package in this repository.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_mcp/kit.dart';

void main(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stderr.writeln(_usage);
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln(_usage);
    // The usage code of the `flutter3d` command's contract (`CliExit.usage`
    // in flutter3d_build), so a script reads every flutter3d tool alike.
    exit(2);
  }
  ProjectMcpServer(
    stdioChannel(input: stdin, output: stdout),
    tools: McpTools(),
  );
}

const String _usage = '''
The tools a flutter3d project's plugins bring, over MCP on stdin and stdout.

  dart run flutter3d_mcp:project_mcp

Takes no arguments. Started from here it lists no tools: a project serves its
own plugins' tools by starting ProjectMcpServer from a bin/ of its own, over
the McpTools its engine installed the plugins into.
''';
