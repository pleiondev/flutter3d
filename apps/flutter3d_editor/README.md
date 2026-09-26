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
| drag a bar of the selection box | move what is selected along that bar |
| click | select a brush |
| arrows | move it on the grid, in X and Z |
| `R` `F`, page up/down | raise and lower it |
| `1` `2` `3`, `−` `=` | pick an axis and resize along it |
| palette, then click | put one down where you clicked |
| `⌘D` | copy what is selected (a monster, a lift, a lamp) |
| `−` `=` | a brush's size, or a light's brightness |
| `,` `.` | turn an entity |
| `⌫` | delete |
| `G` | grid: 0.25 m, 1 m, off |
| `⌘Z`, `⇧⌘Z` | undo, redo |
| `⌘S`, `⇧⌘S` | save, save a copy |
| `⌘O` | open another level |

## Opening a level

There are three ways to open a level, and all of them end in the same read.

`⌘O` puts up the system's open panel. Pick a `.json` level anywhere on the
machine and it opens; there is no working directory to stand in and no path to
spell. While the open document has unsaved changes, `⌘O` refuses and says so in
the bar instead of putting up a dialogue. Closing the window is something
somebody meant to do, so it gets three buttons. `⌘O` is a key next to `⌘S` and
gets pressed by accident.

Every document that opens is recorded, and the next launch offers them back. If
you point the editor at nothing, or at a path that is not there, the screen that
offers the four templates lists the projects you were working on above them:
eight of them, most recent first. A project that has since been moved, renamed
or deleted is left off. The editor asks the disk on every read, so every row on
the list opens. The list lives in `recent.json` beside the settings a game
keeps, through the same storage and for the same reasons: it is per platform,
it is written through a temporary file and a rename, and losing it costs
nothing.

The `--dart-define` is for a level named by something that is not a person. The
tests use it, scripts use it, and so does `flutter run` beside the levels in
this repository. All of them know the path already and have no hand to point
with.

```sh
flutter run -d macos --dart-define=level=../flutter3d_demo_dungeon/assets/levels/crypt.json
```

The panel comes from one plugin, called from one function.
`package:file_selector` is the first plugin here that was not written here.
`pad_input` and `pointer_lock` are packages in this repository, and their
platform code can be read and fixed in the same checkout. The plugin provides
the one thing Dart alone cannot, the panel this platform's own applications put
up, and it is called from `askForLevel` in `src/editor_chooser.dart` and nowhere
else. The parts that can go wrong without a window live elsewhere on purpose:
`src/documents.dart` decides which path a spelling means,
`src/recent_projects.dart` decides which projects are still worth offering, and
both are tested with no plugin registered.

The panel is also not how this application gets *access*. The macOS sandbox is
off here, and `macos/Runner/*.entitlements` carries the whole argument: an
editor that opens a document somewhere in this repository, changes it and
writes it back over itself is exactly what the sandbox exists to stop. The
panel saves somebody typing a path. It grants no permission.

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

The bundle is loaded through `GraphicsDevice.loadShaders` before the renderer
is built and is handed to it as `materials`, so every stage in it wins the name
over the engine's. `ShaderWatch` polls the file's modification time twice a
second. When the time moves, the bytes are read again and the library is
refreshed in place (the handles the renderer holds stay the same objects), and
`Renderer.relinkShaders` drops every pipeline so the next frame links the new
code. A bundle that will not load is refused by name in the bar, and the
previous shaders keep drawing. That covers a shader that no longer compiles, a
section built with another SDK, and a bundle that dropped a stage the renderer
holds. A broken rebuild costs a line of text and leaves the viewport alone.

flutter_gpu sets two limits. A stage *added* to the bundle under a name the
editor had already looked up and found missing stays missing until a restart.
And a bundle must be packed with the same SDK the editor is built with.

*This* bundle holds the same entry points the engine's own asset bundle
registered at start-up, and flutter_gpu keeps those in one process-wide table
by the shader's file name. Loading the packed engine over the asset therefore
shares the code that was registered first. The two are identical, so nothing
shows. The **refresh** is what changes the picture: `reinitializeFromBytes`
marks every stage in the loaded library dirty, so the next pipeline build
registers the edited code under the name, and every material drawn through the
loaded `Pbr` takes it. A bundle of an application's own stages, under its own
names, has no such overlap and behaves the same at load and at refresh.

