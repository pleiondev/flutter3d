## 0.5.0

**Breaking.** Ten flags become events, the mode carries what it means, and the
track reads its own version.

* **Eight flags on `RacerProgress`, two on `RaceState` and one on the
  simulation are gone.** Every event names the car it happened to, which a flag
  living on one `RacerProgress` could not: a caller found out who by knowing
  whose flag it had just read, which stops working the moment anything wants
  the field's moments in the order they happened.
* **`RaceMode` is open, and carries the three questions it was already being
  asked** with `==` in four places: does it start behind lights, does it count
  progress, does it end after so many laps. A game adds elimination or a drift
  event by answering them.
* **`TrackDocument` reads its `version`.** The generator has stamped one into
  every file since the format existed and this reader took the number and
  ignored it. A missing number still reads.
* **`LapReadout` and `PositionReadout`.** The lap counter counts from one and
  stops at the last, which every game that reached for `RacerProgress.lap` got
  wrong in both directions.
* **Sectors, a tow, assists, drift scoring, a qualifying grid and a restart.**
  Sectors are the stretches between checkpoints a circuit already carries, so a
  ghost can finally say *where* a driver lost the time. The slipstream arrives
  on `VehicleInput` rather than on `VehicleController`, which answers questions
  about the car rather than doing things to it. Traction control engages on
  spin while the car is pointing where it is going — written on slip ratio
  alone it would have cut the throttle mid-drift, in a game that scores them.
  `StartGrid.orderBy` turns a qualifying result into a grid, and `restart` puts
  the field back without rebuilding the world.

## 0.4.0

* No changes of its own beyond a doc comment following `gripLimit` to its new
  name; the version moves with the workspace, whose sibling constraints name
  a single release.

## 0.3.0

* **A parked car stays parked.** `SphereVehicle` had no resistance to rolling
  at all: the downhill part of gravity went into the velocity every step, the
  tyres answer a slip rather than a speed and saw nothing to object to, and air
  drag goes as the square of the speed. The circuit's starting grid rises about
  one in fifty, so a driver who touched nothing rolled backwards and kept
  gaining — 3.97 m/s after ten seconds. `rollingResistance` costs a coasting car
  something, and `holdSpeed`/`holdSlope` hold it still below a walking pace on
  anything gentler than about one in eight. Every scene this package was tested
  on was flat, which is why nothing caught it.
* Opponents drive the same car model the player does, and the ghost is the car
  it is racing rather than the box it used to be.

## 0.2.0

* A third genre: a car with grip it can lose, a track measured in metres,
  opponents, tyre wear, damage and the lap that counts.
