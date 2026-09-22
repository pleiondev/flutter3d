---
description: Six cases from import to export — a scanned prop, a lathed vase, a lit corner, a rigged character, a borrowed walk cycle and an agent working beside you — each one replayable from its own journal.
---

# Tutorial: six ways in

The modeller's tutorial is six cases rather than one tour, because the six starting points ask for different things and a single linear walkthrough would teach the intersection of them instead of any one.

Each case lives at [models.pleion.dev/learn/modeler](https://models.pleion.dev/learn/modeler/), where it comes with an account and a cabinet to keep the result in. What follows is what each one is *for*, so you can start at the one that matches what is on your disk.

## The six

| Case | You start with | You end with | What it teaches |
|---|---|---|---|
| **1 · A prop from a scan** | An STL in millimetres, non-manifold, no materials | A clean, welded, textured GLB | Import options, the readiness checks, cleanup that says what it did |
| **2 · A vase from a profile** | Nothing | A lathed, modified, exported mesh | Parametric shapes, the modifier stack, mesh editing |
| **3 · A lit corner** | Two objects and a flat grey render | A lit, shadowed, graded frame | Scene mode: lights, shadow requests, environment, post |
| **4 · A character from a bare mesh** | An unrigged humanoid | A skinned, weighted, posed character | Auto-rig, weight painting, posing, the readiness a skin needs |
| **5 · Borrowing a walk** | A rig and somebody else's clip | Your character walking | Retarget: auto-mapping, foot locking, what a bone map is |
| **6 · An agent beside you** | A project and an MCP connection | The same project, edited by both of you | The tool table, the shared history, the recovery journal |

## Every case is a test

This is the part worth knowing before you follow one.

Each case ships a `.jsonl` journal of the exact commands its scenario ran, and the repository replays that journal from an empty project on every CI run. If a case's prose says "extrude the rim and the readiness check goes quiet", the replay is what holds that sentence honest — it rebuilds the document command by command and compares the result against the committed project, the committed GLB, and the committed picture.

So a case that has gone stale fails a test rather than misleading a reader. That is also why the pictures on those pages are rendered by the same functions the editor draws with, rather than screenshotted by hand: a panel that moves moves the picture, and a picture that no longer matches is a failing check.

## Where the gaps are written down

`doc/modeler-tutorial-gaps.md` in the repository is a journal of everything found *while writing* the cases — every place where the prose wanted something the code could not do. Each row is a gap, its type, and the plan row that closed it.

It is worth reading if you are deciding whether to trust the tool, because it is the list of things that were wrong and are not any more: an agent that could not choose a unit on import, readiness checks that skipped imported geometry, a joint bend with no document-level equivalent, a recovery journal that wrote two inert lines for a recipe that did nothing.

## Starting

The [engine's own quickstart](/quickstart/) is the shorter path if what you want is a scene in code. The modeller is the path when what you have is a file somebody sent you.
