# The ECS world

Every simulation in the engine keeps its state as entities and components in
one place: `EcsWorld`. An entity is nothing but a number; a component is
whatever data a game hangs off it. Keeping everything in one store is what
lets a save file, a network packet and a determinism check all write the whole
world down without a hand-written list of what to include.

## Step 1: Register a component and save two entities

A component type has to be registered with an encoder and a decoder before it
can be saved. `spawn` hands back a fresh entity, and `set` attaches a
component to it.

{{code world}}

`save()` writes every registered component of every living entity into one
document, keyed by the entity's own index.

## Step 2: Carry the save across an edited level

An entity's index is an allocation, not an identity: reload the level with a
monster inserted ahead of an old one, and the indices no longer point at the
same actors. `remapEntitySave` rewrites a save from the indices it was written
at to the indices a reloaded level hands out, matching by name instead.

{{code remap}}

The goblin and the troll both keep their own position, even though the troll's
index moved from 1 to 2 to make room for the ogre. `remap.dropped` lists any
name the new level does not have.

## Step 3: Read the result

The page prints which position ended up on which name, reading each entity by
its new index in the reloaded world.

{{code read}}

Nothing here compares old and new indices directly, because that comparison
is exactly what a level edit breaks. It only asks each name for its own
value.
