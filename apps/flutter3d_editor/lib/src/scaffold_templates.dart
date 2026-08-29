/// The two files every scaffolded project gets that no template ships: a
/// `pubspec.yaml` pointing at this checkout's packages, and a `README.md`
/// explaining what was just written.
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

  flutter3d: ^0.4.0
  flutter3d_game: ^0.4.0
  flutter3d_bridge: ^0.4.0
  flutter3d_session: ^0.4.0

  # The assembly layer, which this seed used to leave out — and with it the
  # settings screen, the key rebinding, the pointer capture and the gamepad.
  # A scaffolded project got a window and a level and no way to turn the
  # volume down, which is not a starting point anybody would choose.
  #
  # It brings `flutter3d_backend` too, so the game picks its backend the way
  # the three demos do rather than naming Impeller here: a project that names
  # one backend has no web build and no software fallback.
  flutter3d_app: ^0.4.0

  # Sound, which the seed also had none of.
  flutter3d_audio: ^0.4.0

  vector_math: ^2.2.0
  # State management — see the note in `packages/flutter3d_ui/pubspec.yaml`.
  flutter_bloc: ^9.1.1

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

```sh
cd <the flutter3d checkout>/apps/flutter3d_editor
flutter run -d macos --dart-define=level=<this directory>/assets/levels/first.json
```

## Running it

```sh
flutter create --platforms=macos .   # adds the platform folders, leaves the rest
flutter pub get
flutter run -d macos
```

`flutter create` adds the platform folders to what is already here and leaves
`pubspec.yaml`, `lib/` and `test/` alone.

**Use the same Flutter the checkout uses.** A different one writes a macOS
project targeting an older system than the packages support, and the build then
fails with a deployment-target error that has nothing to do with this project.
`flutter --version` in the checkout says which one that is.

## What `lib/main.dart` is, and is not

**A seed, not a game.** It reads the level, builds it, and puts a body in it
that walks, looks and jumps. What it deliberately does not do is anything a
*genre* does: no weapons, no monsters, no coins, no doors that open, no score,
no menu, no saving.

Those live in `flutter3d_game_shooter` and `flutter3d_game_platformer`, and wiring one up
is the next thing to do. Each of the three games in the flutter3d checkout keeps
that wiring in its own `lib/src/staging.dart`, which is the file to read first.

## What is wired, and what is only available

The `pubspec.yaml` brings `flutter3d_app`, which is the assembly layer: the
settings and rebinding screens, the save file, the gamepad, and desktop pointer
capture. It also brings `flutter3d_audio`.

**None of that is wired into `lib/main.dart`.** The seed opens a device, reads
a level, and walks a body around it — that is all. What the packages give you
is that adding each of these is an import and a few lines rather than a
package decision:

* a settings screen — `SettingsCubit`, `SettingsOverlay`, `SettingsFile`;
* key and pad rebinding — the same screen, once `actions` is a list of what
  this game lets a player change;
* sound — `openSpeakers`, then `AudioScene.play` where something happens;
* a gamepad — `PadInput`, ticked once a frame beside the keyboard;
* pointer capture for a first-person camera — `PointerLock`.

The crypt's `lib/main.dart` in the flutter3d checkout wires all five, and is
the worked example for each.
''';
