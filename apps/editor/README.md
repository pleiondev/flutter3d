# editor

A level editor: open a document, move what is in it, write it back.

```sh
cd apps/editor
flutter run -d macos --dart-define=level=../dungeon/assets/levels/crypt.json
```

## What it is

The fourth application in this repository and the first that is not a game. It
reads a level document off the disk, draws it with the same `LevelLoader` the
games use, and lets somebody fly around it and change it.

| | |
|---|---|
| `W A S D` | walk, along the ground rather than along the view |
| `Q` `E` | down and up |
| shift | four times faster |
| drag, scroll | look, and move forward |
| click | select a brush |
| arrows | move it on the grid, in X and Z |
| `R` `F`, page up/down | raise and lower it |
| `1` `2` `3`, `−` `=` | pick an axis and resize along it |
| `N`, `L` | a new brush, a new light |
| `⌘D` | copy what is selected — a monster, a lift, a lamp |
| `−` `=` | a brush's size, or a light's brightness |
| `,` `.` | turn an entity |
| `⌫` | delete |
| `G` | grid: 0.25 m, 1 m, off |
| `⌘Z` | undo |
| `⌘S`, `⇧⌘S` | save, save a copy |

## Half a level is not geometry

The crypt is fifty-one brushes and sixteen other things: a spawn point, six
torches, two monsters, three pickups, a door, a key, a trigger, a note and the
way out. The renderer draws none of them — a monster is a coordinate and a word
until the game spawns something — so an editor that could only touch what is on
screen could not place one.

Everything with nothing to show gets a **mark**: a half-metre box, coloured by
its type's own name (six torches are six of the same colour), green for wherever
the player starts, and a light wears the colour it casts. The mark is both what
gets drawn and what a click hits.

A click **prefers the thing to the wall**. A torch is authored inside the
stonework, a monster stands on a floor, a lift's marker sits in the block it
moves — sorted strictly by distance the surface always wins, which would mean
every torch in the crypt is unclickable.

**Copy is how a level gets a second monster.** The editor has no vocabulary: it
cannot know what a `monster` needs in it or which of a lift's properties matter.
So it does not invent one — `⌘D` copies one the level already has, with
everything it was carrying, and you move the copy. A light it *may* invent,
because a `LevelLight` is something the engine defines: a place, a colour, a
strength and a reach.

## Three decisions worth the words

**A generated document is not written back over.** Every level in this
repository was produced by a Python generator, and each one says so in its own
`generatedBy` key — which `Level`'s doc comment calls "the question an editor
has to ask before it is allowed to save". Editing `crypt.json` by hand and
saving it produces a file that looks edited right up until somebody runs
`make_crypt.py` again, at which point the afternoon is gone and nothing ever
said so. `⌘S` refuses and says who owns the file; `⇧⌘S` writes
`crypt.edited.json` beside it **and takes ownership of the copy**, because a
copy still naming the generator invites the same accident.

**Desktop only, and there is no web half.** The other three applications choose
between Impeller and WebGL at compile time because they ship to a browser as
well. This one exists to write a file back over itself, which a browser will
not do — so there is no backend to choose and no `backend_web.dart`.

**It has no vocabulary of its own.** A level says `monster` or `coin` or
`checkpoint`, and what those are worth belongs to the game — the engine's own
`EntityRegistry` doc records that its first version shipped a list of fourteen
kinds a second game silently validated its levels against. So this accepts
whatever a document happens to name and vouches for none of it: `vocabularyOf`
builds a registry out of the types already in the file. What it can honestly
check is geometry, materials and lights.

## Where the parts are

* `src/editing.dart` — the document being changed: select, move, resize, add,
  duplicate, delete, undo, write. **No window anywhere in it**, which is the
  whole reason the split exists: what an editor is *for* is a picture, and what
  it can get catastrophically wrong is a file.
* `src/picking.dart` — a ray against the brushes. Against the *brushes* and not
  against the collision world, because a brush with `solid: false` never
  reaches the collision world — and those are the mouldings and the painted
  alcoves, exactly the decoration somebody opens an editor to move.
* `src/fly_camera.dart` — a camera that goes into walls on purpose. Every other
  camera here follows something and is kept out of geometry, which is right for
  the games and exactly wrong for this.
* `src/vocabulary.dart` — see above.
* `main.dart` — the window, the keys and the mouse.

## Getting about

**W walks along the ground, not along the view.** A camera that moves where it
looks is unusable in a corridor: the edit somebody makes most is to a floor,
which they have to look down at to see, and the next press of W then puts them
underneath the level. Looking at a thing and walking past another thing are two
different directions, so they are two different keys — `Q` and `E` are the only
way to change height, and they are absolute.

It opens **where the player spawns**, at eye height, looking level. A level
opened from four metres up looking down is a level nobody can find their way
around: four metres in a crypt is inside the ceiling.

Nothing stops the camera at a wall, on purpose — see `fly_camera.dart`.

## What it does not do yet

No file dialogue (the path is a `--dart-define`), no entities or lights (brushes
only), no material picker, no redo, and no gizmos — moving is on the keyboard
and on the grid. The rebuild is the whole level on every change, because a brush
is batched into its material's mesh and there is nothing smaller to rebuild; at
the size of the levels here that is a frame's work and it keeps the picture and
the document impossible to disagree.
