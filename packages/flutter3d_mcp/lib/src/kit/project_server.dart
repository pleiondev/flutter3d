/// The one project server: the tools a project's plugins bring, and nothing
/// else.
library;

import 'project_tools.dart';
import 'tool_spec.dart';
import 'tool_table.dart';

/// The version [ProjectMcpServer] tells a client it is: the pubspec's.
const String projectMcpVersion = '1.0.0-rc.1';

/// The version of [ProjectMcpServer]'s own tools, of which there are none.
///
/// **The plugins' tools are not counted here.** Which plugins a project has
/// is the project's choice, so what this server lists differs from one
/// project to the next; each plugin versions its own tools with its own
/// package. This moves only if the server ever offers a tool of its own.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
const String projectMcpSchemaVersion = '1.0.0';

/// A server offering a project's [McpTools] and nothing else.
///
/// **For a project with no other server running.** The editor's, the
/// simulation's and the modeller's servers each take the same registry as
/// `projectTools` and offer the plugins' tools beside their own; a game
/// that runs none of them, and still wants an agent to reach what its
/// plugins brought, starts this one over the registry its engine was given.
///
/// ```dart
/// final tools = McpTools();
/// final loop = EngineLoop(registries: [tools], plugins: installedPlugins);
/// ProjectMcpServer(stdioChannel(input: stdin, output: stdout), tools: tools);
/// ```
///
/// Every tool it lists is `<plugin id>.<name>`, kept in step as plugins are
/// switched on and off.
base class ProjectMcpServer extends ToolTableServer<McpTools, ToolResult> {
  ProjectMcpServer(
    super.channel, {
    required McpTools tools,
    super.pausedBecause,
    super.onProjectCall,
    super.onInitialize,
  }) : super(
         session: tools,
         projectTools: tools,
         name: 'flutter3d.project',
         version: projectMcpVersion,
         schemaVersion: projectMcpSchemaVersion,
         instructions: _instructions,
         tools: const <OfferedTool<McpTools, ToolResult>>[],
         toResult: _same,
       );

  static ToolResult _same(ToolResult result) => result;
}

const String _instructions = '''
The tools a flutter3d project's plugins bring. Each is named after the plugin
that brought it — `wind.gust` is the `wind` plugin's — and the list changes
when a plugin is switched on or off, so read it again when told it changed.''';
