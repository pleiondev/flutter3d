# Stretched highlights

Brushed steel, a vinyl record and the bottom of a saucepan all have fine grooves running
one way. A highlight on them is not a round spot: it smears out into a streak across the
grooves. The anisotropy layer gives a material that streak without modelling the
grooves.

This is a different thing from anisotropic texture filtering, which keeps a texture
sharp at a slant and changes nothing about how the surface reflects light.

## Step 1: Two materials

`anisotropyStrength` is how far the highlight stretches, from nought to one.
`anisotropyRotation` is which way, in radians, turning from the surface's tangent
towards its bitangent. Both live in `MaterialExtensions`, which only
`LightingModel.pbrLayered` reads. The plain material on the left is the same model
without them.

{{code materials}}

## Step 2: A mesh with tangents

The stretch runs along the mesh's tangent, so the mesh needs a tangent that means
something. Where the tangent lies along the normal there is no direction left to stretch
in, and the renderer draws the highlight round.

{{code mesh}}

## Step 3: Turn it while it runs

`MaterialExtensions` cannot be changed in place, so the page builds a new one each
frame from the sliders.

{{code live}}

Compare the right sphere with the left one: the round spot on the left is drawn out
into a band on the right. Drag **Rotation** to a quarter turn and the band swings round
to cross the sphere the other way. **Strength** at nought gives back the round spot.

> **Note.** glTF can also carry an anisotropy texture that sets the direction per
> pixel. The engine keeps it so a file saves back unchanged, but does not draw it: the
> direction comes from the rotation alone.
