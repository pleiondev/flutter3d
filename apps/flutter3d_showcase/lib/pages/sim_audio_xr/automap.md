# An automap

A brush level already has a map baked into it for the monsters: the
navigation grid. `Automap` reuses it for the player, keeping track of which
cells the player has walked near instead of showing the whole level from the
start.

## Step 1: A grid to remember

`Automap` wraps a `NavGrid` and keeps two bitsets over it: which cells are
floor the player has seen, and which are walls beside that floor.

{{code grid}}

## Step 2: Walk near some cells

`reveal` floods outward from a point, along cells an agent could actually
step between, up to `revealRadius` metres. It does not radiate through
walls: a room on the other side of one stays hidden until the player is near
enough on this side of the doorway.

{{code reveal}}

## Step 3: Read what has been seen

`isFloor` and `isRevealed` answer per cell, which is what a screen draws from.

{{code check}}

A cell near where the player walked reads as floor. A cell far across the
same open room, well outside the reveal radius, is not on the map at all yet.

## Step 4: Watch the map fill in

The level on this page is two rooms and a corridor, and the orange dot walks
between them. Each frame it calls `reveal` at its own position, and the map
learns a little more: floor light, walls dark, the rest blank. The second room
stays blank until the dot has actually gone through the doorway. **Forget the
map** starts it again from nothing.

{{code live}}
