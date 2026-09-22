import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'editor_session.dart';
import 'editor_tools.dart';

/// The version this server tells a client it is: the pubspec's.
///
/// A constant, because a compiled server has no pubspec to read. It said
/// 0.1.0 while the package moved on, since "kept beside the pubspec's" was a
/// comment and nothing checked it; `server_version_test.dart` does now.
const String editorMcpVersion = '0.7.0';

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
/// Everything it can do to the document is an `EditorCommand` — the same values
/// the keyboard and the inspector in `apps/flutter3d_editor` go through — so an
/// agent's edit and a person's edit land on the document by one route, get one
/// name in the history, and are undone by the same key. What a server is beyond
/// its tools is `flutter3d_mcp_kit`'s [ToolTableServer].
base class EditorMcpServer extends ToolTableServer<EditorSession, Answer> {
  EditorMcpServer(super.channel, {required super.session})
    : super(
        name: 'flutter3d_editor_mcp',
        version: editorMcpVersion,
        instructions: _instructions,
        tools: editorTools,
        toResult: resultOf,
      );
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
