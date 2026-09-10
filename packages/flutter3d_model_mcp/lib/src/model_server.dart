import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'model_session.dart';
import 'model_tools.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String modelMcpVersion = '0.1.0';

/// A model project, offered to an agent as a table of tools.
///
/// **One project, one process, and no window** — the same shape
/// `flutter3d_editor_mcp` chose, and for the same reason: a socket into a
/// running editor, so an agent and a person share one view, is two writers on
/// one undo stack and a camera that has to follow somebody else's selection.
/// This is the half that can be checked without a GPU: a process started by
/// `dart run`, one `ModelHistory` in it, deterministic text out, and a suite
/// that drives the real protocol over a pair of streams in memory.
base class ModelMcpServer extends MCPServer with ToolsSupport {
  ModelMcpServer(super.channel, {required this.session})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter3d_model_mcp',
          version: modelMcpVersion,
        ),
        instructions: _instructions,
      );

  /// The project being edited, for the life of the process.
  final ModelSession session;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final offered in modelTools) {
      registerTool(
        offered.tool,
        (CallToolRequest request) => _call(offered, request),
      );
    }
    return super.initialize(request);
  }

  /// Runs one tool and turns its answer into a result.
  ///
  /// A refusal comes back as an error result, not a thrown exception — the
  /// same reason `flutter3d_editor_mcp` gives its own: a tool error inside the
  /// result is something the model sees and can act on, while an exception is
  /// reported to the host as the server having failed.
  Future<CallToolResult> _call(
    ModelTool offered,
    CallToolRequest request,
  ) async {
    final answer = await offered.run(
      session,
      request.arguments ?? const <String, Object?>{},
    );
    return CallToolResult(
      content: <Content>[Content.text(text: answer.says)],
      isError: answer.did ? null : true,
    );
  }
}

/// What the host puts in front of the model before it calls anything.
const String _instructions = '''
A 3D model project, open and editable: objects, each a shape that still knows
its own parameters or a mesh with topology, painted with materials from a
shared table.

Work in this order: call `list` to see what is there and what id each thing
has, `select` some of it, then the commands that change it. Commands that add
something — `addPrimitive`, `addLathe` — select what they made; everything
else that moves or deletes acts on the current selection. Mesh commands
(`extrude`, `loopCut`, …) need `select` with an `object` and a `level` first.

`check` says what is wrong with the project as an export would see it, and is
worth calling before `export`. `save` writes the project's own format;
`export` writes `.f3d` or `.obj` for something else to read — glTF/GLB is not
built yet. `import` brings another file's objects in. `journal` writes every
command run this session to a recovery file.

`undo`/`redo` walk the history one step at a time, where a step is whatever one
tool call did — except a drag of many small changes, which nothing here can
send as one call anyway.
''';
