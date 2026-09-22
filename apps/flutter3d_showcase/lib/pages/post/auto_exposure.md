# Auto exposure

A camera with a fixed exposure blows out a bright room and turns a dark one to
mud. Auto exposure measures how bright the scene actually is and moves the
exposure toward a value that puts the middle of the frame at a chosen grey, the
way a camera's own metering does.

## Step 1: Where it starts

The very first frame has nothing to measure yet, so it is drawn at the plain
`exposure` setting. Everything after that is the meter's answer.

{{code seed}}

## Step 2: Turn the meter on

`AutoExposureSettings.enabled` runs a small pass that reads the scene's own
brightness. `target` is the grey it aims the middle of the histogram at, 0.18
by default, the same middle grey a photographer's light meter uses. `speedUp`
and `speedDown` are how many stops a second the exposure is allowed to move.

{{code auto}}

Move the view around this scene while the app is running and the exposure
follows: step to face the bright floor and the picture darkens to compensate,
step toward a dark corner and it brightens. A single still picture cannot show
that motion, which is why this page's own check only holds the first frame to
what Step 1 says it should be.

## Step 3: Read what the frame used

`FrameResult.exposure` is the number the composite actually multiplied by,
whether it came from the setting or from the meter. On the first frame it is
exactly the seed.

{{code reads}}

> **Tip.** Raise Adaptation speed and the exposure of a running scene snaps to
> a new value in a fraction of a second. Lower it and a walk from a bright room
> to a dark one takes a visible moment to catch up, the way an eye does.
