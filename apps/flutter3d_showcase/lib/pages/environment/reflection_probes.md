# Reflection probes

An environment map is the sky, or a picture somebody loaded, seen from
nowhere in particular. A shiny car in a garage does not want the sky. It
wants the garage: the workbench, the door, the light coming through it. A
reflection probe is the scene itself, captured into a cube from one point,
so a mirror finish shows the room it actually stands in.

## Step 1: Put a probe where the reflection should come from

`ReflectionProbeNode` is a point in the scene. On the first frame it is seen,
the renderer draws the world into the six faces of a cube from that point,
then blurs the cube once per roughness level so a duller surface reads a
softer version of the same room. Add it like any other node.

{{code probe}}

`intensity` is its own knob, separate from the scene's flat ambient light: a
probe is the room's light already measured, so a dim room reflects itself at
whatever strength it was actually lit.

## Step 2: Give something a mirror finish

A physical material reads the nearest probe automatically once one is in the
scene. High `metallic` and low `roughness` make the read obvious: a rough
ball barely shows the room, a polished one shows it sharply.

{{code ball}}

Drag **Ball roughness** down and the wall and the floor around it become
readable in the reflection; drag it up and the same room becomes a soft
smear of colour.

## Step 3: What actually happened on the device

The capture is not free, and it does not run every frame for a probe that
is not moving. **Probe intensity** and **Ball roughness** are read fresh
every frame, so a control here only has to change a field.

{{code live}}

> **Note.** The first frame a probe is seen, the renderer draws the scene
> six times into its cube and then filters the whole chain. A kept probe
> after that draws nothing again until `invalidate()` is called or the
> scene changes what it can see.
