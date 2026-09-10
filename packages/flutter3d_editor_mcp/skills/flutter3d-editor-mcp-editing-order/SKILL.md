---
name: flutter3d-editor-mcp-editing-order
description: Use when driving the flutter3d level editor through its MCP server — the order the tools are meant to be called in, why an index has to be read rather than guessed, and what undo can and cannot put back.
---

# list, select, change, validate, save

```
list                       what is in the level, and what index each thing has
select   kind, index       what the next call acts on
place / addBrush / addLight / moveBy / resize / setField / …
validate                   what is wrong with it, as the game would see it
save     path              write it out
```

**`list` first, every time.** Every verb except `place`, `addBrush` and
`addLight` works on *the selection*, and a selection is a kind (`brush`, `light`
or `entity`) and an index into that kind's list. There is no way to guess one:
the process has no window, and nothing else in the protocol reports what the
document contains. Driving the editor without calling `list` is moving the third
brush without ever finding out that there is a third brush.

**Indices move.** The document is three plain lists, so deleting entity 2 makes
entity 3 into entity 2. An index remembered across a delete points at the wrong
thing rather than at nothing, which is the worse failure — the call succeeds and
edits something else. Call `list` again after any delete.

**`place` is how a level grows.** It copies the last thing of that type the
document already has, with everything it was carrying, and puts it where you
said. `addBrush` and `addLight` invent one, which they may do because a box and a
point light are things the engine defines rather than words a particular game
uses.

**`setField` is the escape hatch and it is not a small one.** The typed verbs
reach a position, a size, a light's strength and an entity's facing. Everything
else — a brush's material, whether it is solid, whether it casts a shadow, its
layer; a light's colour, range and type; any property an entity carries — is
`setField`. A value the level format cannot read is refused rather than written.

**`validate` before `save`.** It reports what the game would object to: geometry
that overlaps, a brush naming a material nothing declares, a light that reaches
nowhere, two things answering to one name. It does not object to vocabulary,
because the editor has none of its own — every word the document uses is taken as
a word this game uses.

## Undo is snapshots, sixty-four deep

Going back does not reverse a command. Every change records the whole document
as it was, and undo puts that back. The reason is written into the editor's own
source: an undo that reconstructs state is an undo with its own bugs, and a level
is a few hundred numbers that cost nothing to copy.

What follows from that, and is worth knowing before relying on it:

* **Sixty-four steps, oldest falling off the end.** An editor that stopped
  recording after the sixty-fourth change would be an editor whose undo silently
  stops working halfway through an afternoon.
* **A refused call leaves no step.** `resize` with a light selected changes
  nothing and records nothing, so undo does not have to be pressed twice.
* **The selection survives if it still points at something**, and is dropped if
  it does not.
* **A new change clears the way forward.** Redo after an edit would put back a
  document that never followed from what is there now.
* **Undo says what it took back** — "undid place a torch at 0, 2.5, 8" — so a
  long session can be walked backwards by reading rather than by counting.

## Saving

`save` with no path writes back where the document came from, and is refused
when the file names a generator — see the
`flutter3d-editor-mcp-level-document` skill. `save` with a path writes there and
the copy takes ownership of itself. Either way the answer
names the file that was written; nothing is written when the answer is a refusal.
