/// That the Dart list and the manifest say the same thing.
///
/// Two lists of the same names is a drift waiting to happen, and the drift is
/// silent: a shader added to the manifest and not to Dart is simply unchecked,
/// which is exactly the state that let a backend ship without one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d_shaders/flutter3d_shaders.dart';

void main() {
  test('kRequiredShaders matches the bundle manifest', () {
    final file = File('shaders/flutter3d.shaderbundle.json');
    expect(file.existsSync(), isTrue,
        reason: 'run this from the package root');
    final manifest =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final fromManifest = <String, bool>{
      for (final entry in manifest.entries)
        entry.key: (entry.value as Map<String, dynamic>)['type'] == 'fragment',
    };
    final fromDart = <String, bool>{
      for (final shader in kRequiredShaders) shader.name: shader.fragment,
    };

    expect(fromDart.keys.toSet(), fromManifest.keys.toSet(),
        reason: 'a shader exists in one list and not the other; regenerate '
            'lib/flutter3d_shaders.dart');
    for (final name in fromManifest.keys) {
      expect(fromDart[name], fromManifest[name],
          reason: '$name is a different stage in the two lists');
    }
  });
}
