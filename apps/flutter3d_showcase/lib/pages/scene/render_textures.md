# A camera into a texture

A security monitor, a portal, a minimap: each is a picture of the scene,
taken by a camera that is not the one you are looking through, and shown on a
surface in the scene. `RenderTexture` is that picture. The scene draws it
before its own meshes in the same frame, so the monitor shows what the room
looks like now, not one frame ago.

## Step 1: A second camera

An ordinary `CameraNode` with its own projection, added to the scene like any
other node so it can be moved and aimed. The aspect comes from the texture it
draws into.

{{code watcher}}

## Step 2: A texture for it to draw into

`RenderTexture.create` makes a texture of the given size on the device and
ties it to the camera. The picture is drawn with the frame's lights, shadows
and sky, and no post-processing chain runs on it. Particles and splats are
not in it either. `clearColorSrgb` shows where nothing was drawn.

The texture holds sRGB bytes, the way a picture loaded from a file does. That
means it goes into a material's albedo or emissive slot exactly as an image
would.

{{code texture}}

## Step 3: Show it on a screen

The screen is an unlit plane, so it shows the picture as the camera took it.
A lit plane would light the picture again, like a printed photograph in the
room. A `PlaneShape` stood up has its v running down, the way a picture's rows
do, so the picture comes out the right way up. The sides of a `CuboidShape`
run v upward and would show it upside down.

{{code screen}}

## Step 4: Leave the screen out and add the texture

`excluded` lists meshes the camera does not draw. Without it, the monitor
would hold its own back in the picture. `Scene.addRenderTexture` is what has
the texture drawn each frame, in a `render textures` pass before the scene's
own.

{{code add}}

## Step 5: Every frame, or only when asked

`refreshEveryFrame` is on by default. Off, the texture is drawn once, and
again only after `invalidate`. A portrait of a room where nothing moves is
one picture, not sixty a second. Switch **Every frame** off and the blue block
on the screen stops turning while the one in the room keeps going. **Take the
picture again** calls `invalidate`, and the next frame takes one new picture.

{{code refresh}}

## Step 6: What the page checks

The frame ran the `render textures` pass, and the texture holds a picture
instead of whatever its allocation held before.

{{code check}}

> **Note.** The texture belongs to whoever made it. When the page is left it
> is given back with `Renderer.releaseTextureAfterFrame`, and a game that
> switches a monitor off calls `Scene.removeRenderTexture` first.
