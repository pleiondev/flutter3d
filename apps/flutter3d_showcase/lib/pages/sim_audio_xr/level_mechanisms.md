# Doors, lifts and buttons

A door, a lift and a moving platform are one machine — a kinematic body
sliding along an offset at a fixed speed — with three different rules for
when to move. A button is a separate thing entirely: it does nothing itself,
it only relays an activation to whatever it is wired to, by name.

## Step 1: A world for mechanisms to live in

`MechanismWorld` holds every mechanism in the level and the collision world
they move through.

{{code world}}

## Step 2: Wire a button to a door

`Door` owns a collider and a travel offset. `Button` owns a collider of its
own and a `target`: the name of whatever it should switch on.

{{code wire}}

## Step 3: Press it and watch the door open

`activate` finds the mechanism by name and calls its `activate`. A button
relays that to its target; a door starts moving towards open.

{{code press}}

The door starts closed, at progress 0. After the button is pressed and the
world is stepped forward, the door reaches progress 1 and reports itself
open, well inside the three seconds it is given to hold there.

## Step 4: Press it and watch

The door on this page is the one wired above, drawn: its collider is what the
mechanism moves, and the picture follows the collider. Press the button, or let
it press itself, and the door slides up out of its frame, waits, and comes back
down; the bar on the right is its `progress`, and the button lights while the
activation is on its way.

{{code live}}

{{code press-live}}
