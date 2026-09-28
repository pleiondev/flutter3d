# Horizon occlusion and bounced light

The ambient occlusion page samples a handful of points around each pixel and
counts how many are buried. This page swaps the way the pass looks. It walks
across the depth buffer to find the horizon on each side of a pixel, and the
sky a point can see is the gap between the two horizons. The pass integrates
the visibility across that gap, weighted by the cosine to the surface's
normal, so light from overhead counts for more than light from the side. One
step further, the
same walk can collect the light of the surfaces it passes and bounce it onto
the point, so a red wall tints the white floor at its foot.

## Step 1: A white floor and a red wall

A white floor, a red wall across the back and a white block near it. The
crease where the wall meets the floor is where the occlusion shows, and the
floor in front of the wall is where the bounce shows.

{{code room}}

## Step 2: Light for both to work on

Occlusion darkens the light at each point. The composite multiplies all of
it, the sun's direct light included, because keeping the ambient part apart
would take another buffer. That is a compromise, and it looks right where
most of the light in a crease is ambient, so the scene gets some ambient
light for the occlusion to take away. The bounce carries light the wall
already received, so the wall needs a light of its own. The sun comes from
behind the camera.

{{code light}}

## Step 3: Pick the method

`AmbientOcclusionSettings.method` takes an `AmbientOcclusionMethod`. `ssao`,
the default, is the hemisphere of twelve taps the engine has always drawn.
`gtao` finds the horizon along two slices through each pixel and integrates
the visibility between them. `ssil` takes the same slices, treats each thing
it meets as a slab `thickness` metres deep, 0.3 by default, and splits each
slice's half circle into sixteen sectors. A sample adds its light to the
point for the sectors it is the first to cover, so whatever hides behind a
nearer slab adds nothing. Only `ssil` reads `thickness`. `radius` and
`strength` mean what they mean for `ssao`: how far the search reaches in
metres, and how dark a closed corner goes.

{{code settings}}

{{code methods}}

Pick `ssao`, then `gtao`, and compare the crease under the wall and around the
block. Pick `ssil` and the floor in front of the wall picks up some of its
red. Raise **Strength** and both the darkening and the bounce grow, because
the composite adds the light by the same strength it darkens by. Lower
**Thickness** and each thing the walk meets hides less of what stands behind
it. Under `ssao` and `gtao` the **Thickness** slider does nothing.

## Step 4: Check that it ran

Whatever the method, the pass is still called `ssao` in `FrameResult.passes`.

{{code ran}}

> **Note.** Both new methods read a third scene attachment, the albedo buffer,
> for the colour of the surface that receives the bounce. The colour of the
> bounced light itself comes from the lit scene. On a device with only two
> colour attachments, `gtao` drops the brightening that many bounces give a
> light surface, and `ssil` treats every receiving surface as mid grey.
