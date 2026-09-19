# Raycast, sweep and overlap

A `CollisionWorld` answers three different questions about the same level:
what does a ray meet, how far can a moving shape travel before something
stops it, and what does a shape already overlap. This page asks all three
against one small scene and prints the answers as text, because a raycast is
a number and a picture cannot show you whether it is the right one.

## Step 1: A wall and a pickup

The wall is solid; the pickup is a trigger, which means it reports overlap
but blocks nothing.

{{code world}}

## Step 2: What a ray meets

`raycast` walks the broadphase cell by cell along the ray rather than over
its bounding box, which matters on a long, mostly empty shot down a
corridor.

{{code raycast}}

## Step 3: How far a move gets

`sweep` answers the question a raycast cannot: not just whether something is
in the way, but how far a shape of a given size can travel before it
touches it. `ContactFilter` is `bool Function(SweptContact)`, one object
rather than two parameters, so a filter can grow without breaking every
filter anybody has written against it.

{{code sweep}}

## Step 4: What is already touching

`overlap` is the exact question, with no motion involved: everything a shape
at a position currently intersects, triggers included by default.

{{code overlap}}

> **Note.** All three read the answer back through a reusable object rather
> than a fresh one. A sweep runs several times a step for a character
> controller, sixty times a second, and an allocation there is an allocation
> on the hottest path a game has.

## Step 5: What the page checks

{{code check}}
