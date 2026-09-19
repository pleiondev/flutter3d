# Surfaces of revolution

A lathe mesh starts with a line in the radius-height plane. Sweeping that line
around the Y axis makes a vessel, column, wheel, or any other rotationally
symmetric surface.

## Step 1: Draw the side profile

Each `Vector2` stores radius in `x` and height in `y`. The profile runs from
bottom to top, which gives the finished surface outward-facing normals. Points
on the axis close the base without a separate mesh.

{{code profile}}

## Step 2: Sweep it around the axis

`segments` controls how many angular slices are built. The first vessel keeps
the slices visible, the second uses enough for a smooth outline, and the third
stops after three quarters of a turn so the profile can be seen from inside.

{{code sweep}}

## Step 3: Light the profile

A directional light shows the broad change in normals around each vessel. A
point light behind them catches the rim and makes the open sweep easier to
read.

{{code light}}

## Step 4: Check every variant

The page records the three nodes, checks their names, and confirms that each
variant contributed a draw to the frame.

{{code check}}
