---
name: flutter3d-model-mcp-what-it-refuses
description: Use when a call to the flutter3d model editor's MCP server comes back as an error, or when planning work around it — every refusal it can give, what it means, and which ones are decisions rather than gaps.
---

# Every refusal, and what to do about it

A refused call comes back as a tool result marked as an error, with a sentence
in it, and **nothing was changed**. It is not a broken server: a command
answering "no" to a question that has that answer is the ordinary case, not an
exception — see `Outcome.refused` in `flutter3d_model_core`.

| The answer | What it means | What to do |
|---|---|---|
| `there is no object 40` | The id is not in the project | `list`, then use an id that is there |
| `no object is selected` / `nothing is selected to move` | A command that reads the selection found none | `select` first |
| `the selected object has gone` | The selected id was deleted since | `list`, `select` again |
| `"vase" is still a lathe. Convert it to a mesh first, which is a step you can take back` | A mesh command hit a parametric object | `bakeToMesh` it, then retry |
| `"scan" came from a file and has no topology to edit yet` | A mesh command hit an imported object | Nothing yet — importing to editable topology is not built |
| `"box" is a mesh now, and a mesh has no parameters to set` | `setParametric` hit a converted object | Nothing — the parameters are gone on purpose; undo the bake if that was a mistake |
| `there is no material 4` | The material row does not exist | `list`, then use a row that is there |
| `"roughnesss" is not a material field, or its value is the wrong shape` | `setMaterialField`'s field name or value type is wrong | Check the spelling against `writeFmat`'s field names in the tool description |
| `there is no image 0` | `setTexture`'s `imageIndex` does not exist | `addImage` first |
| `rename cannot be read from those arguments` | The argument shape does not match the schema | Read the schema `tools/list` gave for that tool |
| `this session has no path of its own — give one` | `save` with no path on a project never saved | Give `save` a `path` |
| `there is nothing in this project to export` | `export` on an empty project | Add something first |
| `glTF/GLB export is not built yet — see doc/model-editor-plan.md fmt-06` | Asked `export` for `glb`/`gltf` | Use `f3d` or `obj` |
| `nothing to undo` / `nothing to redo` | The stack is at one end | Nothing; this is information |

## The decisions that will not change

**It will not overwrite what force does not say to.** `export` checks `check`
first and refuses on any error-level issue unless `force: true` is set — an
empty mesh or a face with no area would otherwise be exported silently.
Warnings never block it.

**It will not draw.** There is no `screenshot` tool at all, for the same
reason `flutter3d_editor_mcp` gives its own: every backend in this repository
reaches a `GraphicsDevice` whose finished frame is a Flutter widget, and
`dart run`, which is how this server starts, cannot resolve a package that
depends on the Flutter SDK.

**It will not open a second project.** One project per process, given on the
command line or started fresh if the path does not exist. Two projects means
two processes.

**It will not export glTF or GLB.** `fmt-06` is not built in this repository
yet; `export` is offered and refuses by name rather than being absent, so an
agent reading `tools/list` learns why instead of concluding the server is
broken.

## The two that are gaps, not decisions

**`import` does not appear in `journal`'s recovery file.** Every other
successful command is recorded as a JSON line `CommandJournal.replay` can run
again; `import` builds a whole new document from a decoded file — more than a
journal line can describe — and is applied through `ReplaceDocument`, a
command that exists for exactly this and is deliberately not in
`modelCommandNames`. A journal replayed after an import replays everything up
to it and stops one line short of where the session actually was.

**A command that reads the selection cannot be replayed from `journal` either,
unless every `select` call in between was also recorded.** `moveBy`,
`rotateBy`, `scaleBy`, `deleteObjects`, `duplicateObjects` and every mesh
command act on whatever `select` last set, and `select` itself is not a
`ModelCommand` — it is a direct assignment, the same as a mouse click in the
application, and nothing here journals a click. A recovery file built from
`journal` alone will replay these against whatever selection the lines before
them happened to leave, which may not be the selection they actually ran
against.
