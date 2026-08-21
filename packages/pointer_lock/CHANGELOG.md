## 0.1.0

* Pointer capture on macOS: the cursor is frozen and hidden while motion arrives
  as relative deltas.
* `takeDelta` drains an accumulator, which is the shape a fixed-timestep
  simulation wants.
* Capture is released when the window or the application loses focus, and the
  release is announced on `onStateChanged`.
* Construction resets the native side, so a hot restart cannot strand the cursor.
* `isSupported` answers honestly on platforms with no implementation instead of
  throwing at the first call.
