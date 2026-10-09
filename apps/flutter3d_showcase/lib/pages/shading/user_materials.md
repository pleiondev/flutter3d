# A material of your own

The material language page showed the source parsed and evaluated by hand.
This page is the other end: a material a game writes in a `.f3dmat` file,
compiled the way the build hook compiles one, and drawn by the renderer on
three spheres of one instanced batch. It uses the three things the language
gives a game beyond a fixed look: a `uniform` the game sets while it runs, a
`light` block that decides how the surface answers each light, and the four
numbers each copy of a batch carries, read as `instance`.

## Step 1: Write the material

`param` is a constant: the build folds it into the compiled stage, so it
costs nothing and cannot change at run time. `uniform` is the opposite. It
is a member of the material's parameter block, read every frame, so the
game can move it. `paint` starts white.

The `light` block runs once per light, inside the engine's own light loop.
What it returns is how the surface answers that light, and the engine
multiplies it by the light's colour, its `n·l` and its shadow, as it does
for every lit model. Here `n·l` is rounded to one of three bands and divided
back out, so the bands are what is left. The fragment body reads `lit`,
which is the surface lit through that block with the ambient added the way
the engine adds it, multiplies it by the copy's colour and adds a rim as
strong as the copy's fourth number.

{{code source}}

A game keeps this text in `assets_src/` as a `.f3dmat`, and the build hook
compiles it into a `.f3dshaders` bundle with a section for Impeller, one for
WebGL2, one for WebGPU, and the source itself for the software rasteriser.
The showcase does not run the hook, so the bundle beside this page was
built once with the same compiler and is checked in.

## Step 2: Load the bundle on whatever device is open

`loadShaders` takes the bundle on every backend. A GPU device picks its own
section. The software rasteriser has no compiled code to pick: it compiles
the source with `materialLanguageCompiler`, which `openDevice` hands it.
The device a test opens has none, so the page gives it the compiler itself.

{{code compile}}

## Step 3: Bind a material to it

`BundledMaterials` reads the bundle's sources and answers two things per
material: the lighting model, which tells the renderer what to bind for it
(a `light` block makes it a lit model, so the light list and the shadows
are bound), and a default for every `uniform`. `Renderer.addMaterials` puts
the library in front of the ones the renderer already had, so the stage is
found by its name.

{{code bind}}

A game that wants a hot reload to reach the material calls
`HotSwap.loadMaterial` instead, which does the same and keeps the binding
up to date when the source changes.

## Step 4: One batch, three sets of numbers

`addInstance` takes a transform and, optionally, four numbers of the game's
own. `setInstanceData` changes them later. They are the only thing that
differs between the copies, and there is still one draw.

{{code instances}}

## Step 5: Move the uniform

The slider writes three numbers into the list the material already holds.
The renderer binds `Material.parameters` every frame, so the next frame
shows the warmer paint with nothing rebuilt or reloaded.

{{code uniform}}

## Step 6: What the page checks

The bundle has to carry the very source quoted above. Each sphere's
strongest channel has to be the one its own numbers say. Across the sphere
with no rim, a row of pixels may take at most five shades: three bands, the
unlit side and one boundary. Lit by plain `n·l`, the same row takes a
different value at nearly every pixel. The probe frame is drawn without
dither or bloom so that a band is one value from edge to edge.

{{code check}}

> **Note.** A `param` is folded when the bundle is built and cannot be moved
> at run time, and a variant may not set a `uniform`: the language refuses
> one. The bundle checked in here
> was compiled under one Flutter SDK, and Impeller refuses a bundle from
> another; a game does not see this, because its hook compiles on every
> build, but this page then says why it fell back to the built-in toon
> model. A `uniform` added by an edit reaches a material through
> `HotMaterials.bind`; one changed by hand in `Material.parameters` must keep
> the length the source declares.
