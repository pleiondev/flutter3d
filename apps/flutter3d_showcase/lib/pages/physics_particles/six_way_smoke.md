# Smoke lit by the scene

A smoke sprite is a picture of smoke lit from wherever the artist's light was.
It stays lit from there whichever lamp it drifts past, so a puff between a red
light and a blue one is the same grey on both sides.

A six-way sheet is six pictures of the same puff, each lit from one side:
right, left, top, bottom, back and front. The particle stage mixes them by
where each of the scene's lights really is. Which lights those are is the
renderer's answer, through `ContributorLights`: the lights a mesh of the
particles' bounds would get.

## Step 1: A sheet with no asset

A real sheet comes from a fluid tool's six-way export, repacked by
`importSixWay`, or from the baker in `flutter3d_build`. This page writes a
small one itself so it needs no file: a plain soft ball of smoke, 24 pixels
square, one frame.

The light reaching a point from one side is the density summed along its row
to that side's face. Each pixel then marches once from the viewer through its
column and adds up what each of the six lights leaves there. The two images
are laid out the way `SixWayMaterial` reads them: `positive` holds right, top,
back and coverage, `negative` holds left, bottom, front and emission, and a
cell's rows run bottom to top.

{{code bake}}

## Step 2: Upload the two textures

The two images become two textures and one `SixWayMaterial`. Nothing here
emits, so the emission channel is zero and `emission` stays at its default.

{{code upload}}

## Step 3: Three puffs that stand still

Three particles with no speed and a long life, drawn by a `ParticleContributor`
given the sheet. A second contributor over the same particles has no sheet,
for comparing later.

{{code puffs}}

## Step 4: A red light and a blue one

Two point lights with no shadows, and a scene with no ambient light and no
default light, so everything on the smoke comes from these two.

{{code lights}}

> **Note.** A six-way contributor draws nothing outside a renderer's scene
> pass. That is where the lights are bound, and a stage that declares the
> light list and gets none would crash on Metal.

## Step 5: Move the lights

**Lights around the puffs** turns the pair around the puffs in a circle three
metres out. At zero the red light is on the left and the blue on the right,
and each side of each puff takes the colour of the light on that side. Turn it
to 90 degrees and one light is behind the puffs: their thin edges glow with
it, which is the "back" picture at work.

`SixWayMaterial.ambient` is light arriving evenly from every side, read
through the mean of the six pictures. It sits on the material rather than
coming from the scene, so the **Ambient** slider writes it directly.

{{code orbit}}

## Step 6: Compare with a plain sprite

Switch **Six-way sheet** off and the other contributor draws the same
particles as the plain procedural disc. That stage binds no lights, so the
puffs turn white and stay white however the lights move.

{{code swap}}

> **Warning.** The stage reads right and up as the camera's. A particle with
> a `rotation` turns its picture but not its light, so a puff spun a quarter
> turn is lit as though its right were its top.

## Step 7: What the page checks

The three puffs are alive, the six-way contributor has something to draw, and
the frame drew.

{{code check}}
