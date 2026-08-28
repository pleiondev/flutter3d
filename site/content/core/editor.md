---
description: apps/flutter3d_editor, the fourth application and the first that is not a game. Opening a level, flying around it, and changing what is in it.
---

# The level editor

`apps/flutter3d_editor` opens a level document with the same `LevelLoader` the games use, draws it, and lets somebody fly around, select what's in it, move it, resize it, add to it, and write it back. Desktop only. It exists to write a file back over itself, and a browser will not do that.

<div class="goal">
<ul>
<li>Opening a level, and what happens when the path doesn't exist yet</li>
<li>The fly camera, and why it moves along the ground instead of along the view</li>
<li>Selecting, nudging and resizing on the grid, and what <code>1</code>/<code>2</code>/<code>3</code> and <code>-</code>/<code>=</code> do together</li>
<li>The palette, and what actually happens when you place an entity with no vocabulary in the editor to describe it</li>
<li>The fields panel, built from the document instead of from a schema</li>
<li>What still doesn't exist: a file dialog, and anything dragged with the mouse</li>
</ul>
</div>

## Opening a level

```sh
cd apps/flutter3d_editor
flutter run -d macos --dart-define=level=../flutter3d_demo_dungeon/assets/levels/crypt.json
```

The path is a `--dart-define` because there is no file dialog yet. Point it at a path that doesn't exist and the editor offers a **template** instead of an error:

![The template picker: point the editor at a path that does not exist and it offers to start a platformer or a shooter there](/assets/editor/editor-template.jpg) Picking one writes a whole new project there: a vocabulary, a first level, a model per kind of thing, a `pubspec.yaml`, a `README.md`, an application that runs. Then it opens the level inside it. There is no racing template; a circuit is a different kind of document (points, widths, banks, checkpoints), and editing one is a different editor.

The editor has no vocabulary of its own. A level says `monster` or `torch`, and what those are worth belongs to the game that defines them. The editor builds a registry out of whatever types are already in the document (`vocabulary.dart`) and vouches for none of it. Geometry, materials and lights it can honestly check, so a generated starter level has to load with zero errors and zero warnings against its own game's real rules.

## Getting around

| | |
|---|---|
| `W A S D` | walk, along the ground instead of along the view |
| `Q` / `E` | down / up |
| shift | four times faster |
| drag | look |
| scroll | move forward |

The camera moves where you're pointed on every other page of this site and deliberately doesn't here. The edit made most often is to a floor, which means looking down at it, and a camera that moves where it looks would put you underneath the level on the next press of `W`. Looking and walking are two different things a level editor asks for, so they are two different controls. `Q` and `E` are the only way to change height, and they are absolute regardless of where you are looking. The camera also isn't kept out of walls, on purpose: nothing here should stop you from flying into geometry to look at the back of it.

It opens at the level's own spawn point, at eye height, looking level. Not above the level looking down: in a low-ceilinged room that means opening inside the ceiling.

## Selecting, moving, resizing

Click selects whatever a ray hits, and picking **prefers the thing to the wall**: a torch authored inside stonework or a monster standing on a floor would otherwise be unclickable if the nearest surface always won.

| | |
|---|---|
| click | select |
| arrows | move on the grid, in X and Z |
| `R` `F`, page up/down | raise / lower |
| `1` `2` `3` | pick an axis |
| `-` `=` | resize along the picked axis. With a light selected, dim or brighten it |
| `,` `.` | turn an entity |
| `⌫` | delete |
| `G` | cycle the grid: 0.25 m, 1 m, off |
| `⌘Z` / `⇧⌘Z` | undo, redo (64 steps) |
| `⌘D` | duplicate whatever is selected |
| `⌘S` / `⇧⌘S` | save / save a copy |

Everything the renderer draws nothing for still needs to be clickable and visible: a spawn point, a torch, a monster, a trigger, the exit. Each gets a **mark**, a half-metre box tinted by its type, green for the spawn point, and a light wears the colour it casts.

![The crypt open in the editor: the palette on the left, a wall brush selected, its fields on the right](/assets/editor/editor-brush.jpg)

## The fields on the right

Selecting something opens its document entry as a panel: one row per key that is actually in the file, with the editor chosen by the value that is there — a switch for a flag, a box for a string or a number, three boxes for a vector. There is no case per kind and no case per field, so a key this build has never heard of is shown instead of silently dropped, and the day the format grows a key this panel edits it.

Under **NOT SET** the panel lists what the format defines and this entry leaves out — a brush is solid and casts a shadow by *omission*, so those keys are offered dimmed, at the value the game would read, and writing one puts the key into the document (`Editing.offerable`). Every write goes through the format's own encode and decode (`Editing.setField`), so a value the format cannot read is refused and rolled back instead of saved.

![A trigger selected: its position, size and target as editable fields, and the keys the document leaves unset offered under NOT SET](/assets/editor/editor-trigger.jpg)

## Placing something new

The palette, down the left, is built from the document instead of hardcoded. `paletteOf(level, declared: ...)` lists one row per material a brush could be — `wall`, `floor`, `iron`, each in the colour it is actually painted, because "brush" alone tells you nothing about what you are placing — plus one row for a light and one per entity type the level or its game already declares. Click a row, then click in the scene, on the surface under the cursor instead of in the air in front of the camera:

- **A brush** is placed in the material the row names: `add(at, material: 'wall')` puts down a wall.
- **A light** is placed with `addLight(at)`. The engine defines what a light is, so the editor can invent one without knowing anyone's vocabulary.
- **An entity** is placed by copying the last one of that type already in the document (or a bare one carrying only its `type`, if the level declares the type but has none yet), because the editor cannot know what a `monster` needs in it. Only the game that defines `monster` does.

`⌘D` duplicates whatever's currently selected instead, carrying everything it had.

## Saving, undoing, generated files

Undo is a stack of whole documents, sixty-four deep, replaced wholesale instead of reversed operation by operation. A level is a few hundred numbers, and an undo that reconstructs state from a diff is an undo with its own bugs to have.

`⌘S` refuses to save over a document that says `generatedBy`, and every shipped level here is produced by a Python generator and says so. A hand-edit that looks saved right up until somebody reruns the generator is an afternoon of work that silently disappears. `⇧⌘S` writes a sibling file instead (`crypt.edited.json`) and **takes ownership of the copy**, since a copy that still names the generator would invite the same accident one file over.

## What it does not do yet

No file dialog: the path is a `--dart-define`. Nothing is dragged with the mouse: the marks and selection boxes are drawn, not grabbed, so moving and resizing are keyboard-and-grid only. And the rebuild is the whole level on every change, because a brush is batched into its material's mesh and there is nothing smaller to rebuild; at the size of the levels here that is a frame's work, and it keeps the picture and the document impossible to disagree.

## Next

- [Assembling an application](/core/session/): what the three game apps do instead of this, through `flutter3d_backend`, `flutter3d_session` and `flutter3d_ui`
- [Simulation layer](/core/simulation/): `Level`, `EntityRegistry` and the validator the editor's generated templates are checked against
