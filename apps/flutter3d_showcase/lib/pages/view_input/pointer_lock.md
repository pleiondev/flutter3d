# Pointer lock

An ordinary cursor stops at the edge of the window. A first-person camera
needs the opposite: motion that never runs out of room, so looking left for
a second turn does not depend on how much desk the mouse had left. Pointer
lock hides the cursor and hands a game relative deltas instead of a bounded
position.

> **Note.** `pointer_lock` is not yet a dependency of this application. This
> page demonstrates the idea with the relative deltas Flutter's own pointer
> events already carry, accumulated with nothing to stop them, and says so
> rather than claiming a real capture is in effect.

## Step 1: Sum the deltas

The whole difference between a locked pointer and an ordinary one is here:
nothing clamps the total to the size of the window.

{{code accumulate}}

## Step 2: Drag past the edge

Drag across the panel and keep dragging past where the window ends. The
running total in the corner keeps climbing the whole time, because summing
deltas has no edge to run into, unlike a cursor's own `x` and `y`.

{{code accumulate}}

> **Warning.** A coarse pointer, a phone or a tablet, has no lock to ask
> for. `pointer_lock`'s real `isSupported` answers false there, which is
> what should put a game's on-screen controls on the screen instead.

## Step 3: What a real capture adds

A real `PointerLock.request()` also hides the system cursor and asks the
platform for the capture, releasing it again on a lost focus or a tab
switch the game did not choose. None of that is visible here: this page is
only the arithmetic a capture's deltas are fed into once they arrive.

{{code accumulate}}
