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
