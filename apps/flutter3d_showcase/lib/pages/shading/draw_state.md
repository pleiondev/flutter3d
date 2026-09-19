# Draw order and depth state

Most scenes never need to say in which order things are drawn: the renderer sorts
them. Sometimes you need to overrule it, for a backdrop, a sky or an overlay. A
material has three fields for that, and the render settings have a switch for
triangle backs. This page puts an orange panel in front of a blue box and lets you
decide whether the box shows through.

## Step 1: A box to hide

The box is an ordinary material. It draws in bucket zero, writes depth and passes
the normal depth test, like nearly everything else.

{{code box}}

## Step 2: A panel that steps aside

The panel is nearer to the camera than the box, so by default it would hide it.
Three fields change that. `drawBucket` outranks every other sort term, so a
negative bucket draws before the rest of the scene. `depthWrite: false` makes it
leave the depth buffer alone. `depthCompare` replaces the depth test, and `always`
means the panel does not depend on what is already there.

{{code panel}}

With bucket -1 and no depth writing, the box draws after the panel and finds an
empty depth buffer, so it appears in front of a panel that is physically nearer.
That is how a sky dome or a backdrop works.

## Step 3: Take it apart

Turn Panel writes depth on. The panel now records how near it is, the box fails
the test against it, and the box disappears. Move Panel draw bucket to 0 and the
renderer's own sorting takes over again. Change Panel depth test to `always` and the
panel is drawn over anything drawn before it.

{{code live}}

## Step 4: The backs of triangles

The small red square to the left is turned away from the camera. A triangle seen
from behind is normally skipped, which is what `backfaceCulling` does, and it is
why the square is invisible. Turn Back-face culling off and it appears.

{{code flag}}

The switch is a render setting, read every frame:

{{code culling}}

> **Note.** A material with `doubleSided: true` is never culled, whatever the
> setting says. Use it for thin things such as leaves and cloth.
