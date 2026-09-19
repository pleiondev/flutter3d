# Cameras and lights from a file

glTF can carry more than geometry. `KHR_lights_punctual` puts a light on a
node the same way a mesh sits on one, and `camera` does the same for a
viewpoint an author set up ahead of time. This page writes both into a GLB
and reads them back to show what survives.

## Step 1: Build a document with a light and a camera

A `ModelLight` and a `ModelCamera` are held on `ModelDocument` next to the
surfaces, addressed from a node by index the same way a mesh is. This
document has one cube, one directional light, and one perspective camera.

{{code document}}

> **Note.** `ModelCamera.projection` is a perspective or an orthographic
> camera, glTF's own two kinds. Nothing here reads `aspectRatio`: when a
> file omits it, the camera is meant to follow whatever the viewport's
> aspect ratio is, which is what a null value says.

## Step 2: Write it out and read it back

`GltfWriter` encodes the whole document, lights and camera included, into
one GLB. Reading it back with `GltfLoader` is the only honest way to check
that the two agree on the shape of the file.

{{code roundtrip}}

## Step 3: Draw what came back

The cube and the light both came from the file, not from the document this
page started with. The camera is not drawn; a camera has no shape of its
own to show, only a point of view, and this page's own viewport already
supplies one.

{{code scene}}

## Step 4: Check that the round trip held

A file that writes a light and a camera and reads back none of them has
silently dropped part of the scene. This page's claim is that exactly one
of each came back, and that the camera is still the kind it was written as.

{{code check}}
