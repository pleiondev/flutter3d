---
name: flutter3d-conformance-running-the-suite
description: Use when writing or debugging a flutter3d graphics backend — the suite that says a backend is finished, and how declining differs from passing.
---

# What a backend has to do, as a suite it runs against itself

An interface can only say a call exists. This says a clear covers the whole
attachment, uploaded pixels keep their row order, the HDR format the backend
names is really renderable, and every stage pair the engine links does link.

```dart
void main() {
  runDeviceConformance(
    backend: 'my-backend',
    makeDevice: ({required width, required height}) =>
        MyDevice.create(width: width, height: height),
    // Optional: (id: …, bytes: …, sdk: …), the backend's own shaders packed
    // as a loadable bundle. It adds the loaded-library check.
    ownShaders: () async => (id: id, bytes: bytes, sdk: sdk),
  );
}
```

`backend` names the implementation in every test description. A device is made
per check and disposed in a `finally`, because on the one backend where dispose
frees anything a suite that skipped it leaked every texture it made.

Start with `coreChecks`, the sublist a backend can run before it has compiled a
single shader: clears, uploads and readback. `conformanceChecks` is the full
list — pipelines, blending, stencil, multisampling, sampling, picking, vertex
textures.

The stage-link check earns its place regularly: a varying a fragment stage reads
and no vertex stage writes is a hard error in a browser and invisible on a
backend whose pipelines were linked ahead of time.

## Declining is not passing

```dart
if (!device.supportsOffscreenMsaa) {
  decline(device, 'answers false to supportsOffscreenMsaa, and multisamples nothing');
}
require(pixels[0] == 255, 'the clear did not cover the top-left pixel');
```

A check that cannot run used to `return`, and both harnesses printed PASS — the
multisample check would have reported that the software rasteriser resolves
correctly, which it does not do at all. `decline` throws and both harnesses
report a **skip** with the sentence it carries. Write that sentence about the
capability rather than about the check ("answers false to X, and multisamples
nothing"): it is read on its own, next to a check name, by somebody holding a
phone.

`makeDevice` may decline too — headless Chrome has `navigator.gpu` and hands out
no adapter, and nothing was asked, so nothing may be reported green.

Use `require`, not `expect`. `flutter_test`'s matchers throw
`OutsideTestException` when no test is running, and one backend here cannot run
tests at all: Flutter GPU needs Impeller, which a headless `flutter test` does
not enable, so its harness is an application driving the same check list.

## Adding a check

Add it to the right list in `lib/flutter3d_conformance.dart` and run every
backend, not the one it was written against. The number of checks is written in
prose that `dart run tool/structure.dart` verifies.
