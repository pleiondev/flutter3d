# Automatic multisampling

Multisampling smooths a triangle's edge without touching what is inside it: the
GPU samples each pixel more than once at the edge and blends the answers. It
costs no extra pass and no texture is read back, which is what makes it the
better choice over FXAA wherever a device has it.

## Step 1: Ask the device

There is no setting to turn multisampling on. The scene pass uses it whenever
the device offers an offscreen multisampled target and nothing in the frame
needs to read the picture before it is finished. `GraphicsDevice.supportsOffscreenMsaa`
is what the renderer itself asks.

{{code ask}}

## Step 2: Give the frame a reason to stop

Ambient occlusion, reflections and a few other passes need to read the scene as
a picture rather than as triangles still being drawn, and a multisampled
attachment cannot be read that way mid-frame. Turning one of them on makes the
scene pass give up multisampling for that frame, on any device.

{{code compete}}

Turn Ambient occlusion on and off and look at the edge of the ball against the
floor. On a device that multisamples, the edge sharpens when the toggle goes on
and returns to smoothed when it goes off.

## Step 3: Read what actually happened

`FrameResult.antiAliasing` says what the scene pass did, not what was hoped for.
`msaaSamples` is how many samples it drew with, one for none. `msaaDeclined` is
null when multisampling ran and a short sentence otherwise: either the device has
no offscreen multisampled target, or something in this frame is reading the
surface buffer.

{{code declined}}

> **Note.** On a device with no offscreen multisampled target, the toggle above
> makes no visible difference to the edges, because there was nothing to give up.
> The occlusion itself still runs.
