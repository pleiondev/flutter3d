/// A level editor an agent can drive, over the Model Context Protocol.
///
/// **The same commands a person uses, offered as tools.** Every verb here is an
/// `EditorCommand` from `flutter3d_editor_core` — the values the editor
/// application's keyboard and inspector already go through — so an edit made by
/// an agent and an edit made by a hand take one route into the document, get one
/// name in the history, and come back out under the same undo. Nothing about
/// what an edit *means* is decided twice.
///
/// Two tools are not commands, and both were missing from every sketch of this:
/// [EditorSession.listing], because a program with no screen cannot point at
/// anything and therefore cannot find out what is in the level it is editing;
/// and [EditorSession.validate], because without it the first news of a broken
/// document is a diff somebody reads later.
///
/// ## What it is not
///
/// **Not a connection to a running editor.** The server owns one document for
/// the life of one process, started by `dart run`. A socket into a live window,
/// so that an agent and a person watch the same level change, is a different and
/// much harder program — two writers on one undo stack — and this is the half
/// that can be tested without a device.
///
/// **It draws with no GPU and no Flutter.** `screenshot` renders the level
/// through the software rasteriser, and `report` reads the same frame's
/// object ids to say how much of each brush, light and entity a camera sees
/// and what is in its way — see [LevelView]. It used to refuse, when every
/// renderer here reached a device whose finished frame was a Flutter widget
/// and the level's scene was built inside a Flutter package; neither is true
/// any more, and `dart run` resolves everything it needs.
///
/// ```sh
/// dart run flutter3d_editor_mcp:editor_mcp apps/flutter3d_demo_dungeon/assets/levels/crypt.json
/// ```
library;

export 'src/editor_server.dart';
export 'src/editor_session.dart';
export 'src/editor_tools.dart';
export 'src/level_view.dart';
