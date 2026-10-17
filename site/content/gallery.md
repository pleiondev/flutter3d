---
description: All four games in one page, each running live in the browser through the same WebGL2 backend, with a sample recorded run to download from each.
---

# Gallery

The four games below are one engine playing four genres. Each frame is the
live game, running on the same WebGL2 backend as its own demo page.

<div class="demo">
  <iframe class="demo-frame" src="/demo/shooter/" title="Shooter, live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Shooter · <a href="/shooter/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/shooter.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/platformer/" title="Platformer, live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Platformer · <a href="/platformer/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/platformer.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Racing, live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Racing · <a href="/racing/demo/">full page ↗</a></span>
    <span><a href="/assets/samples/racing.f3drun" download>Download a run (.f3drun)</a></span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/strategy/" title="Strategy, live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Strategy</span>
    <span>No sample run: orders aren't on the tape yet</span>
  </p>
</div>

<div class="note">
<p>Click a frame first, because the keyboard goes to whatever was clicked last. Each game takes a few seconds to fetch its textures and models before the first frame draws.</p>
</div>

## Opening a run

A downloaded `.f3drun` opens in the level editor, on the desktop or in its
web build ([where to get it](/download/)). "Open a run" picks the file, or
drop it on the window, and the editor shows what the file says: the level and
its hash, the build that recorded it, how long it ran and how many
checkpoints it carries.

<div class="note">
<p><strong>A run file is read, not replayed, in the editor.</strong> Stepping through a saved run needs the genre's own simulation, and the editor knows no genre. To pause, step and scrub a run, play it in its game and attach the editor's timeline to the game while it runs, as <a href="/core/editor/">the level editor</a> describes. The web build attaches over the same VM service address the desktop one does.</p>
</div>

## Recording your own

The shooter's sample above came from a real, headless run of the simulation:
a second process, driven over a socket, stepped sixty times a second and
written out as a `.f3drun`. Nobody edited the file by hand. The platformer's
and racing's samples are the same idea in a smaller shape. Each genre's
`test/demo_test.dart` already proves that a shipped level replays byte for
byte, and each has a `tool/record_sample.dart` that runs the same route and
writes the result to `site/assets/samples/` as well as asserting against it.

Strategy has no sample, and a recorder is not what it lacks. The tape in a
`.f3drun` is a `GameAction`'s continuous press, release and analogue state,
sampled every fixed step, which is the shape a shooter's aim or a car's
throttle already has. A strategy match is played through discrete orders
(`CommandPost.restock`, a `TrainOrder`), and `main.dart` never turns those into
an `InputState`; there is no `InputState` anywhere in that file. Recording a
match would mean teaching the tape format a second kind of frame, which is
more than writing a third `tool/record_sample.dart`.

## Next

- [Quickstart](/quickstart/): a scene of your own from pub.dev, and the checkout these are built from
- [The level editor](/core/editor/): what opens the run you just downloaded, and [where to get it](/download/)
- [Testing](/reference/testing/): how a run's checkpoints are recorded and compared
