# gamepad

A gamepad's sticks, triggers and buttons, read as a snapshot the caller asks
for, with a dead zone already applied.

```dart
final pad = Gamepad.instance;
final snapshot = PadSnapshot();

// Once per frame, in the frame that uses it.
pad.read(snapshot);
if (snapshot.down(PadButton.faceSouth)) jump();
final throttle = snapshot.pressure(PadButton.triggerRight);
```

## Pull, not push

The API is a snapshot, not a stream of button events. A game with a fixed
simulation step asks *what is the pad doing now* exactly once per frame, and a
stream would push edge detection — was this the frame the button went down —
into every caller, where every caller would get it slightly differently.

It is also the only honest shape for the browser: `navigator.getGamepads()` is
itself a poll, so a stream there would be a polling loop wearing a costume.

## The button names are positions, and they are permanent

`face.south`, not `a`. These strings are written into a player's configuration
file and read back years later, possibly on different hardware — and Xbox calls
the lower face button `A`, PlayStation calls the same one Cross, and Nintendo
swaps `A` and `B` with respect to Xbox. If the identifier were the printed
label, a file written on one pad would **mean something different** on another,
and plugging in a different controller would silently move every binding.

Position is the invariant the hardware has. It is also what Apple's
`GCExtendedGamepad` and the browser's Standard Gamepad mapping already normalise
to, so no backend has to guess. Printed labels are for showing a player and are
never saved.

Lower case, dot separated, only ever added to, never renamed.

## The dead zone is radial and rescaled

Every pad reports a stick that is not quite centred; a game that believes it
walks the player into a wall while nobody is touching the controller.

*Radial*, because the magnitude is what rests near zero. A per-axis dead zone
carves a square hole out of a round stick, so the same push is live diagonally
and dead along an axis.

*Rescaled*, so the first live value is nought rather than the dead zone itself.
Without it a stick crossing a 0.15 zone jumps straight to 0.15, and that
discontinuity reads as the character twitching into motion — which looks like a
physics bug rather than an input one, and is the commonest way this is written
wrongly.

The default of 0.15 is a starting point and not a measurement. A dead zone can
only be chosen with a controller in hand: give the player a slider and settle it
by moving it.

## Platforms

| Platform | State | How |
|---|---|---|
| macOS | not yet | `GameController.framework` — `GCController.current`, `GCExtendedGamepad`, and analogue triggers for free |
| Web | not yet | `navigator.getGamepads()`, pure Dart, no native code |
| iOS | not yet | the same Swift source as macOS |
| Android | not yet | Kotlin: `InputDevice`, `InputManager.InputDeviceListener`, `MotionEvent` axes |
| Windows | no | XInput, when somebody needs it |
| Linux | no | evdev, likewise |

`isSupported` answers `false` on a platform with no implementation, and answers
it **without opening a channel**: asking and catching the failure costs every
unsupported platform a `MissingPluginException` at first use, and a listener
already attached cannot be un-attached.

## What this package is not

It knows nothing about games — no actions, no bindings, no vocabulary. What
turns `face.south` into "jump" belongs beside the keyboard's equivalent in the
game layer, for the same reason `mouse_capture` reports deltas and lets its
caller decide what they mean.

Deliberately absent, each for the same reason — no consumer, and each would
widen every signature here:

* **more than one pad at a time.** A player index infects every method it
  touches and cannot be removed afterwards. This package is "the current pad";
* **rumble and haptics** — three unrelated platform APIs, nothing testable
  without a device, and the moment it exists it owes a settings toggle;
* **motion, touchpad, battery, LED colour, adaptive triggers**;
* **a mapping database** in the style of SDL, when `GCExtendedGamepad` and the
  Standard Gamepad mapping already normalise the pads anyone will plug in;
* **menu navigation** — that is Flutter's `FocusTraversal`, not a device.

## Testing without a device

An earlier gamepad backend in this repository was **deleted rather than
finished**, because one written without a controller in hand is wrong in a way
no test shows. That is true of the platform channel and false of everything
above it, so everything above it is tested: the dead zone in both directions,
the trigger's travel, a disconnection zeroing before it announces itself, and
the button vocabulary's own spelling. `test/gamepad_test.dart` supplies a fake
platform, as `mouse_capture` does.

What remains manual is written down where it belongs — in the plan, as an
acceptance checklist, because it is the part a person has to do.
