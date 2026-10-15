# A scene written as widgets

Every other page builds its scene by hand: make a `MeshNode`, add it, keep
a reference to move it later. `flutter3d_app` also lets a scene be written
the way the rest of a Flutter app is, as a tree of widgets that says what
should be there now. Each widget owns one node of an ordinary `Scene`. A
rebuild gives the node the widget's new properties, Flutter's keys decide
which node is which, and a widget that leaves the tree takes its node out
of the scene.

## Step 1: Describe the scene

`Light3D`, `Mesh3D`, `Node3D`, `Camera3D` and `Model3D` are the nodes.
`Material3D` is a material as a widget: every `Mesh3D` below it without a
material of its own is drawn with the one engine material it makes, so the
boxes here share it and the renderer can still batch them. `Node3D` is an
empty node with a transform, and what hangs below it moves with it. The
names end in `3D` because `SceneNode` and `Material` are already the
engine's.

The whole scene is one function of three fields of the page: how many
boxes, which paint, and the pivot's angle.

{{code widgets}}

Each box has a key. Without one, removing the first box would hand its
node to the second widget and so on down the row; with one, the node of
`box 0` stays `box 0`. A shape made fresh on every build, as these are, is
built again but uploaded again only when its vertices change.

## Step 2: Mount it into a scene somebody else draws

An app that only wants a picture puts the same children in a `Scene3D`,
which opens a device, makes a renderer and draws every frame. The
showcase already has all of that, so this page uses `SceneWidgets.mount`,
which builds the widgets into a scene it is given and draws nothing.
It is also how a test or a game with its own loop uses them.

Every frame the page turns the pivot a little and calls `update` with the
new tree, which is what `setState` would do under a `Scene3D`. The slider
and the switch only change a field, and the next rebuild shows it.

{{code mount}}

## Step 3: What the page checks

There have to be as many meshes as there are mesh widgets, and the boxes
have to share one material. Then the page rebuilds with one more box and
the other paint: `box 0` has to be the same node as before, still holding
the same material, now in the new colour, and the new box has to be in the
scene. A rebuild with that box gone has to take its node out again.

{{code check}}

> **Note.** A widget sets only the properties it is given. A transform left
> null leaves the node where the game put it, so a node moved by hand is not
> put back by a rebuild that does not say where it goes. The widgets cover
> meshes, models, lights, cameras, materials, reflection probes, decals,
> mirrors and particles; anything else is added by `Contributor3D` or by
> reaching the scene in `Scene3D.onCreated`.
