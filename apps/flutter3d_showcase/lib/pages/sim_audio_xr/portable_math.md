# Portable determinism

A replay only proves anything if the same tape produces the same run
everywhere it is played. Two things break that promise if they are left to
the platform: transcendental functions, whose last few bits differ between
the Dart VM and a browser, and randomness with no readable state, which
cannot be written into a snapshot.

## Step 1: Trig that agrees on every platform

`Portable.sin`, `.cos` and friends are built entirely from addition,
multiplication and square roots, all of which IEEE 754 pins to the same bits
everywhere. `sinCos` returns both at once, which is the shape a direction
usually wants.

{{code trig}}

## Step 2: Roll and save the state

`GameRandom` is a small generator whose whole state is one integer, readable
through `state`. The page rolls two dice and keeps the state after that.

{{code roll}}

## Step 3: Resume from the saved state

A fresh generator given that saved state continues the exact same sequence.

{{code resume}}

The resumed generator's next roll matches the original's third roll exactly,
which is what lets a snapshot carry a simulation's dice forward across a save
and a load.
