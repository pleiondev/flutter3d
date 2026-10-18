# Changing a running game's assets

Flutter's hot reload swaps the Dart code and keeps the app's state. For a
3D game that is only half of it: the textures, models and shaders were
loaded once, and nothing in Flutter knows the files they came from. `HotSwap`
in `flutter3d_app` is the other half. It remembers what was loaded from
which file, and on a hot reload it reads each file again, and whatever
changed is put in place of the old version in the nodes and materials the
game already has. The world keeps running; nothing is instantiated again.

`SceneSurface` calls `HotSwap.instance.swap()` from `reassemble`, which is
what a hot reload runs, and a tool can run the same swap over the VM
service as `ext.flutter3d.assets.swap`. It works in debug builds only: in
profile and release every method returns at once and holds nothing.

## Step 1: Files the page can edit

`HotSwap` never opens a file itself. Each registration takes a function
that reads the file's current bytes and one that builds them into what the
game draws, which is how its own tests run with no disk at all. This page
uses the same door: its two "files" are bytes it holds, and a button
changes them the way saving in an editor would.

{{code files}}

The poster's file decodes into a small square of one colour. The model's
file builds one box called `hull`, in a material called `hull paint`.

{{code decoders}}

## Step 2: Register what was loaded

`registerTexture` and `registerModel` take the asset as it was loaded, the
two functions, and the bytes it was built from, so that the first swap
compares against those rather than taking the file as a change. A game
reading real assets calls `loadTexture` and `loadModel`, which read the
asset bundle and register in one step. Instances of the model are made
through the `SwappableModel`, which remembers them. The scene and the
renderer are registered the way `SceneSurface` registers its own.

{{code register}}

## Step 3: Change both files and swap

After the swap the poster's material holds a new texture, uploaded from
the new bytes; it may be another size or format, since it is a texture of
its own and the old one is released after the frames that still sample
it. The model is built again, and every instance adopts it: each surface
is matched by node name and slot, the matching `MeshNode` is handed the new
geometry and material, and the node itself stays, with its transform and
anything the game hung from it. The report says which files were taken
and which were refused; a file that does not build keeps the last version
that did.

{{code swap}}

## Step 4: Set a material from outside

`setMaterial` is what an inspector's slider sends, over the VM service as
`ext.flutter3d.material.set`. It sets fields on every material of that
name in the registered scenes from the next frame on, and keeps them as
overrides. Saving the model afterwards brings the material as the file has
it, and the override is put back on, so the colour somebody is dragging
does not snap back on every save. `clearMaterial` lets it go.

{{code material}}

## Step 5: A tunable, through the input

A number the simulation reads, like this spin speed, is not a material's
business. It is changed through `InputState.tune`, which is what
`ext.flutter3d.cvar.set` calls, and the step takes it with
`Tunables.take` before it reads anything. Because it goes through the
input, a recorded run holds the change at the step it was made, and a
replay makes it at the same moment.

{{code tunable}}

{{code step}}

## Step 6: What the page checks

Before the swap the poster and the hull are red. After one swap the poster
is blue and the hull green, the report names the texture and one instance
of the model, and the hull is drawn by the same `MeshNode` as before. After
the paint is set to yellow and the model is saved in blue, the hull is
still yellow. A tunable set through the input has the new value after the
step takes it.

{{code check}}

> **Note.** A shader bundle the game loaded from bytes is refreshed the
> same way, through `registerLibrary`, and a `.f3dmat` through
> `loadMaterial`; this page does not draw one, because the bytes it would
> swap are a compiled bundle. A model's embedded images swap with the
> model, not on their own. `setMaterial` refuses a shader parameter the
> material was not loaded with, so a parameter the shader gained since the
> game started needs the material loaded again. A stage added under a name
> the renderer already looked up needs a restart.
