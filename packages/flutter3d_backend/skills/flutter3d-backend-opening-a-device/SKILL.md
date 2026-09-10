---
name: flutter3d-backend-opening-a-device
description: Use when an application needs a GraphicsDevice for flutter3d — openDevice picks Impeller, WebGL2, WebGPU or the software rasteriser, and no library should depend on this.
---

# One call, and no backend in any signature

```dart
final device = await openDevice(width: 1280, height: 720);
final renderer = Renderer.create(device: device);
```

On a desktop or phone the device is `flutter3d_impeller`'s; in a browser it is
`flutter3d_webgl`'s. **Web against native is a conditional export, not an
`if`**: `flutter_gpu` does not compile for the web and `dart:js_interop` does
not compile for macOS, so a file importing both targets nothing. Write no such
file; call `openDevice`.

## The two run-time choices

The software rasteriser is where a native build lands when Impeller will not
start, so a machine with no working GPU still draws.

WebGPU is asked for only when a build asks:

```sh
flutter build web --dart-define=FLUTTER3D_WEBGPU=true
```

and falls back to WebGL2 where the browser has no `navigator.gpu` or hands out
no adapter. Off by default because of size: the probe has to call both openers,
so a build carrying it carries both backends — 376,649 bytes of `main.dart.js`
on the strategy demo, 14.9% more script. An ordinary web build draws through
WebGL2, which is the browser backend with a recorded reference set behind it.

## What this package does not decide

Resolution and shadow budget stay with the application. `kFixedResolution` says
whether the backend renders into a fixed internal target — true in a browser,
where a WebGL canvas resets its drawing buffer on resize — and what that size
should be is the game's own trade:

```dart
final size = kFixedResolution ? const Size(960, 540) : screenSize;
```

## Do not depend on this from a library

It pulls in every backend it can choose between. `flutter3d_session`
deliberately does not, which is what lets a session be mounted over a
`CpuDevice` in its tests, and what keeps a tool like the level editor from
dragging WebGL into a build with no browser target. An application wires the
device in; everything below takes one as a value.