Exercised on 2026-09-03, Flutter 3.47.0 (Dart 3.13.0), on macOS with Impeller:
the crypt opened through the packed engine bundle, `pbr.frag` was tinted and
rebuilt, the bar read `shaders: engine reloaded`, and the level took the tint
on the next frame. The tint reverted the same way.

## Starting a game

Point the editor at a path that does not exist and it offers a template
instead of an error:

```sh
flutter run -d macos --dart-define=level=/where/i/keep/things/deep_mine/assets/levels/first.json
```

Picking one writes a project there and opens the level in it. The project has a
vocabulary, a first level, a model for each kind of thing that has one to draw,
a `pubspec.yaml`, a `README.md` and an application that runs.

There is one template for each of the four genres in this repository, so a
level of any of them can be started from nothing, without copying somebody
else's document and deleting what is in it. The four give different things
because their documents differ. The shooter and the platformer are played
indoors, so their first level is a room. Racing gets a field and no road, for
the reason below. Strategy gets the map its demo is played on: ground made of
eighty-one by eighty-one samples of a hillside, two halls, two seams, a purse
each and a block of workers apiece. That map is read out of
`apps/flutter3d_demo_strategy` and not invented here, because a strategy map is
an economy, and a generator with no game behind it cannot make one up and still
call it playable.

Templates are allowed to exist only because they do not teach the editor a
vocabulary. A template is data: it is copied into the new project and read back
from *there*, by the same `Looks.parse` that reads the crypt's file. The
editor's own code still contains no genre word, only the name of a file. The
genre packages are in this application's `dev_dependencies`, so the words are
proved against the packages that own them, at the sizes those packages give as
their defaults, and are never linked into the program. Putting them in
`dependencies` would compile a vocabulary into an editor designed around not
having one, which is the mistake `EntityRegistry`'s own doc records somebody
already making.

The starter level has to pass with **zero errors and zero warnings** against
each genre's real registry and rules. `LevelLoader.build` throws on a validator
error, and a warning would greet a new project's author with a complaint. The
room's walls surround its floor instead of standing on it (shared faces, no
shared volume), and its light has a range. The racing field's fence posts stand
exactly on the turf's top face for the same arithmetic.

Templates are written by `flutter3d_editor_core`'s `tool/levels/templates.dart`
(through `dart run tool/regenerate_levels.dart`) and their models by
`tool/make_models.py`. That script writes real glTF out of primitives, without
textures, skins, animation or licences, and quantises coordinates onto a
1/4096 m grid so the bytes are the same on every machine. `ci.sh` regenerates
both and fails if what comes out is not what is committed.

Two of the four templates ship no model, on purpose. Racing places no entities
at all, so there is nothing to draw one of. Strategy draws its crowd as one
instanced box `UnitSize` across and its halls as boxes, because a thousand
workers in one draw call is the reason that genre exists. A `.glb` of a worker
would be a file whose only content is a number the strategy package already
holds, and the mark the editor draws is the same box the game builds.

### The racing template is half a circuit

The editor does not edit tracks, and that is deliberate. A circuit in this
repository is two documents. One is a level, in the format everything else
uses: the turf a car lands on when it leaves the road, the posts along the
outside, the sun and the haze. The other is the road itself, read by
`TrackDocument` and not by `Level`. It holds a measured curve of points with a
width, a camber and a bank at each, the barriers along it, the checkpoints
across it and the grid the field starts from. None of that is geometry a brush
could be: a corner is a radius and a width, and the surface under a wheel is
worked out from the curve instead of swept against a box.

So the template is the level half and only that. A new racing project gets
somewhere to drive and no road on it. Editing the curve means dragging control
points, seeing the line a car would take and watching a lap change, which is a
different editor, and that editor does not exist. Until it does, circuits are
written by `flutter3d_editor_core`'s `tool/levels/racing.dart`, which is where
the five in the demo come from.

The level half still covers what the two documents share: the ground, the
scenery and the air. The template's sun and haze are `SkyPresets.morning`, read
out of the racing package instead of numbers chosen beside it, because the sky,
the fog and the colour distance settles to are one decision. Deciding them
together stops the far side of a circuit ending in a visible band, and authoring
them apart is how that band starts.

## The palette

The palette runs down the left and is built from the document. A level with
lifts offers lifts, and a game this repository has never heard of gets an
editor that knows its words without a line being written about it. Click a row
to pick something up, click in the level to put one down where you clicked,
and press `esc` to put it down.

