# Layers and contact callbacks

Two colliders are tested against each other only when each is in the
other's mask. Which bit means what is not this package's business: it ships
one constant, `Layers.all`, and a game names the rest itself.

## Step 1: A zone that only wants one layer

A trigger blocks nothing and only reports. Its mask names the one layer it
cares about, so a collider outside that layer is never even tested against
it, whatever mask that other collider carries.

{{code zone}}

## Step 2: Two movers, two layers

The player carries the layer the zone's mask names. The enemy does not.
Both start well away from the zone.

{{code movers}}

## Step 3: Walk both of them in

Moving a collider is only ever `moveTo`; the world does the rest the next
time it is asked to update.

{{code enter}}

## Step 4: Who gets heard

Only the player's arrival should reach the listener. The enemy touches
exactly the same point in space and is never even considered, because the
zone's mask never named its layer.

{{code check}}

> **Note.** `CollisionListener` is a mixin with three defaults, all empty.
> Almost everything overrides only `onCollisionStart`; `onCollision` fires on
> every step two colliders keep overlapping, and `onCollisionEnd` once they
> stop.
