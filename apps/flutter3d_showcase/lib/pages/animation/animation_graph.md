# An animation graph

Playing one clip at a time by hand works until a character has more than two
things to do. Then every game ends up writing the same code: which clip now,
how long to fade, what to do when an attack is pressed halfway through a
swing. An `AnimationGraph` holds those answers as data. It runs an
`AnimationStateMachine` over a model's own clips, one step at a time, into a
`Pose` that is then written onto the model.

This page drives the robot that ships with the samples. It stands, walks, runs
and slows again on its own, and the controls let you set the speed, lay a wave
over its right arm, let its head follow the camera and make it jump.

## Step 1: The machine

A machine is states, transitions between them, and the parameters the
transitions test. Parameters are typed: float, integer, boolean or trigger.
Writing a float to a trigger, or to a name the schema does not have, is
refused, and the refusal names the call that would have worked.

`idle` plays one clip. `move` is a blend space: `AnimationBlendSpace` puts the
walk at 1.5 m/s and the run at 4 m/s, and between the two the state plays some
of each, by `speed`. The two clips share one phase, so the feet come down
together however the mix is weighted. A second parameter, given as `across:`,
spreads the points over a plane instead of a line, which is how a walk forward,
back and to each side is blended by two speeds.

The transitions say when to leave. Each has its conditions, a crossfade in
seconds and a priority. The jump is a trigger, which stays set until a
transition uses it, so a jump asked for during a fade still happens once the
fade is over. The way out of the jump waits on an exit time of one: the clip
has to finish first.

{{code machine}}

## Step 2: The graph over the model's clips

The graph is made from the machine, the clips and a pose of the model's
skeleton, `Pose.fromNodes`. A machine that cannot run, say one naming a clip
the model does not have, is refused here with every problem listed. A tool
that wants to refuse politely calls `problems(clips)` first.

`rootNode` names the node whose travel along the floor is root motion. Step 6
comes back to it.

{{code graph}}

## Step 3: A layer over the right arm

A layer is a second graph laid on the first one's pose, only where its mask
covers. `AnimationMask.below` takes a node and everything under it, here the
right shoulder down to the fingertips. The layer plays the wave. Its weight
starts at nought, and `fadeTo` brings it in over a few steps, so the arm does
not snap. A layer can also be additive. Then it adds its distance from rest on
top of the base instead of replacing it.

{{code layer}}

## Step 4: A look goal on the head

Goals are inverse kinematics applied after the states and the layers have
posed the skeleton. `LookGoal` turns a joint so that what faced `forward` at
rest faces the target, by at most `limit` radians. Past the limit it turns as
far as it may and stops. `ReachGoal` bends a two-bone arm or leg to a point,
and `FootPlantGoal` puts feet on the floor under them. All three fade by
weight the way a layer does.

{{code look}}

## Step 5: Write the parameters, then step

Once a frame the page writes the speed, fades the layer and the look in or
out, moves the look's target to the camera in the pose's space, and steps the
graph. `evaluate` returns the pose, and `writeTo` puts it on the model's
nodes. Turn **Speed changes by itself** off and drag the slider past half a
metre a second to see the fade from idle into the walk.

{{code drive}}

## Step 6: Root motion

The robot's clips walk on the spot, so the page gives the walk and the run a
stride along the body before it builds the graph. With `rootNode` set, the
graph holds that node over its rest and hands its travel over as `rootDelta`.
The travel is unwound across the loop's turns and mixed by the same weights as
the pose. `rootDeltaIn` carries it into the world by the model's matrix. A
game passes that to `CharacterController.step(drivenBy:)`, which sweeps it, so
a walk stops at a wall. Here it just moves the robot round a circle.

{{code root}}

## Step 7: What has to hold

The check builds a second graph from the same machine and steps it by hand.
It has to start idle. When the speed goes past the threshold it has to take
the transition, and on the next step both states have to be playing with a
fade weight between nought and one. At 2 m/s, a fifth of the way from the
walk's point to the run's, the thigh has to be exactly the walk and the run
sampled at the shared phase and mixed four to one. The body has to travel
forwards. With the wave layer at full weight, the upper arm has to be the
layer's and the head has to stay outside the mask.

{{code check}}

> **Note.** A graph takes one transition a step, and none during a
> crossfade: a fade cannot be interrupted, so a trigger set during one waits
> for it to end. This page steps the graph on the frame, while a game steps
> it on its fixed step and draws the step's pose, so the pose moves at the
> step's rate and is not blended between steps. Root motion is taken from a
> node whose parents stand at rest; a rig whose clips move those parents does
> not get it. The dungeon's monsters run on this graph but get no root motion
> from it yet, since their clips walk on the spot as the robot's do.
