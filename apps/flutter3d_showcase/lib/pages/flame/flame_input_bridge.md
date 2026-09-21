# One key, read by both engines

`FlameInputBridge` does not invent its own key-to-action map. It looks a
Flame key event up in the very same `Bindings` table `flutter3d_game`'s own
`DesktopInput` reads, and writes into the very same `InputState` — so a
player who rebinds a key in one build keeps that rebind in the other.

## Step 1: One table, one shared state

{{code shared}}

## Step 2: A Flame key event, translated

`onKeyEvent` returns `false` when it consumed the key — the opposite polarity
of `KeyEventResult`, but the one `KeyboardHandler` itself expects.

{{code press}}

## Step 3: Both sides read the same answer

Nothing here asks which engine saw the key first. The flutter3d side reads
`held` off the identical `InputState` the Flame-side bridge just wrote into.

{{code reactions}}

The Flame handler reported the key consumed, and the flutter3d side reading
the same `InputState` a moment later found the action already held — one
press, one shared answer, read by two engines that never spoke to each
other directly.

## Step 4: Press a key, walk the sphere

Four keys, bound once in a table both engines read. Flame's side is a
component that hands every key event to the bridge; it also draws four keycaps
that light while the shared state holds their action. flutter3d's side is the
sphere: each frame it reads the same state and walks. Click the scene and press
W A S D, or use **Hold D for me** if there is no keyboard to hand.

{{code live}}

The sphere's half is one read of `moveAxis` per frame; nothing in it knows the
keys came through Flame.

{{code walk}}
