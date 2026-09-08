## 0.6.0

* **The determinism table was matched on a third and a fourth machine, and not
  one number in it moved.** Forty of forty checkpoints, on ubuntu-x64 under the
  VM and under Chrome, in CI run 34121423137. This car is the one that used to
  be the counter-example — a pair recorded on 2026-09-02 disagreed at
  twenty-three of the forty from step 75 onwards — so the confirmation is worth
  more here than anywhere: the arithmetic the tyre curve now runs on carries a
  run across a processor and an operating system as well as across an engine.
  The note is in `test/parity_test.dart` beside the table it is about.
* Nothing in `lib/` changed. The version moves with the set, and the floors on
  its siblings move with it.

## 0.5.1

* **The car replays identically in a browser and on the VM.** It did not: the
  same tape drove measurably different cars, diverging at twenty-three of forty
  checkpoints from step 75, because the tyre curve and the bicycle-model
  steering are made of transcendentals and `dart:math` gives different bits for
  every one of them in the two places. The vehicle, the tyre model, the track's
  camber, the AI driver and the grid placement call `Portable` now — see
  `flutter3d_sim` 0.5.1. Forty of forty.
* No API change. What a car does is a hair different in the last bits, which is
  a saved race from 0.5.0 replaying a hair differently and nothing a player can
  see.

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
