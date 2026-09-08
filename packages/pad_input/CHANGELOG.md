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
