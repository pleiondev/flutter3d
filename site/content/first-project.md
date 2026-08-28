---
description: Your own project, from the editor's template: scaffold it, run it, edit its level, then change how the body moves.
---

# Your first project

[Quickstart](/quickstart/) puts a lit mesh on screen inside this repository. This makes a project that is yours: its own directory, its own level, its own models, and an application that walks around in them.

<div class="goal">
<ul>
<li>A project written from a template, and what each of its files is</li>
<li>Getting it to run, including the one step nobody does for you</li>
<li>Editing its level, and what the editor refuses to save over</li>
<li>Changing how the body feels, and where to test that without a window</li>
<li>What to add next, depending on what you are making</li>
</ul>
</div>

Two things before starting. The workspace has to be resolved and the shader bundle built, both from [Quickstart](/quickstart/). A scaffolded project depends on `flutter3d_impeller` by path, so it uses the bundle that lives in the checkout, and if that has never been built nothing will draw. And this is macOS. The browser is the other supported target, but the editor runs on the desktop.

## Write the project {.step}

The level editor scaffolds it. Point it at a level path that does not exist yet and it offers a template instead of an error:

```sh
cd apps/flutter3d_editor
flutter run -d macos --dart-define=level=/Users/me/games/deep_mine/assets/levels/first.json
```

![The editor pointed at a path that does not exist yet, offering the two templates](/assets/editor/editor-template.jpg)

Two templates: **platformer** and **shooter**. There is no racing one: a circuit is a spline rather than a room, and it is authored by a different tool.

Picking one writes the whole project at `/Users/me/games/deep_mine` and opens the new level in the editor. Note the shape of the path: the editor reads `…/<project>/assets/levels/<name>.json` and takes the part before `assets/` as the project root.

<div class="note">
<p>The template is <strong>data</strong>, not a code path in the editor. It is copied into the new project and read back from there by the same parser that reads any level's vocabulary, which is how an editor that contains no genre word can still start a genre game. The genre packages are in the editor's <code>dev_dependencies</code>, so the words are checked against the packages that own them and never linked into the program.</p>
</div>

## Run it {.step}

```sh
cd /Users/me/games/deep_mine
flutter create --platforms=macos .   # adds the platform folders, leaves the rest
flutter pub get
flutter run -d macos
```

`flutter create` adds `macos/` beside what is already there and leaves `pubspec.yaml`, `lib/` and `test/` alone.

<div class="warn">
<p><strong>Then add two keys to <code>macos/Runner/Info.plist</code>:</strong> <code>FLTEnableFlutterGPU</code> and <code>FLTEnableImpeller</code>, both <code>&lt;true/&gt;</code>. Flutter GPU is enabled per application, not per channel, and without them the app stops at <code>Failed to initialize ShaderLibrary</code>. Every application in this repository sets them; a scaffolded project has no <code>macos/</code> at all until <code>flutter create</code> makes one, so this is the step nobody can do for you. The exact wording of both failures is in <a href="/reference/pitfalls/">Pitfalls</a>.</p>
</div>

<div class="warn">
<p>Two more that bite once each. The pubspec points at the checkout by <strong>path</strong>, because none of these packages is published — those five lines are true on the machine that made the project and nowhere else, and moving either the project or the checkout means fixing them. And use the same Flutter the checkout uses: a different one writes a macOS project targeting an older system than the packages support, and the build then fails with a deployment-target error that mentions none of this.</p>
</div>

## Read what you got {.step}

| | |
|---|---|
| `lib/main.dart` | The application. A device, a renderer, a ticker, a camera, and a cubit that turns the level document into a scene |
| `lib/src/backend.dart` | Which backend this build draws through. One `export`, and the only line to change to run somewhere else |
| `assets/levels/first.json` | The level: brushes, materials, lights, entities. Data, not code |
| `assets/editor.json` | What this game's words look like *to the editor*. Not in the asset list, so no player downloads it |
| `assets/models/*.glb` | One model per kind of thing the level names |
| `test/widget_test.dart` | It loads the level through a software device, with no window |

