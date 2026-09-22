# The view model pass

A weapon or a tool held close to the eye cannot share the world's depth
buffer. A wall a few metres away would slice through it the moment the
camera got close. `ViewModelNode` draws the held item in its own pass, with
its own depth, straight on top of the finished world.

## Step 1: Build the world

An ordinary scene: a floor, a pillar, and a sun. Nothing here is aware that
anything else will be drawn afterwards.

{{code world}}

## Step 2: Build a small scene for the hands

The held tool lives in a scene of its own, lit by its own light rather than
the world's. It has a narrow camera, because a wide lens a few centimetres
from a small object stretches its edges into something that reads as broken.

{{code hands}}

## Step 3: Register the pass

`ViewModelNode` takes the hands scene and its camera. Adding it to the
renderer with `addNode` gives it a pass of its own, run after the world and
before the frame is tone mapped. Nothing about the world scene changes.

{{code pass}}

## Step 4: Move the tool and adjust the lens

The tool bobs a little every frame, the way a held object would as someone
walks. The field of view slider changes the hand camera's projection, and the
tool's edges stretch or relax as it moves, independently of the world camera
you orbit with the pointer.

{{code motion}}

## Step 5: Check the pass ran

The page looks for a pass named `view model` in the frame's own list, and
checks that more than the world's single draw reached the screen.

{{code check}}
