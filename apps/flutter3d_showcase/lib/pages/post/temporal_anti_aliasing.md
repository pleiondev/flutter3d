# Temporal anti-aliasing

A pixel on screen is one sample of whatever lies behind it. A bar thinner than
a pixel is either hit or missed, so its edge turns into stairs and it flickers
as it moves. Temporal anti-aliasing takes more samples by taking them over
time. Each frame the scene is drawn a fraction of a pixel off from the last,
and a resolve pass blends the new frame into a history of the ones before it.
Sixteen frames of a still picture are sixteen samples of every pixel.

## Step 1: Thin bars in front of a wall

Thirteen blue bars, four centimetres wide and tilted, stand just in front of a
pink wall. Both are unlit, so every colour on screen is one of a few flat
colours and anything in between is the resolve's work.

{{code railing}}

## Step 2: Make something change

A still picture is the easy case. The railing slides from side to side, and
every two seconds the wall turns from pink to yellow and back. Moving bars test
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

`TemporalClip.aabb`, the default, is a box in YCoCg colour space: brightness
on one axis and two colour differences on the others. It is cheap but loose
along the diagonals of that space. Its corners hold colours none of the
neighbours have, so a remembered colour that is the right brightness and the
wrong hue can sit inside it and survive. `kdop8`, `kdop16` and `kdop32` bound
the neighbourhood with slabs along four, eight and sixteen axes, and hold the
history closer to the colours that are really there.

That is why the wall is pink and yellow. Next to a bar, the box is built from
yellow and blue, and it is wide on every axis because those two differ on
every axis. Pink is a brightness between theirs and a hue neither has, and it
sits in a corner of that box. A pink wall turning yellow leaves a pink smear
the box lets through. A red wall turning green would not show this: red is
outside any box of green and blue, so the clip pulls it in towards the
box's centre and at worst a greyish smear is left.

{{code clips}}

Watch the moment the wall turns yellow while the bars are sliding. Under
`aabb` the old pink can linger along each bar for a few frames. Pick a k-DOP
and compare. Lowering **History weight** also shortens any trail, under any
clip, but it gives up the smoothing with it.

## Step 5: Read what the frame says

The page checks that the `temporal resolve` pass ran, or that the frame says
the device declined it. `FrameResult.antiAliasing.temporal` reports the same
thing, since it is read off the frame's list of passes, so there is nothing
more to check there. The resolve reads the surface buffer, which cannot be
multisampled, so a frame with the resolve on draws without MSAA.

{{code reported}}
