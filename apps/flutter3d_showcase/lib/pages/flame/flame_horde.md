# Ninety-six monsters in one draw, chasing two players

A horde whose every step is decided by `flutter3d_sim` does not need a scene
node per monster. `InstancedActorComponent` draws a simulated actor as a slot
of a shared `InstancedMeshNode`, and `ActorSystemComponent` steps the whole
system towards several players at once, so each monster goes for the one it
can reach first.

## Step 1: One batch for the horde

The mesh and the material are the batch's; the colour is each slot's own,
which is how a monster shows who it is after.

{{code batch}}

## Step 2: A brain that chases a focus

The system tells each monster which focus is its own on every step, and
`steerTowardsFocus` walks it there. The brain only remembers the answer so
the page can colour it.

{{code brain}}

## Step 3: Several foci

`foci` is read fresh on every step: here, where the two players are now. With
several, each actor attends to the one nearest by walking where the level has
a flow field, and by straight line where it has none, as in this empty yard.
The component is also what steps the actors, so it is the clock their slots
draw between.

{{code foci}}

## Step 4: An actor per monster, a slot per actor

Each monster is an actor in the system and a component in the game. The
component takes a slot when it is added, gives it back when it goes, and
goes itself when the simulation removes its actor.

{{code spawn}}

Drawn with `stepper`, a monster is placed between where it was before the
last step and where it is now, so the horde moves smoothly at any frame rate.
The slot's colour follows the player the brain last went for: orange for the
player on the left, blue for the one on the right, and a monster changes
colour as the two circle and the other one comes nearer.

{{code monster}}
