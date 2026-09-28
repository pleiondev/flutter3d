# Motion blur

A real camera keeps its shutter open for part of each frame, and anything that
moves in that time comes out as a streak. A renderer draws each frame at one
instant, so a fast wheel shows as a set of sharp spokes that jump from frame
to frame. Motion blur puts the streak back, using how far each pixel moved
since the last frame.

## Step 1: Something that turns

Three spokes around a hub. The rim of the wheel moves much faster across the
screen than the hub does, so one frame shows both a long streak and none.

{{code wheel}}

## Step 2: Turn it every frame

The wheel only has motion to blur if it moves between frames, so `update`
turns it by the speed times the frame time. The renderer compares each node
with where it was on the last frame and writes that motion into a velocity
buffer.

{{code turn}}

## Step 3: Turn on the blur

`RenderSettings.motionBlur` takes a `MotionBlurSettings`, off by default. With
`enabled` on, the pass finds the longest motion in each tile of the screen and
its neighbours, and gathers fifteen samples along it for every pixel near
something moving. Pixels with less than half a pixel of motion anywhere
around them are left as they are. The gather follows the reconstruction
filter of McGuire, Hennessy, Bukowski and Osman (2012), with the samples
weighted by how long each one covers the pixel.

`shutterFraction` is how much of the frame's motion the exposure sees, from
nought, a still, to one, the shutter open for the whole frame. The default,
0.5, is the 180 degree shutter of film. `maxRadius` bounds the streak on each
side of a pixel, in pixels, 20 by default and never more than 64, so a whole
streak can be about twice that long. It is also the width of the tiles, so it
bounds the cost too. Anything moving faster is blurred as if it moved exactly
that far.

{{code settings}}

Switch **Motion blur** off and the spokes are sharp. Switch it on and the
tips smear round the circle while the hub stays sharp. Raise **Speed** and the
streak grows until each half of it reaches **Streak each side**, then stops
growing.

## Step 4: Check that it ran

The first frame has no earlier frame to compare with, so it has no motion and
comes out sharp, but the pass still runs. A shutter of nought or a streak
shorter than a pixel skips it.

{{code ran}}

> **Note.** Motion blur reads the surface buffer, which turns multisampling
> off for the scene pass. It also works with temporal anti-aliasing on: the
> blur runs before the resolve, and the resolve blends the blurred frames.
