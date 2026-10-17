/// The programs `flutter3d convert` hands a format to when it does not read
/// that format itself: FBX through FBX2glTF or Blender, `.blend` through
/// Blender, binary USD through `usdcat`. `flutter3d doctor` reports the same
/// list.
library;

import 'dart:io';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ResourceException;

/// A program found or not, with what installs it.
final class ExternalTool {
  const ExternalTool({
    required this.name,
    required this.executables,
    required this.purpose,
    required this.install,
    this.knownLocations = const <String>[],
    this.versionArguments = const <String>['--version'],
  });

  /// What a person calls it.
  final String name;

  /// The names it goes by on `PATH`, tried in order.
  final List<String> executables;

  /// Where an installer puts it off `PATH`, tried after it.
  final List<String> knownLocations;

  /// What it is used for, in a sentence.
  final String purpose;

  /// How to get it.
  final String install;

  /// What asks it for its version.
  final List<String> versionArguments;

  /// Where it is, or null when it is not installed.
  ///
  /// An environment variable `FLUTTER3D_<NAME>` (the name upper-cased,
  /// non-letters as `_`) names it directly and wins over the search.
  String? locate({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final variable =
        'FLUTTER3D_${name.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '_')}';
    final named = env[variable];
    if (named != null && named.isNotEmpty && File(named).existsSync()) {
      return named;
    }
    for (final executable in executables) {
      final found = findOnPath(executable, environment: env);
      if (found != null) return found;
    }
    for (final location in knownLocations) {
      if (File(location).existsSync()) return location;
    }
    return null;
  }
}

/// FBX to glTF, the first choice for an `.fbx`.
const ExternalTool fbx2gltf = ExternalTool(
  name: 'FBX2glTF',
  executables: <String>['FBX2glTF', 'fbx2gltf', 'FBX2glTF-darwin-x64'],
  purpose: 'converts .fbx to glTF',
  install:
      'download a release from https://github.com/godotengine/FBX2glTF/releases '
      'and put it on PATH (or set FLUTTER3D_FBX2GLTF to its path)',
  versionArguments: <String>['--version'],
);

/// Blender, for `.blend` and for an `.fbx` when FBX2glTF is absent.
const ExternalTool blender = ExternalTool(
  name: 'Blender',
  executables: <String>['blender'],
  knownLocations: <String>[
    '/Applications/Blender.app/Contents/MacOS/Blender',
    r'C:\Program Files\Blender Foundation\Blender\blender.exe',
    '/snap/bin/blender',
  ],
  purpose: 'converts .blend (and .fbx without FBX2glTF) to glTF',
  install:
      'install Blender from https://www.blender.org/download/ and put '
      '`blender` on PATH (or set FLUTTER3D_BLENDER to its path)',
);

/// `usdcat`, for a binary (crate) USD layer.
const ExternalTool usdcat = ExternalTool(
  name: 'usdcat',
  executables: <String>['usdcat'],
  purpose: 'turns a binary .usdc layer into text .usda',
  install:
      'install the USD tools (`pip install usd-core`, which brings usdcat) '
      'and put them on PATH',
);

/// Every converter tool, in the order `doctor` lists them.
const List<ExternalTool> externalTools = <ExternalTool>[
  fbx2gltf,
  blender,
  usdcat,
];

/// [executable] on `PATH`, or null.
String? findOnPath(String executable, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final separator = Platform.isWindows ? ';' : ':';
  final suffixes = Platform.isWindows
      ? <String>['', '.exe', '.bat', '.cmd']
      : <String>[''];
  for (final directory in (env['PATH'] ?? '').split(separator)) {
    if (directory.isEmpty) continue;
    for (final suffix in suffixes) {
      final candidate = '$directory${Platform.pathSeparator}$executable$suffix';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}

/// A tool was needed and is not installed.
final class MissingToolException extends ResourceException {
  const MissingToolException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// A tool ran and refused.
final class ToolFailedException extends ResourceException {
  const ToolFailedException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Converts the FBX at [input] to a `.glb` in [workDirectory] and returns
/// its path: FBX2glTF when installed, otherwise Blender.
///
/// Throws [MissingToolException] when neither is, naming both.
String fbxToGlb(String input, Directory workDirectory) {
  final output = '${workDirectory.path}/fbx.glb';
  final converter = fbx2gltf.locate();
  if (converter != null) {
    _run(converter, <String>[
      '--binary',
      '--input',
      input,
      '--output',
      '${workDirectory.path}/fbx',
    ], 'FBX2glTF');
    if (File(output).existsSync()) return output;
    throw const ToolFailedException('FBX2glTF ran and wrote no .glb');
  }
  final blenderPath = blender.locate();
  if (blenderPath != null) {
    _run(blenderPath, <String>[
      '--background',
      '--factory-startup',
      '--python-expr',
      _blenderScript(
        before:
            'bpy.ops.wm.read_factory_settings(use_empty=True)\n'
            'bpy.ops.import_scene.fbx(filepath=${_pythonString(input)})',
        output: output,
      ),
    ], 'Blender');
    if (File(output).existsSync()) return output;
    throw const ToolFailedException('Blender ran and wrote no .glb');
  }
  throw MissingToolException(
    'an .fbx needs FBX2glTF or Blender, and neither is installed. '
    'FBX2glTF: ${fbx2gltf.install}. Blender: ${blender.install}. '
    '`flutter3d doctor` says what it finds.',
  );
}

/// Converts the `.blend` at [input] to a `.glb` in [workDirectory] through
/// Blender and returns its path.
///
/// Throws [MissingToolException] when Blender is not installed.
String blendToGlb(String input, Directory workDirectory) {
  final output = '${workDirectory.path}/blend.glb';
  final blenderPath = blender.locate();
  if (blenderPath == null) {
    throw MissingToolException(
      'a .blend is read by Blender, which is not installed: '
      '${blender.install}. `flutter3d doctor` says what it finds.',
    );
  }
  _run(blenderPath, <String>[
    '--background',
    input,
    '--python-expr',
    _blenderScript(before: '', output: output),
  ], 'Blender');
  if (File(output).existsSync()) return output;
  throw const ToolFailedException('Blender ran and wrote no .glb');
}

/// Turns the binary USD layer at [input] into text in [workDirectory]
/// through `usdcat` and returns its path.
///
/// Throws [MissingToolException] when `usdcat` is not installed.
String usdcToUsda(String input, Directory workDirectory) {
  final tool = usdcat.locate();
  if (tool == null) {
    throw MissingToolException(
      'a binary USD layer (crate) is read through usdcat, which is not '
      'installed: ${usdcat.install}. Or save the layer as .usda.',
    );
  }
  final output = '${workDirectory.path}/layer.usda';
  _run(tool, <String>[input, '-o', output], 'usdcat');
  if (File(output).existsSync()) return output;
  throw const ToolFailedException('usdcat ran and wrote no .usda');
}

String _blenderScript({required String before, required String output}) =>
    'import bpy\n'
    '$before\n'
    'bpy.ops.export_scene.gltf(filepath=${_pythonString(output)}, '
    "export_format='GLB', export_yup=True, export_apply=True)\n";

String _pythonString(String text) =>
    "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

void _run(String executable, List<String> arguments, String name) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    throw ToolFailedException(
      '$name exited with ${result.exitCode}: '
      '${'${result.stderr}'.trim().split('\n').take(5).join(' / ')}',
    );
  }
}
