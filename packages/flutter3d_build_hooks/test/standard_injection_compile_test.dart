/// A material that injects into the engine's standard model — a surface
/// block, a light block reading `standard`, a plugin's light type in the
/// loop — compiled by the real compilers: `impellerc` for Impeller, glslang
/// and naga for WebGPU.
///
///     dart test test/standard_injection_compile_test.dart
///
/// What `flutter3d_core`'s `material_language_standard_test.dart` holds is
/// the text the language writes; what it cannot hold is that the text,
/// `lighting/pbr.frag` with the hooks switched on, is GLSL the backends
/// accept. Skipped where the SDK has no `impellerc`; the WebGPU half needs
/// glslang and naga on `PATH` beside it.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:test/test.dart';

const String _sheen = '''
f3dmat 3
material Sheen {
  lighting standard;
  uniform vec3 sheen = vec3(0.3);
  lighttype tube = acme.tube;

  surface {
    let worn = 0.5;
    out roughness = mix(roughness, 1.0, worn);
    out normal = normal + vec3(0.0, 0.1, 0.0);
  }

  light {
    return standard * (1.0 + tube) + sheen * pow(1.0 - nDotV, 5.0);
  }
}
''';

void main() {
  test('every injection point compiles on Impeller and on WebGPU', () {
    // Mutation: declare `StandardLight` after the model's `ShadeLight`
    // calls it, or define the light-type hook before `SampleLight` declares
    // it. The language still writes the same text, and no backend compiles
    // it.
    final MaterialCompilers located;
    try {
      located = MaterialCompilers.locate();
    } on MaterialBuildException catch (error) {
      markTestSkipped('no impellerc in this SDK: $error');
      return;
    }
    final scratch = Directory.systemTemp.createTempSync('f3d_inject_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final bundle = compileMaterial(
      _sheen,
      source: 'acme/sheen.f3dmat',
      engine: loadShaders(),
      compilers: located,
      scratch: scratch,
    );
    expect(bundle.section(ShaderBundle.impellerSection), isNotNull);
    if (located.wgsl != null) {
      expect(bundle.section(ShaderBundle.webgpuSection), isNotNull);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
