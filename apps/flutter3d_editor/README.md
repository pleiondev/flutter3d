# editor

A level editor: open a document, move what is in it, write it back.

```sh
cd apps/flutter3d_editor
flutter run -d macos --dart-define=level=../flutter3d_demo_dungeon/assets/levels/crypt.json
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
| palette, then click | put one down where you clicked |
| `⌘D` | copy what is selected — a monster, a lift, a lamp |
| `−` `=` | a brush's size, or a light's brightness |
| `,` `.` | turn an entity |
| `⌫` | delete |
| `G` | grid: 0.25 m, 1 m, off |
| `⌘Z`, `⇧⌘Z` | undo, redo |
| `⌘S`, `⇧⌘S` | save, save a copy |

## Editing a shader without restarting

Point the editor at a loadable shader bundle and it keeps reading it:

```sh
# 1. Pack the engine's own shaders as a loadable bundle, once. The packer runs
#    on the Flutter SDK's own dart — the bundle's header carries that dart's
#    version, and the editor refuses a bundle stamped with any other — which
#    is the same rule packages/flutter3d/example/tool/build_shaders.sh keeps.
cd packages/flutter3d_impeller && ./tool/build_shaders.sh && cd ../flutter3d_webgl
DART="$(flutter --version --machine | tr -d ' \n' |
  sed -n 's/.*"flutterRoot":"\([^"]*\)".*/\1/p')/bin/cache/dart-sdk/bin/dart"
"$DART" run tool/pack_shaders.dart \
  --manifest ../flutter3d_shaders/shaders/flutter3d.shaderbundle.json \
  --impeller ../flutter3d_impeller/assets/shaders/flutter3d.shaderbundle \
  --name engine --out /tmp/engine.f3dshaders

# 2. Open the editor on it.
cd ../../apps/flutter3d_editor
flutter run -d macos --dart-define=shaders=/tmp/engine.f3dshaders

