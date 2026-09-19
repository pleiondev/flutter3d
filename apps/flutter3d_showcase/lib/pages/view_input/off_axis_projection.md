# Off-axis frustum

An ordinary perspective camera has its axis down the middle: the same angle
opens to the left as to the right. A headset lens is not built that way, and
neither is a window in a wall that a player looks through from one side.
`OffAxisProjection` describes a frustum whose four sides are given
separately, so the axis can sit anywhere inside it.

## Step 1: Start from a symmetric one

The easiest way to build an off-axis frustum is to start from a symmetric
one and then move its sides. `OffAxisProjection.symmetric` builds the
frustum an ordinary perspective camera of the same field of view would have.

{{code symmetric}}

## Step 2: Shift it

Sliding `tanLeft` and `tanRight` by the same amount keeps the frustum's
width the same but moves its axis. This is the shape a stereo eye or a
portal needs: the lens is not centred on what it is looking at.

{{code skew}}

> **Note.** The four values are tangents of angles from the view axis, not
> angles themselves. That is what the matrix needs directly, and it is what
> a headset runtime already hands over as `XrFovf`.

## Step 3: Watch the sphere move

Drag the slider and the sphere slides across the frame without the camera
itself turning. A symmetric camera cannot do this: turning it would rotate
the whole world with it. An off-axis one reframes without rotating, which is
the one thing this projection is for.

{{code skew}}