The palette offers a brush as its materials instead of as the word "brush".
That came from the question *is brush a wall?* It is not. A brush is a box, and
the material it names is what makes it a wall and not a floor. So the palette
lists `wall`, `floor`, `ceiling` and `iron`, in the colours those are actually
painted, and a row puts down a brush of that material.

A light is the other thing the editor may invent, because a `LevelLight` is
something the engine defines. Everything else is placed by copying the last one
of its type, with everything it was carrying.

## What it draws

The editor draws the level's own textures, read off the disk beside the
document and not out of this application's bundle. A game's assets are in the
game's bundle, and the editor is always looking at somebody else's. Without
this, the one program whose job is to show what a level looks like showed it in
flat grey.

It also draws what the game says its own words look like. A document says
`type: torch` and where the torch is. What a torch *looks* like is in the game's
code: the crypt builds one out of primitives and a light, and there is no torch
model anywhere for anybody to find. The editor cannot work that out and must
not guess, so the game tells it, in an optional `assets/editor.json` beside its
other assets:

```json
{
  "monster": { "model": "assets/models/monster_{kind}.glb", "size": [0.9, 1.9, 0.9] },
  "torch":   { "size": [0.22, 0.75, 0.22], "tint": [1.0, 0.55, 0.12] }
}
```

`{kind}` is any property of the entity, put into the path. One line covers
three monsters, and a fourth is a file and not a new mapping. This does not
teach the editor a vocabulary either: it reads a file whose words it does not
understand, exactly as it reads a level. A game that writes none gets marks.
The file sits beside the game's asset directories and not in one, so no player
downloads it.

What the entity itself says always wins: a level that names a model on one
particular door has said something about that door.

A door is drawn as a door. Anything whose document entry carries a `size` is
drawn at that size, and in the material it names if the level has one, so a
six-metre iron door is a six-metre iron door and a lift is a platform. Anything
carrying a `model` is drawn as the model, read from the game's own
`assets/models`. What has neither is a coloured mark, which is all a coordinate
and a word can be.

## Half a level is not geometry

The crypt is fifty-one brushes and seventeen other things: a spawn point, six
torches, two monsters, three pickups, a door, a key, a trigger, a note and the
way out. The renderer draws none of them, since a monster is a coordinate and a
word until the game spawns something. An editor that could only touch what is
on screen could not place one.

Everything with nothing to show gets a **mark**: a half-metre box, coloured by
its type's own name (six torches are six of the same colour), green wherever the
player starts, and a light wears the colour it casts. The mark is both what gets
drawn and what a click hits.

A click prefers the thing to the wall. A torch is authored inside the
stonework, a monster stands on a floor, and a lift's marker sits in the block it
moves. Sorted strictly by distance, the surface would always win, and every
torch in the crypt would be unclickable.

## Taking hold of something

The selection box is a cage of twelve bars, and those bars are what a hand
grabs. Press on one and the selected thing follows the pointer along that bar
until the button comes up. The bar decides the axis: a wall goes sideways along
the bars that run sideways and up along the ones that stand upright. There is no
mode to be in and nothing to press first.

Everything uses one button, and where a press starts decides what it means. A
press that does not move is a click. A press that moves off a bar is a drag. A
press that moves anywhere else turns the camera; that is most of the screen,
and it is why nobody has to be told how to look around. Looking was on the right
button once. On a trackpad that is a two-finger press-and-drag, and it was so
hard to discover that the person this was built for could not get down the
first corridor.

The press is decided by a ray, not by the pixel. Selecting reads back the pixel
under the click, and that answer arrives a frame later and is allowed to be a
refusal. That is fine for a click and useless for a press that has to know
*this instant* whether it is dragging a wall or turning the view. So each bar is
also a box, built from the same numbers that draw it, and the press traces a ray
against the twelve of them with the `Picking` the rest of the editor already
uses.

A drag is one step in the history instead of sixty. The document moves on
every report of the pointer, because the picture is rebuilt from the document
and nothing smaller than the document exists to move. Recorded one report at a
time, that would spend the whole undo stack in a second, and the change
somebody actually wanted back would go with it. So the moves are made straight
in the document. On release, the editor puts the thing back where the drag
started and makes the whole move once, inside one transaction. The stack gets
one entry, taken against the level as it stood before anybody touched the mouse.

A level gets a second monster by copying. The editor has no vocabulary: it
cannot know what a `monster` needs in it or which of a lift's properties matter.
So it does not invent one. `⌘D` copies one the level already has, with
everything it was carrying, and you move the copy. A light it *may* invent,
because a `LevelLight` is something the engine defines: a place, a colour, a
strength and a reach.

