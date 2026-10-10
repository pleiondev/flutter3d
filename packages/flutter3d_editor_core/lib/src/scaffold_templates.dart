/// The two files every scaffolded project gets that no template ships: a
/// `pubspec.yaml` naming the published packages, and a `README.md` explaining
/// what was just written.
///
/// Split out of `scaffold.dart` because these are boilerplate text and not
/// part of what decides *what* gets written where — `Template`, `projectAt`
/// and `scaffold` stay together, and the words a new project reads on its
/// first day live here.
library;

import 'scaffold.dart';

/// The `pubspec.yaml` a scaffolded project starts with.
///
/// Hosted versions, not paths into the checkout. **They were paths for as long
/// as the packages were unpublished**, which made every scaffolded project
/// true on the machine that made it and nowhere else; since 0.4.0 the packages
/// are on pub.dev and a new project travels.
///
/// **The floors move with the set, and being late is worse here than
/// anywhere.** A caret below 1.0.0 stops at the minor, so `^0.4.0` reaches
/// 0.4.x and no further: a project scaffolded against a stale line resolves the
/// engine of the month the line was written, compiles, runs, and only tells its
/// author how old it is when a name from a tutorial is not there. The seed says
/// what the repository publishes.
String pubspecFor(String name) =>
    '''
name: $name
description: "A game, started from a template."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter

  flutter3d: ^1.0.0-rc.1
  flutter3d_game: ^1.0.0-rc.1
  flutter3d_sim: ^1.0.0-rc.1

  # What the seed's own genre is written against: a plugin with a manifest,
  # installed into the view's loop.
  flutter3d_plugin_api: ^1.0.0-rc.1

  # The widgets over the game: the settings and rebinding screens, touch
  # controls, the HUD, and the words they say in the player's language.
  flutter3d_game_ui: ^1.0.0-rc.1

  # The assembly layer under `Flutter3dView`: the backend chooser with its
  # software fallback, the save file, the gamepad and the pointer capture.
  flutter3d_app: ^1.0.0-rc.1

  # Sound, placed where the view's camera is.
  flutter3d_audio: ^1.0.0-rc.1

  vector_math: ^2.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/levels/
    - assets/models/
''';

/// The `README.md` a scaffolded project starts with.
///
/// **It names no genre, and the wording of one sentence is deliberate.** This
/// prose is a string literal in a published package, and `no package names a
/// genre` reads string literals — it strips comments and nothing else, because
/// a word in a comment cannot be called and a word in a string can end up
/// switched on. So the seed says what it leaves out without listing weapons,
/// monsters or coins, which is the same sentence and one this package is
/// allowed to say.
String readmeFor(String name, Template template) =>
    '''
# $name

${template.about}

Made from the **${template.name}** template by the flutter3d level editor.

## What is here

```
assets/editor.json        what this game's words look like, for the editor
assets/levels/first.json  the level
assets/models/*.glb       a model per kind of thing
```

`assets/editor.json` is read by the editor and by nothing else — it is not in
`pubspec.yaml`'s asset list, so no player ever downloads it.

## Opening it again

Open `assets/levels/first.json` in the flutter3d level editor.

## Running it

```sh
flutter create --platforms=macos .   # adds the platform folders, leaves the rest
flutter pub get
```

`flutter create` adds the platform folders to what is already here and leaves
`pubspec.yaml`, `lib/` and `test/` alone.

**Then add two keys to the `macos/Runner/Info.plist` it just wrote**, inside
the top-level `<dict>`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<key>FLTEnableImpeller</key>
<true/>
```

Flutter GPU is enabled per application rather than per channel, and Impeller is
not yet the default renderer on macOS. Nothing can write these for you: there
is no `macos/` directory until `flutter create` makes one. **Skipping them does
not fail** — the game opens and draws, through the Dart software rasteriser,
because that is what `flutter3d_app` falls back to when Impeller will not
start. The only sign is a line in the console beginning
`flutter3d_app: Impeller would not start`, and a frame rate that is the
fallback's rather than the engine's. If you see that line, these keys are why.

```sh
flutter run -d macos
```

**Use a Flutter the packages support** (their `environment:` says which). An
older one writes a macOS project targeting an older system than the packages
support, and the build then fails with a deployment-target error that has
nothing to do with this project.

## What `lib/main.dart` is, and is not

**A seed, not a game.** It is a `Flutter3dView`, which opens the device, makes
the renderer, runs the engine's loop and owns focus and the lifecycle. Into
that loop it installs a small genre of its own, a body that walks, looks and
jumps through the level, steered by an `ActionMap` and saying on the event bus
when it lands. What it deliberately does not do is anything a real genre does:
nothing to fight, nothing to collect, no doors that open, no score, no menu,
no saving.

Those live in `flutter3d_game_shooter` and `flutter3d_game_platformer`, and
installing one in place of the seed's own is the next thing to do: each is a
`GenrePlugin` handed to the view's `plugins`, with the run it steps set when a
level is up.

## What is wired, and what is only available

The `pubspec.yaml` brings `flutter3d_app`, which is the assembly layer: the
settings and rebinding screens, the save file, the gamepad, and desktop pointer
capture. It also brings `flutter3d_audio`.

**Not all of that is wired into `lib/main.dart`.** The seed reads a level and
walks a body around it, on the keyboard through its `ActionMap`. What the
packages give you is that adding each of the rest is an import and a few lines
rather than a package decision:

* a settings screen — `GameSettings` and `SettingsFile` from `flutter3d_game`,
  `SettingsOverlay` from `flutter3d_game_ui`;
* key and pad rebinding — the same screen, over the seed's `ActionMap`;
* sound — `openSpeakers`, which throws when there is no audio device, then
  `AudioScene.play` where something happens, with the listener placed from
  the view's `onListenerMoved`;
* a gamepad — `PadInput`, over the same `ActionMap`;
* pointer capture for a first-person camera — `PointerLock`.
''';
