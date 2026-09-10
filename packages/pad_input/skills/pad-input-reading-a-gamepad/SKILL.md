---
name: pad-input-reading-a-gamepad
description: Use when reading a gamepad in Flutter — the snapshot API, why button names are positions rather than printed labels, the radial dead zone, and which platforms answer isSupported.
---

# A snapshot, once a frame

```dart
final pad = Gamepad.instance;
final snapshot = PadSnapshot();

pad.read(snapshot);                                   // once per frame
if (snapshot.down(PadButton.faceSouth)) jump();
final throttle = snapshot.pressure(PadButton.triggerRight);
final steer = snapshot.axis(PadAxis.leftStickX);
```

Pull, not push: a game with a fixed step asks what the pad is doing now once per
frame, and a stream would push edge detection into every caller, where every
caller would get it slightly differently. In the browser it is also the only
honest shape, since `navigator.getGamepads()` is itself a poll.

Edges belong to the caller: keep last frame's snapshot (`copyFrom`) and compare,
or feed it into an input layer that latches them, which is what
`flutter3d_game`'s `InputState` does.

## The button names are positions, and they are permanent

`PadButton.faceSouth`, never `a`. These strings go into a player's configuration
file and are read back years later on possibly different hardware: Xbox calls
the lower face button `A`, PlayStation calls it Cross, Nintendo swaps `A` and
`B` relative to Xbox. If the identifier were the printed label, a file written
on one pad would **mean something different** on another, and plugging in a
different controller would silently move every binding.

Position is the invariant the hardware has, and what Apple's
`GCExtendedGamepad` and the browser's Standard Gamepad mapping already normalise
to. Printed labels are for showing a player and are never saved. Ids are lower
case, dot separated, only added to, never renamed.

## The dead zone is radial and rescaled

Every pad reports a stick that is not quite centred, and a game that believes it
walks the player into a wall while nobody touches the controller.

**Radial**, because the magnitude is what rests near zero — a per-axis dead zone
carves a square hole out of a round stick, so the same push is live diagonally
and dead along an axis.

**Rescaled**, so the first live value is nought rather than the dead zone
itself. Without it a stick crossing a 0.15 zone jumps straight to 0.15, and the
discontinuity reads as the character twitching into motion, which looks like a
physics bug. It is the commonest way this is written wrongly.

The default 0.15 is a starting point rather than a measurement: a dead zone can
only be chosen with a controller in hand, so give the player a slider.

## Platforms, and asking before using

macOS, iOS, web and Android are implemented; Windows and Linux are not.
`isSupported` answers false there **without opening a channel**, so asking costs
no `MissingPluginException` and attaches no listener that cannot be detached.
Branch on it before offering pad bindings in a settings screen.

Which implementation a build gets is a conditional export rather than a plugin
registration, which is also why a browser build has a gamepad under `flutter
test --platform chrome`, where a generated plugin registrant never runs.