## Three decisions worth the words

The editor does not write over a generated document. Every level in this
repository was produced by a Python generator, and each one says so in its own
`generatedBy` key, which `Level`'s doc comment calls "the question an editor
has to ask before it is allowed to save". Editing `crypt.json` by hand and
saving it produces a file that looks edited right up until somebody runs
`make_crypt.py` again. At that point the afternoon is gone and nothing ever said
so. `⌘S` refuses and says who owns the file. `⇧⌘S` writes `crypt.edited.json`
beside it and takes ownership of the copy, because a copy still naming the
generator invites the same accident.

The editor is desktop only, with no web half. The other three applications
choose between Impeller and WebGL at compile time because they ship to a
browser as well. This one exists to write a file back over itself, which a
browser will not do, so there is no backend to choose and no
`backend_web.dart`.

The editor has no vocabulary of its own. A level says `monster` or `coin` or
`checkpoint`, and what those are worth belongs to the game. The engine's own
`EntityRegistry` doc records that its first version shipped a list of fourteen
kinds that a second game silently validated its levels against. So the editor
accepts whatever a document happens to name and vouches for none of it:
`vocabularyOf` builds a registry out of the types already in the file. What it
can honestly check is geometry, materials and lights.

## Where the parts are

Half of this application lives outside it. Everything with no window in it (the
document being changed, what a click hits, the palette, what a game says its
own words look like, the project a template becomes) is in
`packages/flutter3d_editor_core`, which is plain Dart and which anything may
depend on. The split exists because what an editor is *for* is a picture, what
it can get catastrophically wrong is a file, and only the picture needs a screen
to be checked. `Editing`, `Picking`, `handlesOf`, `Placeable`, `Looks`,
`vocabularyOf` and `scaffold` all arrive through
`package:flutter3d_editor_core/flutter3d_editor_core.dart`.

What is left here is the half that reaches a device:

* `src/documents.dart` handles the disk: which file is open, reading it, and
  writing it back atomically. It is `dart:io`, and it is where a crash loses
  somebody's work.
* `src/fly_camera.dart` is a camera that goes into walls on purpose. Every other
  camera here follows something and is kept out of geometry, which is right for
  the games and exactly wrong for this. It needs the renderer to have a camera
  at all, which is why it did not travel.
* `src/scene_dressing.dart` turns the document into something drawn and draws
  the handles over it: the marks, the selection box, the bars of it a drag
  takes hold of, and the gesture that moves what was grabbed.
* `src/recent_projects.dart` holds the projects offered back on the second
  launch: what the stored document still means, which order they go in, and
  which of them the disk no longer has. It reaches `dart:io` only through a
  `Storage`, so it is tested against a map.
* `src/editor_cubit.dart` and the widgets beside it track which document is
  open, why one is not, and what the strip along the bottom says.
  `editor_chooser.dart` is also where the open panel is called, in one
  function, because it is the one screen whose whole subject is choosing a
  document.
* `src/shader_watch.dart` reloads the shader bundle while somebody edits it.
* `main.dart` holds the window, the keys and the mouse.

## Getting about

W walks along the ground, not along the view. A camera that moves where it
looks is unusable in a corridor. The edit somebody makes most is to a floor,
which they have to look down at to see, and the next press of W then puts them
underneath the level. Looking at one thing and walking past another are two
different directions, so they are two different keys. `Q` and `E` are the only
way to change height, and they are absolute.

The editor opens where the player spawns, at eye height, looking level. From
four metres up looking down, nobody could find their way around a level: four
metres in a crypt is inside the ceiling.

Nothing stops the camera at a wall, on purpose (see `fly_camera.dart`).

## What it does not do yet

Dragging moves things and nothing else. Size is still `1` `2` `3` and `−` `=`
on the keyboard, and facing is still `,` and `.`, because a bar that meant
"move" when pulled and "resize" when pushed would be a bar nobody could aim.
Everything a drag does is on the grid, the same quarter of a metre the arrow
keys use.

Every change rebuilds the whole level, because a brush is batched into its
material's mesh and there is nothing smaller to rebuild. At the size of the
levels here that is a frame's work, and it keeps the picture and the document
from ever disagreeing. A drag goes through the same gate as everything else: the
document is marked stale and the next frame rebuilds it. A pointer reporting
faster than the screen draws therefore costs one rebuild, not one per report.
