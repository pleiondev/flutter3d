## 0.5.2

* **A browser build can ask for WebGPU, and has to ask.**
  `--dart-define=FLUTTER3D_WEBGPU=true` makes the web half try `openWebGpu`
  first and fall back to WebGL2 where the browser has no `navigator.gpu` or
  refuses an adapter — the same `try`/`catch` shape, and for the same reason,
  as the native half's fall back to the software rasteriser. Without the define
  nothing changes: an ordinary web build opens WebGL2 and never mentions
  WebGPU.
* **Why it is a define and not simply the behaviour.** A probe that can call
  either opener keeps both backends reachable, and dart2js ships what it can
  reach. Measured on `apps/flutter3d_demo_strategy`, `flutter build web
  --release` writes 2,529,865 bytes of `main.dart.js` with the flag off and
  2,906,514 with it on — 376,649 bytes, 14.9%, of device, encoder, pipeline
  cache and WGSL that a build which never opens WebGPU would be carrying
  anyway, and 368 KiB on the whole of `build/web`. That is a trade a game
  makes, not one this package makes for it. Both readings are from the same
  afternoon and the same checkout; an earlier pair over a smaller tree said
  372,686, which is why the figure is taken again rather than quoted.
* The browser half now has tests of its own, and a `tool/ci.sh` step that runs
  them. It had never been executed anywhere: the existing suite says outright
  that a VM run *is* the native half, and which backend a web build opens was a
  decision with nothing holding it.
* Floors again, for the same reason as 0.5.1 and a different feature. An
  engine at 0.5.2 binds a `MorphInfo` block and a `morph_texture` sampler in
  its vertex stages; a backend older than that has neither in its bundle and
  cannot upload the float texture the deltas travel in. Impeller throws, naming
  the block; the software backend and WebGL read what is missing as nothing and
  go on drawing the base shape, saying nothing. `^0.5.2` on all three.

## 0.5.1

* **The floors move to the 0.5.1 backends, and the reason is a coupling the
  version graph could not otherwise state.** `flutter3d` 0.5.1 changed what the
  surface buffer's alpha means and added a member to the `FogInfo` uniform
  block, so an engine at 0.5.1 and a backend at 0.5.0 disagree about the shape
  of a block and about the units of a depth. Nothing forced them to move
  together: the engine names no backend — that is a structure rule — so this
  package is the only edge in the graph where the requirement can be written
  down, and it said `^0.5.0`.
* What that mismatch actually does, since a floor is worth what it prevents:
  Impeller throws a `StateError` naming the block and the member, which is the
  failure this package's floor now makes unreachable; the software backend is
  quieter and merely goes on drawing the old picture, which is the case that
  wanted the floor most.
* **One direction only.** This package does not depend on `flutter3d`, so it
  cannot say "an engine at least as new as these backends". A project that
  pins the engine down while letting the backends float is still able to
  assemble a pair that disagrees.

## 0.5.0

* No API change. Its floors move to the 0.5.0 backends.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* Picks the graphics backend a build draws through, with a conditional import
  rather than a runtime branch: the two pull in worlds that do not compile for
  each other's platform.
* `openDevice` was three files in each of three games and byte-identical in two
  of them.
* Deliberately does not decide resolution or shadow budget. Those are a game's
  trade against its own scene, and a shared constant would be wrong for two of
  the three.
