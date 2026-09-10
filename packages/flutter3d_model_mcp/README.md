# flutter3d_model_mcp

[flutter3d](https://flutter3d.pleion.dev)'s model editor, offered to an agent:
an MCP server over stdio whose tools are the editor's own commands, one project
per process.

```bash
dart run flutter3d_model_mcp:model_mcp my-model.f3dproj
```

A path that does not exist yet starts a fresh project there, so the first call
an agent makes can be `addPrimitive` rather than a separate "create" step.

**Plain Dart, and a host is why.** `dart run` cannot resolve a package that
depends on the Flutter SDK, so a Flutter import anywhere in this graph is not a
heavier process — it is a server that will not start on a machine without the
Flutter tool. That is checked in CI, in a container with the Dart SDK and
nothing else — `dart run tool/structure.dart`'s "a flat Dart package resolves
without the Flutter SDK" rule.

## Work in this order

1. `list` — everything in the project, one line each, plus the material table
   and the current selection. There is no other way to find out what a
   project holds or what id something has.
2. `select` — object ids for the object-level commands, or one object plus a
   level (`vertex`/`edge`/`face`) and element ids for the mesh-level ones.
3. The command that does the thing. `addPrimitive`/`addLathe` select what they
   make; everything else that moves, deletes or transforms acts on the
   current selection.
4. `check` before `save` or `export`, to see what an export would refuse or
   warn about.

`undo`/`redo` walk the history one call at a time. `save` writes the project's
own format; `export` writes `.f3d` or `.obj` for something else to read.
`import` brings another file's objects in as new objects, one undo step.
`journal` writes every command run this session to a `doc-16` recovery file.

## Tool table

| Tool | What it does |
|---|---|
| `list`, `select` | Find out what is there and choose what the rest act on |
| `undo`, `redo` | Walk the history |
| `check` | What an export would refuse or warn about |
| `save`, `export`, `import`, `journal` | The project's life outside one edit |

Every other tool is one of `flutter3d_model_core`'s commands, under its own
name — `rename`, `setTransform`, `moveBy`, `rotateBy`, `scaleBy`, `setParent`,
`setOrigin`, `applyTransform`, `addPrimitive`, `addLathe`, `setParametric`,
`bakeToMesh`, `deleteObjects`, `duplicateObjects`, `extrude`, `loopCut`,
`deleteElements`, `transformElements`, `mergeByDistance`, `dissolveEdges`,
`separate`, `triangulate`, `recalculateNormals`, `selectAll`, `selectNone`,
`invertSelection`, `growSelection`, `shrinkSelection`, `selectLinked`,
`selectEdgeLoop`, `selectEdgeRing`, `selectByMaterial`, `addMaterial`,
`removeMaterial`, `duplicateMaterial`, `setMaterialField`, `setTexture`,
`addImage`, `assignMaterial`. `test/tools_test.dart` holds this file's claim
against `modelCommandNames`, both ways round, so a command added to the core
package without a tool here is a failing test rather than a silent gap.

## It cannot draw, and glTF/GLB is not built yet

There is no `screenshot` tool: every backend in this repository reaches a
`GraphicsDevice` whose finished frame is a Flutter widget, and `dart run`
cannot resolve a package that depends on the Flutter SDK. `export` writes
`.f3d` and `.obj`; asked for `glb`/`gltf` it refuses and says why — `fmt-06`,
which is not built yet — rather than pretending to write nothing, or writing
nothing silently.

## Skills

- `flutter3d-model-mcp-server` — why the graph must stay free of the Flutter
  SDK, and the shape the server is built to.
- `flutter3d-model-mcp-project-document` — what a project holds: objects,
  geometry, materials, the profile.
- `flutter3d-model-mcp-editing-order` — list, select, act; what needs a
  selection and what does not.
- `flutter3d-model-mcp-what-it-refuses` — every refusal phrase, what it means,
  and what to do about it.

## Plain Dart

`packages/flutter3d_formats` and `packages/flutter3d_model_core` are both flat
Dart packages, so `ModelSession`'s export and import verbs go through the same
`ModelDocument`/`F3dWriter`/`ObjWriter`/`decodeModel` abstractions the rest of
the engine does, with a small `AssetSource` of this package's own reading
files through `dart:io` — the `FileAssetSource` `flutter3d` ships depends on
Flutter and may not be named here. `test/agent_builds_a_table_test.dart`
drives the real protocol over an in-memory pair of streams and proves the
whole graph resolves and runs without one.

## Licence

MIT.
