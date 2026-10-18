/// A [ToolSpec] written with the MCP library's schema builders.
///
/// **Inside this package only.** The builders are the convenient way to
/// write a schema, and the library they come from is pre-1.0, so they stay
/// out of every public signature: a tool is a [ToolSpec], whose schemas are
/// plain JSON, by the time anything outside this file sees it. Not exported.
library;

import 'package:dart_mcp/server.dart' show ObjectSchema;
import 'package:flutter3d_mcp/model.dart' show ToolHints, ToolSpec;

/// A tool called [name], with its arguments in [inputSchema] and, when it
/// answers `structuredContent`, that answer's shape in [outputSchema].
ToolSpec mcpTool({
  required String name,
  String? description,
  required ObjectSchema inputSchema,
  ObjectSchema? outputSchema,
  ToolHints hints = ToolHints.writes,
}) => ToolSpec(
  name: name,
  description: description,
  inputSchema: inputSchema as Map<String, Object?>,
  outputSchema: outputSchema as Map<String, Object?>?,
  hints: hints,
);
