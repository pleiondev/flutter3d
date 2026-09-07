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
/// **It cannot draw, and says so rather than going quiet.** [editorTools]
/// offers a `screenshot` that refuses with its reason: every backend in this
/// repository reaches a `GraphicsDevice` whose finished frame is a Flutter
/// widget, so a process that can render a level is a Flutter process — and
/// `dart run` cannot resolve a package that depends on the Flutter SDK, which
/// `packages/flutter3d_cpu/tool/dump_fixture.dart` records finding out. An
/// absent tool would have an agent inventing ways around it; a refusal with a
/// reason ends the question.
///
/// ```sh
/// dart run flutter3d_editor_mcp:editor_mcp apps/flutter3d_demo_dungeon/assets/levels/crypt.json
/// ```
library;

export 'src/editor_server.dart';
export 'src/editor_session.dart';
export 'src/editor_tools.dart';
