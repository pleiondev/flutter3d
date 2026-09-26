# flutter3d_editor_core

The headless half of [flutter3d](https://flutter3d.pleion.dev)'s level editor: a
document you can select in, nudge, resize, duplicate, undo and write back; the
handles a pointer hits; the palette a level builds out of itself; and the
project a template turns into.

It is plain Dart, with no Flutter, no renderer and no disk. `dart test` runs the
suite with no binding, and a linter, a service or a tool can open a level without
a Flutter SDK anywhere near it.

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

These eight files sat in `apps/flutter3d_editor/lib/src` and never named
Flutter, so everything that wanted them had to depend on an application. The
repository's structure scan forbids that, and pub cannot express it anyway: an
application is not published, so the dependency holds only inside one checkout,
on one machine.

The cost was practical. A level is a document, a document can be
wrong, and the programs that most want to say so are the ones with no window in
them.

## What it does not do

It does not draw. A `Handle` is a box with a size and a colour. Turning handles
into a mesh or a widget on a screen is the work of `flutter3d_app` and the
editor.

It does not read a disk. `Editing` parses text and writes text; `scaffold`
returns a project as a map of bytes. Choosing a path, reading it and writing it
back stayed in the application, because that is where a crash loses somebody's
work and where each platform has its own rules.

It knows no genre. A level says `monster` or `coin` or `checkpoint`, and this
package vouches for none of it: `OpenKind` accepts whatever the document names,
so an editor built on it can open a game it has never heard of. `Looks` is how a
game says what its own words look like, in a file this package reads without
understanding any of it.

A rule in `tool/structure.dart` checks the boundary.
`the simulation names no Flutter` reads a list of plain Dart packages, this one among them, and fails on
the first import that would put a Flutter SDK back in front of a program that
only wants to open a level. The rule kept the name it was published under, from
when the simulation was the only package on the list.

## Licence

MIT.
