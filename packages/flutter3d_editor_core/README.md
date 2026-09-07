# flutter3d_editor_core

The headless half of [flutter3d](https://flutter3d.pleion.dev)'s level editor: a
document you can select in, nudge, resize, duplicate, undo and write back; the
handles a pointer hits; the palette a level builds out of itself; and the
project a template turns into.

**Plain Dart.** No Flutter, no renderer, no disk. `dart test` runs the suite with
no binding, and a linter, a service or a tool can open a level without a Flutter
SDK anywhere near it.

```dart
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:vector_math/vector_math.dart';

final editing = Editing.parse(text, path: 'assets/levels/first.json');

editing.selectHandle(Picking.at(handlesOf(editing.level), from, along));
editing.nudge(Vector3(0, 0, 1));
editing.undo();

final saved = editing.write();
```

## Why it is a separate package

Not tidiness. These eight files sat in `apps/flutter3d_editor/lib/src` and named
Flutter nowhere at all, so everything that wanted them had to depend on an
application — which the repository's structure scan forbids, and which pub
cannot express anyway: an application is not published, so the dependency is
true only inside one checkout, on one machine.

What that blocked is not hypothetical. A level is a document, and a document can
be wrong; the programs that most want to say so are the ones with no window in
them.

## What it does not do

**It does not draw.** A `Handle` is a box with a size and a colour, not a mesh
and not a widget. Turning handles into something on a screen is
`flutter3d_bridge`'s work and the editor's.

**It does not read a disk.** `Editing` parses text and writes text; `scaffold`
returns a project as a map of bytes. Choosing a path, reading it and writing it
back down stayed in the application, because that is where a crash loses
somebody's work and where a platform gets an opinion.

**It knows no genre.** A level says `monster` or `coin` or `checkpoint` and
nothing here vouches for any of it: `OpenKind` accepts whatever the document
happens to name, so an editor built on this opens a game it has never heard of.
`Looks` is how a game says what its own words look like, in a file this package
reads without understanding a word of it.

The boundary is checked rather than described: `the simulation names no Flutter`
in `tool/structure.dart` reads a list of plain Dart packages — this one among
them — and fails on the first import that would put a Flutter SDK back in front
of a program that only wants to open a level. It kept the name it was published
under, from the day the simulation was the only package on the list.

## Licence

MIT.
