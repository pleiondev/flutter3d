/// A level editor with the editor taken out: the document, what nudging it
/// means, what a pointer hits, what a palette offers, and what a template turns
/// into.
///
/// **Plain Dart, and that is the whole of why this package exists.** The
/// document layer sat in `apps/flutter3d_editor/lib/src` for as long as the
/// editor was the only program that wanted it. The moment anything else did —
/// a command-line linter for a level, a tool an agent speaks to, a service that
/// checks an uploaded level before a player ever loads it — it had to depend on
/// an application, and `no package depends on an application` in
/// `tool/structure.dart` says no. It says no because pub cannot express such a
/// dependency at all: an application is not published, so the dependency exists
/// only inside this checkout and only on a machine that has it.
///
/// ## What it does not do
///
/// **It does not draw.** [Handle] is a box with a colour and a size, not a mesh
/// and not a widget; turning a list of handles into something on a screen is
/// `flutter3d_bridge`'s and the editor's, and nothing here knows that anything
/// does.
///
/// **It does not read a disk.** [Editing] parses text and writes text back,
/// [scaffold] returns a project as a map of bytes, and neither opens a file.
/// The half with `dart:io` in it — pick a path, read it, write it down again —
/// stayed in the application, because that half is where a crash loses
/// somebody's work and where a platform gets an opinion.
///
/// **It knows no genre.** A document says `monster` or `coin` or `checkpoint`
/// and this package vouches for none of it: [OpenKind] accepts whatever the
/// level happens to name, so an editor built on it opens a game it has never
/// heard of. The rule is held by `the engine names no genre` in the scan, and
/// [Looks] is how a game gets to say what its own words look like without a
/// line of code here learning them.
///
/// The boundary is checked rather than described: `the simulation names no
/// Flutter` in `tool/structure.dart` reads a list of plain Dart packages, this
/// one among them, and fails on the first import that would put a Flutter SDK
/// in front of a program that only wants to open a level. The rule keeps the
/// name it was published under, from the day the simulation was the only
/// package on that list.
library;

export 'src/editing.dart';
export 'src/editor_command.dart';
export 'src/editor_history.dart';
export 'src/gizmos.dart';
export 'src/listing.dart';
export 'src/looks.dart';
export 'src/palette_items.dart';
export 'src/picking.dart';
export 'src/scaffold.dart';
export 'src/scaffold_templates.dart';
export 'src/vocabulary.dart';
