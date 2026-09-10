# flutter3d_editor_mcp

A level editor an agent can drive, over the
[Model Context Protocol](https://modelcontextprotocol.io). One level document,
one process, stdio in and stdio out, no window and no GPU.

```sh
dart run flutter3d_editor_mcp:editor_mcp apps/flutter3d_demo_dungeon/assets/levels/crypt.json
```

As a host would configure it:

```json
{
  "mcpServers": {
    "flutter3d-editor": {
      "command": "dart",
      "args": ["run", "flutter3d_editor_mcp:editor_mcp", "assets/levels/first.json"]
    }
  }
}
```

## The same commands a person uses

Every verb here is an `EditorCommand` from
[`flutter3d_editor_core`](https://pub.dev/packages/flutter3d_editor_core) — the
values the editor application's keyboard and inspector already go through. So an
edit made by an agent and an edit made by a hand take one route into the
document, get one name in the undo stack, and come back out under the same key.
Nothing about what an edit *means* is decided twice, and the list of tools is
built from `editorCommandNames` rather than from a copy of it.

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
| `validate` | What the game would object to |
| `save` | Write it out, or say why it will not |
| `screenshot` | Refuses, with the reason |

Ten of those are the document commands. The two that are not, and were missing
from every sketch of this, are `list` and `validate` — and they are missing in
the same way. Every other verb works on *the selection*, which is a kind and an
index that a program with no screen cannot guess; and without `validate` the
first news of a broken level is a diff somebody reads later.

## It cannot draw, and says so

`screenshot` is offered and refuses with its reason. Every backend in this
repository reaches a `GraphicsDevice` whose finished frame is a Flutter widget,
so a process that can render a level is a Flutter process — and `dart run`,
which is how this server starts, cannot resolve a package that depends on the
Flutter SDK.

The tool exists rather than being absent on purpose: an agent that finds no
`screenshot` concludes the server is incomplete and goes looking for another way,
while one that is told why stops asking. Open the level in
`apps/flutter3d_editor` to look at it; `validate` is the better question anyway.

## It will not overwrite a generated document

Most levels in this repository are written by a generator, and CI re-runs every
one of them and diffs the result. So a document carrying `generatedBy` can be
opened, changed and saved **somewhere else**, and the copy takes ownership of
itself. Saving over the original is refused, because that save would look like it
worked right up until the next run of the generator threw the work away.

## Skills

`skills/` holds three, in the shape the rest of the repository uses: what a level
document is made of, what order the tools are meant to be called in, and every
refusal this server can give. They are prose for whatever is driving the editor,
and each of them is about something the code here actually enforces.

A project depending on this package installs them with
`dart run skills@ get`, which reads the `skills/` directory of every dependency
and copies the chosen ones into the agent's own directory. That is why each one
is named `flutter3d-editor-mcp-…`: the CLI skips a skill whose directory does
not start with its package's name.

## Plain Dart

No Flutter in the dependency graph — the editor's headless core, the simulation's
level format, and `dart_mcp`. `dart test` runs the suite with no binding, and
`the simulation names no Flutter` in `tool/structure.dart` reads `lib/`, `bin/`
and `test/` here to keep it that way.

The suite drives the real server through the real protocol over a pair of
in-memory streams, places three torches in the shooter template and compares the
file that comes out against a fixture, byte for byte. That comparison is fair
because stability was settled before this package existed: the document is
written through a JSON encoder with a two-space indent and every coordinate is
snapped to a quarter of a metre.

## Licence

MIT. See `LICENSE`.
