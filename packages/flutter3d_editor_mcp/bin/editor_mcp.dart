/// A level editor an agent can drive, speaking MCP over stdin and stdout.
///
///     dart run flutter3d_editor_mcp:editor_mcp <level.json>
///
/// **The level is an argument and there is no tool to change it**, which is the
/// one decision this file makes on its own. The document is the state: an agent
/// that could open a second level halfway through would be left holding an undo
/// stack of sixty-four snapshots of a file it is no longer editing, and every
/// one of them would restore cleanly. A host that wants two levels open starts
/// two processes, which costs nothing and cannot be got wrong.
///
/// Nothing is printed to stdout that is not a protocol message — stdout *is* the
/// channel — so the two things that can go wrong before the protocol starts, a
/// missing argument and an unreadable document, are written to stderr and the
/// process exits non-zero. A host reads that as a server that would not start,
/// which is what it is; a friendly line on stdout would be read as a malformed
/// frame and the failure would be reported as a protocol error instead.
///
/// Registered as `bin/` rather than as an `executables:` entry, because no
/// package in this repository declares one — `dart run <package>:<name>` is how
/// they are all invoked, and `packages/flutter3d_sim/bin/headless_run.dart` is
/// the pattern.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run flutter3d_editor_mcp:editor_mcp <level.json>\n'
      'One level document, opened for the life of this process.',
    );
    exit(64);
  }

  final EditorSession session;
  try {
    session = EditorSession.open(arguments.first);
  } catch (error) {
    stderr.writeln('could not open ${arguments.first}: $error');
    exit(66);
  }

  EditorMcpServer(
    stdioChannel(input: stdin, output: stdout),
    session: session,
  );
}
