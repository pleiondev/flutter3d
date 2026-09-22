# Light channels

`LightNode.channels` and `SceneNode.lightChannels` are two bit masks that
meet in the middle: a light reaches an object only when
`light.channels & node.lightChannels` is not zero. Both default to every bit
set, so a scene that has never heard of channels is lit exactly as it
always was. Nothing here is a check the shader makes at the last minute; a
light that cannot reach an object never takes one of its eight slots
either.

## Step 1: Two balls, two channels

The near ball is on channel `0`, the far ball on channel `1`, and a red
light is restricted to channel `0` as well. Only the near ball sees it; a
plain fill light keeps the far one visible.

{{code channels}}

## Step 2: Open the second channel

The toggle adds the far ball's channel to the near ball's mask, so the same
red light that only reached the near ball now reaches both.

{{code live}}

## Step 3: What this page checks

The claim is the mask itself: the red light's channel and the ball it is
meant to light have to share a bit, and the light has to actually be
restricted rather than left on every channel by accident.

{{code check}}

> **Tip.** `LightChannels.only(n)` is the nth bit, counting from zero.
> `LightChannels.all` and `LightChannels.none` are the two values a caller
> does not have to invent themselves.
