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
