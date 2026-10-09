/// `flutter3d create project`: a new application with one lit sphere on
/// screen, the build hook wired, and `assets_src/` waiting for models.
library;

import 'dart:io';

import 'init.dart';

/// The new project's Flutter import, spelled in two halves: this package is
/// plain Dart, and the structure rule that keeps it so reads an import line
/// in a template as an import of its own.
const String _flutterMaterial =
    'package:'
    'flutter/material.dart';

/// Whether [name] is a valid Dart package name.
bool isPackageName(String name) =>
    RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name) &&
    !const <String>{'flutter', 'test', 'flutter3d'}.contains(name);

/// The files of a new project called [name], by path.
Map<String, String> projectTemplate(String name) => <String, String>{
  'pubspec.yaml':
      '''
name: $name
description: "A flutter3d game."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter
  flutter3d: ^1.0.0-rc.1
  flutter3d_app: ^1.0.0-rc.1
  vector_math: ^2.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
''',
  'analysis_options.yaml': 'include: package:flutter_lints/flutter.yaml\n',
  'lib/main.dart':
      '''
import '$_flutterMaterial';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

void main() => runApp(const MaterialApp(home: Game()));

/// One lit sphere. Models go in `assets_src/`; the build hook converts
/// them on every build, and `Model3D` draws one by its source path.
class Game extends StatelessWidget {
  const Game({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 1.2, 3.5), target: Vector3.zero()),
      // Candela. The default camera is exposed for daylight (f/4, 1/60 s,
      // ISO 100), so a lamp that fills the frame is far brighter than a
      // household bulb's hundred.
      Light3D.point(
        position: Vector3(2.0, 2.5, 2.0),
        intensity: 92650.0,
        range: 20.0,
      ),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28, 1.0),
        roughness: 0.35,
        children: const <Widget>[Mesh3D(shape: SphereShape(radius: 1.0))],
      ),
    ],
  );
}
''',
  'assets_src/.gitkeep': '',
  'README.md':
      '''
# $name

A flutter3d game, made by `flutter3d create project`.

```sh
flutter create --platforms=macos .   # adds the platform folders, leaves the rest
flutter pub get
flutter run -d macos
```

On macOS and iOS, add `FLTEnableFlutterGPU` and `FLTEnableImpeller`, both
`<true/>`, to `Runner/Info.plist`. Without them the game falls back to the
software renderer and says so in the console.

Models, textures and materials go in `assets_src/`; the build hook converts
them into `flutter3d_generated/` on every build. Assets from another engine
come in with `flutter3d convert`:

```sh
flutter3d convert path/to/Chair.prefab -o assets_src/imported
```
''',
};

/// Writes a new project called [name] into [target], which must be empty
/// or not exist, and wires the build hook. Returns what it did, or why it
/// did not.
({bool did, String says}) createProject(String target, String name) {
  if (!isPackageName(name)) {
    return (
      did: false,
      says:
          '"$name" is not a package name: lower case letters, digits and '
          'underscores, starting with a letter',
    );
  }
  final root = Directory(target);
  if (root.existsSync() && root.listSync().isNotEmpty) {
    return (
      did: false,
      says: '$target is not empty; a new project goes in an empty directory',
    );
  }
  final files = projectTemplate(name);
  for (final MapEntry(:key, :value) in files.entries) {
    File('$target/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value.startsWith('\n') ? value.substring(1) : value);
  }
  final steps = planInit(root);
  for (final step in steps) {
    if (!step.blocked) step.apply!();
  }
  return (
    did: true,
    says: <String>[
      'created $name in $target:',
      for (final path in files.keys) '  $path',
      for (final step in steps) '  ${step.description}',
      '',
      'next:',
      '  cd $target',
      '  flutter create --platforms=macos .',
      '  flutter pub get && flutter run -d macos',
    ].join('\n'),
  );
}
