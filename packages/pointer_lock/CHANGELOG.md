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
