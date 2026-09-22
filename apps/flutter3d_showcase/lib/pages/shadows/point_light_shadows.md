# Point and spot shadows

The sun shines one way, so one picture from its side is enough. A lamp shines in every
direction, so its shadow needs a picture in every direction: six, one for each face of
a cube, packed into a shared atlas. A spotlight uses the same atlas and needs one face
of it. This page has a lamp beside a column and a spotlight on the other side, in front
of a wall that catches both shadows.

## Step 1: A lamp that casts

Asking for the shadow works exactly as it does for the sun. `castsShadow: true` on a
point light gives it a row in the atlas. `range` matters more here than for the sun,
because everything beyond it is out of the lamp's reach and nothing is drawn for it.

{{code lamp}}

> **Warning.** The atlas has a fixed number of rows. A light that asks for a shadow
> when they are all taken shades without one and is counted in
> `FrameResult.shadowsDenied`.

## Step 2: A spot that casts

A spot light is the same request with a cone. It aims down its own forward axis, so
`lookAt` points it. It does not get a separate system: it draws into one face of the
cube slot and reads the same settings as the lamp.

{{code spot}}

## Step 3: Tune the cube

`ShadowSettings` has a small group for these lights. `cubeResolution` is the width of one
face, and it costs memory fast, since there are six faces per row. `pointSoftness` is
the width of the blurred edge in texels of a face. `pointBias` is a distance in metres
that keeps a surface from shadowing itself.

Watch the floor as you lower **Bias**. Too little and a surface can speckle with its own
shadow. Raise it too far and the column's shadow lets go of its base.

`casterFaces` picks which side of an object is recorded. **Back** is the default and
suits closed solids. **Front** records the side facing the lamp. **Both** records
each and also catches a one-sided wall that the other two see straight through.

{{code settings}}
