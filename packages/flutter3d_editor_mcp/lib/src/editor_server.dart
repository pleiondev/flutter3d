import 'dart:async';

import 'package:dart_mcp/server.dart';

import 'editor_session.dart';
import 'editor_tools.dart';

/// The version this server tells a client it is. Kept beside the pubspec's.
const String editorMcpVersion = '0.1.0';

/// A level editor, offered to an agent as a table of tools.
///
/// **One document, one process, and no window.** The alternative — a socket
/// into a running editor, so an agent and a person share a view — is a
/// different program and a much harder one: two writers on one undo stack, a
/// camera that has to follow somebody else's selection, and a test that needs
/// a GPU before it can assert anything. This is the small half, and it is the
/// half that can be checked: a process started by `dart run`, one `Editing` in
/// it, deterministic text out, and a suite that drives the real protocol over a
/// pair of streams in memory.
///
/// Everything it can do to the document is an [EditorCommand] — the same values
/// the keyboard and the inspector in `apps/flutter3d_editor` go through — so an
/// agent's edit and a person's edit land on the document by one route, get one
/// name in the history, and are undone by the same key.
base class EditorMcpServer extends MCPServer with ToolsSupport {
  EditorMcpServer(super.channel, {required this.session})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter3d_editor_mcp',
          version: editorMcpVersion,
        ),
        instructions: _instructions,
      );

  /// The document being edited, for the life of the process.
  final EditorSession session;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    for (final offered in editorTools) {
      registerTool(
        offered.tool,
        (CallToolRequest request) => _call(offered, request),
      );
    }
    return super.initialize(request);
  }

  /// Runs one tool and turns its answer into a result.
  ///
  /// **A refusal comes back as an error result, not as a thrown exception**, and
  /// the protocol is explicit about why: a tool error inside the result is
  /// something the model sees and can act on, while an exception is reported to
  /// the host as the server having failed. "Resize did nothing because a light
  /// is selected" is information for whoever called; it is not a broken server.
  CallToolResult _call(EditorTool offered, CallToolRequest request) {
    final answer = offered.run(
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
///
/// Short on purpose. The three facts an agent gets wrong without being told are
/// all here — that a selection has to be made before most verbs do anything,
/// that indices move when something is deleted, and that a generated document
/// will not be written over — and the rest is in the tools' own descriptions,
/// where it is read at the moment it matters.
const String _instructions = '''
A level document for a flutter3d game, open and editable. It is JSON: some
materials, a list of boxes called brushes, a list of lights, and a list of
entities — everything else the game names, each a position and a word.

Work in this order: call `list` to see what is there and what index each thing
has, `select` one of them, then the verbs that change it. `place` and the two
`add` tools do not need a selection; everything else does. Deleting renumbers
what follows it, so call `list` again afterwards rather than counting.

`validate` says what is wrong with the document as the game would see it, and is
worth calling before `save`. `undo` goes back sixty-four steps.

This process cannot draw. `screenshot` says so and why.
''';
