# Gamepad

`pad_input` reads a physical gamepad once a frame as a `PadSnapshot`: two
sticks, two triggers and a set of buttons named by their physical position
on the pad rather than by what a particular game uses them for, because the
string ends up in a player's saved config and is read years later on
another pad entirely.

> **Note.** `pad_input` is not yet a dependency of this application. This
> page shows the one piece of maths every stick needs, a dead zone, against
> a stand-in stick driven by the arrow keys, and says so rather than
> pretending a real pad is being read.

## Step 1: A stick, from whatever is at hand

A real `PadSnapshot.leftStick` is a `Vector2` from the hardware. The arrow
keys make the same shape by hand: each key nudges one axis to -1, 0 or 1.

{{code raw}}

## Step 2: The dead zone

A stick rarely rests at exactly zero, so a reading under a small threshold
is thrown away entirely, and what is left is rescaled so the stick still
reaches its full range at the edge. This is what `pad_input`'s `Deadzone`
does to every stick before a game ever sees the number.

{{code deadzone}}

> **Tip.** Rescaling after the cut matters as much as the cut itself. Without
> it, a stick that used to read from 0 to 1 would only ever report from the
> dead zone's edge to 1, and a full push would feel weaker than it is.

## Step 3: Watch the numbers

Hold an arrow key and the raw and dead-zoned readings above the viewport
both move; hold it only slightly (which the keyboard cannot really do, but
the slider simulating the dead zone's own threshold can) and the dead-zoned
number stays at zero until the threshold is crossed.

{{code deadzone}}
