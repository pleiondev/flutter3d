/// Compiling the package's materials, `assets_src/*.f3dmat`, into the
/// bundles it ships, `assets/*.f3dshaders`: what the build hook runs on
/// every build of an application that depends on the package, and what
/// `tool/build_materials.dart` runs by hand.
library;

import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_shaders/compile.dart';

/// Compiles every material under [package]`/assets_src` into
/// [package]`/assets`; returns the sources, which the hook names as what it
/// depends on.
///
/// **Built rather than committed**, as the engine's own bundle is: a bundle
/// carries an `impellerc` section tied to the Flutter SDK that built it, so
/// one committed goes stale on the next upgrade with nothing to say so.
List<File> buildMaterialBundles(Directory package) {
  final sources = <File>[
    for (final entity in Directory('${package.path}/assets_src').listSync())
      if (entity is File && entity.path.endsWith('.f3dmat')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  final engine = loadShaders(from: package.path);
  final compilers = MaterialCompilers.locate();
  final scratch = Directory.systemTemp.createTempSync('f3dmat');
  try {
    Directory('${package.path}/assets').createSync(recursive: true);
    for (final file in sources) {
      final name = file.uri.pathSegments.last.replaceAll('.f3dmat', '');
      final bundle = compileMaterial(
        file.readAsStringSync(),
        source: file.path,
        engine: engine,
        compilers: compilers,
        scratch: scratch,
      );
      File(
        '${package.path}/assets/$name.f3dshaders',
      ).writeAsBytesSync(bundle.encode().buffer.asUint8List());
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
  return sources;
}
