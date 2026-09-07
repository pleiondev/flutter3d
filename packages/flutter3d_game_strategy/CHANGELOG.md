## 0.5.1

* **A fourth genre, and the first one that is not about a protagonist.** Units,
  orders and a step that walks them over a `Heightfield` by descending shared
  flow fields, shoving overlapping neighbours apart and sitting everybody back
  on the ground. The shape came out of a measurement rather than a preference:
  ten thousand agents cost 256 microseconds to descend, 717 to shove everybody
  against everybody and 19 to write their transforms, so separation is applied
  to the whole crowd rather than to what a camera can see — the saving is 717
  microseconds and the price is a run that stops replaying the same way twice.
* **An order costs half a millisecond, because the grid it walks is coarse.**
  `NavGrid` is baked at two metres instead of the half-metre a shooter bakes for
  its corridors: the same field costs 8.4 milliseconds on the fine lattice and
  0.52 on this one, while descending it barely changes (375 microseconds against
  307 for ten thousand agents). `Formation` follows from the same arithmetic —
  a squad walks to one place and takes its slots on arrival, because twenty
  separate points would be twenty cells, so twenty fields.
* **The map stops being only ground.** A `Building` is a footprint and a height
  rather than a collider, so what it is to the simulation is a patch that stops
  being walkable; placing one re-bakes the grid, which costs about a millisecond
  over an eighty-metre map and happens when a player builds rather than sixty
  times a second. It also moves whoever was standing under it: a unit in a cell
  the fields can no longer reach used to hold its orders and never walk again,
  silently, for the rest of the match.
* **A side digs, spends and grows.** `ResourceNode` is what the ground holds,
  `HarvestJob` is the loop a worker runs when nobody is pointing — ten carried,
  filled at eight a second, out and home again — `Stockpile` is a side's rather
  than the map's, and `Producer` turns 25 of a pile into a unit every four
  seconds. What a side has left and what a side has ever brought home are two
  numbers, not one, because a side that spends everything it digs would show
  nought while out-earning an opponent sitting on a pile.
* **Each side has its own map, and the rules read it too.** `FogOfWar` keeps
  explored and visible apart on a lattice of its own — four metres against the
  navigation grid's two, because a twenty-metre reveal touches about eighty
  cells at four and three hundred at two — refreshed every sixth step, a tenth
  of a second at sixty. The policy that sends workers asks it, so a seam nobody
  has walked past cannot be dug and somebody has to go and look; the drawing
  half asks the same lattice, so a view shows a side's knowledge rather than the
  simulation's.
* **A side plays itself, and the match it plays is the load test.** `Bot` drives
  a side through the handles a player has, on a cadence of thirty steps rather
  than every one, and reads no clock and rolls no die. `Match` steps the
  policies before the world, ends at 400 delivered or when the ground and
  everybody's hands are empty, and answers *drawn* when neither side got
  further — two mirrored sides running one policy should finish level, and a
  match that invented a winner there would hide the bias the mirror exists to
  find. Above all of it, `MapCamera` watches a place over `CameraRig`,
  `Selection` picks units out of a ray the application unprojects, and
  `StrategyVisuals` is the only file that draws.
* **What none of this does is fight.** No combat, no unit types, no line of
  sight through a ridge, and no snapshot, tape or seeded random — so a match can
  be watched but not yet replayed or rewound, and the two sides here are two
  rather than however many a game wants. The package waits for those before it
  goes anywhere.
* Ten files of arithmetic under `src/`, and one beside them that reaches a
  renderer.
