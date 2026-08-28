---
description: The device, the frame surface and the level lifecycle every shipped game assembles the same way, through flutter3d_backend, flutter3d_session and flutter3d_ui.
---

# Assembling an application

[The tutorial](/core/tutorial/) opens a device and drives a `Ticker` by hand, because that is what is actually happening underneath. By the second game, the same conditional import, the same forty-line frame widget and the same load-restart-save sequence had been written out three times, close enough to identical that a bug fixed in one copy stayed broken in the other two. Three packages exist because of that: `flutter3d_backend`, `flutter3d_session` and `flutter3d_ui`. This page is what they do, and how `apps/flutter3d_demo_dungeon` puts them to use. It is the most complete worked example of all three together.

<div class="goal">
<ul>
<li><code>flutter3d_backend.openDevice()</code>: one line that opens Impeller on desktop and WebGL2 on the web, without either name appearing at the call site</li>
<li><code>SceneSurface</code>: the widget that hands a frame to Flutter, and why its settings are a function rather than a value</li>
<li><code>RunSession&lt;L&gt;</code>: the five questions a game answers to get loading, restarting, saving and moving on for free</li>
<li>Where <code>flutter3d_ui</code> and the input packages fit in, how <code>flutter3d_app</code> puts all five behind one import, and where two of the five applications have not caught up to any of this yet</li>
</ul>
</div>

## Picking a device

```dart
import 'package:flutter3d_backend/flutter3d_backend.dart';

final device = await openDevice(width: 1280, height: 720);
```

`openDevice` picks between backends two different ways. Web or native is a **conditional export**, resolved at compile time, because `flutter_gpu` does not compile for the web and `dart:js_interop` does not compile for macOS. A file importing both could target neither. On the native half, Impeller or software is a **runtime `try`/`catch`**: `flutter3d_impeller`'s `GpuRenderBackend.create()` is tried first, and if it throws, `openDevice` falls back to `flutter3d_cpu`'s `CpuDevice`, built from `CpuShaderLibrary(builtinCpuShaders())`. It throws when Flutter GPU refuses to start on Skia, or when the platform never enabled Impeller. It has to be a runtime check: `flutter_gpu` ships with the SDK and is always importable, so no `dart.library.*` condition can see whether it will actually start. On the web half it is `flutter3d_webgl`'s `openWebGl(width:, height:)`, with no fallback: a software rasteriser would not make a browser without WebGL2 any more able to draw the picture. `width`/`height` are ignored by Impeller, which sizes itself per frame, and used by both WebGL and the software fallback, neither of which can.

<div class="warn">
<p>The software fallback is <code>flutter3d_cpu</code>, which the rest of this site describes as a golden-test backend and a dev dependency, not a production one. It is a Dart rasteriser with no GPU under it, and a frame that would take a millisecond on Impeller takes a great deal longer here. It exists as a last resort, so that a broken Impeller start shows <em>something</em>, playable if slow, instead of nothing at all. It is not a supported way to ship a game. <code>debugPrint</code> logs which one actually ran; <code>openDevice</code>'s return type does not say, on purpose, so every existing caller keeps compiling unchanged.</p>
</div>

What it does not decide is `kFixedResolution` — whether the backend renders to a fixed internal target that Flutter then stretches. It's `false` on native (Impeller allocates its frame targets at whatever size the widget was laid out at) and `true` on the web (a WebGL canvas resets its drawing buffer on resize, so `WebGlDevice` owns a canvas at one size and `present` takes a `BoxFit` to stretch it). *What* size is left to the application: the crypt and the platformer draw at 720p, the racing game at 960×540, and each says why where the number is.

<div class="note">
<p><code>flutter3d_backend</code> was deliberately not folded into <code>flutter3d_session</code>. Session would then depend on both backends, and <code>apps/flutter3d_editor</code>, which is desktop only and has no browser build to choose for, would pull WebGL through it for nothing.</p>
</div>

## The frame surface

`SceneSurface` is the widget every game's build method ends with:

