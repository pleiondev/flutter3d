/// A plugin's lit model with a block and a texture of its own, compiled by
/// the real impellerc: Impeller binds both by name (D21), so the names the
/// slot table gives have to be the names the bundle carries.
///
///     dart test test/impeller_slots_test.dart
///
/// `flutter3d_impeller`'s `GpuPassEncoder.bindUniformBlock` asks flutter_gpu's
/// reflection for the block by its name and `bindTexture` for the sampler by
/// its name, which needs a GPU context no test has; what a test can hold is
/// the half before it, that impellerc compiled the stage with the block
/// `Strands` and the sampler `material_fur` in it, under those names. Here
/// rather than beside the encoder because this is the package that runs
/// impellerc, and the backend does not depend on it.
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:test/test.dart';

const String _hair = '''
f3dmat 2
material acme_sample_Hair {
  uniform float gloss = 0.5;
  uniform(Strands) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strands) float shift = 0.1;
  texture fur;

  light { return albedo * tint * nDotL; }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

void main() {
  test('impellerc keeps the material\'s own block and texture by name', () {
    final scratch = Directory.systemTemp.createTempSync('f3d_slots_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final MaterialCompilers located;
    try {
      located = MaterialCompilers.locate();
    } on MaterialBuildException catch (error) {
      markTestSkipped('no impellerc in this SDK: $error');
      return;
    }
    final bundle = compileMaterial(
      _hair,
      source: 'acme_sample/hair.f3dmat',
      engine: loadShaders(),
      // The Impeller section is the question; the WebGPU one is another
      // package's, and needs glslang and naga.
      compilers: MaterialCompilers(
        impellerc: located.impellerc,
        impellerIncludes: located.impellerIncludes,
        sdk: located.sdk,
      ),
      scratch: scratch,
    );
    final section = bundle.section(ShaderBundle.impellerSection)!;
    // The flatbuffer impellerc writes carries each slot's name as text.
    final text = latin1.decode(
      section.buffer.asUint8List(section.offsetInBytes, section.lengthInBytes),
    );
    // Mutation: emit the texture under its source name, `fur`, and the name
    // the renderer binds it by is not there.
    expect(text, contains('Strands'));
    expect(text, contains('MaterialParams'));
    expect(text, contains('material_fur'));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
