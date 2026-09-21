# Keeping a Flame position and a flutter3d node in step

`Object3dComponent` is the one place a Flame `PositionComponent` and a
flutter3d `SceneNode` are kept at the same place, on one `BridgePlane`. A
`SyncDirection` decides which side is authoritative each frame; nothing here
infers a direction from which value changed most recently.

## Step 1: The scene is authoritative

The default direction, `SyncDirection.sceneToFlame`, is what every existing
flutter3d system — a rigid body, an actor — already wants: it decides where
things are, and the Flame component only ever reads that. Moving the node and
calling `update` carries the move onto the Flame side.

{{code scene-authoritative}}

## Step 2: Flame is authoritative

`SyncDirection.flameToScene` reverses it: the Flame component decides, and
`update` writes that position onto the node instead — a Flame-driven prop
that should also draw as a 3D object, say.

{{code flame-authoritative}}

## Step 3: One `BridgePlane`, both directions

Both components above share the same ground plane, so a Flame `(x, y)` and a
flutter3d `(x, height, y)` mean the same point everywhere in this scene.

{{code shared-plane}}

A node moved to `(3, 0, 2)` reads back as Flame `(3, 2)`; a Flame position set
to `(4, -1)` reads back as scene `x=4, z=-1`.

The node that moved carried its position onto the Flame side, and the Flame
position that moved carried its onto the node — both readings came back
exactly where the bridge's own plane said they would.

## Step 4: Watch them keep step

On the page the blue cube is the scene-authoritative one: flutter3d moves it
round in a circle, and the blue dot on Flame's map follows. The orange cube is
the reverse: Flame slides its component along a figure of eight, and the cube
in the scene follows. Drag to turn the view and compare the floor with the map.

{{code live}}
