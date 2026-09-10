# flutter3d_stereo

Stereo for this engine: a rig of two eyes, the widget that draws them side by
side into one frame, and a head to point them with.

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

## What is here, and what is deliberately not

**Here is what a phone and a headset agree about.** Two cameras a fixed distance
apart, two views into one target, a set of render settings a pair can actually
have, and a pose that comes from outside. None of it mentions OpenXR, and none
of it needs a device to be right — which is the point, because all of it can be
got wrong long before there is a runtime to blame.

**Not here, until a headset has answered:** the swapchain, the frame's timing,
and a pose predicted by a compositor rather than reported by a sensor. Those
change *who drives the frame*, and an interface guessed at before the device has
spoken is an interface describing the wrong machine.

## The three parts

| | |
|---|---|
| `StereoRig` | stage → head → two eyes. The head is what the tracker says; the stage is where the player stands, and the only thing an application moves. Walking, riding, or starting somewhere other than the origin all happen on the stage, because arguing with the sensor sixty times a second is not a locomotion system. |
| `StereoSurface` | `SceneSurface` for a pair: it renders two views into one frame and applies `RenderSettings.forStereo` itself rather than trusting the caller to remember. |
| `HeadTracker` | where the head is. `SensorHeadTracker` reads the phone's rotation vector; a headset's runtime replaces it without the other two noticing. |

## Why the settings are not the caller's to choose

Ambient occlusion and screen-space reflections are compiled for the first view
and then applied to the whole frame, so on a pair drawn side by side they
reconstruct the right eye with the left eye's camera — occlusion in the wrong
places and reflections along the wrong ray, on half the picture. Bloom blurs
across the seam, so a bright edge in one eye glows into the other. All three are
wrong on a pair rather than merely slow, and a rule a caller can forget is a
rule that is sometimes broken. `StereoSurface` applies it.

Fog survives: it is applied per draw with the view's own camera. So does auto
exposure, and wanting it to — one exposure for two eyes rather than two that
disagree while the head turns.

## Where the tracker works, and where it does not

`SensorHeadTracker` is an Android plugin: on desktop, on the web and on iOS
there is nothing behind its channel, and it says so once and leaves the head
where it is. The rig and the surface do not care — a scene still draws in
stereo, and an application that points the head itself (a replay, a test, a
camera on rails) never wanted the sensor anyway.

## Three degrees of freedom on a phone

`SensorHeadTracker` reports rotation and nothing else. Leaning forward moves
nothing, and that is honest: a neck model inventing a translation from a
rotation reads as the room sliding about.

The arithmetic between Android's frame and the engine's lives in
`headRotationFromSensor`, in Dart, where a test can hold it to numbers — the
native side forwards the sensor's values and how far the screen is turned, and
decides nothing. Three frames meet there and none of them is the engine's, which
is one of the two traps this package has already paid for. The other is written
on that function: in `vector_math`, `Quaternion.rotate` applies the transpose of
what `asRotationMatrix` builds, and it is the matrix a `SceneNode` uses.

## The example

`example/` draws a room in stereo on whatever is at hand, pointed by the
device's own sensor. It is the acceptance tool for the three parts above on real
hardware — not a demo of VR, which needs the half a phone does not have.
