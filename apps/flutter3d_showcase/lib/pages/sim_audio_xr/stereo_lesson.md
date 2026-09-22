# A lesson through the rig

A lesson document is the same `edu_step` entities a step panel already
authors: where the stage stands, and which named nodes are visible. Playing
it through a stereo rig instead of editing it is a matter of stepping
through the same list with a button, since a phone in a holder has no
keyboard to reach for.

## Step 1: Two steps

The first hides a detail; the second reveals it.

{{code steps}}

## Step 2: Wrap it in a view

`LessonStereoView` puts a `StereoSurface` around the rig and the player,
with Previous and Next buttons doing the stepping.

{{code view}}

## Step 3: Check what a step actually changes

{{code apply}}

Applying the first step leaves the detail hidden; moving to the second and
applying it again shows the detail, because that step names it in its own
`visible` list.
