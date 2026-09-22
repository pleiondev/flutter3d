# The level format

A level is a document: brushes for the architecture, entities for what
spawns, and a validator that reads the whole thing and says what is wrong
with it before anybody plays it.

## Step 1: Build a small level

Two brushes that happen to overlap by a metre, and one entity.

{{code level}}

## Step 2: Write it down and read it back

`toJson` and `fromJson` round-trip the whole document. Every brush that went
in comes back out.

{{code write}}

## Step 3: Validate it

`LevelValidator` needs an `EntityRegistry` so it knows which entity types this
game actually has; an empty one is enough to check the geometry alone.
`validate` returns every issue it finds rather than stopping at the first.

{{code validate}}

The overlap between the two brushes shows up as one of the issues, alongside
anything the validator has to say about an entity type it does not
recognise.

## Step 4: Edit the level, ask the validator

The two brushes are on the floor, the green ball is the spawn, and the red
lamps below are the validator's issues, one lamp to an issue. Slide the second
brush apart and back until it overlaps the first, drop the spawn point, and
each change goes through the same round trip: written to JSON, read back,
validated. The lamps are whatever the validator says about the document it
reads, not about the picture.

{{code live}}
