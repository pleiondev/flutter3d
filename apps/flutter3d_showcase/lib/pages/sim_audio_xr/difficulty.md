# Difficulty axes

`Difficulty` is four numbers rather than a name a genre has to interpret: how
much the player is hurt by, what their own attacks are worth, how quickly the
opposition reacts, and how much of whatever help the genre offers is
switched on. A game reads the axes it has a use for and ignores the rest.

## Step 1: Scale a hit by a difficulty

`damageTaken` is a plain multiplier on whatever a genre already computes.

{{code apply}}

## Step 2: List the four that ship

`Difficulty.offered` is `gentle`, `normal`, `hard` and `punishing`. A game
free to invent its own difficulty is not limited to these four; they are a
starting point.

{{code list}}

## Step 3: Compare the extremes

{{code compare}}

The same ten-point hit costs less on `gentle` and more on `punishing`,
because `damageTaken` is a multiplier and the two settings sit on either
side of one.
