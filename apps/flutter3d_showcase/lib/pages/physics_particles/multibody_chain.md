# A chain that does not stretch

An ordinary joint is a constraint between two free bodies. Each step the
solver pulls the two sides back together, but only so far, and a light link
between a heavy weight and the rest of the chain cannot pull hard enough. The
chain stretches. A multibody on the physics core holds the same joints in
reduced coordinates. Each link is placed from its parent by its joint's angle
or travel and nothing else, so there is no gap for a joint to open.

This page lays the same chain out twice and lets it go. Twelve links of
0.1 kg each, 0.3 m long, with a weight of 10 kg on the end. The left chain is
held by ordinary hinge joints and the right one is a multibody. Each link
turns red as the joint above it opens.

## Step 1: One chain, laid out level

Both chains are made by one function: a fixed post, then the links in a
level row from it, then a ball for the weight. How each body is held to the
one before it is the only argument, so that is all that differs between
the two.

{{code lay}}

## Step 2: Joints on the left, a multibody on the right

On the left, `createJoint` puts a revolute joint about z between each body
and the one before it, at the point they share. On the right,
`createMultibody` roots a tree at the post, and `addLink` hangs each body
under its parent on a revolute joint at the same point, about the same axis.
A fixed root is a fixed base; a dynamic one would float. The link indices
count from the root at nought, so link k's parent is k − 1. The angle where
a link is added is its joint's nought.

A link also takes limits (`setLinkLimits`) and a motor (`setLinkMotor`),
and `linkJoint` reads its angle or travel and speed back. This page uses
none of them.

{{code both}}

## Step 3: How far a joint is open

Two ends that should meet: the parent's far end and the link's near end,
each where its own body is now. On the post the anchor is its centre, and on
the weight it is the edge of the ball.

{{code gap}}

## Step 4: Drawing it

Every link is drawn where the core has it, reddening as the joint above it
opens, fully red at three centimetres. The world steps once a frame and lets
go of both chains again every ten seconds. Move **Weight on the end** to
change the weight: at a kilogram the ordinary chain opens by about a
centimetre at its worst joint, and at twenty by more than twenty. The multibody stays white throughout.

{{code draw}}

## Step 5: What the two should show

Two seconds from level, with ten kilograms on the end. Every joint of the
multibody stays shut to within a millimetre (the core keeps them within a
thousandth of one). Some joint of the ordinary chain opens by more than a
centimetre, four on macOS. The multibody's weight has swung well below its
post.

{{code check}}

> **Note.** The links of a multibody still move freely within a step, with
> their contacts, and are put back where their joints say after it. A
> contact the step resolved can be partly undone by that. A spherical link
> turns freely: there is no cone limit on it yet. A multibody has at most 32
> links and 64 degrees of freedom.
