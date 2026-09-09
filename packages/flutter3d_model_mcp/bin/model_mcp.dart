/// A model editor an agent can drive, speaking MCP over stdin and stdout.
///
///     dart run flutter3d_model_mcp:model_mcp <project.f3dproj>
///
/// **A usage line and nothing else yet, on purpose.** What this proves today is
/// the thing that has to be true before any of the server exists: that a
/// machine with the Dart SDK and no Flutter can resolve this package and run
/// it. That is checked in a container from CI — `dart pub get`, then `--help` —
/// and it is the check that would have failed on the first day if the document
/// layer had depended on `flutter3d` for `MeshData`.
///
/// The server itself is `doc-19` of `doc/model-editor-plan.md`; when it lands,
/// this file opens the project named on the command line and hands the channel
/// to `ModelMcpServer`, the way `flutter3d_editor_mcp`'s entry point does.
///
/// Nothing is written to stdout that is not a protocol message — stdout *is*
/// the channel — so usage goes to stderr and the exit code is what a host
/// reads.
library;

import 'dart:io';

void main(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stderr.writeln(_usage);
    return;
  }

  stderr.writeln(
    'the model server is not built yet — see doc/model-editor-plan.md '
    'doc-19.\n\n$_usage',
  );
  exit(69);
}

const String _usage = '''
A model editor an agent can drive, over MCP on stdin and stdout.

  dart run flutter3d_model_mcp:model_mcp <project.f3dproj>

One project, opened for the life of the process. A host that wants two
starts two processes.
''';
