# Rectangle area lights

`LightType.area` is the one light shape in this engine that is not
punctual: it has extent, a width and a height, so what reaches a surface is
an integral over the rectangle rather than a value read at a single point.
That is the difference between a room lit by a window and a room lit by a
bright dot with a window painted behind it.

## Step 1: A window

The panel faces the node's local `-Z`, the same axis a spot light and a
camera both look along, so `lookAt` aims it exactly the way it aims
everything else in the scene. Here it sits in the back wall and looks into
the room.

{{code window}}

## Step 2: Something to see

The light itself is not drawn, so a room lit by it has a window you cannot
see. A glowing rectangle of the same size, just behind the light, stands in
for the glass.

{{code pane}}

## Step 3: A room for it to light

A plain, rough back wall. The window shines away from it, into the room, so
the wall stays dim and the window reads against it.

{{code room}}

## Step 4: A floor that can shine

The floor has a material of its own, so its roughness can change on its own.

{{code floor}}

## Step 5: Resize the window, polish the floor

The sliders' `width` and `height` are written back into the light every frame, so the
sliders change the panel a person can see rather than a copy nothing reads. The glowing
pane is scaled to the same size, and the floor's roughness is written back the same way.

The light's `intensity` stays the same as the panel grows, and the shader spreads it over
the area: each square metre of a bigger window is dimmer. The pane's glow is a material
the light knows nothing about, so the page scales it by the same ratio, the starting
2.5 by 1.5 over the current width times height, to keep the pane as bright as the
reflection it stands for.

{{code live}}

Bring **Floor roughness** down toward 0.05 and the floor reflects the window as a sharp
rectangle. Widen the window and the reflection widens with it and dims. Raise the
roughness and the reflection softens: at middling roughness it still shows the panel's
proportions, and near 1 it spreads into a blob. The highlight is
integrated over the whole rectangle, not read at one point of it, which is why a long
window gives a long reflection.

{{code check}}
