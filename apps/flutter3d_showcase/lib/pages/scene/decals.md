# Decals

A scorch on a floor, a puddle, a sign painted on a wall: none of these needs
polygons of its own. A `DecalNode` is a box. Whatever geometry stands inside
it takes the decal's colour, and the box itself is never drawn.

The decal changes the colour of the surface, not the light falling on it. The
renderer reads back how much light each pixel got and lays the decal's colour
under that same light, so a decal in a shadow stays in the shadow. In this
scene the crate's shadow falls across the blue patch and darkens it like the
floor around it.

## Step 1: A room with something to paint on

A floor, a wall, a crate on the floor and a sun that casts shadows. Nothing
here knows about decals.

{{code room}}

## Step 2: Lay two decals on the floor

The box is the node's unit cube, from minus a half to a half on each axis. So
the node's scale sets the decal's size: x and z for the picture, y for how
deep it reaches. With no rotation the box lies flat and stamps down its own
y axis, which is what a floor needs.

`color` is an sRGB tint, and its `w` is the opacity. There is no `texture`
here, so each decal paints its tint alone, which is enough for a stain. A
texture would be multiplied by the tint, and `region` picks one cell of an
atlas.

The red stain's box is 1.4 m tall, so it reaches the top of the crate as well
as the floor around it.

{{code floor}}

## Step 3: Turn a box to face a wall

To put a decal on a wall, rotate the box until its up points out of the
wall. A quarter turn about x points it along +z, toward the camera, and the
yellow sign lands on the wall.

{{code wall}}

## Step 4: Decide which decal is on top

Where two decals overlap, the higher `order` is painted over the lower. When
two decals have the same order, the one attached later goes on top. Switch
**Blue over red** to swap them where the puddle crosses the stain.

{{code order}}

## Step 5: Keep a decal off the sides

`angleLimit` is the angle from the box's up past which a surface takes none
of the decal. The default is seventy-five degrees, so a stain on the floor
stays off the walls around it instead of smearing down them. The crate's
sides are at ninety degrees, so they stay clean. Drag **Angle limit** past 90°
and the stain runs down them too. `angleFade` softens that edge, and
`depthFade` softens the top and bottom of the box.

{{code angle}}

## Step 6: Switch the pass on

Decals are off by default. `DecalSettings(enabled: true)` turns on the pass
that paints them. It runs between the opaque half of the scene and the
transparent half, so glass in front of a decal is drawn over it. The pass
needs three colour attachments and turns multisampling off for the frame, as
everything that reads the surface buffer does. Switch **Decals** off and the
room is bare again.

{{code switch}}

## Step 7: What the page checks

The scene holds the three decals, and the frame ran the `decals` pass instead
of culling or skipping it.

{{code check}}

> **Note.** A decal paints the albedo only. It does not change a normal or a
> roughness, so a painted crack catches the light the way the wall under it
> does. Up to sixteen decals and four pictures go into one draw, and more
> are drawn in further batches.
