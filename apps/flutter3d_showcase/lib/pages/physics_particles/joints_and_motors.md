# Joints and motors

A joint holds two bodies to each other, so that they can still move in some
ways and not in others. The physics core has five kinds: fixed, spherical (a
ball joint), revolute (a hinge), prismatic (a slider) and distance. This page
puts four of them in a row. From the left: a hinge that swings into its
limits, a slider driven by a motor, a ball joint held in a cone, and one
distance joint made three ways, as a rod, as a spring and as a rope.

Joints belong to the core's `NativeWorld`. The Dart reference has none, so
when the core will not start this page shows the row standing still and says
why beside the viewport.

Every joint here joins a moving body to a fixed one. A fixed body is made
with `NativeBodyType.fixed` and a mass of nought. It does not need a shape,
because nothing has to touch it.

## Step 1: A hinge with limits

`createJoint(NativeJointType.revolute, a, b, anchor:, axis:)` pins the two
bodies together at the anchor and lets them turn about the axis only. Both
are given in world space, and the joint is taken from where the bodies stand
when it is made: that pose is angle nought. `setJointLimits` then keeps the
angle between a lower and an upper bound, in radians. The bar starts hanging
straight down and spinning fast enough to reach half a radian, so it keeps
running into both stops.

{{code hinge}}

## Step 2: A slider and its motor

A prismatic joint is the same call with `NativeJointType.prismatic`. The
carriage can only slide along the axis, and it cannot turn at all. Its
limits are now a travel in metres. `setJointMotor` drives the joint at a
speed, here 0.6 m/s, pushing with no more than the force it is given. A
motor of speed nought with a small force works as friction in the joint.

The motor does not turn round by itself at the end of the rail. The page
watches `jointValue`, which reads a slider's travel, and turns the motor
round near each end.

{{code slider}}

## Step 3: A ball joint in a cone

A spherical joint holds one point of each body together and lets them turn
any way about it. Its axis, here straight down along the limb, is what two
limits are measured from. `setJointCone` keeps the limb's swing within an
angle of that axis, like a shoulder. `setJointLimits` on a ball joint limits
its twist about the axis. `setJointFriction` resists turning with a set
torque, so the limb settles instead of swinging forever. A ragdoll's joints
are built from this.

{{code ball}}

## Step 4: One distance joint, three ways

`createDistanceJoint` holds a point on one body at a distance from a point on
another. The distance is the one between the two points when the joint is
made. As it comes, the joint is a rod. `setJointLength` gives it a rest
length and a least and a most it may be stretched to. `setJointSpring` gives
it a frequency and damping, and with those it pulls back towards the rest
length like a spring. With a spring of nought hertz and a least of nought,
nothing pulls at all until the joint reaches its most, so it is a rope:
slack until it is taut. The rope's weight starts beside its hook, falls
freely and is caught.

{{code distance}}

## Step 5: Step it

Each frame turns the motor round if the carriage is at an end, then steps
the world by a sixtieth of a second. The cords are drawn from each hook to
its weight. After twelve seconds the row starts again.

{{code step}}

## Step 6: What each joint has to do

The page's check starts the row again and steps it for six seconds, reading
every joint after every step. The hinge has to reach its stops and go no
more than two degrees past them. The carriage has to run at the motor's 0.6
m/s. The limb has to swing out to its cone and twist to its limit without
going past either. The rod has to keep its length to within five
millimetres. The rope has to start slack, go taut and never get longer than
itself. The spring has to stay between its least and its most.

{{code check}}

> **Note.** A limit is solved softly, in the same substeps as the contacts,
> so a fast body can pass it a little for a step before it is pushed back.
> On this page the hinge stays just inside its limits and the limb never
> passes its cone, but a heavier bar or a longer
> step would go further. The cords are drawn
> straight even when the rope is slack, because the joint has no shape of
> its own to draw. A chain of many light bodies with a heavy one at the end
> is where these joints stretch most; the core's multibodies are made for
> that case.
