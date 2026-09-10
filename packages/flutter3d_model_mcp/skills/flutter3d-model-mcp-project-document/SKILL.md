---
name: flutter3d-model-mcp-project-document
description: Use when editing a flutter3d model project through its MCP server — what an object is made of, why an id never changes, why a material is a row number, and what save keeps that export throws away.
---

# A project is objects, materials, and a profile

`list` prints it: every object with its id, name and kind, the material table
by row, and what is selected. Three things worth knowing before driving it.

**An object's geometry is one of three kinds, and only one of them can be
reshaped by number.** A `parametric` object still knows the numbers that build
it — a cylinder's radius and segment count — and `setParametric` can change
them. A `mesh` object has been converted (`bakeToMesh`) or built by hand
(`extrude`, `loopCut`, …) and has topology instead of parameters; asking
`setParametric` for one is refused by name: `"box" is a mesh now, and a mesh
has no parameters to set`. An `imported` object arrived from a decoded file
and has neither; the same tool refuses it as `"scan" came from a file and was
never described by numbers`.

**A material is a row, addressed by position, not by an id.** `addMaterial`
appends one; its row is the table's length *before* the call, which `list`
then shows. `removeMaterial` collapses the table: everything below the row
removed is untouched, the row itself unpaints whatever wore it, and everything
above shifts down one. `assignMaterial id: 3, to: 0` paints object 3 with row
0; leaving `to` out takes the paint off.

**`save` and `export` are not the same promise.** `save` writes the project's
own container — every parameter a shape still knows, the material table, the
whole object hierarchy — and reopening it is exact. `export` writes `.f3d` or
`.obj`, which is allowed to lose what the target format cannot hold: a
parametric object bakes to triangles, a shape's own parameters do not survive.
`check` says what would be lost or refused before either is attempted.

## Ids are stable, positions are not

An object's id never changes and is never reused, even across a delete —
`duplicateObjects` and `addPrimitive` hand out new ones from a counter that
only goes up. A material's row *does* move when an earlier row is removed. So
an id from an old `list` call is always safe to use; a material row from
before a `removeMaterial` may not be.

## What a fresh project already has

Opening a path that does not exist starts an empty project rather than
refusing — the first call can be `addPrimitive`. The default profile requires
triangles (`requireTriangles: true`, matching what `.f3d`/`.obj` write) and
does not require a manifold mesh (`requireManifold: false`), so a pinched
vertex is a warning from `check`, not a reason it refuses.