# 3. Edit a stage the level draws with — the crypt's materials are PBR, so
#    packages/flutter3d_shaders/shaders/lighting/pbr.frag — and run step 1
#    again. The bar says "shaders: engine reloaded" and the level is drawn
#    with the new stage on the next frame.
```

What happens underneath: the bundle is loaded through `GraphicsDevice.loadShaders`
before the renderer is built and handed to it as `materials`, so every stage in
it wins the name over the engine's. `ShaderWatch` polls the file's modification
time twice a second; when it moves, the bytes are read again and the library is
refreshed in place — the handles the renderer holds stay the same objects — and
`Renderer.relinkShaders` drops every pipeline so the next frame links the new
code. A bundle that will not load — a shader that no longer compiles, a section
built with another SDK, one that dropped a stage the renderer holds — is refused
by name in the bar and the previous shaders keep drawing, so a broken rebuild
costs a line of text rather than the viewport.

Two limits, both flutter_gpu's: a stage *added* to the bundle under a name the
editor had already looked up and found missing stays missing until a restart,
and a bundle must be packed with the same SDK the editor is built with.

One thing worth knowing about *this* bundle in particular: it holds the same
entry points the engine's own asset bundle registered at start-up, and
flutter_gpu keeps those in one process-wide table by the shader's file name.
Loading the packed engine over the asset therefore shares the code that was
registered first — the two are identical, so nothing shows — and it is the
**refresh** that changes the picture: `reinitializeFromBytes` marks every stage
in the loaded library dirty, so the next pipeline build registers the edited
code under the name and every material drawn through the loaded `Pbr` takes it.
A bundle of an application's own stages, under its own names, has no such
overlap and behaves the same at load and at refresh.

Exercised on 2026-09-03, Flutter 3.47.0 (Dart 3.13.0), on macOS with Impeller:
the crypt opened through the packed engine bundle, `pbr.frag` was tinted and
rebuilt, the bar read `shaders: engine reloaded`, and the level took the tint
on the next frame; the tint reverted the same way.

## Starting a game

Point the editor at a path that does not exist and it offers a **template**
instead of an error:

```sh
flutter run -d macos --dart-define=level=/where/i/keep/things/deep_mine/assets/levels/first.json
```

Picking one writes a project there — a vocabulary, a first level, a model per
kind of thing that has one to draw, a `pubspec.yaml`, a `README.md` and an
application that runs — and opens the level in it.

**There is one for each of the four genres this repository has**, which is the
point: a level of any of them can be started from nothing rather than by copying
somebody else's document and deleting what is in it. What the four give differs
because their documents differ. The shooter and the platformer are played
indoors, so their first level is a room. Racing gets a field and no road, for the
reason below. Strategy gets the map its demo is played on — ground made of
eighty-one by eighty-one samples of a hillside, two halls, two seams, a purse
each and a block of workers apiece — read out of
`apps/flutter3d_demo_strategy` rather than invented here, because a strategy map
is an economy and a generator with no game behind it cannot make one up and
still call it playable.

**This is not the editor learning a vocabulary**, and the distinction is the
whole of why it is allowed to exist. A template is data: it is copied into the
new project and read back from *there*, by the same `Looks.parse` that reads the
crypt's file. The editor's own code still contains no genre word — only the name
of a file. The genre packages are in this application's `dev_dependencies`, so
the words are proved against the packages that own them, at the sizes those
packages give as their defaults, and never linked into the program. Put them in
`dependencies` instead and you have compiled a vocabulary into an editor whose
whole design is not having one, which is the mistake `EntityRegistry`'s own doc
records somebody already making.

The starter level is checked hard, because `LevelLoader.build` throws on a
validator error and a warning is a new project greeting its author with a
complaint: **zero errors and zero warnings**, against each genre's real registry
and rules. The room's walls surround its floor rather than standing on it —
shared faces, no shared volume — and its light has a range; the racing field's
fence posts stand exactly on the turf's top face for the same arithmetic.

Templates are written by `tool/make_templates.py` and their models by
`tool/make_models.py`, which writes real glTF out of primitives: no textures, no
skins, no animation, no licences, and coordinates quantised onto a 1/4096 m grid
so the bytes are the same on every machine. `ci.sh` regenerates both and fails if
what comes out is not what is committed.

**Two of the four ship no model, and the absence is deliberate.** Racing places
no entities at all, so there is no kind of thing to draw one of; strategy draws
its crowd as one instanced box `UnitSize` across and its halls as boxes, because
a thousand workers in one draw call is the reason that genre exists — so a `.glb`
of a worker would be a file whose only content is a number the strategy package
already holds, and the mark the editor draws is the same box the game builds.

### The racing template is half a circuit

**A track is not edited here, and it is not an oversight.** A circuit in this
repository is two documents. One is a level, in the format everything else uses:
the turf a car lands on when it leaves the road, the posts along the outside, the
sun and the haze. The other is the road itself — a measured curve of points with
a width, a camber and a bank at each, the barriers along it, the checkpoints
across it and the grid the field starts from — and it is read by `TrackDocument`,
not by `Level`. Nothing about it is geometry a brush could be: a corner is a
radius and a width, and the surface under a wheel is worked out from the curve
rather than swept against a box.

So the template is the level half, and only that. A new racing project gets
somewhere to drive and no road on it: editing the curve means dragging control
points, seeing the line a car would take, and watching a lap change — which is a
different editor, and one that does not exist. Until it does, circuits are
written by `apps/flutter3d_demo_racing/tool/make_track.py`, which is where the
five in the demo come from.

What the level half still buys is the part that is genuinely shared: the ground,
the scenery and the air. The template's sun and haze are `SkyPresets.morning`
read out of the racing package rather than numbers chosen beside it, because the
sky, the fog and the colour distance settles to are one decision — that is what
stops the far side of a circuit ending in a visible band, and authoring them
apart is how it starts.

## The palette

Down the left, built from the document. A level with lifts offers lifts; a game
this repository has never heard of gets an editor that knows its words without a
line being written about it. Click a row to pick something up, click in the level
to put one down where you clicked, `esc` to put it down.

**A brush is offered as its materials rather than as the word "brush"**, and the
question that caused that is worth keeping: *is brush a wall?* It is not. A brush
is a box; what makes it a wall rather than a floor is the material it names. So
the palette lists `wall`, `floor`, `ceiling`, `iron` — in the colours those are
actually painted — and a row puts down a brush of that material.

A light is the other thing the editor may invent, because a `LevelLight` is
something the engine defines. Everything else is placed by copying the last one
of its type, with everything it was carrying.

## What it draws

**The level's own textures**, read off the disk beside the document rather than
out of this application's bundle — a game's assets are in the game's bundle, and
the editor is always looking at somebody else's. Without it the one program whose
job is to show what a level looks like showed it in flat grey.

**What the game says its own words look like.** A document says `type: torch`
and where it is; what a torch *looks* like is in the game's code — the crypt
builds one out of primitives and a light, and there is no torch model anywhere
for anybody to find. The editor cannot work that out and must not guess, so the
game tells it, in an optional `assets/editor.json` beside its other assets:

```json
{
  "monster": { "model": "assets/models/monster_{kind}.glb", "size": [0.9, 1.9, 0.9] },
  "torch":   { "size": [0.22, 0.75, 0.22], "tint": [1.0, 0.55, 0.12] }
}
```

`{kind}` is any property of the entity, put into the path: one line covers three
monsters, and a fourth is a file rather than a mapping. **This is not the editor
learning a vocabulary** — it reads a file whose words it does not understand,
exactly as it reads a level. A game that writes none gets marks. The file is
beside the game's asset directories rather than in one, so no player downloads
it.

What the entity itself says always wins: a level that names a model on one
particular door has said something about that door.

**A door as a door.** Anything whose document entry carries a `size` is drawn at
that size, and in the material it names if the level has one — so a six-metre
iron door is a six-metre iron door and a lift is a platform. Anything carrying a
`model` is drawn as the model, read from the game's own `assets/models`. What has
neither is a coloured mark, which is all a coordinate and a word can be.

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

**Half of this application is not in this application.** Everything with no
window in it — the document being changed, what a click hits, the palette, what
a game says its own words look like, the project a template becomes — is
`packages/flutter3d_editor_core`, which is plain Dart and which anything may
depend on. That is the whole reason the split exists: what an editor is *for* is
a picture, and what it can get catastrophically wrong is a file, and only one of
those needs a screen to be checked. `Editing`, `Picking`, `handlesOf`,
`Placeable`, `Looks`, `vocabularyOf` and `scaffold` all arrive through
`package:flutter3d_editor_core/flutter3d_editor_core.dart`.

What is left here is the half that reaches a device:

* `src/documents.dart` — the disk: which file is open, reading it, and writing
  it back atomically. It is `dart:io`, and it is where a crash loses somebody's
  work.
* `src/fly_camera.dart` — a camera that goes into walls on purpose. Every other
  camera here follows something and is kept out of geometry, which is right for
  the games and exactly wrong for this. It needs the renderer to have a camera
  at all, which is why it did not travel.
* `src/scene_dressing.dart` — the document turned into something drawn, and the
  handles drawn over it.
* `src/editor_cubit.dart` and the widgets beside it — which document is open,
  why one is not, and what the strip along the bottom says.
* `src/shader_watch.dart` — the shader bundle reloaded while somebody edits it.
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

No file dialogue (the path is a `--dart-define`), and nothing is dragged with
the mouse — the marks and selection boxes are drawn, not grabbed, so moving and
resizing are on the keyboard and on the grid. The rebuild is the whole level on
every change, because a brush is batched into its material's mesh and there is
nothing smaller to rebuild; at the size of the levels here that is a frame's
work and it keeps the picture and the document impossible to disagree.
