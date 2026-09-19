# Rectangle area lights

`LightType.area` is the one light shape in this engine that is not
punctual: it has extent, a width and a height, so what reaches a surface is
an integral over the rectangle rather than a value read at a single point.
That is the difference between a room lit by a window and a room lit by a
bright dot with a window painted behind it.

## Step 1: A window

The panel faces the node's local `-Z`, the same axis a spot light and a
camera both look along, so `lookAt` aims it exactly the way it aims
everything else in the scene.

{{code window}}

## Step 2: A room for it to light

A back wall and a floor, both plain and rough, so the light falling across
them is easy to read.

{{code room}}

## Step 3: Resize the window

Width and height are written back into the light every frame, so the
sliders change the panel a person can see rather than a copy nothing reads.

{{code live}}

{{code check}}
