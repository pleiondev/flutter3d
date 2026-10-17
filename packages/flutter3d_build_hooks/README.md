# flutter3d_build_hooks

What a package's own build hook needs to compile its flutter3d materials, and nothing else.

A material written in the material language (`*.f3dmat`) is compiled ahead of time into one shader bundle that every GPU backend loads: `impellerc`'s output for Impeller, GLSL ES 3.00 for WebGL2, and WGSL for WebGPU when glslangValidator and naga are on `PATH`. A build hook runs for every application that depends on its package, so whatever the hook imports is resolved into every game. That is why this is a package of its own: [`flutter3d_build`](https://pub.dev/packages/flutter3d_build) is the converter and the `flutter3d` command, and brings the MCP servers with it; a hook that compiles one material needs none of that.

| Name | What it is |
| --- | --- |
| `compileMaterial` | One material source as a `ShaderBundle`, compiled for every backend the compilers can serve |
| `MaterialCompilers` | The programs a build runs; `locate()` finds them in the Flutter SDK running the hook |
| `generateMaterialAccessors` | The typed accessors a package commits beside its materials |
| `MaterialBuildException` | A material that did not build, with the source, line and column |

`flutter3d_build` exports all four, so a project whose hook already depends on it sees the same names.

## Example

```dart
// hook/build.dart
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    final root = Directory.fromUri(input.packageRoot);
    final source = File('${root.path}/assets_src/water.f3dmat');
    final scratch = Directory.systemTemp.createTempSync('f3dmat');
    try {
      final bundle = compileMaterial(
        source.readAsStringSync(),
        source: source.path,
        engine: loadShaders(from: root.path),
        compilers: MaterialCompilers.locate(),
        scratch: scratch,
      );
      File('${root.path}/assets/water.f3dshaders')
          .writeAsBytesSync(bundle.encode().buffer.asUint8List());
    } on MaterialBuildException catch (error) {
      throw BuildError(message: '$error');
    } finally {
      scratch.deleteSync(recursive: true);
    }
    output.dependencies.add(source.absolute.uri);
  });
}
```
