/// A bundle arriving as bytes, and arriving again.
///
/// Runs on both platforms for the reason `webgpu_shaders_test.dart` gives:
/// refusing a bundle, keeping a handle's identity across a reload and leaving
/// the old code in place when the new one will not compile are all decisions
/// made before anything touches a GPU.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_loaded_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Module {
  const _Module(this.wgsl, this.serial);

  final String wgsl;
  final int serial;
}

final class _Compiler implements WgslModuleCompiler {
  final List<String> compiled = <String>[];
  final Set<String> rejected = <String>{};

  @override
  Object compileModule(String name, String wgsl) {
    compiled.add(name);
    if (rejected.contains(name)) {
      throw StateError('the "$name" shader did not compile: fake');
    }
    return _Module(wgsl, compiled.length);
  }
}

WebGpuStage _stage(String wgsl) => WebGpuStage(
  wgsl: wgsl,
  attributes: const <WebGpuAttribute>[
    WebGpuAttribute(
      name: 'position',
      location: 0,
      format: VertexFormat.float32x3,
    ),
  ],
  blocks: const <WebGpuBlock>[],
  samplers: const <WebGpuSampler>[],
);

/// A bundle whose fourth section holds [vertex] and [fragment].
///
/// [version] is written into the section document when it is given, and left
/// out when it is not — which is the shape the codec writes today and the shape
/// this backend reads as version one.
ByteData _bundle({
  String name = 'materials',
  Map<String, String> vertex = const <String, String>{},
  Map<String, String> fragment = const <String, String>{},
  Iterable<String>? claims,
  int? version,
  ByteData? section,
}) {
  final written =
      section ??
      _withVersion(
        encodeWebGpuSection(
          vertex: <String, WebGpuStage>{
            for (final entry in vertex.entries) entry.key: _stage(entry.value),
          },
          fragment: <String, WebGpuStage>{
            for (final entry in fragment.entries)
              entry.key: _stage(entry.value),
          },
        ),
        version,
      );
  return ShaderBundle(
    name: name,
    sdk: '',
    stages: <ShaderBundleStage>[
      for (final stage in claims ?? <String>[...vertex.keys, ...fragment.keys])
        ShaderBundleStage(stage, fragment: fragment.containsKey(stage)),
    ],
    sections: <String, ByteData>{ShaderBundle.webgpuSection: written},
  ).encode();
}

ByteData _withVersion(ByteData section, int? version) {
  if (version == null) return section;
  final document =
      jsonDecode(
            utf8.decode(
              section.buffer.asUint8List(
                section.offsetInBytes,
                section.lengthInBytes,
              ),
            ),
          )
          as Map<String, dynamic>;
  return Uint8List.fromList(
    utf8.encode(jsonEncode(<String, Object?>{'version': version, ...document})),
  ).buffer.asByteData();
}

ByteData _bytes(List<int> raw) => Uint8List.fromList(raw).buffer.asByteData();

