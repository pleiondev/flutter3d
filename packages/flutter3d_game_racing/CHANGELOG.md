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
