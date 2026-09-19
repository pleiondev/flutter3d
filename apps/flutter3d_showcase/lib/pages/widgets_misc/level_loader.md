# Loading a level

`LevelLoader` is the bridge between a level document and something drawable:
brushes become mesh nodes, lights become light nodes, and the result is a
`LoadedLevel` with its own scene, collision world and a list of anything
that went wrong along the way.

## Step 1: A document

A floor and a light, built in code rather than read from a file.

{{code document}}

## Step 2: Build it

`LevelLoader.build` does everything `load` does except finding the
document, which is what lets a level built in memory — an editor's unsaved
document, a page like this one — go through the same path a bundled level
does.

{{code build}}

## Step 3: Share repeated meshes

`SharedMeshes` uploads a shape once and hands the same `DeviceMesh` back to
anything that asks for it again, so three torch posts of the same size cost
one upload.

{{code shared}}

A clean document loads with an empty `issues` list; a level with a missing
texture or an unknown entity type would still load, with the problem named
there instead of stopping the level from playing.
