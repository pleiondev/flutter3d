# The field kept current

The irradiance field page fills its probes once, by casting rays, when the page opens. If
the room changes after that, the probes still hold the room as it was.

With `gpuUpdates` above zero the renderer keeps the field current itself. Each frame it
takes a few probes in turn, draws the room into a small cube from where each one
stands, and folds that into the texture the lit materials read the field from. Since
the room it draws is already lit by the field, every pass adds one more bounce.

## Step 1: A room with a painted wall

A grey floor, a wall along its left side, and one lamp above them. The wall's
material is kept, because the page repaints it later. The scene's ambient strength is
set to one: the field is read at that strength, in place of the flat ambient.

{{code room}}

## Step 2: An empty field that the renderer fills

Eight probes in a 2 by 2 by 2 grid, between the floor and the lamp. Nothing is gathered
here: a new field holds zeros, so it starts black. `gpuUpdates` is how many probes the
renderer draws each frame, going round all of them in order. At two, each of the eight
is looked at again every fourth frame. The first few frames fill the room in.

{{code field}}

## Step 3: Change the room

Each frame the page writes the chosen colour into the wall's material and passes the
two sliders on to the field.

`hysteresis` is how much of a probe's old value it keeps at each update, from nought
to one; the default is 0.9. Pick another **Wall colour** and watch the tint on the
floor near the wall change over from the old colour to the new one. Drag **Hysteresis**
down and it changes faster, but a probe also jumps more from one update to the next.
Drag **Probes a frame** up and every probe is visited sooner, at the cost of drawing
more cubes each frame.

{{code live}}

> **Note.** The updates need cube textures and a second colour attachment. On a device
> without them, the field stays what the application filled it with, which for this
> page is black. `RenderSettings.frameWorkBudget` can hold the updates to a time budget
> per frame; a probe that does not fit waits for the next frame.
