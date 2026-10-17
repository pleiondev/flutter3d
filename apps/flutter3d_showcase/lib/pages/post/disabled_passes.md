# Switching steps off

A frame is a list of passes: shadows, the scene, occlusion, bloom, the final
composite and so on. Each one has its own settings, but sometimes you want to
skip a few without remembering which flag turns each one off, for a
screenshot, a profile, or a device that is running late.
`RenderSettings.without` takes the steps to leave out, and the frame tells you
what it did about each of their passes.

## Step 1: Know the steps

`RenderStep` names every step of the frame that can be switched off, as one
vocabulary: `RenderStep.bloom`, `RenderStep.ambientOcclusion`,
`RenderStep.shadows` and the rest, in `RenderStep.values`. Each one knows the
passes it owns, by the names the frame prints. This page picks the five steps
its scene turns on.

{{code names}}

## Step 2: Hand the steps to the settings

`without` switches each step off through its own setting, the same `copyWith`
you would have written by hand, so the frame is the one you would get that
way. A step that another needs takes that one with it: the lens flare is
drawn from the glow, so switching bloom off switches the flare off too.

{{code disabled}}

The switches beside the picture add and remove steps. Bloom starts switched
off. Turn on Skip ambientOcclusion and the soft dark at the base of the shapes
goes away, while the shadows the sun casts stay. Turn on Skip edgeSmoothing
and the edges of the ball turn to stairs.

The scene and the composite are not steps: they are the frame, and there is
no way to ask for a frame without a picture.

## Step 3: Read what the frame says

A pass whose step was switched off is reported as `PassSkip.switchedOff`.
That is a different answer from `PassSkip.settings`, which means the pass had
nothing to do because its own settings were off. If a picture is missing an
effect you expected, this is the place to look first.

{{code report}}

> **Tip.** A pass that is skipped is also missing from `FrameResult.passes`.
> Compare the two lists and you can tell what ran, what was asked to stay
> out, and what had nothing to do.
