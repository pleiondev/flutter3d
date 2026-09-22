# Identical-draw batching

A hundred identical crates drawn one at a time are a hundred pipeline binds,
hundreds of uniform writes and a hundred draw calls. `RenderSettings.batchIdenticalDraws`
finds the runs of nodes that share a mesh, a material, a mirroring and a
reflection probe, and draws each run through one instanced call instead.

## Step 1: A grid of identical crates

Twelve boxes, sharing one uploaded mesh and one material, arranged in a
grid. Nothing about any single crate is unique, which is exactly the case
this setting looks for.

{{code crates}}

## Step 2: The switch

One flag, and the renderer decides for itself which draws qualify.

{{code settings}}

## Step 3: What the frame says it did

`FrameResult.batchedDraws` counts how many individual draws the batcher
replaced. With the switch on, a dozen crates collapse into far fewer calls;
with it off, nothing is merged and the count is zero.

{{code check}}

> **Note.** A run has to be at least `RenderSettings.batchRunMinimum` draws
> long before merging it is worth the pipeline switch on either side. Two
> identical crates next to each other are drawn as two crates, not batched.
