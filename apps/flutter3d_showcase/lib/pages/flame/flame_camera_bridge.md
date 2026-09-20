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
