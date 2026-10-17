/// `flutter3d create project`: a new application of one of the
/// [ProjectKind]s, the build hook wired, and `assets_src/` waiting for
/// models.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_mcp/kit.dart' show Answer;

import 'init.dart';
import 'project_kinds.dart';
import 'project_model.dart';
import 'template_versions.dart';

/// The new project's Flutter import, spelled in two halves: this package is
/// plain Dart, and the structure rule that keeps it so reads an import line
/// in a template as an import of its own.
const String _flutterMaterial =
    'package:'
    'flutter/material.dart';

/// What a new project is for, which decides what `lib/main.dart` draws and
/// what the project depends on.
///
/// **A final class with constant instances rather than an enum**, for the
/// reason `PluginKind`'s doc gives: a fourth kind is a minor release, and a
/// `switch` somebody wrote against three would stop compiling on it.
///
/// The level-based genres (a platformer, a shooter, a racer, a strategy
/// map) are the level editor's templates, made from its new-project screen;
/// these are the projects that start from code.
final class ProjectKind {
  const ProjectKind._(this.name, this.about);

  /// One lit sphere in a `Scene3D`: the smallest application.
  static const ProjectKind scene = ProjectKind._(
    'scene',
    'one lit sphere in a Scene3D, the smallest application',
  );

  /// A model on a stand, turned by a drag and moved in by a pinch or a
  /// scroll, through `Flutter3dView`.
  static const ProjectKind viewer = ProjectKind._(
    'viewer',
    'a model from assets_src/ that a drag turns and a pinch or a scroll '
        'brings closer, through Flutter3dView',
  );

  /// A Flame game over a 3D layer, through `flame_flutter3d`.
  static const ProjectKind arcade = ProjectKind._(
    'arcade',
    'a Flame game drawn over a 3D layer through flame_flutter3d: a catcher, '
        'falling orbs and a score',
  );

  /// The three, in the order `--list` prints them.
  static const List<ProjectKind> values = <ProjectKind>[scene, viewer, arcade];

  /// The kind called [name], as `--kind` spells it.
  ///
  /// Throws an [ArgumentError] naming every kind for any other word.
  static ProjectKind named(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    throw ArgumentError.value(
      name,
      'kind',
      'a project is one of ${values.map((ProjectKind k) => k.name).join(', ')}',
    );
  }

  /// The word on the command line: `scene`, `viewer`, `arcade`.
  final String name;

  /// One line, for `--list`.
  final String about;

  @override
  String toString() => name;
}

/// Whether [name] is a valid Dart package name.
bool isPackageName(String name) =>
    RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name) &&
    !const <String>{
      'flutter',
      'test',
      'flutter3d',
      'flame',
      'flame_flutter3d',
    }.contains(name);

/// The text files of a new project called [name], of [kind], by path.
///
/// A [ProjectKind.viewer] project also gets `assets_src/model.glb`, which
/// is not text and is written by [createProject].
Map<String, String> projectTemplate(
  String name, {
  ProjectKind kind = ProjectKind.scene,
}) => switch (kind) {
  ProjectKind.viewer => viewerTemplate(name),
  ProjectKind.arcade => arcadeTemplate(name),
  _ => _sceneTemplate(name),
};

Map<String, String> _sceneTemplate(String name) => <String, String>{
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
${dependencyLine('flutter3d')}
${dependencyLine('flutter3d_app')}

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
''',
  'analysis_options.yaml': analysisOptions,
  'lib/main.dart':
      '''
import '$_flutterMaterial';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

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
  'test/widget_test.dart': sceneTest(name),
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

/// Writes a new project called [name], of [kind], into [target], which must
/// be empty or not exist, and wires the build hook. Returns what it did, or
/// why it did not.
Answer createProject(
  String target,
  String name, {
  ProjectKind kind = ProjectKind.scene,
}) {
  if (!isPackageName(name)) {
    return Answer(
      did: false,
      says:
          '"$name" is not a package name: lower case letters, digits and '
          'underscores, starting with a letter, and not the name of a package '
          'the project depends on',
    );
  }
  final root = Directory(target);
  if (root.existsSync() && root.listSync().isNotEmpty) {
    return Answer(
      did: false,
      says: '$target is not empty; a new project goes in an empty directory',
    );
  }
  final files = projectTemplate(name, kind: kind);
  for (final MapEntry(:key, :value) in files.entries) {
    File('$target/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value.startsWith('\n') ? value.substring(1) : value);
  }
  final binaries = <String, Uint8List>{
    if (kind == ProjectKind.viewer) viewerModelPath: viewerModelGlb(),
  };
  for (final MapEntry(:key, :value) in binaries.entries) {
    File('$target/$key')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(value);
  }
  final steps = planInit(root);
  for (final step in steps) {
    if (!step.blocked) step.apply!();
  }
  return Answer(
    did: true,
    says: <String>[
      'created $name ($kind) in $target:',
      for (final path in <String>[...files.keys, ...binaries.keys]) '  $path',
      for (final step in steps) '  ${step.description}',
      '',
      'next:',
      '  cd $target',
      '  flutter create --platforms=macos,web .',
      '  flutter pub get && flutter run -d macos',
    ].join('\n'),
  );
}
