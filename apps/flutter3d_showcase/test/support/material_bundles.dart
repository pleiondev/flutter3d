import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_showcase/pages/shading/user_materials.dart';

/// Compiles [UserMaterialsDemo.source] into the bundle the page loads, with
/// the compiler a package's build hook runs, and writes it where the page
/// asks for it.
///
/// **Built rather than committed**, as every `.f3dshaders` in the tree is: a
/// bundle carries an Impeller section tied to the Flutter SDK that built it,
/// so one committed goes stale on the next upgrade. The showcase has no hook,
/// so the test that draws the page builds it first.
///
/// Written twice: beside the page, which is where a build of the app takes
/// its assets from, and into the folder `flutter test` serves `rootBundle`
/// from (`UNIT_TEST_ASSETS`), which was filled before this test started.
void buildUserMaterialsBundle() {
  final scratch = Directory.systemTemp.createTempSync('f3dmat');
  try {
    final bytes = compileMaterial(
      UserMaterialsDemo.source,
      source: UserMaterialsDemo.bundlePath.replaceAll('.f3dshaders', '.f3dmat'),
      engine: loadShaders(from: Directory.current.path),
      compilers: MaterialCompilers.locate(),
      scratch: scratch,
    ).encode().buffer.asUint8List();
    for (final root in <String>[
      Directory.current.path,
      ?Platform.environment['UNIT_TEST_ASSETS'],
    ]) {
      File('$root/${UserMaterialsDemo.bundlePath}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