```dart
SceneSurface(
  renderer: renderer,
  scene: loaded.scene,
  view: _view,
  onBeforeFrame: _placeCamera,
  settings: () => RenderSettings(
    reflections: const ReflectionSettings(),
    fog: fogFromLevel,
  ),
)
```

<small>from `apps/flutter3d_demo_dungeon/lib/main.dart`</small>

`renderer`, `scene` and `view` are unsurprising. `settings` is not a `RenderSettings` value. It is a **function called once per frame, immediately after `onBeforeFrame`**. That ordering is the whole reason it's a function: the racing game's fog colour is the colour of the air along the current view, which only exists once the camera has moved for this frame, and `onBeforeFrame` is where the camera moves. A stored `RenderSettings` would describe last frame's air.

`SceneSurface` clamps the render target to at least one pixel in each dimension, because a panel mid-animation or a window dragged to nothing is a real, zero-sized layout, and a render target of zero pixels is not a state the renderer has to tolerate.

## The run

`RunSession<L>` is loading a level, restarting it, moving to the next one, saving, resuming, and reporting how a run ended — the sequence three games wrote out separately: a 278-line cubit in the dungeon, nine private methods in a 1441-line platformer widget, and nothing at all in the racing game, whose saves never worked. A game answers five questions and gets the sequence for free:

```dart
final class DungeonRun extends RunSession<LevelReady> {
  DungeonRun({required super.firstLevel, required super.saves, /* ... */});

  @override
  Future<LevelReady> open(String asset) async {
    final loaded = await const LevelLoader().load(asset, device: device, registry: registry, rules: sampleRules());
    // ... build the scene and collision visuals, stage the level
    return LevelReady(/* ... */);
  }

  @override
  RunOutcome outcomeOf(LevelReady level) => level.staged.sim.state.outcome;

  @override
  String? nextOf(LevelReady level) => level.staged.sim.nextLevel;

  @override
  Snapshot snapshotOf(LevelReady level) => level.staged.sim.save();

  @override
  void restoreInto(LevelReady level, Snapshot snapshot) => level.staged.sim.restore(snapshot);

  // Keys do not carry between levels. A level designer's promise, and the
  // plumbing must not break it.
  @override
  void carryFrom(LevelReady level, String next) => inventory.keys.clear();
}
```

<small>abridged from `apps/flutter3d_demo_dungeon/lib/src/run_cubit.dart`</small>

`RunSession` is an ordinary class, not a `Cubit`. Two of the three games wrap it in one, calling `onChanged` from `emit`, and the package neither knows nor requires that. Driving it is five methods: `begin()` (the saved run, or `firstLevel`, falling back to a fresh start if the save names a level that no longer exists), `load(asset, {resume})`, `restart()`, `advance()` (moves on once `outcomeOf` reports the level is over, and does nothing on the second call, since a finished level would otherwise restart a load on every subsequent frame), and `save()`.

<div class="warn">
<p>Two optional overrides matter more than they look. <code>startFresh()</code> is what a restart rebuilds from. Skip it and a restart begins with the health you died at, which is not a restart. <code>carryFrom(level, next)</code> runs on the level being left, before the next is read, which is the only moment both are knowable; the dungeon empties the key ring there, the platformer copies lives and elapsed time.</p>
</div>

Not every game fits the shape. The racing game moves from one circuit to the next and remembers where somebody got to, which looks like a `RunSession` and isn't one: nobody resumes a race half a lap in, so `snapshotOf`/`restoreInto` would be two required overrides returning nothing. It uses `SceneSurface` without `RunSession`, and `test/one_assembly_test.dart`, the check that exactly one function per game turns a level document into a run, reads all three applications instead of assuming the base class applies to all of them.

## Settings and saves

