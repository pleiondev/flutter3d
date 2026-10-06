## Unreleased

- **The liquids run on the physics core.** `main` starts the run's physics
  (`preparePhysics`) before the bench is made, so the bench's `FluidWorld`
  steps its waves, streams and drops on the core — natively by FFI, in the
  browser as WebAssembly — and on the Dart reference where the core will
  not start or `--dart-define=FLUTTER3D_PHYSICS=dart` asks for it. The
  tests start it too, so they hold the bench to the same promises on either.

- **A flask leant and topped up no longer floods the bench.** The glass
  turns towards its lean at a hand's pace (`Vessel.aimTilt`, followed by
  `Bench.step`) rather than at once, which had laid the liquid's old level
  out as a wave that emptied it at a lean holding all of it; and `pour`
  fills a leaning glass only to what it holds as it leans. With
  `flutter3d_physics`' bounded drops, breaking waves and an overfull glass
  spilling over its edge, the stream, the drops in the air and the frame of
  three and a half seconds are gone.
