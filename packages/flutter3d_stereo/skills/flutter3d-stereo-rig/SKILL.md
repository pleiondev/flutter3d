---
name: flutter3d-stereo-rig
description: Use when drawing a flutter3d scene in stereo — the stage/head/eyes rig, why the post-processing settings are not the caller's, and what a phone's sensor reports.
---

# A stage, a head, and two eyes

```dart
final rig = StereoRig();          // two cameras 64 mm apart, under a head
scene.add(rig.stage);             // the only node an application moves

StereoSurface(
  renderer: renderer,
  scene: scene,
  rig: rig,
  onBeforeFrame: () => rig.applyHead(tracker.pose.value),
  settings: () => const RenderSettings(exposure: 1.2),
);
```

**Move the stage, never the head.** The head is what the tracker says; the stage
is where the player stands. Walking, riding a vehicle and starting somewhere
other than the origin all happen on the stage, because arguing with a sensor
sixty times a second is not a locomotion system.

## The surface decides the settings a pair may have

`StereoSurface` applies `RenderSettings.forStereo` itself rather than trusting
the caller to remember, because three effects are **wrong on a pair rather than
merely slow**: ambient occlusion and screen-space reflections are compiled for
the first view and applied to the whole frame, so they reconstruct the right eye
with the left eye's camera; and bloom blurs across the seam, so a bright edge in
one eye glows into the other.

Fog survives, applied per draw with the view's own camera. So does auto
exposure, deliberately — one exposure for two eyes rather than two that disagree
while the head turns.

## Three degrees of freedom on a phone

`SensorHeadTracker` reports rotation and nothing else. Leaning forward moves
nothing, which is honest: a neck model inventing a translation reads as the room
sliding about.

The arithmetic between Android's frame and the engine's is
`headRotationFromSensor`, in Dart, where a test can hold it to numbers; the
native side forwards the sensor's values and how far the screen is turned and
decides nothing. Two traps are written on that function: three coordinate frames
meet there and none is the engine's, and in `vector_math`,
`Quaternion.rotate` applies the transpose of what `asRotationMatrix` builds —
and it is the matrix a `SceneNode` uses.

## What is deliberately absent

The swapchain, the frame's timing, and a pose predicted by a compositor rather
than reported by a sensor. Those change **who drives the frame**, and an
interface guessed at before a headset has answered describes the wrong machine.

Nothing here mentions OpenXR and nothing needs a device to be right, which is
the point: all of it can be got wrong long before there is a runtime to blame.
`example/` is the acceptance tool for these three parts on real hardware.
