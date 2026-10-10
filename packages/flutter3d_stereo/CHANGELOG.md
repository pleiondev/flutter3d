## 1.0.0-rc.1

- **Docs**: `StereoRig.interpupillaryDistance` says its default, 64 mm.
- **`StereoSurface.onListenerMoved` is handed a `ListenerPose`**, as
  `Flutter3dView`'s is: position, forward, up and the scene's origin.
- **Breaking: `StereoSurface` is a `Flutter3dView`.** It draws the rig's
  two views through the view, which owns the frame clock, focus and the
  pause a route change brings, so the pair redraws every frame without the
  caller rebuilding it; `onBeforeFrame` runs each frame before it is drawn,
  and `onListenerMoved` follows the left eye. The renderer is borrowed, as
  before. `verticalFieldOfView` is `fovY` on `StereoSurface`, on
  `StereoRig.fitToViewport` and on `StereoRig` itself. `dart fix` carries
  the renames. `LessonStereoView`'s step buttons read their tooltips from
  `Flutter3dAppLocalizations`.
- **Breaking: `headRotationFromSensor(displayRotationDegrees:)` is
  `displayRotation:`**, a `double` in radians (docs/CONTRACTS.md).
  `decodeSensorEvent` converts the platform's degrees where it reads them.
- **Each eye keeps its own past.** The rig's two `RenderView`s are kept for
  its life, and since 1.0 a view, not a camera, holds the reprojection's last
  frame; `StereoRig.dispose` gives back what renderers kept for them.

- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **Breaking: `HeadTracker` is an `abstract base class`**, extended rather
  than implemented, so a member added in a minor release can arrive with a
  body. `start` and `stop` do nothing by default; a tracker says where the
  head is. `SensorHeadTracker` extends it.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**`applyLessonStep` takes `restPositions`**, so a step's `offsets` place each
node at its rest position plus what the step names: a model taken apart in
layers, as the flat lesson player already did.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **The first publication, and the number skips from 0.1.1.** 0.1.0 and 0.1.1
  below were numbers this package carried inside the workspace; neither
  reached pub.dev, so nobody outside saw the ones passed over. The shelf goes
  out on one number so that one number names one tree, and `^0.7.0` on any
  `flutter3d_*` package resolves against every other. `doc/boundary-0.7.0.md`
  lists the thirteen that begin at this release.
* **A lesson plays through the rig, which neither entry below mentions.**
  `applyLessonStep(rig, step, nodes:)` moves the stage to an `edu_step`'s `at`
  and `yaw` and shows or hides the scene nodes the step names in `visible` and
  `hidden`; a node a step does not mention stays as the previous step left it.
  `LessonPlayer` holds which step of an `edu_sequence` a lesson is on, and
  `LessonStereoView` wraps a `StereoSurface` around one with a Previous and a
  Next button, since a phone in a holder has no keyboard. Its `viewer` defaults
  to `StereoViewer.cardboardV2`. Those lens numbers are the published ones and
  have not been checked against a real holder.
* **`LessonStereoView.onTick`.** Called once a frame beside
  `LessonPlayer.applyCurrent`, so a caller that resolved a level's
  `widget_surface` entities can `tick()` them and a `WidgetSurface` draws and
  updates in stereo. Nothing in the rendering path changed for it. Tapping a
  `WidgetSurface` through a stereo pair is not built.
* `flutter3d_sim` `^0.7.0` is a dependency, for `EntityDef`, and the floors on
  `flutter3d` and `flutter3d_app` are `^0.7.0`.

## 0.1.1

* **No API change.** `StereoSurface` shows a frame through `presentFrame` from
  `flutter3d_app` now, since `GraphicsDevice.present` is gone (mcp-01n) — a
  new dependency, not a new parameter, so nothing that already built against
  `StereoSurface` has to change.

## 0.1.0

**The stereo half of a headset, on hardware that is not one.** `StereoRig`
places two eyes under a head under a stage; `StereoSurface` draws them side by
side into one frame and applies the settings a pair can have; `SensorHeadTracker`
points the head with the device's own rotation sensor.

Nothing here names OpenXR. What a phone and a headset agree about is written
now; what they do not — the swapchain, the frame's timing, a predicted pose —
waits for a device to answer rather than being guessed at.

**And the holder the phone goes into.** `StereoViewer` carries the numbers
holders differ by — lens separation, screen-to-lens distance, the lens axis
above the tray, and the window the lens allows — with `cardboardV1` and
`cardboardV2` as the published profiles and `StereoScreen` for the size of the
glass. `StereoRig.applyViewer` turns those into an off-centre frustum per eye,
wider away from the nose than towards it, which is the shape a lens actually
looks through; `StereoSurface` takes a `viewer` and does it every frame.

Lens distortion is still uncorrected, and the package says so where somebody
choosing a holder will read it: undoing a lens curve wants a post-processing
pass in four shader dialects, and until that exists a wide-angle holder bows
straight lines near the rim.
