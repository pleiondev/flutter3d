# Two layouts, and whoever presses first is player one

`PlayerSeats` keeps every way of holding a game at one machine, each a
`FlameInputBridge` with its own bindings and state, and lets the game claim
one as the next player when it sees it pressed. Here the two ways are two
halves of one keyboard. Nobody plays until they press their join key, and
seats go in the order people join, whichever layout is listed first.

## Step 1: A table and a state for each layout

Each layout is a bridge of its own: the same `ActionMap` and `InputState`
pair a native `flutter3d_game` reads, one per player, so a key reaches the
player it is bound for and no other.

{{code layouts}}

## Step 2: Claim a seat by pressing

What counts as asking to join is the game's to say. Here it is the join key
going down this step on a layout nobody has claimed. `claim` makes it the
next player, and `seated` keeps them in the order they came.

{{code claim}}

## Step 3: Keys from the keyboard, not the focus

`listenToKeyboard` feeds every layout from `HardwareKeyboard`, so a key
reaches the game wherever the focus is, and a key let go while a button or a
menu had the focus is still let go. `stepEnds` closes every layout's step
after the frame, the free ones as well, so a press made to join is seen once
and not on every frame after.

{{code lobby}}

## Step 4: A marker for each player

A layout that has just joined shows its cube in its seat's colour: amber for
player one, blue for player two. From then on it walks with its own four
keys. Press Slash before Space and the arrows are player one.

{{code seat}}
