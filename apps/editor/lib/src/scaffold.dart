/// Everything a new project is made of, as bytes.
///
/// **No disk and no window in this file**, the same split `editing.dart` makes
/// and for the same reason: writing a directory somebody will spend a week in
/// is the part that can go wrong permanently, and it is the part a test can
/// hold still. The half that has `dart:io` in it does two things — read the
/// template out of the bundle, write these bytes down — and neither is a
/// decision.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A template, as its manifest describes it.
final class Template {
  const Template({
    required this.id,
    required this.name,
    required this.about,
    required this.files,
  });

  /// The directory it lives in, and the word written into a level so the
  /// palette can be rebuilt later.
  final String id;

  /// What a person picking one reads.
  final String name;
  final String about;

  /// What to copy: the file's name in the template, against where it lands in
  /// a project.
  ///
  /// A manifest rather than a directory listing, because the template is read
  /// out of an application bundle and a bundle cannot be listed — and because
  /// a file that exists and is not listed is a file that never arrives.
  final Map<String, String> files;

  factory Template.parse(String id, String manifest) {
    final json = jsonDecode(manifest) as Map<String, Object?>;
    final files = json['files'];
    return Template(
      id: id,
      name: json['name'] as String? ?? id,
      about: json['about'] as String? ?? '',
      files: <String, String>{
        if (files is Map<String, Object?>)
          for (final entry in files.entries)
            if (entry.value is String) entry.key: entry.value! as String,
      },
    );
  }
}

/// Where a project's directory is, given the level path somebody asked for.
///
/// **A path that does not exist is a request to make one**, and what it names
/// is a level inside a project rather than the project. `…/my_game/assets/
/// levels/first.json` means `my_game`; a bare `…/my_game/first.json` means the
/// directory it is in, and the level lands where the layout says it goes.
({String root, String level}) projectAt(String levelPath) {
  const inside = '/assets/';
  final at = levelPath.lastIndexOf(inside);
  if (at > 0) {
    return (root: levelPath.substring(0, at), level: levelPath);
  }
  final slash = levelPath.lastIndexOf('/');
  final root = slash <= 0 ? levelPath : levelPath.substring(0, slash);
  return (root: root, level: '$root/assets/levels/first.json');
}

/// The name a directory and a pub package can both have.
///
/// Lower case, words joined by underscores, never starting with a digit. Pub is
/// strict about this and the error it gives is about a file nobody has opened
/// yet, so it is worth being strict here where the name is being typed.
String packageName(String typed) {
  final cleaned = typed
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (cleaned.isEmpty) return 'my_game';
  return RegExp(r'^[0-9]').hasMatch(cleaned) ? 'game_$cleaned' : cleaned;
}

/// Lays a new project out: every file, as bytes, against the path it goes to.
///
/// [sources] is the template's own files, by the names its manifest uses.
/// [packagesAt] is where this repository's packages are on this machine — a
/// path, because they are not published and a new project has to point at the
/// checkout it was made from.
Map<String, Uint8List> scaffold({
  required Template template,
  required String project,
  required Map<String, Uint8List> sources,
  required String packagesAt,
}) {
  final name = packageName(project);
  final out = <String, Uint8List>{};

  for (final entry in template.files.entries) {
    final bytes = sources[entry.key];
    if (bytes == null) {
      throw StateError(
        'the ${template.id} template lists ${entry.key} and the bundle has no '
        'such file — check the assets: lines in pubspec.yaml',
      );
    }
    out[entry.value] = entry.value.endsWith('levels/first.json')
        ? _disown(bytes)
        : bytes;
  }

  out['pubspec.yaml'] = _bytes(_pubspec(name, packagesAt));
  out['README.md'] = _bytes(_readme(name, template));
  // The test arrives with the rest of the template — see `app.test.dart.txt`
  // in the index, and `apps/template_app/test/widget_test.dart`, which is the
  // file itself and is run by CI like any other.
  return out;
}

/// The starter level, with the generator's name taken off it.
///
/// **A scaffolded level belongs to the person who made it.** The template's
/// copy is generated and says so honestly, and `generatedBy` is exactly the key
/// that stops an editor writing over a file a script owns — so copying it
/// unchanged produces a new project whose very first save is refused, with a
/// message about a Python file the author has never heard of.
///
/// Taken off the decoded map rather than through `Editing.write(claiming:)`,
/// which sets the key rather than removing it, and rather than through
/// `Level.toJson`, which writes unknown keys straight back.
Uint8List _disown(Uint8List level) {
  final json = jsonDecode(utf8.decode(level)) as Map<String, Object?>;
  json.remove('generatedBy');
  return _bytes('${const JsonEncoder.withIndent('  ').convert(json)}\n');
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String _pubspec(String name, String packagesAt) => '''
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

String _readme(String name, Template template) => '''
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
cd <the flutter3d checkout>/apps/editor
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
