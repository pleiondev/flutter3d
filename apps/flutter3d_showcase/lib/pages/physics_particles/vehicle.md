# A car on four springs

A vehicle on the physics core is an ordinary dynamic body, the chassis, with
up to eight wheels under it. The wheels are not bodies. Each step, every
wheel casts a ray straight down from where its suspension is fixed. Where the
ray lands, a spring and a damper hold the chassis up, the drive and the brake
push it along the road, and the tyre holds it from sliding sideways. The
chassis still collides, rolls over and sleeps like anything else.

This page drives a car round a loop on a flat road with a plank across it.
Steer it, change its speed, brake, or put it on ice.

## Step 1: A road and a chassis

The road is a fixed box, and so is the plank. The chassis is a box of
1200 kg, 1.8 m wide, 0.6 m tall and 4 m long, a metre above the road at the
start. Nothing about it says yet that it is a car.

{{code road}}

## Step 2: Four wheels under it

`createVehicle` makes the chassis a car and says which of its own axes are
up and forward. Up is where the springs push and the axis a wheel steers
about; forward is the way a wheel rolls. Each wheel is fixed to the chassis
at a point in the chassis's own frame. It has a suspension 0.4 m long at
rest, a radius of 0.35 m, a spring of 30 000 N/m, a damper of 3000 N s/m and
a grip, the friction coefficient between tyre and road.

The grip is set when a wheel is made. Picking **Ice** takes the car's
vehicle out and fits it again with a grip of 0.1 instead of 1, on the same
chassis, moving as it was.

{{code wheels}}

## Step 3: A driver

`setWheel` is what a driver asks of one wheel: a steering angle in radians,
positive to the left, a drive force in newtons and a brake force. It holds
until it is set again. This driver sets all four every step. The front
wheels steer about one point on the line of the rear axle, so the inner
wheel turns more than the outer one. With both at the same angle they would
scrub against each other through every turn. The rear wheels push in
proportion to how far the car is under the speed it was asked for, up to
2400 N each.

{{code drive}}

## Step 4: Drawing the wheels

`wheelsOf` answers each wheel as the last step left it: whether it touches
the road, its suspension's length, its centre, how far it has turned about
its axle, its spring's force, how fast it is sliding sideways, and its skid,
which is how far past its grip the tyre was asked to go. The car is drawn
from that. Each wheel sits at its centre, turned by its steering and its
rotation, and its tyre goes red as it skids. On tarmac the tyres stay black
except for a moment over the plank. On ice the rear wheels spin under the
drive and the car slides wide of the turn it is steered into.

{{code draw}}

## Step 5: What the car should do

On tarmac with nothing asked of it, the car settles in three seconds with
all four wheels down, at the height the springs put it. Each spring holds a
quarter of the weight, so it is squeezed by m g / 4k, about 0.1 m. Driven
straight for two seconds it goes forward and not sideways. Steered left for
a second and a half it ends to the left, facing left, still turning that
way.

{{code check}}

> **Note.** The tyres are a friction circle solved once per step: eight
> passes over the wheels, through the chassis's mass and inertia, and the
> forces they settle on are held for the whole step. There is no tyre model
> beyond that, so no slip angle curve or load sensitivity. The wheels are
> rays, one down the middle of each wheel. A kerb narrower than the wheel
> but beside that ray is never seen, and an edge the ray crosses lifts the
> wheel at once, with no rounding over it.
