/// The material language's corpus through a backend's own compiler: the
/// null backend, written outside the engine against its published API,
/// is handed every construct of the versions it claims and answers with a
/// section naming every stage, and a material past the budget is refused
/// before any compiler is asked.
///
///     dart test test/data_plugin/material_compiler_corpus_test.dart
///
/// What CONTRACTS asks of a GPU backend's compiler ("A backend's material
/// compiler"): it accepts every construct of the versions it claims, or
/// refuses the whole material by name. The null compiler compiles nothing,
/// so what this holds is the engine's half: every stage of every version
/// reaches the compiler, and its section is what a device loads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_backend_null/flutter3d_backend_null.dart';
import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/compile.dart' show loadShaders;
import 'package:test/test.dart';

/// The null compiler, with what it was asked written down.
final class _Asked extends MaterialCompiler {
  final List<String> asked = <String>[];

  static const NullMaterialCompiler _null = NullMaterialCompiler();

  @override
  String get backend => _null.backend;

  @override
  String get bundleSection => _null.bundleSection;

  @override
  bool get compilesAtRunTime => _null.compilesAtRunTime;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    asked.add(request.name);
    return _null.compile(request);
  }
}

/// A material of version 2 with blocks and a texture of its own.
const String _ownBlocksAndTextures = '''
f3dmat 2
material Hair {
  uniform(Hair) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strand) float shift = 0.1;
  texture fur;
  light { return albedo * tint * nDotL; }
  fragment { return vec4(lit + sample(fur, uv).rgb * shift, alpha); }
}
''';

/// A full-screen stage of version 2.
const String _fullscreen = '''
f3dmat 2
fullscreen Tint {
  param float amount = 0.5;
  fragment { return vec4(sample(scene, uv).rgb * amount, 1.0); }
}
''';

/// A lit model with [textures] textures of its own.
String _fur(int textures) =>
    '''
f3dmat 3
material Fur {
${[for (var i = 0; i < textures; i++) '  texture fur$i;'].join('\n')}
  light { return albedo * nDotL; }
  fragment {
    return vec4(lit${[for (var i = 0; i < textures; i++) ' + sample(fur$i, uv).rgb'].join()}, alpha);
  }
}
''';

void main() {
  final engine = loadShaders().sources;
  final corpus = <String, String>{
    for (final path in <String>[
      'test/fixtures/v1/rim_glow.f3dmat',
      'test/fixtures/v2/rim_glow.f3dmat',
      'test/fixtures/v3/rim_glow.f3dmat',
      'test/fixtures/v3/tube_light.f3dmat',
    ])
      path: File(path).readAsStringSync(),
    'own blocks and textures': _ownBlocksAndTextures,
    'a full-screen stage': _fullscreen,
    'every texture of its own a lit model has': _fur(
      MaterialStageBudget.materialTextures,
    ),
  };

  for (final MapEntry(key: what, value: source) in corpus.entries) {
    test(
      '$what reaches the null compiler, and a device loads its section',
      () async {
        final compiler = _Asked();
        // Mutation: hand the compiler only the fragment stage, and the
        // vertex block's stages are missing from its section.
        final bundle = runtimeMaterialBundle(
          source,
          backend: NullDevice.name,
          from: what,
          engineSources: engine,
          compilers: MaterialCompilerRegistry(<MaterialCompiler>[compiler]),
        );
        expect(compiler.asked, <String>[bundle.name]);
        final section = bundle.section(nullSection)!;
        final names =
            (jsonDecode(
                      utf8.decode(
                        section.buffer.asUint8List(
                          section.offsetInBytes,
                          section.lengthInBytes,
                        ),
                      ),
                    )
                    as List<Object?>)
                .cast<String>();
        expect(names, <String>[
          for (final ShaderBundleStage stage in bundle.stages) stage.name,
        ]);
        final device = await NullDevice.open(width: 4, height: 4);
        final library = await device.loadShaders(bundle.encode());
        for (final name in names) {
          expect(library[name], isNotNull, reason: name);
        }
      },
    );
  }

  test('a material past the budget is refused before a compiler is asked', () {
    final compiler = _Asked();
    // Mutation: ask the compiler before counting, and a backend from
    // outside is handed a stage no WebGPU device can bind.
    expect(
      () => runtimeMaterialBundle(
        _fur(MaterialStageBudget.materialTextures + 5),
        backend: NullDevice.name,
        from: 'fur.f3dmat',
        engineSources: engine,
        compilers: MaterialCompilerRegistry(<MaterialCompiler>[compiler]),
      ),
      throwsA(
        isA<RuntimeShadersException>().having(
          (RuntimeShadersException e) => e.message,
          'message',
          allOf(contains('"Fur"'), contains('textures')),
        ),
      ),
    );
    expect(compiler.asked, isEmpty);
  });
}