`flutter3d_ui` is the screens a game has that are not the game: `SettingsOverlay` (volumes, a gamepad and accessibility sliders, a rebinding list that takes a key or a pad button, and where a licence's attribution goes) and `SaveFile` (where `RunSession.saves` reads and writes, per platform, through `Storage`). Wiring the overlay into a HUD is one widget per game:

```dart
SettingsOverlay(
  settings: settingsCubit,
  mixer: audio.mixer,
  bindings: devices.bindings,
  config: config,
  padConnected: pad.isConnected,   // asked every frame, not assumed
  actions: shooterActions,
  defaultBindings: defaultShooterBindings,
  opening: pauseTheGame,
)
```

It was extracted when the second game wanted rebinding, which mattered for accessibility more than for convenience: the alternative was four hundred lines of panel copied into the second game, and the racing game's copy had already drifted: it told its own panel there was no controller connected while the other two asked the pad.

## Input

A game rarely calls `pad_input` or `pointer_lock` directly. `flutter3d_game`'s `DesktopInput` and pad-action layer already wrap both, and that is what `_devices.isCaptured` and `_devices.captureMouse()` in an app's `main.dart` reach. The two packages underneath are worth knowing because they're where a fifth platform gets implemented:

```dart
final pad = Gamepad.instance;
final snapshot = PadSnapshot();
pad.read(snapshot);                                  // once per frame
if (snapshot.down(PadButton.faceSouth)) jump();
```

`Gamepad` is pull, not push — a fixed-step simulation asks *what is the pad doing now* exactly once per step, and a stream would push edge detection into every caller differently. Button identifiers are physical positions (`face.south`, not `a`), because the string is what lands in a player's config file, read back on a possibly different pad. Implemented on macOS, iOS, Web and Android; Windows and Linux are not yet.

```dart
final lock = PointerLock.instance;
if (lock.isSupported) await lock.capture();
final delta = lock.takeDelta();                       // synchronous, drained once per step
```

`PointerLock` fills a gap Flutter leaves on every desktop platform: no pointer lock, which an FPS-style camera needs, since without it the cursor reaches the window edge and the view stops turning. `takeDelta()` is synchronous on purpose. It is called from inside the simulation step, where awaiting anything would mean the step no longer sees a consistent snapshot of its inputs. Two backends: a method channel on macOS, and the browser's own `requestPointerLock` through static interop. The choice is a conditional export, so nothing registers a plugin and `flutter test --platform chrome` can exercise it. Windows and Linux are not implemented and say so, so a game falls back to a drag instead of to a camera that does not turn. Losing focus drops the capture automatically, which a game should treat as a reason to pause rather than as an error; in a browser the capture also has to be asked for inside the handler of the press that prompted it, because `requestPointerLock` is refused without a user gesture behind it.

## One import for all of it

The five packages this page walks are re-exported by `flutter3d_app`, so an application names the layer once rather than naming its parts:

```dart
import 'package:flutter3d_app/flutter3d_app.dart';
```

Thirty-five lines, all of them `export`. It changes nothing about how the five relate: none of them knows about the others, and the barrel does not make them. What it saves is five import lines being copied into every new project, which is how this page's subject started.

What is deliberately not behind it: `flutter3d`, `flutter3d_bridge`, `flutter3d_game` and a genre package. Those say what a scene looks like and what kind of game this is, and a facade cannot choose a genre for an application.

## Where two applications have not caught up

The three demo games import `flutter3d_app`. `apps/flutter3d_editor` and `apps/flutter3d_template_app` do not: they name `flutter3d_impeller` and `flutter3d_session` directly and open their device with `GpuRenderBackend.create()`, the way [the tutorial](/core/tutorial/) does.

For the editor that is defensible, since it is desktop-only and there is no backend to choose between. For the scaffold it is a gap rather than a second valid pattern, and the more expensive of the two: a project copied from it today gets the older wiring, which is exactly the copying this page exists to stop. `apps/flutter3d_demo_dungeon` is the one to read for the pattern described here. If you are starting a new project, copy the scaffold for its shape and this page for its wiring.

## Next

- [Core: what core is](/core/): the five packages underneath all of this
- [Tutorial: first scene](/core/tutorial/): the raw version of device-opening this page builds on
- [The level editor](/core/editor/): the fourth application, and the one with no genre package at all
