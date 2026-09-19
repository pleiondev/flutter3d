# Shadows of cut-out leaves

A leaf, a fence or a net is usually one flat quad with a texture whose transparent
pixels are the holes. The picture drawn for the eye already respects those holes. The
picture drawn for the shadow has to as well, or every leaf casts the shadow of a
solid rectangle.

The engine does this for materials in the cut-out alpha mode: while the shadow map is
drawn, each caster's texture is read and any pixel below the cutoff is skipped.

## Step 1: A texture with holes

The page makes its own leaf texture in code: a grid of soft discs, opaque in the middle
and fading to nothing at the rim. The fade is what makes the cutoff meaningful, since
a higher cutoff keeps only the more opaque middle of each disc.

{{code texture}}

## Step 2: A material that cuts out

`MaterialAlphaMode.mask` is the switch. It needs a base-colour texture with an alpha
channel, here `albedo`, and a threshold, `alphaCutoff`. The material is double sided
so the leaves show from underneath as well. Nothing on the light or the settings says
that this caster is special: the renderer sees the mode and picks the cut-out shadow
stage by itself.

{{code leaves}}

## Step 3: A sun that casts

The same request as on every shadow page. Look at the ground: the canopy's shadow is
a pattern of discs, not a square.

{{code sun}}

## Step 4: Change the cut

The page writes the mode and the cutoff into the material each frame. Switch **Cut out**
off and the canopy becomes opaque, so its shadow fills in as a solid square. Drag
**Cutoff** up and the discs in the shadow shrink, because fewer pixels are opaque enough.

{{code live}}
