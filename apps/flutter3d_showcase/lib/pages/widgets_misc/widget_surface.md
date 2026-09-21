# Widgets in the scene

`WidgetSurface` puts a live Flutter widget on a mesh in the 3D scene: a sign
beside a road, a screen on a wall, a map on a table. It draws the widget off
the visible tree, at exactly the resolution asked for, and uploads the
result as the mesh's own texture. The screen on this page is an ordinary
widget tree: a title, a clock that runs and a bar that fills every four
seconds.

## Step 1: Build a surface

A width and a height in metres, and any widget. The plane's front faces -Z
at `yaw` zero, so this page stands its camera there; a surface seen from
behind would be invisible unless it is drawn from both sides, which is what
`doubleSided` on its material does. Orbit round the back to see it.

The widget is wrapped in `Transform.flip` on both axes. What a surface draws
lands on its mesh turned half way round, so the widget is turned half way
round to meet it, and reads the right way up. The pendulum lab in this
repository does the same for the same reason.

{{code surface}}

## Step 2: Redraw it when it changes

`tick` checks whether the widget's own pixels changed since the last call
and only re-uploads when they did. The clock changes every frame, so this
page uploads every frame, one at a time: a slow upload is not queued behind by
the next.

{{code tick}}

## Step 3: Turn a world point into a UV

`uvAt` is the other half of hitting a widget on a wall: given a point on the
surface's own plane, it answers where that point falls in the widget's
pixels.

{{code hit}}

The centre of the plane maps to the centre of its UV space, whatever
position or yaw the surface is placed at. `uvAt` answers in the mesh's own
coordinates, before the half turn above, so a tap on a flipped widget wants
the same treatment the pendulum lab gives it.
