# Several shapes on one body

A table is not a box. Shaped as one, it stands on a slab where its legs should
be, and a ball rolled under it hits nothing that is drawn. The physics core can
build one body out of several shapes instead: a compound of up to sixty-four
parts, each a sphere, box, capsule, cylinder, cone or hull, placed and turned
in the compound's own frame. The body moves as one piece and touches the world
with every part.

This page drops three of them onto a floor: a table of five boxes, a dumbbell
of two balls and a capsule, and a hammer whose head is a hull. Each is dropped
a little tilted, lands on one part first, and settles onto the rest. Compounds
are the core's alone, so in the browser the page waits for the core to load
and says so beside the viewport until it has.

## Step 1: Describe the parts

A `NativeCompoundPart` is a shape and where it goes: `at` for its centre and
`turn` for how it is turned. A capsule and a cylinder stand along y, so the
dumbbell's bar and the hammer's handle are given a quarter turn about z to lie
along x. Each part here comes with the mesh that draws it, made to the same
sizes.

A hull is different, because the world keeps it. `createHull` takes the head's
eight corners and moves them so that the hull's centre of mass is at its
origin. `hullOffset` says by how much, and the part is placed with that
offset added, so the head ends up where its corners say. The head is
narrower at its face than at its back, which makes its centre sit off the
middle and shows why the offset is there.

{{code parts}}

## Step 2: One body, shaped as all of them

`createCompound` makes the compound from the parts and `setCompound` shapes a
body as it. The parts are treated as one solid of even density. The core
moves all of them together so that their centre of mass is at the body's
origin, the point the body turns about and the one `positionOf` reports.
`compoundOffset` is that move. To put the compound's own origin somewhere,
the table's under the middle of its legs for instance, the body goes that much
further along, turned with the body.

{{code body}}

## Step 3: Draw each part

Every body gets a scene node, and every part a mesh under that node. A part's
mesh sits where the core put the part: its place in the compound less the
offset, with its own turn.

{{code draw}}

## Step 4: Follow the bodies

Each frame the world steps a sixtieth of a second and every node takes its
body's position and orientation. The parts come along as children. Every six
seconds the three are dropped again.

{{code follow}}

## Step 5: What has to be true once they settle

After four seconds all three are asleep. The table stands on its legs: the
compound's origin, where the legs end, is on the floor to within a
centimetre, and the top is level at 75 cm. Both of the dumbbell's balls touch
the floor, so the bar lies level at their radius. The hammer lies on its head
and on the far end of its handle, which is on the floor at the handle's
radius. If the parts were not moved by the offset, or a part were missing from
the contacts, one of these would be off by several centimetres.

{{code check}}

> **Note.** A body touching something has one contact manifold with it, and a
> compound's parts all feed that one. Their contacts are joined along the
> normal of whichever part goes deepest, and a part whose own normal turns
> more than about eighteen degrees away from it is left out for that step.
> Against a flat floor every part pushes the same way and nothing is lost,
> but a compound wedged into a corner can be held by one side of it at a
> time. The mass is spread as if the parts were one
> solid, and where two parts overlap, as the dumbbell's bar does inside its
> balls, the overlap is counted twice.
