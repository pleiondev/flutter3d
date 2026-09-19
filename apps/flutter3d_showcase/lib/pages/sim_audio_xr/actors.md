# Actors, brains and health

An `Actor` is a thin handle onto an entity: everything it answers, `health`,
`brain`, `body`, `facing`, is read off a component that may or may not be
there. A turret has no body; a barrel has no brain. Nothing forces an actor
to carry parts it never uses.

## Step 1: A brain with its own memory

A game's own brain extends `Brain` and overrides only the hooks it cares
about. This one remembers whether it has ever been hurt.

{{code brain}}

## Step 2: Build an actor from components

`Vitality` wraps a `Health`; `Thinking` wraps a `Brain`. Setting both on an
entity and wrapping it in an `Actor` gives a single handle onto them.

{{code actor}}

## Step 3: Hurt it and read the result

`applyDamage` goes through `Health.damage`, which returns true only on the
hit that kills. The brain hears about it separately, through `onHurt`.

{{code hurt}}

Twelve damage against thirty health leaves the goblin at eighteen, still
alive, and its brain now remembers being hurt.
