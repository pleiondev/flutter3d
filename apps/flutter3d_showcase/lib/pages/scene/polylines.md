# Polylines in screen pixels

A route should not become a hairline when the camera pulls back. A polyline
keeps its width in pixels, joins every segment into one band, and carries a
separate colour at each point.

## Step 1: Lay out the routes

The example uses three paths with different bends and widths. Each point is a
position in the scene. The palette will be repeated along each route, making
the interpolation between points easy to see.

{{code routes}}

## Step 2: Build each joined band

`buildPolyline` writes two vertices for every point. Those vertices also carry
the previous and next positions, so the vertex shader can form the join after
the camera has moved. Adjacent segments share their corner instead of meeting
as two separate rectangles.

The widths here are 6, 12, and 22 pixels. The colour list has exactly one
entry for every route point.

{{code geometry}}

## Step 3: Use the matching material

Polyline geometry needs `Material.polyline`. Its vertex stage widens the band
against the render target, while its unlit fragment stage preserves the
per-point colours. One mesh node draws each complete route.

{{code material}}

## Step 4: Update the viewport after a resize

The material stores the render target width and height. If that target changes,
update `polylineViewport`; the mesh itself does not need to be rebuilt. The
showcase renders at 1280 by 720 pixels, so those values are used initially.

{{code resize}}

## Step 5: Check the result

The page checks the two-vertices-per-point index layout, the specialised
lighting model, and the viewport values. It also requires all three routes to
reach the frame as separate draw calls.

{{code check}}
