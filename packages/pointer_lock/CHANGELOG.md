## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* Relative mouse deltas, which Flutter offers on no desktop platform.
* A reset on construction, because a plugin outlives a hot restart and would
  otherwise strand the cursor; and focus loss releases rather than pauses, or a
  hidden cursor ends up over another application's window.
