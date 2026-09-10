---
name: flutter3d-model-mcp-editing-order
description: Use when driving the flutter3d model editor through its MCP server — the order the tools are meant to be called in, which commands need a selection and which take an id directly, and what undo can and cannot put back.
---

# list, select, change, check, save

```
list                              what is there, and what id each thing has
select    objects: [ids]          object mode
select    object, level, elements mesh mode: one object, one level, its elements
addPrimitive / addLathe / rename id: … / setTransform id: … / …
check                             what an export would refuse or warn about
save      path?                   write it out
```

**Two kinds of command, and the schema does not say which is which.** Most
object commands take an `id` in their own arguments — `rename`, `setTransform`,
`setOrigin`, `assignMaterial`, `setParametric`, `bakeToMesh`, `applyTransform`,
`setParent` — and do not need a selection at all; call them with the id from
`list`. A smaller set reads the *current selection* instead: `moveBy`,
`rotateBy`, `scaleBy`, `deleteObjects`, `duplicateObjects`, and every mesh
command (`extrude`, `loopCut`, `deleteElements`, `transformElements`,
`mergeByDistance`, `dissolveEdges`, `triangulate`, `recalculateNormals`,
`separate`, and the `select*` family). Call `select` before any of these; a
call with nothing selected is refused by name rather than doing nothing
quietly — `nothing is selected to move`, `no object is selected`.

**Mesh mode needs an object and a level.** `select object: 3, level: "face",
elements: [0, 4]` puts object 3 in mesh mode with faces 0 and 4 picked; the
commands after it — `extrude`, `loopCut`, the `select*` structural commands —
act on that mesh. Switching `level` keeps the object but changes what
`elements` means. A mesh command refuses outright on a parametric or imported
object: `"vase" is still a lathe. Convert it to a mesh first, which is a step
you can take back` — that step is `bakeToMesh`.

**Adding something selects it.** `addPrimitive` and `addLathe` both select
what they made, so the next call — typically `moveBy` or `assignMaterial` —
already has something to act on without a separate `select`.

**`check` before `save` or `export`.** It reports the same issues an export
would: the triangle budget, faces the target format cannot hold, a pinched
vertex, a face with no area. `no issues` means both will go cleanly; anything
else is worth reading before writing a file.

## Undo is whole documents, sixty-four deep

Every change keeps the document as it was before it, the same design
`flutter3d_editor_mcp` uses and for the same reason: an undo that reconstructs
state has its own bugs, and structural sharing means a two-hundred-object
project with one thing moved costs one new object.

* **Sixty-four steps, oldest falling off the end.**
* **A refused call leaves no step**, so undo never has to be pressed twice for
  one mistaken call.
* **`undo` says what it took back** — `undid set the transform — object 3` —
  so a session can be read backwards rather than counted.
* **A new change clears the way forward.** `redo` after a fresh edit would put
  back a document that no longer follows from what is there.
* **`import` is one undo step however many objects it brings in**, and is the
  one edit not recorded to `journal` — see
  `flutter3d-model-mcp-what-it-refuses` for what that costs a recovery file.

## Saving and exporting

`save` with no path writes back where the project was opened from; with a path
it writes there and that becomes the path for the next bare `save`. `export`
always needs a path and writes `.f3d` or `.obj` — `format` is read from the
suffix unless given explicitly. Neither tool overwrites silently on an
error-level `check` issue: `export` refuses and lists them unless `force` is
set.
