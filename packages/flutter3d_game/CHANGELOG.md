## 0.3.0

* `InputTape` records a run as transitions plus axes, one entry per fixed step,
  and replays it exactly. A tape of intents, not of poses.
* `StepSystems`: a game adds a rule to a genre's step without forking it.
  Phases are named by the genre, announced unconditionally, and run in a
  defined order — never in whatever order a hash map returns.
* `InputState` exposes this step's presses, releases and analogue readings,
  which is what a recorder needs and cannot ask for by name.

## 0.2.0

* An ECS whose every component serialises, and one snapshot mechanism serving
  the save, the network packet and the determinism test.
* Actors with a flow field to walk it, mechanisms composed through signals, and
  movers that carry what stands on them.
* A pad and a touch layer that arrive as the same actions a key does, and
  `GameAction` opened from an enum to a value class so a genre can invent its
  own.
* `WorldStep`: the order the world is stepped in, as named phases the game
  calls, because two genres want their actors on different sides of the index.

## 0.1.0

* A fixed timestep with an accumulator that reports the steps it had to drop,
  and interpolation at draw time.
* Device-independent input: actions, bindings, and a keyboard — all arriving as
  the same thing.
* Levels as documents — brushes, entities, lights, materials — with a validator
  that reports a coordinate rather than "the file is broken".
