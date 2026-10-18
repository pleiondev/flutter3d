# A level is a scene, and the camera frames the whole party

A game with levels moves from one to the next, and in flutter3d a level is a
scene: its floor, its lights, its air. `HasFlutter3d.replaceScene3d` moves a
Flame game's 3D layer to the next scene, with the camera, on the same device
and renderer. `ViewCamera` eases a camera towards wherever a function says,
for a view no single component decides, such as a party of four.

## Step 1: Two levels, two scenes

Both are built up front. The game opens on the first, and the second waits
without being drawn.

{{code levels}}

## Step 2: Move on with replaceScene3d

Every six seconds the party goes to the next level. The game carries its own
nodes across, since what was in the old scene stays there, and then replaces
the scene. The camera goes with it, and `Flutter3dFlameWidget` draws the
game's scene as it is now, not the one it opened with.

{{code next}}

## Step 3: Where the party should be seen from

The view is worked out from every member at once: above and behind their
middle, further back the more they spread. It is asked once a frame and
writes the eye and the point looked at into the two vectors it is handed.

{{code frame}}

## Step 4: A camera eased towards it

`ViewCameraComponent` runs the view camera after whatever moves what it
frames. On a new level the party starts somewhere else, and the camera eases
across to it rather than jumping.

{{code camera}}
