## 0.5.0

* **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `PadSnapshot.connected` is `isConnected`. `dart fix` carries the renames.
* **Controllers on Windows and Linux.** Windows asks XInput's four slots
  about a hundred and twenty times a second; Linux reads the kernel's
  joystick devices, `/dev/input/js0` to `js3`. Both plugins send the
  platform's own numbers untouched, and `XInputPadState` and
  `JoystickPadState` read them in Dart, where a test can see that XInput's
  stick y is up-positive and Linux's is not, which number the `xpad` driver
  gives which button, and that a trigger at rest on Linux reads −32767.
  Neither plugin could be built where this was written; the desktop jobs
  in CI build them.

## 0.4.3+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and Flutter 3.47.0, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.4.3

* **A second player holds a second controller.** `Gamepad(index: 1)` reads
  the controller in the second slot, the second to connect, up to
  `GamepadPlatform.maxPads`; `GamepadPlatform.readPad` reads any slot, and a
  backend that tells no controllers apart reports every slot past the first
  as disconnected rather than the first pad twice. On macOS and iOS every
  controller `GameController` reports is read, each in a slot that is also
  its `playerIndex`, so its light says which player holds it. In a browser
  the slots are the standard pads in the order it lists them. On Android
  every controller is reported by device, and its buttons are forwarded
  with their device from the window, since through Flutter's keyboard two
  controllers pressing A were one A; a d-pad that sends keys is now the
  pad's d-pad rather than a keyboard's arrows. A slot a controller leaves
  is the next one's, and the others keep theirs.

## 0.4.2

* **An iOS build no longer fails on the buttons the plugin reads.** The Swift
  package declared iOS 12.0 and macOS 10.14 as its floor, and Swift Package
  Manager compiles the target against that floor, so the stick clicks (12.1),
  menu and options (13.0) and the home button (14.0) in `GamepadPlugin.swift`
  failed the build. The floor is now iOS 14.0 and macOS 11.0, what the sources
  have always needed.
* **The package ships a skill** under `skills/` for an agent that has to read a
  gamepad through it, and the README says where it is.

## 0.4.1

* **The page pub.dev serves stops pointing at a directory nobody visiting it
  can see.** The README's closing line sent a reader to
  `apps/flutter3d_template_app`, a relative path inside the repository that
  renders on a package page as a link to nothing; it now names the editor's
  scaffold and the guide that explains it. Documentation only — not one byte of
  `lib/`, of the Android or Darwin plugin, or of the pubspec's dependencies
  changed.
* **A patch on this package's own line, and not the engine's 0.6.0.** This is a
  plugin the engine happens to vendor: it names no sibling in its pubspec,
  nothing here was built against the engine release, and every dependent asks
  for `^0.4.0`, which this satisfies. Joining the set's numbering would claim a
  share in a release that contains none of its code, and would retire a 0.5 line
  it never had.

## 0.4.0

* The Android plugin performs the stream's own teardown when detached from an
  engine — input-device listener unregistered, motion listener detached —
  instead of leaving the system `InputManager` holding the plugin with a live
  listener across an engine restart. Idempotent with `onCancel`, which is not
  guaranteed to have run.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* A gamepad read as a snapshot once per frame, with a dead zone applied and no
  opinion about what any button means.
* Buttons are named by physical position, because the string ends up in a
  player's config and is read years later on another pad.
* Web, Android, macOS and iOS, with the native half deciding nothing: every
  decision is in Dart and under test, because that is where the difficulty is.
