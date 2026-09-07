---
name: level-document
description: Use when editing a flutter3d level document, by hand or through the editor's MCP server — what the file is made of, why every number lands on a quarter of a metre, and why a document that names its generator will not be written back over.
---

# A level is a JSON document, and it has an owner

```json
{
  "version": 1,
  "name": "shooter start",
  "generatedBy": "tool/make_templates.py",
  "materials": { "wall": { "baseColor": [0.5, 0.47, 0.44, 1.0] } },
  "brushes":  [ { "at": [0,2,-8.5], "size": [16,4,1], "material": "wall" } ],
  "lights":   [ { "type": "point", "at": [0,3.2,0], "intensity": 9, "range": 16 } ],
  "entities": [ { "type": "torch", "at": [-7.7,2.6,0], "yaw": 1.5708 } ]
}
```

Three lists, and everything an editor does is to one of them.

**Brushes** are boxes: a centre, a size, and the name of a material the
`materials` map declares. A brush naming a material that is not declared draws
as grey and the validator says so, which is why the editor picks the material
the level is mostly made of when it is not told one.

**Lights** are typed things the engine defines — a place, a colour, a strength
and a reach. That is why a new one can be invented out of nothing.

**Entities** are everything else the game names, and the editor vouches for none
of it. `torch`, `pickup`, `exit`, `player_spawn` are words this document happens
to use; another game's document uses its own. Everything not reserved (`type`,
`at`, `yaw`, `name`) is a property, so the format grows by writing new keys and
there is no schema to consult.

That is why placing an entity **copies the last one of its type** rather than
writing a fresh one. Nothing in the editor can know what a `torch` needs in it,
and a bare entity with the right `type` and nothing else may not appear in the
game at all. A copy is honest about what a program cannot know.

## Quarters of a metre, and why the diff stays readable

Every coordinate an edit writes is snapped to `0.25`, and the file is written
through a JSON encoder with a two-space indent. Both are deliberate: every level
in this repository was produced by a generator writing rounded numbers, and a
hand-edited brush sitting a millionth of a metre off is a diff nobody can read
and a seam a player can see light through.

The practical consequence for anything driving the editor: **ask for coordinates
that are already on the grid**, or expect the document to round them. `2.5` and
`7.75` survive; `2.4` becomes `2.5` and the answer says so.

## `generatedBy` is who owns the file

Most documents in this repository are written by a Python generator, and
`tool/ci.sh` re-runs every one of them and diffs the result. A file that says

```json
"generatedBy": "tool/make_templates.py"
```

can be opened, changed and saved — **somewhere else**. Saving over it is refused,
because the save would look like it worked right up until the next run of that
generator, at which point the afternoon is gone and nothing ever said so.

Saving elsewhere rewrites the key to name whatever wrote the copy. A file sitting
beside the original still naming the generator is a file that invites somebody to
regenerate it, and regenerating it is exactly what throws the work away.

A document with no `generatedBy` is somebody's own, and is written back in place
without argument.
