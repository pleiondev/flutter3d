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
| macOS | **yes** | `GameController.framework`, one Swift source shared with iOS |
| Web | **yes** | `navigator.getGamepads()`, pure Dart, no native code |
| iOS | **yes** | the same file, through `sharedDarwinSource` |
| Android | **yes** | Kotlin forwards raw `MotionEvent` axes and an inventory of what the device has; every decision is in Dart |
| Windows | no | XInput, when somebody needs it |
| Linux | no | evdev, likewise |

Which implementation a build gets is a **conditional export**
(`lib/src/platform_default.dart`), not a plugin registration: the web backend is
pure Dart with nothing to register, and the choice is a fact about the platform
rather than a preference. It also means a browser build has a gamepad under
`flutter test --platform chrome`, where a generated plugin registrant never runs.

`isSupported` answers `false` on a platform with no implementation, and answers
it **without opening a channel**: asking and catching the failure costs every
unsupported platform a `MissingPluginException` at first use, and a listener
already attached cannot be un-attached.

## On Apple's platforms, one sign is the whole difference

`GCExtendedGamepad` is already the shape this package chose — face buttons by
position, four d-pad buttons, two analogue triggers, two clickable sticks — so
there is no per-device guessing and no mapping database to consult. Apple
normalised the hardware years ago. macOS and iOS share one Swift file, because
the framework is the same framework on both.

What is left is **`GameController` reports a stick's y positive upwards**, where
Android, the browser and this package all report it downwards. It is a difference
no code review catches and a room with a controller catches in one second,
because the character walks backwards. So it is negated in
`lib/src/darwin_mapping.dart`, once, with a test on it — rather than in Swift,
where nothing could see it.

## On Android, the native side decides nothing

The rule that got a previous gamepad backend deleted rather than finished still
holds, so the way past it is to leave the Kotlin with nothing in it a test would
have caught. It reports which controller is attached and **which axes that
controller admits to having**, forwards each `MotionEvent` untouched, and says
when the application goes to the background. Everything else —
`lib/src/android_mapping.dart` — is Dart, and `test/android_test.dart` covers it.

Three Android facts worth knowing, because each is a device disagreeing with
another device:

* **A trigger is on one of two axis pairs.** Some drivers report `AXIS_LTRIGGER`
  and `AXIS_RTRIGGER`; others report `AXIS_BRAKE` and `AXIS_GAS` — the same
  physical control under a steering wheel's name — and a few report neither and
  offer only the digital `L2`/`R2` buttons. Which to read is chosen per device
  from the inventory, never guessed.
* **A d-pad is a hat or it is arrow keys.** A hat (`AXIS_HAT_X`/`AXIS_HAT_Y`) is
  read as a d-pad. A pad without one sends `KEYCODE_DPAD_*`, which Flutter maps
  to the arrow keys — indistinguishable in Dart from a keyboard's arrows, because
  a `KeyEvent` does not say which device it came from. Those are deliberately
  **not** claimed as `pad:dpad.*`: writing that identifier for a key that might
  be a keyboard's would put a lie in the player's permanent config file. On such
  hardware the d-pad works as arrow keys, which every game here binds to walking
  anyway.
* **Buttons arrive through Flutter, not through the plugin.** Android delivers
  them as `KeyEvent`s and Flutter's embedding already maps their key codes to
  `gameButtonA` and its neighbours. Catching them natively as well would be a
  second source of truth for one event. Sticks are the opposite case: Flutter
  turns pointer and scroll motion into `PointerEvent`s and drops the rest, so a
  joystick's `MotionEvent` never reaches Dart, and that is the one thing the
  plugin exists for.

Android has **no way to ask** a gamepad what it is doing — input arrives as
events aimed at the focused window — so events fill a mirror and `read` copies
it. The API stays a pull; the transport is a push; the value is as fresh as a
poll's would have been.

### Building it

`packages/pad_input/example` is the Android runner, and there is a **JDK pin** in
the repository's `.mise.toml` because of it: the Android Gradle Plugin's
`core-for-system-modules` transform runs `jlink --disable-plugin system-modules`,
which a JDK 26 refuses, and the error it produces names neither Java nor the
transform.

```sh
cd packages/pad_input/example
mise exec -- flutter build apk --debug   # the pin is what makes this work
mise exec -- flutter run -d <device>
```

## On the web, two things will surprise you

**A pad is invisible until a button is pressed.** Browsers hide gamepads from a
page that has never seen one used, as a fingerprinting defence. Nothing can be
done about it and nothing can detect it: press a button first.

**`getGamepads()` freezes rather than empties** while the page is in the
background — it keeps returning the last values it saw, so a player who switches
tabs mid-corner would come back to a car that never stopped accelerating. So
focus and visibility are both watched, and an unfocused page reports a pad that
is attached and doing nothing. Not disconnected: the controller is still there,
the player is not, and everything downstream releases through the ordinary path.

**Only the standard mapping is used.** A pad the browser will not vouch for is
treated as no pad, because without the mapping the indices come from whatever
the driver felt like — index three might be a trigger — and binding it would
write `pad:face.north` into a player's permanent file for something that is not
a face button. There is deliberately no mapping database here to resolve that
with, and an identifier that means the wrong thing is worse than a pad that does
not answer.

## What this package is not

It knows nothing about games — no actions, no bindings, no vocabulary. What
turns `face.south` into "jump" belongs beside the keyboard's equivalent in the
game layer, for the same reason `pointer_lock` reports deltas and lets its
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
platform, as `pointer_lock` does.

The browser's mapping table is tested too, and separately from the browser: the
seventeen button indices and four axis indices live in
`lib/src/standard_mapping.dart`, which imports no `dart:js_interop` and so is
checked by an ordinary unit test — including the mistake this is most likely to
ship with, a trigger looked for in the axis list where the right stick lives.
Run the suite both ways; the second one compiles the web backend:

```sh
flutter test
flutter test --platform chrome
```

The Android backend is tested the same way and for the same reason: the trigger
pair chosen per device, the hat becoming four buttons, arrow keys *not* becoming
a d-pad, a second controller's stick being ignored, the background releasing
everything without disconnecting, and the channel's own decoding against a mock
messenger. What is left for a person is whether the events arrive at all.

`packages/pad_input/example` is the tool for that half — every axis, every trigger
and every button live on one screen, with the dead-zone sliders beside them, so
the acceptance checklist can be walked in a minute.

What remains manual is written down where it belongs — in the plan, as an
acceptance checklist, because it is the part a person has to do.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team.
Documentation: <https://flutter3d.pleion.dev>.
