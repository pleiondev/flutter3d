# Head tracking

`HeadTracker` promises one thing: a `pose` that says which way the head is
turned. `SensorHeadTracker`, the real implementation, reads that from a
phone's rotation sensor. This page cannot run on one, so it implements the
same interface by hand, driven by a drag of the pointer, and the rig on the
other end cannot tell the two apart.

## Step 1: A tracker that is not a sensor

{{code tracker}}

## Step 2: Feed the pose to the rig

`StereoRig.applyHead` reads a pose's rotation and position and points the
head node with them, whichever kind of tracker produced it.

{{code apply}}

Drag across the page and the view turns, the same way turning a phone would.

## Step 3: Check that turning the head turns the gaze

{{code turn}}

`StereoRig.gaze` reads where the head is looking in world space. Dragging
the pointer changes the tracker's pose, and applying that pose visibly
turns it.
