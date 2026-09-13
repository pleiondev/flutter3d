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
