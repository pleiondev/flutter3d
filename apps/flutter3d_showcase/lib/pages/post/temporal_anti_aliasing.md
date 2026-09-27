# Temporal anti-aliasing

A pixel on screen is one sample of whatever lies behind it. A bar thinner than
a pixel is either hit or missed, so its edge turns into stairs and it flickers
as it moves. Temporal anti-aliasing takes more samples by taking them over
time. Each frame the scene is drawn a fraction of a pixel off from the last,
and a resolve pass blends the new frame into a history of the ones before it.
Sixteen frames of a still picture are sixteen samples of every pixel.

## Step 1: Thin bars in front of a wall

Thirteen blue bars, four centimetres wide and tilted, stand just in front of a
red wall. Both are unlit, so every colour on screen is one of two exact
colours and anything in between is the resolve's work.

{{code railing}}

## Step 2: Make something change

A still picture is the easy case. The railing slides from side to side, and
every two seconds the wall turns from red to green and back. Moving bars test
whether the history follows the motion. A wall that changes colour tests
whether the resolve lets go of a colour that is no longer there.

{{code motion}}

## Step 3: Turn on the resolve

`AntiAliasSettings.temporal` takes a `TemporalSettings`, off by default. With
`enabled` on, the projection is moved along a Halton sequence of
`sequenceLength` offsets, sixteen by default, a velocity pass records how far
each pixel moved, and the resolve reprojects the history through that motion
before blending.

`historyWeight` is how much of each pixel comes from the history, 0.9 by
default. Higher is smoother and slower to follow a change. `sharpen`, 0.25 by
default, runs a contrast-adaptive sharpen after the resolve to put back the
softness a history adds.

{{code settings}}

Switch **Temporal resolve** off and the bars go back to stairs that crawl as
they slide. Switch it on and the edges settle into smooth lines.

## Step 4: Choose how the history is clipped

Before the resolve blends, it pulls the remembered colour into the range of
colours around the pixel in this frame. Whatever falls outside that range is
old news and would otherwise show as a ghost. `TemporalSettings.clip` picks
the shape of that range.

`TemporalClip.aabb`, the default, is a box in YCoCg colour space. It is cheap
but loose along the diagonals, so a remembered red can sit inside a box built
from green and blue and leave a red trail. `kdop8`, `kdop16` and `kdop32`
bound the neighbourhood with slabs along four, eight and sixteen axes, and
hold the history closer to the colours that are really there.

{{code clips}}

Watch the moment the wall turns green while the bars are sliding. Under
`aabb` the old red can linger beside each bar for a few frames. Pick a k-DOP
and compare. Lowering **History weight** also shortens any trail, under any
clip, but it gives up the smoothing with it.

## Step 5: Read what the frame says

`FrameResult.antiAliasing.temporal` says whether the scene was jittered and
resolved this frame. The resolve reads the surface buffer, which cannot be
multisampled, so a frame with the resolve on draws without MSAA.

{{code reported}}
