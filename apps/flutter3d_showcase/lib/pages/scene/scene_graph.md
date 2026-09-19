# The scene graph

A scene graph stores local transforms in a hierarchy. Moving a parent changes
where every child appears, so an orbit can be expressed with a pivot instead of
recalculating each object's world position by hand.

## Step 1: Build the hierarchy

The system pivot owns the planet orbit. The planet orbit owns both the planet
and a second pivot, which in turn owns the moon. Each child keeps a small local
transform relative to its parent.

{{code hierarchy}}

## Step 2: Attach the branch to the scene

Adding the top pivot registers every mesh below it with the scene. The root can
also hold unrelated nodes, such as the star and its point light.

{{code root}}

## Step 3: Rotate the pivots

The system pivot carries the whole branch around the star. Rotating the planet
pivot at another rate moves the moon around the planet without changing the
moon's own local position.

{{code motion}}

## Step 4: Read a current world transform

`readWorldPosition` resolves the ancestor chain when a version changed. The
page checks that the moon kept its parent chain, received a new world version,
and moved from the position recorded before the first update.

{{code check}}
