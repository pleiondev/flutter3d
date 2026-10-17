# Joints that break

A joint in the physics core holds whatever it is asked to. A shelf on two
brackets would carry a piano. `setJointBreak` gives a joint a force, and if
it likes a torque, that it lets go past. At the end of a step in which the
joint held its second body harder than that, the core takes the joint out,
wakes both bodies, and raises a `jointBroken` event naming them.

On this page a shelf hangs on a wall from two brackets, and a crate is set on
it every fifty steps until the brackets give way. The slider sets the force
they break past. Breaking joints are the core's alone, so in the browser the
page waits for the core to load and says so beside the viewport until it has.

## Step 1: Hang the shelf

The wall is a fixed body and the shelf a dynamic one of four kilograms. Each
bracket is a fixed joint between them, which holds the shelf where it was
against the wall, both place and turn. Joined bodies do not collide, so the
shelf can sit against the wall without the two pushing apart. Each bracket
then gets its limit. A limit of nought means never, and it is what a joint
starts with.

{{code hang}}

## Step 2: Load it, step it, and listen

Every fifty steps a three-kilogram crate is set down five centimetres above
the shelf, each in its own place along it. The world steps, and the page
keeps the `jointBroken` events. The other events the step raised, bodies
falling asleep and contacts beginning, are read and dropped, so the world's
queue never fills.

The two brackets share the load evenly. Each holds 19.6 N of empty shelf and
14.7 N more for every crate at rest. A crate landing, even from five
centimetres, pulls far harder than that for a step. With the limit at 150 N
the shelf carries four crates and goes when the fifth lands. At 80 N the
first landing is enough.

{{code tick}}

## Step 3: Show what is left

The shelf and the crates are drawn where the core has them. A bracket is
drawn only while `containsJoint` still finds its joint, so it disappears in
the step it breaks.

{{code show}}

## Step 4: What has to happen

Before the fifth crate, with four crates on the shelf, both brackets are still
there and each holds 78.5 N, half of sixteen kilograms. By step three hundred
both are gone, there were exactly two breaks, each naming the wall and the
shelf, and the shelf is on the floor. If the limit were never read, the
brackets would still be there. If the event lost a body, the names would not
match.

{{code check}}

> **Note.** A joint breaks on what it held over the last substep, so a short
> hard knock breaks it as surely as a steady load. That is how a real bracket
> behaves under an impact, but it also means the limit to set is higher than
> the weight the joint should carry at rest. How high depends on how things
> arrive, so it is worth trying with the drops a game actually has. When two
> joints share a load, as these brackets do, they often break within a few
> steps of each other.