The imports at the top of `main.dart` say where the halves are: `flutter3d` draws, `flutter3d_game` simulates, `flutter3d_session` owns loading, and `flutter3d_bridge` is the only one allowed to see both sides. [Assembling an application](/core/session/) is that seam in detail.

<div class="note">
<p><strong><code>main.dart</code> is a seed, not a game.</strong> It reads the level, builds it, and puts a body in it that walks, looks and jumps. What it deliberately leaves out is everything a <em>genre</em> is: no weapons, no monsters, no coins, no doors that open, no score, no menu, no saving. Those live in <code>flutter3d_game_shooter</code> and <code>flutter3d_game_platformer</code>, and adding one is the last step below.</p>
</div>

## Change the level {.step}

Run the editor again with the same command — the path exists now, so it opens rather than offers. `W A S D` walks, `Q`/`E` go down and up, drag looks, scroll moves forward.

Click a palette row on the left, then click a surface: that puts one down where you clicked. Click a brush to select it; arrows move it on the grid, `R`/`F` raise and lower it, `1` `2` `3` pick an axis and `−` `=` resize along it. `G` cycles the grid between 0.25 m, 1 m and off. `⌘Z` steps back.

`⌘S` saves.

<div class="note">
<p><code>⌘S</code> refuses to save over a document whose JSON carries a <code>generatedBy</code> key, and every level shipped in this repository carries one: they are written by a Python generator, so a hand-edit survives right up until somebody reruns it. <code>⇧⌘S</code> writes a copy and takes ownership of that. A scaffolded level has no such key — it is yours from the first save.</p>
</div>

## Change how it feels {.step}

This is the part a level cannot express. The body in the template is a `CharacterController` built with its defaults:

```dart
CharacterController(world: world, position: at)
```

Every number that decides how it feels is in the tuning beside it, in metres and seconds:

```dart
CharacterController(
  world: world,
  position: at,
  tuning: const MovementTuning(
    jumpSpeed: 9.5,     // 8.0 by default: metres per second, straight up
    gravity: 22.0,      // 24.0: lower is floatier
    coyoteTime: 0.15,   // 0.1: how long after a ledge a jump still counts
  ),
)
```

The rest of them, and the ones each genre adds on top, are in [the knobs](/reference/tuning/).

`tuning` is not `final`, which is deliberate and is what ice, mud, a low-gravity room and a slow-effect are all made of: assign a different constant while the game is running and the body changes on the next step.

<div class="why">
<p>What makes those safe to play with is that none of it needs a window. <code>flutter3d_game</code>, <code>flutter3d_physics</code> and the genre packages import no renderer at all, so a jump height, a monster's patience or a lap counter is reachable from a plain <code>test()</code> that runs in milliseconds. Put your second change there: a test says what happened, where a run shows you a frame of it and leaves you to judge.</p>
</div>

## Add a genre {.step}

The seed walks; a game does something. Each of the three games in this checkout keeps that wiring in one file, `lib/src/staging.dart`: what an entity type spawns, what a weapon is, what a coin does when you touch it. The one to copy from is `apps/flutter3d_demo_dungeon/lib/src/staging.dart` for a shooter, `apps/flutter3d_demo_platformer/lib/src/staging.dart` for a platformer, and `apps/flutter3d_demo_racing/lib/src/staging.dart` for a racer.

The genre pages say what each package brings: [what a shooter adds](/shooter/), [what a platformer adds](/platformer/), [what a racing game adds](/racing/).

## Where to go next

Pick by what you want to do.

| I want to… | Read |
|---|---|
| Know what a word here means | [Glossary](/reference/glossary/) |
| Change how the game feels | [The knobs](/reference/tuning/) |
| Understand what draws a frame | [The frame](/core/rendering/) |
| Put my own models in | [Assets & animation](/core/assets/) |
| Author levels rather than write code | [The level editor](/core/editor/), then [Simulation layer](/core/simulation/) for the format |
| Build a game from an empty directory instead | [Tutorial: build an FPS](/shooter/tutorial/) · [a platformer](/platformer/tutorial/) · [a racer](/racing/tutorial/) |
| Find out why something looks wrong | [Pitfalls](/reference/pitfalls/) |
| Ship it in a browser | [The playable demos](/platformer/demo/) |
