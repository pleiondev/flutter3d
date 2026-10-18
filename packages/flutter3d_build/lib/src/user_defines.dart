/// What a project says to the build hook in its pubspec, under
/// `hooks: user_defines:` and its own package name, read strictly.
///
/// ```yaml
/// hooks:
///   user_defines:
///     my_game:                  # the project's `name:`
///       textures: bc            # auto, bc, etc2, universal or none
///       deviceClasses: [web]    # phone, web, desktop
///       fullShaders: true
/// ```
///
/// **A mistake is said, not swallowed.** `textures: bx` fell back to the
/// platform's family and `fullShader: true` was never read, while
/// `flutter3d_assets.yaml`, the other half of the same configuration,
/// refuses an unknown key with its line. A value of `textures` or
/// `deviceClasses` that is not one of the choices fails the build naming
/// them; a key this does not read is warned about, so a newer project's
/// key does not stop an older build.
library;

import 'package:flutter3d_core/flutter3d_core.dart' show DeviceClass;
import 'package:yaml/yaml.dart';

import 'convert.dart' show TextureFamily;
import 'device_classes.dart' show parseDeviceClasses;

/// The keys the hook reads among a project's user defines.
const Set<String> hookUserDefineKeys = <String>{
  'textures',
  'deviceClasses',
  'fullShaders',
};

String _unread(Object? key) =>
    'flutter3d_build: warning: the user define "$key" is not one this build '
    'reads (${hookUserDefineKeys.join(', ')}), so it changes nothing';

/// The family `textures:` names, or null when it names none. Throws a
/// [FormatException] naming the choices for a value that is not a family.
TextureFamily? texturesDefine(Object? value) => switch (value) {
  null => null,
  final String name when TextureFamily.tryParse(name) != null =>
    TextureFamily.tryParse(name),
  _ => throw FormatException(
    'flutter3d_build: the user define "textures: $value" is not a texture '
    'family; the choices are ${TextureFamily.values.join(', ')}',
  ),
};

/// The classes `deviceClasses:` names, or null when it names none. Throws a
/// [FormatException] naming the choices for a value naming a class there
/// is not.
List<DeviceClass>? deviceClassesDefine(Object? value) {
  if (value == null) return null;
  return parseDeviceClasses(value) ??
      (throw FormatException(
        'flutter3d_build: the user define "deviceClasses: $value" names a '
        'class there is not; the choices are '
        '${DeviceClass.values.map((DeviceClass c) => c.name).join(', ')}, '
        'as a list or joined by commas',
      ));
}

/// A warning for each key under `hooks: user_defines: <package>:` in
/// [pubspec] that the hook does not read; empty when there is none, or
/// when the text is not YAML (the pub tool says that itself).
///
/// [package] is the project whose hook runs: the defines a hook is handed
/// are its own package's, in its own pubspec or, for a workspace member,
/// in the workspace's.
List<String> unknownUserDefineWarnings(
  String pubspec, {
  required String package,
}) {
  final Object? document;
  try {
    document = loadYaml(pubspec);
  } on YamlException {
    return const <String>[];
  }
  final block = switch (document) {
    {'hooks': {'user_defines': final Map<Object?, Object?> defines}}
        when defines[package] is Map<Object?, Object?> =>
      defines[package]! as Map<Object?, Object?>,
    _ => const <Object?, Object?>{},
  };
  return <String>[
    for (final key in block.keys)
      if (!hookUserDefineKeys.contains(key)) _unread(key),
  ];
}
