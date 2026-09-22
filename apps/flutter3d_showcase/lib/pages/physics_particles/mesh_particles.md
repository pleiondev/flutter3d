# Mesh particles

A billboard is a quad that always faces the camera, which is right for a
spark or a puff of smoke and wrong for a shard of debris that should tumble
and show its edges. `MeshParticleContributor` draws every live particle as a
copy of a real mesh instead, in one instanced call.

## Step 1: One mesh, uploaded once

The shape is ordinary geometry, built and uploaded exactly the way a wall or
a prop would be. Nothing about it knows it is about to become a particle.

{{code mesh}}

## Step 2: A second contributor, not a second mode

`ParticleContributor` and `MeshParticleContributor` share a pool and a pass
and almost nothing else: their vertex buffers, their layouts and their
shaders all differ, because a billboard is four vertices built on the CPU
and a mesh particle is eight floats of placement next to geometry that is
already on the device.

{{code contributor}}

## Step 3: What the frame should show

The claim is the ordinary one for a particle page: the contributor is
active, the system holds exactly as many particles as were burst, and the
frame actually drew something.

{{code check}}

> **Note.** One mesh per contributor. Two different shapes of debris in the
> same burst are two contributors, which is cheap to arrange and honest
> about the extra draw call it costs.
