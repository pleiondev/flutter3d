# flutter3d_stereo example

A room in stereo, pointed by the device's own rotation sensor.

    flutter run -d <a phone>

The acceptance tool for `StereoRig`, `StereoSurface` and `OffAxisProjection` on
real hardware: two eyes side by side, a checkerboard floor and pillars at
several distances, and a head that moves when the device does.

This is not a VR demo. A phone has no compositor, no predicted pose and no
seventy two hertz. What it does have is the other half, and that half is what
this example checks.
