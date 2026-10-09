/// [McpTools] alone: the registry a project's plugins fill with their MCP
/// tools, without the servers and the loopback transport.
///
/// **For an application that keeps the registry and runs no server in the
/// same build.** `kit.dart` exports the loopback HTTP server
/// too, which reaches `dart:io`, and an application built for the browser —
/// the level editor is one — cannot import it. This library imports nothing
/// that a browser lacks, so the editor installs its plugins into the same
/// [McpTools] on every platform and a server started beside it on the
/// desktop is handed that registry as `projectTools`.
library;

export 'src/kit/project_tools.dart';
export 'src/kit/tool_spec.dart';
