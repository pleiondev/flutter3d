## 0.6.0

* **Floors, and no code.** Storage, settings, the frame clock and the screens
  are byte for byte 0.5.0's. `flutter3d_backend`, `flutter3d_session` and
  `flutter3d_screens` move to `^0.6.0`; `pad_input` and `pointer_lock` stay at
  `^0.4.0`, which their 0.4.1 covers.
* **What arrives through the barrel is one line wider without this package
  changing.** `flutter3d_backend` 0.6.0 can try WebGPU on a web build given
  `--dart-define=FLUTTER3D_WEBGPU=true`; an application assembled from here
  gets that by raising the floor and nothing else, because `openDevice` was
  always the whole of the question this layer asks.

## 0.5.0

* No API change. Its floors move to the 0.5.0 packages it assembles.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* A barrel over `flutter3d_backend`, `flutter3d_session`, `flutter3d_screens`,
  `pad_input` and `pointer_lock` — the five packages an application assembles
  itself from, none of which know about each other. No code of its own.
