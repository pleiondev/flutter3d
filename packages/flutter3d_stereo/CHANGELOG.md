## 0.1.0

**The stereo half of a headset, on hardware that is not one.** `StereoRig`
places two eyes under a head under a stage; `StereoSurface` draws them side by
side into one frame and applies the settings a pair can have; `SensorHeadTracker`
points the head with the device's own rotation sensor.

Nothing here names OpenXR. What a phone and a headset agree about is written
now; what they do not — the swapchain, the frame's timing, a predicted pose —
waits for a device to answer rather than being guessed at.
