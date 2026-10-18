/// One call of a tool, as the tool's body is handed it.
library;

/// One call of a project tool: what an agent passed, under the name it
/// called.
///
/// **One object rather than the arguments alone**, so a tool's body can be
/// handed more in a minor release (a way to report progress, to hear that
/// the call was cancelled, the project's root) without a second parameter,
/// which would break every tool written against 1.0. `ProjectToolRun` and
/// `OfferedTool.run` take one.
final class ToolCall {
  /// A call of the tool published as [name] with [arguments].
  const ToolCall({required this.name, required this.arguments});

  /// The name the tool was called by, as published: `wind.gust` for a
  /// plugin's tool, `level.list` for a server's.
  final String name;

  /// What the agent passed, already held to the tool's input schema.
  final Map<String, Object?> arguments;
}

/// One call of a server's own tool: a [ToolCall] with the session the
/// server runs it against.
final class SessionToolCall<S> extends ToolCall {
  /// A call of a server's own tool against [session].
  const SessionToolCall({
    required super.name,
    required super.arguments,
    required this.session,
  });

  /// What the tool acts on: the editor's document, the modeller's scene.
  final S session;
}
