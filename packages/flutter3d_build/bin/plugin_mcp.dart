/// The plugin author's MCP server, speaking over stdin and stdout.
///
///     dart run flutter3d_build:plugin_mcp
///
/// **No arguments.** A plugin is a directory, and each tool names the one it
/// works on, so one process serves every plugin an agent writes in a
/// session. Nothing but protocol messages goes to stdout, which is the
/// channel.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_build/src/cli_contract.dart' show CliExit;

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'usage: dart run flutter3d_build:plugin_mcp\n'
      'Takes no arguments: each tool names the plugin directory it works on.',
    );
    exit(CliExit.usage);
  }
  PluginAuthorMcpServer(
    stdioChannel(input: stdin, output: stdout),
    session: PluginWorkshop(),
  );
}
