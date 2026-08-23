# flutter3d_backend

Which graphics backend a build draws through, chosen at compile time.

```dart
import 'package:flutter3d_backend/flutter3d_backend.dart';

final device = await openDevice(width: 1280, height: 720);
```

`openDevice` returns a `GraphicsDevice` from `flutter3d_hardware`. Neither
backend appears in any signature: on a desktop or a phone the device is
`flutter3d_impeller`'s, in a browser it is `flutter3d_webgl`'s, and the choice is
a conditional export rather than a runtime branch — `flutter_gpu` does not
compile for the web and `dart:js_interop` does not compile for macOS, so a file
importing both could target neither.

## What it does not decide

Resolution and shadow budget stay in the application. `kFixedResolution` tells a
caller whether the backend renders to a fixed internal target — true in a
browser, where a WebGL canvas resets its drawing buffer when it is resized —
and *what size* is the game's own trade against its own scene. The three games
in this repository answer it differently and each says why where the number is.

## Why it is a package

The conditional import and `openDevice` were three files in each of three games,
byte-identical in two of them down to the paragraph explaining the conditional.

`flutter3d_session` was the obvious home and is the wrong one: it would have to
depend on both backends, and then `apps/flutter3d_editor` — which opens a file, changes it
and writes it back, and has no browser build to choose for — would pull WebGL
through it. Session stays backend-neutral, which is what lets it be mounted over
a `CpuDevice` in its own tests.
