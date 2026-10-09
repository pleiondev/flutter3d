# River Sortie

A jet up a river that never ends, in 3D. A homage to River Raid, which
Carol Shaw wrote for the Atari 2600 in 1982, and a Flame game from end to
end: flutter3d draws it and does nothing else.

```
flutter run -d macos
flutter run -d macos --dart-define=RIVER_LEVEL=3   # start on a later level
```

Arrows or WASD steer; up and down open and close the throttle. Space fires.
On a phone, Flame's own stick and a fire button do the same.

## The game

The river winds, narrows and splits round islands. Tankers and helicopters
wait on it, jets cut across it, and the tank runs dry unless the jet flies
low over a fuel depot. A bridge ends every stretch and has to be shot down
to pass; lose a jet and the next starts past the last bridge brought down.
A tanker is 30 points, a helicopter 60, a depot 80, a jet 100 and a bridge
500, and every ten thousand points is another jet in reserve.

The river is the same every run, because a seeded generator lays it out a
stretch at a time (`lib/src/course.dart`), the way the cartridge's river was
the same every time it was switched on.

## Levels and tasks

Five levels, then an open river that goes on for ever
(`lib/src/levels.dart`). Each level is a few bridges long, has its own mix
of targets, speeds and islands, and gives the pilot a task:

| Level | Bridges | Task |
|---|---|---|
| Shakedown | 2 | Bring down both bridges |
| Supply Line | 3 | Sink six tankers |
| Rotor Alley | 3 | Down five helicopters; some fire back |
| Jet Stream | 3 | Shoot down three jets |
| Long Haul | 4 | Eight tankers and four helicopters, on little fuel |

The last bridge of a level is shielded until its task is done. Glowing
rails show it; a shot throws sparks and the panel says what is still
wanted. Bringing it down pays the level's bonus.

## What happens when something is hit

- A **tanker** lists and sinks, trailing smoke.
- A **helicopter** spins down into the river and throws up a splash.
- A **jet** goes up in the air.
- A **fuel depot** goes up in a fireball that takes whatever is close with
  it — including a jet refuelling over it.
- A **bridge** breaks in the middle, and each half swings down into the
  water from its bank.
- A **gunner helicopter** turns after the jet and fires; its red tracers
  are slow enough to dodge.

Anything shot loses its hitbox at once, so a sinking tanker is scenery and
not something to fly into.

## Sound

A droning engine that climbs with the throttle, a falling whistle for a
shot, crunching noise for anything hit and a deeper one for a bridge or a
depot, chirps while a depot fills the tank, a two-beep alarm below a quarter
of a tank, a ping off a shielded bridge, and a jingle for a finished level
and for another jet. In the spirit of a 1982 cartridge rather than copies of
one: square waves and a shift-register noise, written by
`tool/make_sounds.py` (`python3 tool/make_sounds.py` rewrites them), with
nothing sampled from any game.

The game speaks through `flutter3d_audio`, into a silent backend until the
first take-off opens the speakers: that is the player's first input, which
is when a browser lets a page make a sound.

## Flame runs it, flutter3d draws it

`lib/src/river_game.dart` is an ordinary Flame game. Every moving thing is a
Flame component on a flat map of the river; Flame's collision detection
decides what hit what, `onCollisionStart` says so, and Flame paints the
instrument panel. Each of those components is an `Object3dComponent` from
`packages/flame_flutter3d`, which writes its Flame position into a scene
node every frame, and `Flutter3dFlameWidget` puts the 3D layer under
Flame's and runs both from Flame's clock.

The one thing not done with hitboxes is the banks: the river's edge is a
curve the course can answer for any point, so the jet asks whether it is
over water.

## Models

The jets, the helicopter and the tankers are free models; who made each and
under what licence is in `assets/models/LICENSES.md`. Two are CC BY 3.0 and
are credited there. The valley, trees, houses, bridges, depots and effects
are built in code (`lib/src/models.dart`), which also draws primitive
stand-ins until the model files have loaded.

## Tests

`flutter test` runs the course, the rules, the campaign, a frame drawn on
the CPU backend, and the game itself: the real `FlameGame`, loaded and
stepped the way Flame's own test harness does it, with every hit found by
Flame's collision detection.
