# Post effects on your own image

Bloom, exposure and the tone curve normally run inside a frame, on a scene the
renderer just drew. `Renderer.renderPost` runs them on a picture you hand it.
That is what you want when the picture came from somewhere else: a video frame,
a texture you painted, or a second scene you drew earlier in the same update.

This page draws a glowing bar into a texture of its own, sends that texture
through `renderPost`, and shows the answer on a screen in a second scene.

## Step 1: Make a picture

The source is a small scene with one very bright bar on black. It has its own
`Scene`, its own camera and its own `RenderView`, so nothing in it is shared with
what you see on the screen.

{{code source}}

## Step 2: Draw it without post effects

The first render turns bloom and tone mapping off, so what comes back is the
picture as it was drawn. `frame` is the renderer's own target and is only good
until the next render, so the next step has to use it straight away.

{{code first}}

## Step 3: Send it through renderPost

`renderPost` takes the picture as `hdr`, runs bloom over it, applies exposure and
the tone curve from the settings you pass, and writes the result into `target`.
Nothing about a scene is involved: there are no lights to count and no meshes to
cull, which is why the answer is a `PostFrameResult` and not a `FrameResult`.

Drag Threshold down and the glow around the bar gets wider, because more of the
picture is bright enough to feed it. Drag Exposure to make the whole picture
brighter or darker before the curve.

{{code post}}

Only bloom and the composite run here. Passes that read a surface buffer, such as
ambient occlusion, need a scene to describe and are not part of this call.

## Step 4: Put the answer somewhere

The target is an ordinary texture, so it can be used like one. Here it is the
albedo of an unlit screen, and the scene that the viewport draws is only that
screen.

{{code screen}}

## Step 5: Say what happened

The page checks that `renderPost` was called and that it wrote into the texture
it was given.

{{code answer}}
