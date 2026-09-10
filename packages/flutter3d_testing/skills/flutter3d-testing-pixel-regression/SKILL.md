---
name: flutter3d-testing-pixel-regression
description: Use when adding pixel regression tests to a game built on flutter3d — renderFrame and expectMatchesGolden run with no GPU, and the tolerance is zero on purpose.
---

# A picture, in an ordinary test, on a machine with no GPU

```dart
test('the crypt still looks like the crypt', () async {
  final frame = await renderFrame(
    width: 320,
    height: 180,
    build: (request) {
      final scene = Scene();
      // put the level in it, uploading meshes to request.device
      return (scene: scene, camera: camera);   // a FrameSubject record
    },
  );
  await expectMatchesGolden(frame, 'test/goldens/crypt.png');
});
```

The first run records the reference and says so; later runs fail when the
picture changes, and say by how much and how to re-record.

Keep frames small. This rasterises in Dart, so 320×180 is a test and 1080p is a
wait — and a regression needing more than that is usually one a smaller frame
would also have shown.

## The tolerance is zero, deliberately

The frame comes from a software rasteriser: no driver, no clock, no thread to
disagree, so the same scene drawn twice is the same bytes twice. A difference is
a change rather than noise.

A test that allows a few pixels of drift has stopped watching the drift. Raise
`tolerance` only when something has been **measured** to move, and say in the
call why.

## What these references are

They say what the software backend draws. They are not a comparison against a
GPU: the same scene differs by a fraction of a percent between a rasteriser and
a driver, and one shared set would need a tolerance covering that for ever. The
cross-backend question is asked as its own test over the two committed sets.

A game's references made here are still the right thing to regress against: a
change that alters the picture alters it on both.

## Why this is its own package

`flutter3d_cpu` must not depend on `flutter3d` — a backend that could not
compile without the engine would be part of the engine — and `flutter3d` must
not depend on a backend, which `tool/structure.dart` enforces. Neither can hold
something that needs both, and this needs both.
