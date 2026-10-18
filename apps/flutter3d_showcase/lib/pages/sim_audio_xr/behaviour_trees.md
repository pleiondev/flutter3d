# Behaviour trees

A brain written in Dart is quick to start with and hard to change later: every
new idea means another branch in code that only a programmer can edit. A
behaviour tree puts the decisions in a document. `BehaviorTree.read` turns
JSON into a tree, `BehaviorBrain` runs it for an actor, and everything the
tree remembers lives on the actor's entity, where a save or a rewind finds it.

On this page a red guard walks between two posts on the far side of a wall.
The blue target drifts along the near side. While the wall hides it, the guard
patrols. When the target comes out past the wall's end, the guard sees it and
gives chase. The coloured strokes over the guard are the path the tree took,
one per node, and the line runs to where its leaf is heading.

## Step 1: The tree as a document

Composites are the tree's own: `sequence`, `selector`, `utility`, `invert`,
`alwaysSucceed` and `cooldown`. A `selector` asks its children in order, from
the top, every time it is ticked, so the chase is asked about first on every
step. A `sequence` resumes where it was, so the patrol keeps its place: after
waiting at post `a`, it walks to `b` rather than starting over. A `utility`
node scores its options instead of taking them in order, each score being a
weight times its considerations, and gives the running option a little
inertia so it does not flicker between two near ties.

{{code tree}}

## Step 2: Read it

Leaves and considerations are looked up by kind in `BehaviorKinds`. The
standard ones are what an actor's `Mind` can already do: `goTo` a point on the
board, `goToFocus`, `wait`, `seesFocus`, `check` and `set` a board value, and
a few more. A game registers its own kinds next to them. A document that does
not read gives no tree. It gives every problem instead, each with where it is,
such as `root.children[2]: no leaf kind "fly"`, so it can be fixed in one pass.

{{code read}}

## Step 3: An actor that runs it

`BehaviorBrain` is the brain, and it keeps nothing. The running path, each
node's memory, cooldowns, the tree's clock and what the actor last heard or
felt are on a `Blackboard` component of its entity. Here the board is given
the two posts before the first step. Because the board is a component, a
snapshot taken halfway through a wait brings back the same wait, half done. A
board left by a different tree, told apart by the tree's digest, starts again
instead of resuming at node numbers that now mean something else.

{{code spawn}}

## Step 4: Step

The tree is ticked in the fixed step, through `ActorSystem.step`. The focus is
the point the actors pay attention to, here the target. `seesFocus` asks for a
clear line from the guard's eyes to it, against the level only.

{{code step}}

## Step 5: The overlay

`BehaviorOverlay` reads every actor's board and hands lines to the renderer's
`debugLines`. Amber is a node still running, green one that succeeded, red one
that failed. `describe()` gives the same path by name, as in
`guard: guard › chase › goToFocus (running)`. The overlay never makes a board,
so turning it on cannot change what the next snapshot holds. The dungeon draws
it, names and all, on the B key.

{{code overlay}}

## Step 6: What has to hold

A fresh guard, with the target hidden behind the wall for a second, has to be
on the patrol branch, at a `goTo` or a `wait`. Five steps after the target
appears past the wall's end, the selector has to have picked the chase, with
`goToFocus` as the leaf. The overlay has to draw one stroke for each node on
that path and one line to the goal.

{{code check}}

> **Note.** There is no `parallel` node: one body steers one way, so two
> leaves that both move it would fight. The names are not printed in this
> page's viewport, only drawn as strokes; `describe()` is the way to read
> them, and the check uses it in its messages. A 600-step trace of a tree's
> digests agrees across a restore in the tests, but it has been measured on
> one operating system so far.
