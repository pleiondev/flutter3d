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

The package holds what a phone and a headset agree about: two cameras a fixed
distance apart, two views into one target, a set of render settings a pair can
actually have, a pose that comes from outside, and the handful of numbers that
describe a holder. None of it mentions OpenXR, and none of it needs a device to
be right. All of it can be got wrong long before there is a runtime to blame.

Three things wait until a headset has answered: the swapchain, the frame's
timing, and a pose predicted by a compositor rather than reported by a sensor.
Those change *who drives the frame*, and an interface guessed before the
device exists would describe the wrong machine.

Lens distortion is missing for a plainer reason. A lens bends straight lines
outward. Undoing that means drawing the frame into a texture and sampling it
back through the inverse curve, which is a post-processing pass written once
per shader dialect across four backends. Until that pass exists, a wide-angle
holder shows straight edges bowed near the rim of the picture. The geometry
below is right; the rim is not.

## The four parts

| | |
|---|---|
| `StereoRig` | stage → head → two eyes. The head is what the tracker says. The stage is where the player stands, and it is the only thing an application moves. Walking, riding, or starting somewhere other than the origin all happen on the stage, because overriding the sensor sixty times a second does not make a locomotion system. |
| `StereoSurface` | `SceneSurface` for a pair. It renders two views into one frame and applies `RenderSettings.forStereo` itself instead of relying on the caller to remember. |
| `StereoViewer` | the holder, described by the numbers holders differ in: how far apart the lenses are, how far the screen sits from them, how high the lens axis is above the tray, and how wide a window the lens allows. `cardboardV1` and `cardboardV2` are the published profiles; a holder that states its own figures is written out instead. |
| `HeadTracker` | where the head is. `SensorHeadTracker` reads the phone's rotation vector; a headset's runtime replaces it without the other two noticing. |

## The holder, and why a centred pair is wrong in one

```dart
StereoSurface(
  renderer: renderer,
  scene: scene,
  rig: rig,
  viewer: StereoViewer.cardboardV2,
  screen: const StereoScreen(width: 0.147, height: 0.068),   // metres
  onBeforeFrame: () => rig.applyHead(tracker.pose.value),
  settings: () => const RenderSettings(exposure: 1.2),
);
```

The lens does not sit in the middle of the half of the screen it looks at. Two
lenses are a face's width apart and a phone is wider than that, so each eye
reaches further towards the outside of its half than towards the inside. If
both halves get the same centred frustum, the picture lands off the lens axis
by that difference. The eyes then disagree about where things are, and the
person wearing it reports a headache instead of a bug.

`StereoScreen` is in metres, because the arithmetic is a ratio between two
lengths. If it is left out, the surface estimates it from its own size at 160
logical pixels to the inch. That is close enough to try a holder with, but the
real figure is better. Take care with `trayToLensHeight`: here it is measured
to the bottom edge of the **screen**, while a published profile measures to
the bottom of the phone, so subtract the bezel before passing it on.

Without a viewer nothing changes. The frustums stay centred and as wide as half
the surface, which is what a phone held in the hands wants.

## Why the settings are not the caller's to choose

Ambient occlusion and screen-space reflections are compiled for the first view
and then applied to the whole frame. On a pair drawn side by side they
reconstruct the right eye with the left eye's camera, which puts occlusion in
the wrong places and reflections along the wrong ray on half the picture.
Bloom blurs across the seam, so a bright edge in one eye glows into the other.
On a pair all three effects are wrong, not merely slow. A caller could forget
to turn them off, so `StereoSurface` does it.

Fog survives, because it is applied per draw with the view's own camera. Auto
exposure survives too, on purpose: one exposure for two eyes is better than two
that disagree while the head turns.

## Where the tracker works, and where it does not

`SensorHeadTracker` is an Android plugin. On desktop, on the web and on iOS
there is nothing behind its channel, so it reports that once and leaves the
head where it is. The rig and the surface do not depend on it. A scene still
draws in stereo, and an application that points the head itself (a replay, a
test, a camera on rails) has no use for the sensor anyway.

## Three degrees of freedom on a phone

`SensorHeadTracker` reports rotation and nothing else, so leaning forward moves
nothing. A neck model that invented a translation from a rotation would make
the room appear to slide about.

The arithmetic between Android's frame and the engine's lives in
`headRotationFromSensor`, in Dart, where a test can check it against numbers.
The native side forwards the sensor's values and how far the screen is turned,
and decides nothing. Three frames meet in that function and none of them is
the engine's; that is one of the two traps this package has already hit. The
other is documented on the same function: in `vector_math`,
`Quaternion.rotate` applies the transpose of what `asRotationMatrix` builds,
and the matrix is what a `SceneNode` uses.

## The example

`example/` draws a room in stereo on whatever device is at hand, pointed by the
device's own sensor. It is the acceptance tool for the three parts above on
real hardware. It is not a VR demo, since VR needs the half that a phone does
not have.
