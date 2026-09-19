# The virtual pendulum lab

A teaching lab needs a simulation small enough that changing one number
visibly changes how a run unfolds, and an instructor needs to know exactly
where a student's run stopped matching the assignment. A pendulum is the
first, and the engine's own digest trace is the second.

> **Note.** `flutter3d_lab`'s real `PendulumSimulation` is not a dependency
> of this app. This page reimplements its formula by hand, a dozen lines of
> semi-implicit Euler, and checks it with the real `DigestTrace` the rest of
> the simulation package uses.

## Step 1: Run the assignment

Semi-implicit Euler: the velocity updates first, then the position from the
updated velocity, the same order the rest of the engine steps everything
else with.

{{code pendulum}}

{{code assignment}}

## Step 2: Run a student's attempt

This student changes the pendulum's length partway through the run.

{{code student}}

## Step 3: Find where they parted

{{code compare}}

The two runs agree at every checkpoint before the change, and the checkpoint
covering step 30 is the first to disagree — exactly where the student's
length stopped matching the assignment's.
