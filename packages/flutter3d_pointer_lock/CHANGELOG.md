## 0.5.1

* **A native side without a method answers nothing, not an exception.**
  `capture`, `release` and `reset` catch the `MissingPluginException` a
  native side raises for a method it has no handler for, and return: the
  capture state stays where it was, which `stateChanges` already says. The
  engine pins this package at `^0.5.0`, so a method a later minor adds must
  not throw on a native side that predates it, and the catch has to be in
  the Dart side before that minor exists.

## 0.5.0

* **The package is published as `flutter3d_pointer_lock`**, the name it
  has carried from 0.4.3 on; up to 0.4.2+2 it was `pointer_lock`. Move the
  dependency to `flutter3d_pointer_lock: ^0.5.0` and the import to
  `package:flutter3d_pointer_lock/flutter3d_pointer_lock.dart`, or let
  `dart run flutter3d_build:migrate` do both. The native side has the name
  too: the plugin classes are `Flutter3dPointerLockPlugin` (macOS, Linux) and
  `Flutter3dPointerLockPluginCApi` (Windows), and the channels are
  `dev.flutter3d/flutter3d_pointer_lock` and its `/events`, so an app that
  still gets the old package through another dependency registers both
  without a clash.
* **Breaking: `PointerLock.takeDelta` is `drainDelta`**, the verb the engine
  uses for a read that empties what it reads. `release` stays: it is the
  other half of `capture`, not a teardown, and its doc now says so; `dispose`
  is the teardown.
* **Windows and Linux capture the pointer.** On Windows the motion comes
  from Raw Input, the mouse's own counts before acceleration and the screen's
  edge, and the hidden cursor is clipped to the window's centre so a click
  cannot land on another application. On Linux the seat is grabbed with a
  blank cursor and the pointer warped back to the centre after each motion,
  which X11 allows and Wayland does not: there the deltas stop at the
  window's edge. Both let go when the window loses focus, as macOS does.
  Neither could be built where this was written; the desktop jobs in CI
  build them.
* **Android and iPadOS capture the pointer too, so pub.dev lists all six
  platforms.** On Android the Flutter view asks for
  `View.requestPointerCapture` (API 26 on) and the motion comes from its
  captured-pointer listener, in logical pixels; a click while captured
  reaches Flutter at the view's centre. On an iPad the Flutter view
  controller answers `prefersPointerLocked`, the motion comes from
  `GCMouse`, and the capture counts as held only once the scene says it is,
  which it will not in Split View or Slide Over. Both let go when the
  application loses focus, as the desktops do, and both sum the motion
  natively and send it once a frame rather than once a mouse event.
* **On a phone or a tablet `isSupported` follows the mouse.** It is true
  while one is connected and false otherwise, so a game on a phone with no
  mouse still shows its touch controls. The answer arrives a moment after
  start, and each change of it after that, on the new
  `PointerLock.onSupportChanged` (`PointerLockPlatform.supportChanges` for a
  platform implementation, a stream that never fires by default).

## 0.4.2+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and Flutter 3.47.0, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.4.2

* **The package ships a skill** under `skills/` for an agent that has to
  capture the mouse through it, and the README says where it is. The method
  channel, the web backend and the platform interface are 0.4.1's.

## 0.4.1

* **The page pub.dev serves stops pointing at a directory nobody visiting it
  can see.** The README's closing line sent a reader to
  `apps/flutter3d_template_app`, a relative path inside the repository that
  renders on a package page as a link to nothing; it now names the editor's
  scaffold and the guide that explains it. Documentation only — the method
  channel, the web backend and the platform interface are byte for byte 0.4.0's.
* **A patch on this package's own line, and not the engine's 0.6.0.** It names
  no sibling in its pubspec and nothing here was built against the engine
  release; every dependent asks for `^0.4.0`, which this satisfies. A jump to
  the set's number would claim a share in a release that contains none of its
  code.

## 0.4.0

* The example stores its state subscription and cancels it in `dispose`,
  rather than calling `setState` from a listener that outlived the widget.
  The plugin itself was already symmetric on every path.

## 0.3.0

* **A web backend.** `document.requestPointerLock` through static interop,
  selected by conditional export the way `pad_input` selects its gamepad — so a
  desktop browser captures the pointer instead of being told it cannot, and a
  first-person game in a browser is played with the mouse rather than by
  dragging the world around. Pure Dart: nothing to register, and its tests run
  under `flutter test --platform chrome`.
* Refusals, releases the player did not ask for, and captures asked for outside
  a user gesture are all handled as the browser reports them: a refused capture
  leaves the state released rather than assuming success.
* A coarse pointer — a phone or a tablet — answers `isSupported: false`, which
  is what puts a game's on-screen controls on the screen.

## 0.2.0

* Relative mouse deltas, which Flutter offers on no desktop platform.
* A reset on construction, because a plugin outlives a hot restart and would
  otherwise strand the cursor; and focus loss releases rather than pauses, or a
  hidden cursor ends up over another application's window.