void main() {
  group('loading', () {
    test('answers the names the section carries', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      expect(library.name, 'materials');
      expect((library['MeshVertex']!.backend as WebGpuShader).stage.wgsl, 'v0');
      expect((library['Pbr']!.backend as WebGpuShader).isVertex, isFalse);
      expect(library['Composite'], isNull);
      expect(library.debugTrackedModuleCount, 2);
    });

    test('compiles a stage only when it is asked for', () {
      final compiler = _Compiler();
      WebGpuLoadedShaderLibrary.load(
        compiler,
        _bundle(vertex: <String, String>{'MeshVertex': 'v0'}),
      );
      expect(compiler.compiled, isEmpty);
    });

    test('refuses a bundle with no section for this backend, by name', () {
      expect(
        () => WebGpuLoadedShaderLibrary.load(
          _Compiler(),
          const ShaderBundle(
            name: 'no-webgpu',
            sdk: '',
            stages: <ShaderBundleStage>[],
          ).encode(),
        ),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((ShaderBundleRefused r) => r.name, 'name', 'no-webgpu')
              .having(
                (ShaderBundleRefused r) => r.reason,
                'reason',
                contains('has no "webgpu" section'),
              ),
        ),
      );
    });

    test('refuses a section that is not the document, by name', () {
      expect(
        () => WebGpuLoadedShaderLibrary.load(
          _Compiler(),
          _bundle(section: _bytes(utf8.encode('{"vertex": 7}'))),
        ),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((ShaderBundleRefused r) => r.name, 'name', 'materials')
              .having(
                (ShaderBundleRefused r) => r.reason,
                'reason',
                contains('is not the JSON document'),
              ),
        ),
      );
    });

    test('refuses bytes that are not a section at all, by name', () {
      expect(
        () => WebGpuLoadedShaderLibrary.load(
          _Compiler(),
          _bundle(section: _bytes(<int>[0xff, 0xfe, 0x00, 0x01])),
        ),
        throwsA(
          isA<ShaderBundleRefused>().having(
            (ShaderBundleRefused r) => r.name,
            'name',
            'materials',
          ),
        ),
      );
    });
  });

  group('the section says which shape it is', () {
    test('a document with no version is the shape that shipped', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(vertex: <String, String>{'MeshVertex': 'v0'}),
      );
      expect(library['MeshVertex'], isNotNull);
    });

    test('a document saying version one is read', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          version: WebGpuLoadedShaderLibrary.sectionVersion,
        ),
      );
      expect(library['MeshVertex'], isNotNull);
    });

    test('a shape this backend does not know is refused by name', () {
      expect(
        () => WebGpuLoadedShaderLibrary.load(
          _Compiler(),
          _bundle(vertex: <String, String>{'MeshVertex': 'v0'}, version: 2),
        ),
        throwsA(
          isA<ShaderBundleRefused>()
              .having((ShaderBundleRefused r) => r.name, 'name', 'materials')
              .having(
                (ShaderBundleRefused r) => r.reason,
                'reason',
                allOf(
                  contains('version 2'),
                  contains(
                    'reads version '
                    '${WebGpuLoadedShaderLibrary.sectionVersion}',
                  ),
                ),
              ),
        ),
      );
    });

    test('the container stays at the version three backends already read', () {
      // The lever the section's own version exists to avoid pulling: raising
      // `ShaderBundle.formatVersion` would refuse every bundle in existence to
      // Impeller, WebGL2 and the software rasteriser, none of which can see
      // this section at all.
      expect(ShaderBundle.formatVersion, 1);
      final refused = () {
        try {
          WebGpuLoadedShaderLibrary.load(
            _Compiler(),
            _bundle(vertex: <String, String>{'MeshVertex': 'v0'}, version: 9),
          );
        } on ShaderBundleRefused catch (error) {
          return error;
        }
        return null;
      }();
      expect(refused, isNotNull);
      expect(refused!.reason, contains('format version 1'));
    });

    test('a reload of an unknown shape leaves the library as it was', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(vertex: <String, String>{'MeshVertex': 'v0'}),
      );
      final handle = library['MeshVertex']!;
      expect(
        () => library.refresh(
          _bundle(vertex: <String, String>{'MeshVertex': 'v1'}, version: 2),
        ),
        throwsA(isA<ShaderBundleRefused>()),
      );
      expect(identical(library['MeshVertex'], handle), isTrue);
      expect((handle.backend as WebGpuShader).stage.wgsl, 'v0');
    });
  });

  group('reloading', () {
    test('replaces the code behind a handle already handed out', () {
      final compiler = _Compiler();
      final library = WebGpuLoadedShaderLibrary.load(
        compiler,
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      final handle = library['MeshVertex']!;
      final before = (handle.backend as WebGpuShader).module as _Module;

      library.refresh(
        _bundle(
          name: 'materials-2',
          vertex: <String, String>{'MeshVertex': 'v1'},
          fragment: <String, String>{'Pbr': 'f1'},
        ),
      );

      expect(identical(library['MeshVertex'], handle), isTrue);
      final after = handle.backend as WebGpuShader;
      expect(after.stage.wgsl, 'v1');
      expect((after.module as _Module).wgsl, 'v1');
      expect((after.module as _Module).serial, greaterThan(before.serial));
      expect(library.name, 'materials-2');
      // `Pbr` was never asked for, so nothing recompiled it.
      expect(compiler.compiled, <String>['MeshVertex', 'MeshVertex']);
    });

    test('a pipeline built before the reload keeps the code it was built '
        'from', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      final pipeline =
          createWebGpuPipeline(library['MeshVertex']!, library['Pbr']!).backend
              as WebGpuPipeline;
      library.refresh(
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v1'},
          fragment: <String, String>{'Pbr': 'f1'},
        ),
      );
      // The frame between a refresh and `Renderer.relinkShaders` is the old
      // picture, not a missing one.
      expect((pipeline.vertexModule as _Module).wgsl, 'v0');
      expect((library['MeshVertex']!.backend as WebGpuShader).stage.wgsl, 'v1');
    });

    test('a name answered null before may arrive with the new bundle', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(vertex: <String, String>{'MeshVertex': 'v0'}),
      );
      expect(library['Sky'], isNull);
      library.refresh(
        _bundle(vertex: <String, String>{'MeshVertex': 'v1', 'Sky': 's0'}),
      );
      expect((library['Sky']!.backend as WebGpuShader).stage.wgsl, 's0');
    });

    test('refuses a bundle that dropped a stage in use, naming it', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      final handle = library['Pbr']!;
      expect(
        () => library.refresh(
          _bundle(vertex: <String, String>{'MeshVertex': 'v1'}),
        ),
        throwsA(
          isA<ShaderBundleRefused>().having(
            (ShaderBundleRefused r) => r.reason,
            'reason',
            allOf(contains('fragment stage "Pbr"'), contains('already in use')),
          ),
        ),
      );
      expect((handle.backend as WebGpuShader).stage.wgsl, 'f0');
      expect(library.name, 'materials');
    });

    test('refuses a bundle whose header no longer claims a stage in use', () {
      // The section still has the text; the header does not claim it. The other
      // backends hold a refresh to what the header says, and so does this one.
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(vertex: <String, String>{'MeshVertex': 'v0'}),
      );
      expect(library['MeshVertex'], isNotNull);
      expect(
        () => library.refresh(
          _bundle(
            vertex: <String, String>{'MeshVertex': 'v1'},
            claims: const <String>[],
          ),
        ),
        throwsA(
          isA<ShaderBundleRefused>().having(
            (ShaderBundleRefused r) => r.reason,
            'reason',
            contains('MeshVertex'),
          ),
        ),
      );
    });

    test('compiles everything before it swaps anything', () {
      final compiler = _Compiler();
      final library = WebGpuLoadedShaderLibrary.load(
        compiler,
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      final vertex = library['MeshVertex']!.backend as WebGpuShader;
      final fragment = library['Pbr']!.backend as WebGpuShader;

      compiler.rejected.add('Pbr');
      expect(
        () => library.refresh(
          _bundle(
            vertex: <String, String>{'MeshVertex': 'v1'},
            fragment: <String, String>{'Pbr': 'f1'},
          ),
        ),
        throwsA(
          isA<ShaderBundleRefused>().having(
            (ShaderBundleRefused r) => r.reason,
            'reason',
            contains('did not compile'),
          ),
        ),
      );
      // Neither half moved: an editor that rebuilt a bundle wrongly keeps the
      // picture it had rather than losing the stages that still work.
      expect(vertex.stage.wgsl, 'v0');
      expect(fragment.stage.wgsl, 'f0');
    });

    test('a stage nobody asked for may be dropped freely', () {
      final library = WebGpuLoadedShaderLibrary.load(
        _Compiler(),
        _bundle(
          vertex: <String, String>{'MeshVertex': 'v0'},
          fragment: <String, String>{'Pbr': 'f0'},
        ),
      );
      expect(library['MeshVertex'], isNotNull);
      library.refresh(_bundle(vertex: <String, String>{'MeshVertex': 'v1'}));
      expect(library['Pbr'], isNull);
    });
  });
}
