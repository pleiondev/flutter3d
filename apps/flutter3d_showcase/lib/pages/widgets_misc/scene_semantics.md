# Describing the scene to a screen reader

A 3D viewport is one opaque rectangle to the platform. Everything inside it
is pixels in a texture, so a screen reader arriving at it finds one target
the size of the window and nothing about what is actually there.
`SceneSemantics` overlays one accessibility node per object, positioned
where the camera projects it.

## Step 1: Say what to announce

An application names a node and a label for it. The bounds are not known
yet; they depend on where the camera ends up.

{{code announce}}

## Step 2: Project them through the camera

`semanticObjectsFor` turns the announcements into positioned objects, for a
viewport of a given size.

{{code project}}

## Step 3: Publish them

`SceneSemantics` wraps the viewport and adds one Flutter semantics node per
object on top of it.

{{code overlay}}

The left wheel projects to the left of the right one, because the camera
sits in front of them looking down `-Z` the way every camera in this engine
does.
