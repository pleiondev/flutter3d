# The stereo rig

A headset reports where the head is inside a room, which leaves nowhere to
put walking, riding a vehicle, or a level that starts somewhere other than
the origin. `StereoRig` is three nodes for that reason: a stage the
application moves, a head the tracker points, and two eyes under it, a fixed
distance apart.

## Step 1: Build the rig

{{code rig}}

## Step 2: Draw it as a pair

`StereoSurface` renders both eyes into one frame, left half and right, and
applies the settings a stereo pair needs — `RenderSettings.forStereo()` — so
a caller does not have to remember to.

{{code surface}}

## Step 3: Check the split

{{code views}}

The rig always draws exactly two views, the left filling the left half of
the frame and the right filling the right half, whatever runtime is driving
the head.
