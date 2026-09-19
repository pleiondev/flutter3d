# Touch controls

A touch device has no physical stick, so a game draws one: a knob a thumb
can drag, reporting how far from its centre it has moved. `TouchStick` and
`TouchButton` are that idea, feeding the same `InputState` a key or a
gamepad axis writes into, so the rest of a game never has to ask which of
the three produced a given action.

> **Note.** `flutter3d_game` is not yet a dependency of this application.
> This page reimplements the stick's own arithmetic, drag distance clamped
> to a radius, against a plain pointer listener, and says so rather than
> claiming its widgets are in use.

## Step 1: Read the drag

The knob's reading is the drag distance from the stick's centre, divided by
the stick's radius: 0 at the centre, 1 at the edge, and clamped there for
anything further.

{{code drag}}

## Step 2: Let go on release

A touch control lets go the instant the finger leaves it. Holding the last
value instead is the bug this guards against: an axis stuck at full
deflection because a menu opened over the stick and the finger never
reported leaving it normally.

{{code release}}

> **Warning.** `onPointerCancel` matters as much as `onPointerUp`. A pointer
> is cancelled, not lifted, when the system takes it away for its own
> reasons, and a stick that only released on `onPointerUp` would stay
> pressed through one.

## Step 3: Try it

Drag inside the small panel above the ball. The knob's reading grows from
zero as you move away from its centre and clamps once you pass the radius;
release and it snaps back to zero immediately.

{{code drag}}
