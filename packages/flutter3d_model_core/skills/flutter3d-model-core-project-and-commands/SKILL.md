---
name: flutter3d-model-core-project-and-commands
description: Use when working on the flutter3d model editor's headless half — the package is a registered frame today, and this is the shape it is being filled in to.
---

# A frame, and the shape it is being filled in to

**Today this package holds its library header and nothing else.** It was
registered before it was filled so the structure scan, the publishing order and
the container check cover it from the first commit. What goes here is in
`doc/model-editor-plan.md` §2.2, and it follows the shape
`flutter3d_editor_core` already proved on levels.

## Plain Dart, checked through the graph

No Flutter, no renderer, no disk. `flutter3d_model_mcp` cannot start on a
machine with only the Dart SDK if anything in this graph reaches the Flutter SDK
— including transitively, which the text-matching scan does not see. Check what
a new dependency drags in, not just what it imports.

## The shape

**`ModelProject`** holds `profile`, `objects`, `materials`, `images`,
`skeletons`, `clips` and `nextId`, immutable, with structural sharing:
`withObject` and `copyWith` leave untouched parts `identical`. A `ModelObject`
has a stable id and a `version`. Geometry is sealed — parametric, edited
(`EditMesh`), or imported (`MeshData`).

**Every edit is a `ModelCommand`**, sealed, with `name`, `says`, `arguments`,
`toJson`, a `fromJson` returning null rather than throwing on incomplete input,
and `apply(project, selection)`. The MCP tool table is generated from
`modelCommandNames`, so a command added without a tool is a red test.

**`ModelHistory`** groups commands into transactions — a drag of a hundred is
one undo step — and answers `undoSays` and `isDirty`; `amend(replacement)`
updates the current step instead of growing the stack.

**Selection survives undo** when the ids still exist, because it is not stored
on the objects.

**`.f3dproj`** is the container: magic, version, a 16-byte header, a section
directory, four-byte alignment, and sections for the manifest, materials,
meshes, images, skins, animations, journal and history. An unknown section is
stepped over; a future version is refused. Writing is canonical — interned
strings, sorted keys, one rounding — so write→read→write is byte-identical.

**`ExportReadiness.check(project)`** says whether the result may leave: budget,
n-gons, manifoldness, joint count, texture size, material slots, names. It
caches per object version, so editing one object rechecks one object.

## The rule behind all of it

A refusal is a sentence somebody can act on, and every refusal has a test
quoting the same phrase. That is what makes the MCP server's errors worth
reading rather than worth retrying.
