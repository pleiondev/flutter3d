---
description: All four games in one page, each running live in the browser through the same WebGL2 backend, with a sample recorded run to download from each.
---

# Gallery

Four genres, four live builds, one engine. Each frame below is the actual
game — the same WebGL2 backend its own demo page uses — not a recording.

<div class="demo">
  <iframe class="demo-frame" src="/demo/shooter/" title="Shooter — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Shooter · <a href="/shooter/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/shooter.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/platformer/" title="Platformer — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Platformer · <a href="/platformer/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/platformer.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Racing — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Racing · <a href="/racing/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/racing.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/strategy/" title="Strategy — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Strategy</span>
    <span>No sample run: orders aren't on the tape yet</span>
  </p>
</div>

<div class="note">
<p>Click a frame first — the keyboard goes to whatever was clicked last. Each one takes a few seconds to fetch its own textures and models before the first frame draws.</p>
</div>

## Opening a run

A downloaded `.f3drun` opens in the desktop level editor
(`apps/flutter3d_editor`, `flutter run -d macos`), on the timeline panel
described in [the level editor](/core/editor/) — pause, step, scrub to any
recorded moment.

<div class="warn">
<p><strong>Not from this page, and not from a browser at all.</strong> The editor is desktop-only by its own design — it writes a level document back to the disk it came from, which a browser will not do, so unlike the four games above it has no web build to open a run in. A downloaded run opens on whatever desktop the editor is installed on, not in this page.</p>
</div>

## Recording your own

The shooter's sample above came from a real, headless run of the actual
simulation — a second process, driven over a socket, stepped sixty times a
second and written out as a `.f3drun` — not a hand-edited file. The
platformer's and racing's samples are the same idea in a smaller shape: each
genre's own `test/demo_test.dart` already proves a shipped level replays
byte for byte, and each has a `tool/record_sample.dart` that runs the exact
same route and writes the result to `site/assets/samples/` instead of only
asserting against it.

Strategy has none, and not for want of a recorder. `.f3drun`'s tape is a
`GameAction`'s continuous press/release/analogue state, sampled every fixed
step — the shape a shooter's aim or a car's throttle already is. A strategy
match is played through discrete orders (`CommandPost.restock`, a
`TrainOrder`) that `main.dart` never turns into an `InputState` at all —
confirmed by there being no `InputState` in that file to find. Recording one
would mean teaching the tape format a second kind of frame, not writing a
third `tool/record_sample.dart`.

## Next

- [Quickstart](/quickstart/): build these four yourself, from a fresh checkout
- [The level editor](/core/editor/): what opens the run you just downloaded
- [Testing](/reference/testing/): how a run's checkpoints are recorded and compared
