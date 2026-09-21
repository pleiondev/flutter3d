# Reconciling an orthographic camera and a Flame viewfinder

`CameraSyncController` keeps a flutter3d `CameraNode` and a Flame
`Viewfinder` describing the same view. Position goes through the same
`BridgePlane`/`SyncDirection` every other bridge in this category shares;
zoom and an `OrthographicProjection`'s `height` are reconciled by
`zoom = 1 / height`, the one correspondence that moves the two the same way
with no further data.

## Step 1: Two cameras, one plane

{{code cameras}}

## Step 2: flutter3d leads

The flutter3d camera moves; the controller carries its position and its
lens height onto the Flame viewfinder.

{{code scene-to-flame}}

## Step 3: Flame leads

Reversed, with `SyncDirection.flameToScene`: the viewfinder moves and zooms,
and the controller carries that onto the flutter3d camera's own projection.

{{code flame-to-scene}}

The flutter3d camera's move landed on the viewfinder as position and as
`1 / height`; the viewfinder's own move and zoom landed back on the camera as
position and as `1 / zoom` — both directions of the same reconciliation, over
the same plane.

## Step 4: See both lenses agree

The picture is the same ground twice. flutter3d looks straight down through an
orthographic camera at nine pillars; Flame draws a yellow ring round each one
in its own world, through its own viewfinder. When the two lenses agree, every
ring sits on its pillar, whatever the camera does.

The plane stands at the camera's own height: when Flame leads, the controller
writes the camera's position through it, and a plane at zero would put the
lens on the floor.

{{code live}}

## Step 5: Move one, and the other follows

Pick who leads with **Who leads**. The camera drifts and its lens height
breathes in and out. Either the flutter3d camera moves and the viewfinder is
told, or the viewfinder moves and the camera is told; the rings stay on the
pillars either way.

{{code drive}}

The controller's zoom is one over the height, which is a number and not a size
on screen. Turning it into pixels to the metre is the page's own step, after
`advance`: the game is as many pixels high as the picture under it.
