# CPU raycasting

Picking by pixel asks the renderer to draw a whole extra frame. Sometimes
that is too slow, or there is no renderer at all: an editor tool measuring a
model, or a game asking "is anything between me and that wall" many times a
step. `Raycaster` answers that on the CPU, against the geometry directly,
with no frame involved.

## Step 1: One raycaster, reused

A `Raycaster` holds its own ray and its own scratch state, and is meant to be
kept around and reused rather than built fresh for every question.

{{code raycaster}}

## Step 2: Aim it and ask

`setFromNdc` points the ray through a spot in normalized device coordinates,
`-1` to `1` on each axis with the camera at the centre. `intersectScene`
walks the scene's meshes and returns the nearest one the ray meets, or null.

{{code cast}}

> **Note.** A skinned mesh is tested where its skeleton actually puts it, not
> in its rest pose, because `Raycaster.posed` defaults to true. A shot at a
> running figure hits the raised arm where the arm now is.

## Step 3: Read the answer

The ray in this page always points at the middle of the screen, where the
ball sits, so `intersectScene` finds it every frame. Move the ball off the
camera's axis and the same ray would return null instead.

{{code cast}}
