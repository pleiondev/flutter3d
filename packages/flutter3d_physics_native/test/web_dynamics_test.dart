// flutter3d_physics' bodies on the core in the browser — P9: NativeDynamics
// on the WebAssembly module, under both web compilers, steps the mirrored
// scene to the hash the native library steps it to.
//
//     dart test -p chrome test/web_dynamics_test.dart
//     dart test -p chrome -c dart2wasm test/web_dynamics_test.dart
@TestOn('browser')
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

import 'scenes/dynamics_scene.dart';

void main() {
  // The test runner serves the package root one up from the test's page.
  setUpAll(() => loadPhysicsCore(url: '../web/f3d_physics.wasm'));

  test('the mirrored scene steps to the native library\'s hash', () {
    expect(dynamicsSceneHash(), dynamicsSceneExpected);
  });
}
