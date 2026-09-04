# flutter3d_session

The part of a game that is neither its simulation nor its screens: the seam a
rendered frame reaches Flutter through, and the run being played.

## Why it is its own package

A session reads a level and writes a save. Reading a level needs
`flutter3d_bridge`, and therefore the renderer. Writing a save needs
`flutter3d_screens`, and therefore storage. **Those two packages do not know about
each other**, deliberately — the bridge has no business knowing what a settings
file is, and the UI has no business knowing what a scene is.

So the code that needs both cannot live in either. It lived, instead, in three
`main.dart` files, written out three times.

## What is in it

| | |
|---|---|
| `SceneSurface` | The widget that hands a frame to Flutter. Its settings are a **function called per frame**, not an object, so anything derived from where the camera ended up is derived after it got there. |
| `RunSession` | Loading a level, restarting it, moving to the next, saving and resuming, and reporting how the run ended. |

## What is deliberately not in it

**The title card and the loss screen.** Those are the face of a particular game.
Three identical title screens would be a loss, not a saving.

**`backend.dart` and its two halves.** All three games carry it and all three
copies are near enough byte-identical, which looks like the clearest extraction
in the repository until you read what it does: a conditional import choosing
between `flutter3d_impeller` and `flutter3d_webgl`. A shared copy would have to
depend on both, against the decision written into `flutter3d.dart` — *"an
application picks one and depends on one by name"*. Three files of a dozen lines
is cheaper than every game carrying both backends.

**A state-management choice.** `RunSession` is an ordinary class. Two of the
three games wrap it in a cubit and the package neither knows nor cares.

**The third game's season.** Racing moves from one circuit to the next and keeps
where somebody got to, which looks like a `RunSession` and is not one: nobody
resumes a race half a lap in, so `snapshotOf` and `restoreInto` would be two
required overrides returning nothing. A base class whose contract half its users
have to stub is a base class that has been stretched one game too far.

## The rule this package exists to keep

**One assembly per game.** Every game has exactly one function that turns a
level document into a run — `stage` in each application — and nothing else
spawns a level. The platformer had six copies of that assembly and they had
drifted; the dungeon had two, and one of them proved the crypt finishable with a
loadout the game never gives anybody.

It is checked rather than remembered: `test/one_assembly_test.dart` here reads
all three applications, in the shape of `no_genre_test.dart` — one rule about
three games, so one file rather than three. The racing game was the third
offender and was found by that scan being written.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
