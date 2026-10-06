# Physical sky

The procedural sky draws a gradient from colours somebody picked. That works
for a level with a fixed look, and it goes wrong as soon as the sun moves:
dusk needs a different set of colours, and the sun's light stays the colour it
was given while the sky around it turns orange.

A physical sky starts from the air instead. Sunlight is scattered once on its
way to the eye, by molecules, which scatter blue far more than red, and by
haze, which scatters all colours and mostly forwards. The colours come out of
where the sun is: blue overhead at noon, a pale band at the horizon, red
towards a low sun and dark away from it. Stars come out once the sun is far
enough down.

## Step 1: The air

`PhysicalSky` describes the air of a planet. The defaults are the Earth's:
how strongly the molecules and the haze scatter, how fast each thins with
height, the planet's radius and the sunlight entering the air. Change them
for a hazier day or a different planet. Every colour on this page is read off
this one value.

{{code air}}

## Step 2: Put it in the sky

`SkySettings.physical` takes the air, and `directionToSun` says where the sun
is. A cube map on the same settings would still win. Since 0.9.0 a sky that
is switched on with none of the gradient's colours given draws
`const PhysicalSky()` without being asked, so a level that never chose a
gradient gets this sky.

{{code sky}}

## Step 3: A sun that takes the air's colour

A directional light standing for the sun should have the colour that is left
after its light has come through the air. `PhysicalSky.sunlight` answers that
for a direction: close to white at noon, orange low down, and black once the
sun is below the horizon. The page sets the light's colour from it every
frame, so the ground, the houses and the tower are lit by the same sun the sky
shows.

{{code sun}}

{{code sunlight}}

## Step 4: Fog that lies on the ground

`FogSettings.heightFalloff` thins the fog as it rises: at a height `y` the fog
is `density * e^(-heightFalloff * (y - baseHeight))` thick, worked out along
each ray in closed form. The default is 0.05 per metre, which halves the fog
every fourteen metres. Nought is the old flat fog. The fog's colour is the
sky's own along the horizon ahead, from `SkySettings.sample`, so the far end
of the street melts into the sky at any hour.

Drag **Sun height** from noon down to the horizon and below it. The sky
reddens towards the sun, the light on the houses goes orange, and past the
horizon the stars come out. Raise **Height falloff** and the fog sinks into
the street while the top of the tower stands clear of it. Drag it to nought
and the tower is as foggy at the top as at the foot.

{{code fog}}

## Step 5: What the frame should show

The sky is one full-screen draw inside the scene pass, after the meshes, so
the pass draws one more than there are meshes. The light standing for the sun
at twenty degrees has come through enough air to lose more blue than red.

{{code check}}

> **Note.** The physical sky is marched per pixel of sky: sixteen samples
> along each view ray and eight towards the sun from each. On a desktop GPU
> that costs little. On a phone, a frame that is mostly sky pays for it, and
> the gradient is three mixes.
