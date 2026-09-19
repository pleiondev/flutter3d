# Widgets in the scene

`WidgetSurface` puts a live Flutter widget on a mesh in the 3D scene: a sign
beside a road, a screen on a wall, a map on a table. It draws the widget off
the visible tree, at exactly the resolution asked for, and uploads the
result as the mesh's own texture.

## Step 1: Build a surface

A width and a height in metres, and any widget.

{{code surface}}

## Step 2: Redraw it when it changes

`tick` checks whether the widget's own pixels changed since the last call
and only re-uploads when they did.

{{code tick}}

## Step 3: Turn a world point into a UV

`uvAt` is the other half of hitting a widget on a wall: given a point on the
surface's own plane, it answers where that point falls in the widget's
pixels.

{{code hit}}

The centre of the plane maps to the centre of its UV space, whatever
position or yaw the surface is placed at.
