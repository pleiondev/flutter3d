# flutter3d_mcp

MCP servers for flutter3d, and the kit they are built on. Each server is a library and a command a host starts with `dart run`:

```bash
dart run flutter3d_mcp:editor_mcp <level.json>   # a level editor
dart run flutter3d_mcp:model_mcp <project>       # a model editor
dart run flutter3d_mcp:project_mcp               # the project server
```

Plain Dart all the way down, so `dart run` can resolve it with no Flutter SDK in sight. The server that plays a game, `flutter3d_sim_mcp`, takes Flutter and so stays a package of its own, built on `kit.dart` here.

| Library | Was | What it is |
| --- | --- | --- |
| `kit.dart` | `flutter3d_mcp_kit` | The parts every flutter3d MCP server shares, written once |
| `editor.dart` | `flutter3d_editor_mcp` | A level editor an agent can drive, over the [Model Context Protocol](https://modelcontextprotocol.io) |
| `model.dart` | `flutter3d_model_mcp` | The model editor of [flutter3d](https://flutter3d.pleion.dev), offered to an agent |

## `kit.dart`

*Until 1.0.0-rc.1, `flutter3d_mcp_kit`.*

The parts every flutter3d MCP server shares, written once:

- `OfferedTool<S, A>` holds a tool and the code that runs it in one value, so
  every tool a server offers has a body.
- `ToolTableServer<S, A>` is a server built from a list of those over one
  session.
- `Answer` and `PictureAnswer` carry what a call did and the sentence to say
  about it. `resultOf` and `pictureResultOf` turn a refusal into an error
  result the agent reads, so the server itself does not fail.
- `LoopbackMcpServer` serves any of those servers over `127.0.0.1` HTTP with a
  per-server token, for an application that wants to hand an agent the session
  a person already has open.

- `McpTools` is where a project's plugins put their tools. A plugin calls
  `host.registry<McpTools>().addTool(tool, run)` in `install`, and the tool
  is published as `<plugin id>.<name>`. Every server takes the registry as
  `projectTools`, offers those tools after its own, and keeps the list up to
  date as plugins are switched on and off. `ProjectMcpServer` offers the
  registry on its own, for a project with no other server running.

A server's `api/<package>.mcp` snapshot is the server built without
`projectTools`. Each plugin's tools belong to the plugin's package, which
snapshots and versions them itself.

`flutter3d_mcp/editor.dart`, `flutter3d_mcp/model.dart` and `flutter3d_sim_mcp` (with
both of its servers) are built on it. It is plain Dart, so a server that uses
it starts without the Flutter SDK.

## `editor.dart`

*Until 1.0.0-rc.1, `flutter3d_editor_mcp`.*

A level editor an agent can drive, over the
[Model Context Protocol](https://modelcontextprotocol.io). It works on one level
document in one process, reads stdin and writes stdout, and needs no window and
no GPU.

```sh
dart run flutter3d_mcp:editor_mcp apps/flutter3d_demo_dungeon/assets/levels/crypt.json
```

As a host would configure it:

```json
{
  "mcpServers": {
    "flutter3d-editor": {
      "command": "dart",
      "args": ["run", "flutter3d_mcp:editor_mcp", "assets/levels/first.json"]
    }
  }
}
```

### The same commands a person uses

Every verb here is an `EditorCommand` from
[`flutter3d_editor_core`](https://pub.dev/packages/flutter3d_editor_core), the
same values the editor application's keyboard and inspector go through. An edit
made by an agent and an edit made by hand take one route into the document, get
one name in the undo stack, and come back out under the same key. What an edit
*means* is decided in one place, and the list of tools is built from
`editorCommandNames` instead of from a copy of it.

| Tool | What it does |
|---|---|
| `list` | Everything in the level, one line each, with the index `select` takes |
| `select` | Choose what the next call acts on |
| `moveBy`, `resize` | Move anything; resize a brush |
| `addBrush`, `addLight`, `place` | Put something down |
| `duplicate`, `delete` | Copy or remove the selection |
| `setField` | Write any field the format has, including ones added after this was released |
| `brighten`, `turn` | A light's strength; an entity's facing |
| `undo`, `redo` | Sixty-four steps of whole-document snapshots |
| `generate` | Add a room, corridor or scatter as a seeded recipe |
| `validate` | What the game would object to |
| `save` | Write it out, or say why it will not |
| `screenshot` | A flat picture of the level from a camera you may name |
| `report` | What that camera sees of every brush, light and entity, and what is in the way |
| `play`, `play_status`, `play_events`, `play_swap`, `play_stop`, `play_devices` | Run the game the level belongs to, see its console and the events it posts (read by cursor, so none is seen twice or skipped), swap its code, stop it, and choose the device — the editor's Play button, from [`flutter3d_editor_play`](../flutter3d_editor_play). While it runs, `save` sends the level to it |
| `play_send_level` | Send the level as it stands, unsaved changes included, to the running game without writing the file |
| `play_build` | Build the game with `flutter build` for a target, debug unless asked, and say which lines broke it; refused while the game runs |
| `play_keep_tape` | Write the last seconds the running game kept into its project's `test/tapes/` as a `.f3drun` |
| `render_passes`, `render_draws`, `render_draw`, `render_pick`, `render_read_pixel`, `render_pass_output`, `render_scan_nan`, `render_stats` | The frame the running game actually drew: its passes and draws, which draws painted a pixel, a pixel's value, NaNs, and the cost. Each tool takes `vmService` to ask a game that `play` did not start |

Ten of those are the document commands. The two that are not, `list` and
`validate`, were missing from every sketch of this, and missing in the same
way. Every other verb works on *the selection*, which is a kind and an index
that a program with no screen cannot guess. Without `validate`, the first news of
a broken level is a diff somebody reads later.

### It draws in software, flat

`screenshot` renders the level through `flutter3d_cpu`'s rasteriser at 320×200,
so it needs no GPU and no Flutter. The scene comes from `flutter3d_editor_core`'s
`LevelScene`, with the same brushes, lights and probes a game loads. Textures
are not drawn, because decoding them is the application's job, so every brush
shows in its material's colour and every light and entity as a small box.

`report` answers what a picture only half answers. It draws the same frame once
more with the level split into one draw per brush and reads back which draw owns
each pixel. For every brush, light and entity it gives how many pixels it owns,
where on the screen, how far away, and which pieces cover the part of the screen
it would fill. "The torch is hidden by brush 3" is then a count of pixels after
the depth test.

### It will not overwrite a generated document

Most levels in this repository are written by a generator, and CI re-runs the
generator for every one of them and diffs the result. A document carrying
`generatedBy` can be opened, changed and saved *somewhere else*, and the copy
then owns itself. Saving over the original is refused, because that save would
look like it worked until the next run of the generator threw the work away.

### Skills

`skills/` holds three, in the shape the rest of the repository uses. They cover
what a level document is made of, the order the tools are meant to be called
in, and every refusal this server can give. They are prose for whatever drives
the editor, and each one describes something the code here enforces.

A project depending on this package installs them with `dart run skills@ get`,
which reads the `skills/` directory of every dependency and copies the chosen
ones into the agent's own directory. Each one is named
`flutter3d-mcp-editor-…` because the CLI skips a skill whose directory does not
start with its package's name.

### Plain Dart

The dependency graph has no Flutter in it: the editor's headless core, the
simulation's level format, and `dart_mcp`. `dart test` runs the suite with no
binding, and the rule `the simulation names no Flutter` in `tool/structure.dart`
reads `lib/`, `bin/` and `test/` here to keep it that way.

The suite drives the real server through the real protocol over a pair of
in-memory streams, places three torches in the shooter template, and compares
the file that comes out against a fixture byte for byte. The comparison is fair
because output stability was settled before this package existed: the document
is written through a JSON encoder with a two-space indent, and every coordinate
is snapped to a quarter of a metre.

### Licence

MIT. See `LICENSE`.

## `model.dart`

*Until 1.0.0-rc.1, `flutter3d_model_mcp`.*

The model editor of [flutter3d](https://flutter3d.pleion.dev), offered to an
agent: an MCP server over stdio whose tools are the editor's own commands, one
project per process.

```bash
dart run flutter3d_mcp:model_mcp my-model.f3dproj
```

A path that does not exist yet starts a fresh project there, so the first call
an agent makes can be `addPrimitive` instead of a separate "create" step.

**The package is plain Dart because of the host.** `dart run` cannot resolve a
package that depends on the Flutter SDK, so a Flutter import anywhere in this
graph would not just make the process heavier. The server would fail to start
on a machine without the Flutter tool. CI checks this in a container with the
Dart SDK and nothing else, through the "a flat Dart package resolves without
the Flutter SDK" rule of `dart run tool/structure.dart`.

### Work in this order

1. `list`: everything in the project, one line each, plus the material table
   and the current selection. It is the only way to find out what a project
   holds or what id something has.
2. `select`: object ids for the object-level commands, or one object plus a
   level (`vertex`/`edge`/`face`) and element ids for the mesh-level ones.
3. The command that does the work. `addPrimitive`/`addLathe` select what they
   make; everything else that moves, deletes or transforms acts on the
   current selection.
4. `check` before `save` or `export`, to see what an export would refuse or
   warn about.

`undo`/`redo` walk the history one call at a time. `save` writes the project's
own format; `export` writes `.f3d` or `.obj` for something else to read.
`import` brings another file's objects in as new objects, one undo step.
`journal` writes every command run this session to a `doc-16` recovery file.

### Tool table

| Tool | What it does |
|---|---|
| `list`, `select` | Find out what is there and choose what the rest act on |
| `undo`, `redo` | Walk the history |
| `check` | What an export would refuse or warn about |
| `save`, `export`, `import`, `journal` | The project's life outside one edit |

Every other tool is one of `flutter3d_model_core`'s commands, under its own
name: `rename`, `setTransform`, `moveBy`, `rotateBy`, `scaleBy`, `setParent`,
`setOrigin`, `applyTransform`, `addPrimitive`, `addLathe`, `setParametric`,
`bakeToMesh`, `deleteObjects`, `duplicateObjects`, `extrude`, `loopCut`,
`deleteElements`, `transformElements`, `mergeByDistance`, `dissolveEdges`,
`separate`, `triangulate`, `recalculateNormals`, `selectAll`, `selectNone`,
`invertSelection`, `growSelection`, `shrinkSelection`, `selectLinked`,
`selectEdgeLoop`, `selectEdgeRing`, `selectByMaterial`, `addMaterial`,
`removeMaterial`, `duplicateMaterial`, `setMaterialField`, `setTexture`,
`addImage`, `assignMaterial`. `test/tools_test.dart` checks this list against
`modelCommandNames` in both directions, so a command added to the core package
without a tool here fails a test instead of leaving a silent gap.

### It cannot draw, and glTF/GLB is not built yet

There is no `screenshot` tool. Every backend in this repository reaches a
`GraphicsDevice` whose finished frame is a Flutter widget, and `dart run`
cannot resolve a package that depends on the Flutter SDK. `export` writes
`.f3d` and `.obj`. Asked for `glb`/`gltf`, it refuses and gives the reason
(`fmt-06`, which is not built yet) instead of silently writing nothing.

### Skills

- `flutter3d-mcp-model-server`: why the graph must stay free of the Flutter
  SDK, and the shape the server is built to.
- `flutter3d-mcp-model-project-document`: what a project holds (objects,
  geometry, materials, the profile).
- `flutter3d-mcp-model-editing-order`: list, select, act; what needs a
  selection and what does not.
- `flutter3d-mcp-model-what-it-refuses`: every refusal phrase, what it means,
  and what to do about it.

### Plain Dart

`packages/flutter3d_core` and `packages/flutter3d_model_core` are both flat
Dart packages, so the export and import verbs of `ModelSession` go through the
same `ModelDocument`/`F3dWriter`/`ObjWriter`/`decodeModel` abstractions as the
rest of the engine. This package adds a small `AssetSource` of its own that
reads files through `dart:io`, because the `FileAssetSource` that `flutter3d`
ships depends on Flutter and may not be named here.
`test/agent_builds_a_table_test.dart` drives the real protocol over an
in-memory pair of streams and shows that the whole graph resolves and runs
without Flutter.

### Licence

MIT.
