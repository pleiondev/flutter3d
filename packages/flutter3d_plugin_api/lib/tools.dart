/// What a plugin hands an agent, without depending on a server: the tools
/// it adds to a project's MCP servers, and what calling one is.
///
/// **A game's plugin should not need the agent servers to bring tools.** A
/// plugin is a dependency of a game, and the servers (`flutter3d_mcp`, with
/// the editor, the modeller and a pre-1.0 MCP library under it) are not. So
/// the slot a plugin fills, [McpTools], and the values a tool is made of,
/// [ToolSpec], [ToolCall] and [ToolResult], live here over the plugin API
/// alone, as the editor's hints do in `editor.dart`:
///
/// ```dart
/// void install(PluginHost host) {
///   host.maybeRegistry<McpTools>()?.addTool(
///     const ToolSpec(
///       name: 'gust',
///       description: 'Blow once, as hard as asked.',
///       inputSchema: {'type': 'object'},
///     ),
///     (ToolCall call) => ToolResult.text('blew'),
///   );
/// }
/// ```
///
/// An engine with no server simply has no [McpTools] among its registries.
/// The servers hand theirs to the plugin host and offer what the plugins
/// added; `flutter3d_mcp`'s `kit.dart` and `project_tools.dart` re-export
/// this library, so a type is the same whichever import named it.
library;

export 'src/tools/project_tools.dart';
export 'src/tools/tool_call.dart';
export 'src/tools/tool_spec.dart';
