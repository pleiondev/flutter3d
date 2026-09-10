---
name: flutter3d-editor-core-editing-a-level
description: Use when opening, changing, validating or scaffolding a flutter3d level document from code — Editing and its commands, handles and picking, and what this package refuses to know.
---

# A level document, editable with no window anywhere

```dart
final editing = Editing.parse(text, path: 'assets/levels/first.json');

editing.selectHandle(Picking.at(handlesOf(editing.level), from, along));
editing.nudge(Vector3(0, 0, 1));
editing.undo();

final saved = editing.write();     // text back out
```

Plain Dart, so a linter, a service or a command-line tool can open a level with
no Flutter SDK near it. A level is a document, a document can be wrong, and the
programs that most want to say so have no window in them.

Every change is an `EditorCommand` and `EditorHistory` takes it back, so undo is
a property of the document rather than of a widget.

## What it does not do

**It does not draw.** A `Handle` is a box with a size and a colour. Turning
handles into something on a screen belongs to `flutter3d_bridge` and the editor
application.

**It does not read a disk.** `Editing` parses text and writes text; `scaffold`
returns a project as a map of bytes. Choosing a path, reading it and writing it
back stayed in the application, because that is where a crash loses somebody's
work and where a platform gets an opinion.

**It knows no genre.** `OpenKind` accepts whatever the document names, so an
editor built on this opens a game it has never heard of, and `Looks` is how a
game says what its own words look like in a file this package reads without
understanding a word of it. A genre word here fails
`dart run tool/structure.dart`, and so does a Flutter import.

## Scaffolding and the palette

`scaffold` with the templates in `scaffold_templates.dart` turns a template into
a project as bytes — the level, the pubspec, the main file — which is what
<https://flutter3d.pleion.dev/first-project/> walks through. The application
writes them down; this decides what they contain.

`palette_items.dart` builds the palette out of the level itself, because what a
document already contains is what an author most often wants another of.
`Listing` is the flat view, and `vocabulary.dart` is how a game's words reach
both without this package learning any of them.
