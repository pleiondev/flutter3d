# Volumetric fog

Distance fog fades the scene toward one colour and knows nothing about lights. Real
air is lit: a lamp in a smoky room glows in the air around it, not only on the wall
it shines at.

Volumetric fog marches each view ray through the air a step at a time. At every step
it asks which lights reach that point, adds the light the air sends toward the eye,
and keeps track of how much of the scene behind still gets through. The march runs at
half resolution, and the result is brought up to full size by comparing depths, so a
glow behind an object stops at its edge.

## Step 1: A floor of torches

The floor from the clustered lights page: a white slab and an eight by eight grid of
point lights thirty centimetres above it, each a different hue. Here each light
reaches a metre and a half, so the pools of light overlap. There is no sun.

{{code torches}}

## Step 2: Let the air see the lamps

The air finds its point and spot lights through the cells that clustered lights cut
the view into. So this page switches `clusteredLights` on. Without it, the air is lit
by the sun and by `ambient` alone, and this scene has neither.

{{code cells}}

## Step 3: Fill the room with air

`VolumetricFogSettings` is off by default. `density` is the air's extinction: how much
of the light passing through it is lost per metre, at `baseHeight`, which is zero
here. The default is 0.02; this page
uses 0.3, a thick haze, because the whole room is only a few metres across.
`heightFalloff` thins the air as it rises: the density at a height `y` is
`density * e^(-heightFalloff * (y - baseHeight))`, so at 1.0 the air a metre up holds about a
third of what lies on the floor. Zero is air of the same thickness everywhere.

`steps` is how many samples each ray takes, at most sixty-four. `distance` is how far
the march goes, in metres; past it there is no more air. `color` is the air's albedo,
a tint on the light it scatters. White scatters every light as it is. Null is also
white.

Switch **Volumetric fog** off and on to see what it adds: a coloured glow in the air
over each torch. Drag **Height falloff** to zero and the air is as thick up by the eye
as it is on the floor. Then switch **Clustered lights** off. The air can no longer see
the torches, so it only dims the floor, and thirty-two of the torches stop lighting
the floor for the reason the clustered lights page gives.

{{code fog}}

> **Note.** A light that casts a shadow into the cube atlas is shadowed in the air as
> well, so its glow stops at a wall beside it. A sun that casts shadows lights the air
> through its cascades, so the air in an object's shadow stays dark. Light shafts and
> volumetric fog both scatter the sun, so turn on one or the other, not both.
