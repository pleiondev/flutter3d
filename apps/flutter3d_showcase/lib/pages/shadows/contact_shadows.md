# Contact shadows

A shadow map has a resolution, so the shadow of a crate on the floor starts a little way
from the crate. You get a thin bright gap where the two meet, and the crate looks like
it floats. Turning the map up moves the gap around but never closes it.

Contact shadows fix that gap a different way. For each pixel on screen, the renderer
walks a short distance toward the sun through the picture it has already drawn. If it
finds something in the way, the pixel is in shadow.

## Step 1: Things resting on the ground

A crate and a ball, both touching the ground. That contact line is where the effect
shows.

{{code props}}

## Step 2: A sun that asks for no map

The sun here never asks for a shadow map. Contact shadows only need to know which way
the sun lies, so any darkness near the bottom edges of the crate and the ball comes from
the march and from nothing else.

{{code sun}}

## Step 3: Turn it on

`ContactShadowSettings` is off by default. `length` is how far the march reaches, in
metres: short, because it only has to cover the gap a map leaves. `steps` is how many
samples it takes along that length, up to sixteen.

`thickness` matters most. It says how deep a blocker is assumed to be, so a wall that
merely stands nearer to you than the floor does not shadow everything behind it. Raise it
and the shadows fatten, lower it and they thin out.

`strength` is how much of the result reaches the picture. Zero is the same as off.

{{code settings}}

## Step 4: Add the shadow map back

Switch **Contact shadows** off and on to see what it adds. Then switch **Shadow map
too** on. This is the same request the other shadow pages make. The map draws the long
shadow across the ground, and the contact shadow tightens the join underneath the crate
and the ball.

{{code map}}

> **Note.** Contact shadows only see what is on screen. Something outside the picture,
> or hidden behind another object, cannot block the march.
