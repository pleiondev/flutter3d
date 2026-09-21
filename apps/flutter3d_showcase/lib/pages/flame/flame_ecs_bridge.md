# Bridging a flutter3d_sim actor

`ActorComponent` wraps one `flutter3d_sim` `Actor` the same way
`Object3dComponent` wraps any other bridged transform, plus the one extra hop
an actor needs: its body's simulated position lives on a
`CharacterController`, stepped by `ActorSystem`, not on the `SceneNode`
itself. `ActorSystemComponent` is the one place a bridged game steps that
shared system, once a frame.

## Step 1: A brain that decides

A game's own brain extends `Brain` and overrides only the hooks it cares
about. This one always walks towards +x.

{{code brain}}

## Step 2: An actor with a body

`ActorSystem.spawn` gives an entity a `CharacterController` body and a brain,
and hands back a thin `Actor` handle onto both.

{{code system}}

{{code actor}}

## Step 3: Bridge it, then step it

`ActorComponent` bridges the actor's body to a `SceneNode`; `ActorSystemComponent`
is the only thing that calls `ActorSystem.beginStep`/`step`, once a frame —
never the actor component itself, which would double-step a shared system.

{{code bridge}}

{{code step}}

Ninety steps of the shared system moved the goblin's real physics body
forward, and the bridged Flame position read back exactly the body's own `x`
— the mesh followed the actor, through the bridge, with nothing hand-copied
in between.

## Step 4: Three goblins on the map

The same pieces, three times over. Every goblin is an actor of one shared
system; each has a bridge component that copies its body onto its mesh and,
through the plane, onto a Flame position, and the dots on the map are those
Flame positions. One `ActorSystemComponent` steps the whole system once a
frame. A goblin that walks off the far edge is put back on the near one, so
the walk goes on.

{{code live}}
