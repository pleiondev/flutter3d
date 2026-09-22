# Switching passes off

A frame is a list of passes: shadows, the scene, occlusion, bloom, the final
composite and so on. Each one has its own settings, but sometimes you want to
skip one without touching them, for a screenshot, a profile, or a device that is
running late. `RenderSettings.disabledPasses` takes the names of the passes to
leave out, and the frame tells you what it did about each name.

## Step 1: Know the names

A name is typed exactly as the frame prints it, spaces included. The engine
publishes the full list, in the order the passes run, as
`RenderSettings.passOrder`, so nobody has to guess whether it is `ssao` or
`occlusion`. This page picks the five passes its scene turns on.

{{code names}}

## Step 2: Hand the names to the settings

`disabledPasses` is a set of strings. It is data and not a function, so it can be
written into a file, compared with another set and printed in a bug report. A
name that no pass carries is refused with the name in the message, which is how
a typo shows up.

{{code disabled}}

The switches beside the picture add and remove names. Bloom starts switched off.
Turn on Skip ssao and the soft dark at the base of the shapes goes away, while
the shadows the sun casts stay. Turn on Skip antialias and the edges of the ball
turn to stairs.

Three passes cannot be switched off: `scene`, `composite` and `object ids`.
`RenderSettings.undisablePasses` lists them, because a frame with no scene or no
composite would have no picture to give back.

## Step 3: Read what the frame says

A pass that was switched off by name is reported as `PassSkip.disabled`.
That is a different answer from `PassSkip.settings`, which means the pass had
nothing to do because its own settings were off. If a picture is missing an
effect you expected, this is the place to look first.

{{code report}}

> **Tip.** A pass that is skipped is also missing from `FrameResult.passes`.
> Compare the two lists and you can tell what ran, what was asked to stay
> out, and what had nothing to do.
