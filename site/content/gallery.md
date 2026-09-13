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
    <span>Sample run: not recorded yet</span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Racing — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Racing · <a href="/racing/demo/">full page ↗</a></span>
    <span>Sample run: not recorded yet</span>
  </p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/strategy/" title="Strategy — live demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>Strategy</span>
    <span>Sample run: not recorded yet</span>
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
second and written out as a `.f3drun` — not a hand-edited file. The other
three genres do not yet have an equivalent standalone recorder outside their
own test suites, which is why their rows above say so rather than linking to
a file that would otherwise quietly go stale.

## Next

- [Quickstart](/quickstart/): build these four yourself, from a fresh checkout
- [The level editor](/core/editor/): what opens the run you just downloaded
- [Testing](/reference/testing/): how a run's checkpoints are recorded and compared
