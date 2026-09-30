# Eighty sparks in one draw, fire and smoke in two

A Flame game with many small things of one shape does not need a scene node
for each. `InstancedObject3dComponent` is an ordinary Flame component that
takes a slot in a shared `InstancedMeshNode` while it is in the game, and
the batch is one draw however many are in it. Blasts come from
`Particles3dComponent`, a particle pool on Flame's clock.

## Step 1: One batch for every spark

The mesh and the material are the batch's. It grows if it has to.

{{code batch}}

## Step 2: Sparks as Flame components

Each spark sets its own position as any Flame component would, and writes it
into its slot only when it moved. Removing one gives its slot back at once,
and the last spark in the batch moves into the hole.

{{code sparks}}

## Step 3: Fire adds light, smoke takes it away

The fire pool draws additively. The smoke pool uses the darkening blend,
which multiplies what is behind a puff by one minus its colour, so smoke can
be dark without the particles being sorted.

{{code pools}}

Both are drawn once the game has the renderer, in `onRenderer3d`.

{{code draw}}
