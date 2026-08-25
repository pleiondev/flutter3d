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
/// [packagesAt] is where this repository's packages are on this machine — a
/// path, because they are not published and a new project has to point at the
/// checkout it was made from.
String pubspecFor(String name, String packagesAt) => '''
name: $name
description: "A game, started from a template."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter

  # **Paths, because none of this is published**, and paths into the checkout
  # this project was made from — so they are true on the machine that made it
  # and nowhere else. Moving the project means fixing these five lines.
  flutter3d:
    path: $packagesAt/flutter3d
  flutter3d_game:
    path: $packagesAt/flutter3d_game
  flutter3d_bridge:
    path: $packagesAt/flutter3d_bridge
  flutter3d_session:
    path: $packagesAt/flutter3d_session
  flutter3d_impeller:
    path: $packagesAt/flutter3d_impeller

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
String readmeFor(String name, Template template) => '''
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
''';
