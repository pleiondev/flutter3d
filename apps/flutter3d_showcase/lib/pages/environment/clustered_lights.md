# Clustered lights

Each draw gets a short list of lights: eight slots, plus a tail of twenty-four more,
ranked against the draw's bounding sphere. For a vase that is plenty. A floor that
spans the whole map is a single draw, though, so it gets the thirty-two brightest
lights anywhere on it, and every other lamp over it does nothing.

Clustered lights hand the list out per pixel instead. Each frame, the view is cut into
16 by 9 tiles and 24 depth slices, and each of those cells gets the lights whose range
reaches it. A fragment reads the lights of the cell it lands in.

## Step 1: One big floor

A white slab twelve metres square, drawn in one call. The scene's ambient light is
turned down to 0.03 so that only the lamps light it.

{{code floor}}

## Step 2: Sixty-four lamps

An eight by eight grid of point lights, a metre apart and thirty centimetres above
the floor, each a different hue. None of them casts a shadow. With a range of 0.8
metres each lamp makes its own spot on the floor, so you can count which ones reach
it.

{{code lights}}

## Step 3: Turn the cells on

`clusteredLights` is a single flag on `RenderSettings`, off by default. Switch
**Clustered lights** off and the floor falls back to the per-draw list: thirty-two of
the sixty-four spots stay dark. Switch it on and all of them light up.

Drag **Light range** up and the spots grow into each other. Each cell then holds more
lights, and each pixel does more work.

{{code settings}}

> **Note.** The cells only take over when a scene has more lights than the eight
> slots and no light channels are in use. The eight slots stay either way, and they
> are still the only lights that can cast a shadow.
