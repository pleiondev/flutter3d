# Emitter shapes

Where a particle starts and which way it leaves is the emitter's job, and
this package ships four of them. Nothing about a burst's colour or lifetime
changes what you see here; only the emitter does.

## Step 1: Four shapes, four spots

A sphere throws particles outwards in every direction, which is what an
explosion looks like. A cone narrows that spread around one axis, for a
muzzle flash or sparks off a wall. A box starts particles anywhere inside a
volume rather than at a single point, which is the only way to get rain over
an area rather than rain from a point. A drift barely spreads at all: it is
what smoke and rising dust use.

{{code shapes}}

## Step 2: One burst each

Every shape is burst from its own position, so the four read as four
separate small explosions standing in a row rather than one blur.

{{code burst}}

## Step 3: What each one is for

A sphere is the right choice whenever nothing about the burst should favour
one direction. A cone is for anything that comes out of a barrel or off a
surface: it takes a direction and narrows around it. A drift ignores the
direction it is given and always heads up, slowly, which is the one shape
built for something that should look weightless.

A box is different: the point of emitting over an area is that every
particle should go the same way, rain falling down rather than outwards, so
it takes a fixed `along` direction instead of using the burst's own.

{{code along}}

> **Tip.** All four take a `speed` range rather than one fixed number.
> Identical particles read as a texture rather than as an effect, and speed
> is the cheapest place to add the variation that makes a burst look alive.

## Step 4: What the page checks

Four bursts of a known count should add up to a known total, and the
contributor should have actually drawn them.

{{code check}}

