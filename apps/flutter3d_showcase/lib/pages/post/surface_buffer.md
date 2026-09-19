# The surface buffer

Ambient occlusion, reflections, viewport shading and a few other passes all
need to know a surface's world-space normal and how far away it is, without
walking the scene again. The scene pass writes both into a second colour
attachment once, and every screen-space effect reads that one buffer instead of
recomputing it.

## Step 1: Ask to see it raw

`RenderSettings.showSurfaceBuffer` composites that buffer straight to the
screen instead of the lit picture, encoded as colour: the normal as RGB, the
depth in the alpha channel. It is how you find out whether the normals in it
are right side up before something starts reflecting off them.

{{code show}}

Turn Show the buffer on and the ring and the floor turn into flat colours that
shift as their surfaces turn, rather than the lit picture. Turn it off and the
ordinary scene comes back.

## Step 2: Know what it costs

The buffer is a second attachment, and opening it is not free everywhere.
Whenever something in the frame reads it, whether that is this switch,
ambient occlusion, or one of the others, the scene pass gives up
multisampling for the whole frame: the two are the same decision made twice,
because a multisampled attachment cannot also be read back mid-frame.

{{code consumed}}

## Step 3: Compare it against a picture that only asks for part of it

The ambient occlusion page reads the same buffer for a real effect rather than
to display it directly. Looking at the two together is the fastest way to see
what the buffer actually holds: a shape's own facing and its distance from the
camera, nothing about its colour or its light.

{{code show}}

> **Note.** A device that can only open one colour attachment cannot hold this
> buffer at all, and the passes that would have read it are dropped with
> `PassSkip.unsupported` instead of drawing something wrong.
