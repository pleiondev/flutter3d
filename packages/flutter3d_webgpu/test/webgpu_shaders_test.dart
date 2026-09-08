/// Name resolution and pipeline building, without a GPU.
///
/// Runs on both platforms, which is the point of the file it tests: everything
/// a shader library does apart from turning text into a module is arithmetic
/// over the sidecar, so it is asserted on the VM in a second rather than only
/// in a browser that has WebGPU. The one seam that needs a device is
/// `WgslModuleCompiler`, and here it is a counter.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

/// A module that is not a `GPUShaderModule`, so the library can be asked what
/// it compiled and how often.
final class _Module {
  const _Module(this.wgsl, this.serial);

  final String wgsl;

  /// Which compile made this one, so two modules from one text are still two.
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

WebGpuStage _stage(
  String wgsl, {
  List<WebGpuAttribute> attributes = const <WebGpuAttribute>[],
  List<WebGpuBlock> blocks = const <WebGpuBlock>[],
  List<WebGpuSampler> samplers = const <WebGpuSampler>[],
}) => WebGpuStage(
  wgsl: wgsl,
  attributes: attributes,
  blocks: blocks,
  samplers: samplers,
);

WebGpuBlock _block(String name, int group, int binding, int size) =>
    WebGpuBlock(
      name: name,
      group: group,
      binding: binding,
      sizeInBytes: size,
      members: <WebGpuBlockMember>[
        WebGpuBlockMember(name: 'mvp', offsetInBytes: 0, sizeInBytes: size),
      ],
    );

WebGpuSampler _sampler(String name, int group, int texture) => WebGpuSampler(
  name: name,
  group: group,
  textureBinding: texture,
  samplerBinding: texture + 1,
  dimension: WebGpuTextureDimension.twoDimensional,
);

void main() {
  final vertexStage = _stage(
    'vertex wgsl',
    attributes: const <WebGpuAttribute>[
      WebGpuAttribute(
        name: 'position',
        location: 0,
        format: VertexFormat.float32x3,
      ),
      WebGpuAttribute(
        name: 'texcoord',
        location: 1,
        format: VertexFormat.float32x2,
      ),
      WebGpuAttribute(
        name: 'i_offset',
        location: 2,
        format: VertexFormat.float32x4,
      ),
    ],
    blocks: <WebGpuBlock>[_block('FrameInfo', 0, 0, 64)],
    samplers: <WebGpuSampler>[_sampler('morph_texture', 0, 1)],
  );
  final fragmentStage = _stage(
    'fragment wgsl',
    blocks: <WebGpuBlock>[_block('FragInfo', 1, 0, 32)],
    samplers: <WebGpuSampler>[_sampler('base_color_texture', 1, 1)],
  );
  final sidecar = (
    vertex: <String, WebGpuStage>{'MeshVertex': vertexStage},
    fragment: <String, WebGpuStage>{'Pbr': fragmentStage},
  );

  group('a library over a sidecar', () {
    test('answers a name it has and refuses one it has not', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      final vertex = library['MeshVertex']!;
      expect(vertex.name, 'MeshVertex');
      final shader = vertex.backend as WebGpuShader;
      expect(shader.isVertex, isTrue);
      expect(shader.stage.wgsl, 'vertex wgsl');
      expect((library['Pbr']!.backend as WebGpuShader).isVertex, isFalse);
      expect(library['NoSuchStage'], isNull);
    });

    test('compiles a stage once however often it is asked for', () {
      final compiler = _Compiler();
      final library = WebGpuShaderLibrary(compiler, sidecar);
      final first = library['MeshVertex'];
      final second = library['MeshVertex'];
      expect(identical(first, second), isTrue);
      expect(compiler.compiled, <String>['MeshVertex']);
      expect(library.debugTrackedModuleCount, 1);
    });

    test('compiles nothing for a name the sidecar has not', () {
      final compiler = _Compiler();
      final library = WebGpuShaderLibrary(compiler, sidecar);
      expect(library['NoSuchStage'], isNull);
      expect(library['NoSuchStage'], isNull);
      expect(compiler.compiled, isEmpty);
      expect(library.debugTrackedModuleCount, 0);
    });

    test('does not cache a stage that failed to compile', () {
      final compiler = _Compiler()..rejected.add('MeshVertex');
      final library = WebGpuShaderLibrary(compiler, sidecar);
      expect(() => library['MeshVertex'], throwsStateError);
      expect(() => library['MeshVertex'], throwsStateError);
      expect(compiler.compiled, <String>['MeshVertex', 'MeshVertex']);
      expect(library.debugTrackedModuleCount, 0);
    });

    test('two libraries answering one name hold two modules', () {
      // The lesson `webgl_shaders.dart` learnt the expensive way, asked of the
      // shape rather than of a cache: a module lives on the handle, so a
      // library layered over another cannot be handed the other's code.
      final compiler = _Compiler();
      final engine = WebGpuShaderLibrary(compiler, sidecar);
      final application = WebGpuShaderLibrary(compiler, (
        vertex: <String, WebGpuStage>{
          'MeshVertex': _stage('the application\'s own vertex wgsl'),
        },
        fragment: <String, WebGpuStage>{},
      ));
      final layered = LayeredShaderLibrary(application, engine);
      final chosen = layered['MeshVertex']!.backend as WebGpuShader;
      expect(chosen.stage.wgsl, 'the application\'s own vertex wgsl');
      expect(
        (engine['MeshVertex']!.backend as WebGpuShader).stage.wgsl,
        'vertex wgsl',
      );
    });
  });

  group('a pipeline without a layout', () {
    test('interleaves the vertex stage\'s attributes in location order', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      final pipeline =
          createWebGpuPipeline(library['MeshVertex']!, library['Pbr']!).backend
              as WebGpuPipeline;
      expect(pipeline.buffers, hasLength(1));
      final buffer = pipeline.buffers.single;
      expect(buffer.stepMode, VertexStepMode.vertex);
      expect(buffer.strideInBytes, 12 + 8 + 16);
      expect(
        buffer.attributes.map((WebGpuVertexAttribute a) => a.name).toList(),
        <String>['position', 'texcoord', 'i_offset'],
      );
      expect(
        buffer.attributes
            .map((WebGpuVertexAttribute a) => a.offsetInBytes)
            .toList(),
        <int>[0, 12, 20],
      );
      expect(
        buffer.attributes
            .map((WebGpuVertexAttribute a) => a.shaderLocation)
            .toList(),
        <int>[0, 1, 2],
      );
    });

    test('orders by location and not by the order the table was written', () {
      final library = WebGpuShaderLibrary(_Compiler(), (
        vertex: <String, WebGpuStage>{
          'Shuffled': _stage(
            'wgsl',
            attributes: const <WebGpuAttribute>[
              WebGpuAttribute(
                name: 'second',
                location: 1,
                format: VertexFormat.float32x2,
              ),
              WebGpuAttribute(
                name: 'first',
                location: 0,
                format: VertexFormat.float32x3,
              ),
            ],
          ),
        },
        fragment: <String, WebGpuStage>{'Pbr': fragmentStage},
      ));
      final pipeline =
          createWebGpuPipeline(library['Shuffled']!, library['Pbr']!).backend
              as WebGpuPipeline;
      expect(
        pipeline.buffers.single.attributes
            .map((WebGpuVertexAttribute a) => a.name)
            .toList(),
        <String>['first', 'second'],
      );
      expect(
        pipeline.buffers.single.attributes
            .map((WebGpuVertexAttribute a) => a.offsetInBytes)
            .toList(),
        <int>[0, 12],
      );
    });

    test('carries the modules of both stages and their names', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      final handle = createWebGpuPipeline(
        library['MeshVertex']!,
        library['Pbr']!,
      );
      expect(handle.name, 'MeshVertex+Pbr');
      final pipeline = handle.backend as WebGpuPipeline;
      expect((pipeline.vertexModule as _Module).wgsl, 'vertex wgsl');
      expect((pipeline.fragmentModule as _Module).wgsl, 'fragment wgsl');
    });
  });

  group('a pipeline with a declared layout', () {
    final layout = const VertexLayoutSpec(<BufferLayout>[
      BufferLayout(
        strideInBytes: 32,
        attributes: <InputAttribute>[
          // Two components where the stage declares three, which WebGPU allows
          // and fills the rest of with zeros and a one. The disagreement is
          // deliberate: it is what makes "the layout describes the bytes"
          // something the test can tell apart from "the sidecar does".
          InputAttribute(name: 'position', format: VertexFormat.float32x2),
          InputAttribute(
            name: 'texcoord',
            format: VertexFormat.float32x2,
            offsetInBytes: 20,
          ),
        ],
      ),
      BufferLayout(
        strideInBytes: 16,
        stepMode: VertexStepMode.instance,
        attributes: <InputAttribute>[
          InputAttribute(name: 'i_offset', format: VertexFormat.float32x4),
        ],
      ),
    ]);

    test('takes locations from the sidecar and the rest from the layout', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      final pipeline =
          createWebGpuPipeline(
                library['MeshVertex']!,
                library['Pbr']!,
                layout: layout,
              ).backend
              as WebGpuPipeline;
      expect(pipeline.buffers, hasLength(2));

      final mesh = pipeline.buffers.first;
      expect(mesh.strideInBytes, 32);
      expect(mesh.stepMode, VertexStepMode.vertex);
      expect(
        mesh.attributes
            .map(
              (WebGpuVertexAttribute a) =>
                  '${a.name}@${a.shaderLocation}+${a.offsetInBytes}',
            )
            .toList(),
        <String>['position@0+0', 'texcoord@1+20'],
      );
      expect(mesh.attributes.first.format, VertexFormat.float32x2);
      expect(
        (library['MeshVertex']!.backend as WebGpuShader)
            .stage
            .attributes
            .first
            .format,
        VertexFormat.float32x3,
      );

      final instances = pipeline.buffers.last;
      expect(instances.stepMode, VertexStepMode.instance);
      expect(instances.strideInBytes, 16);
      expect(instances.attributes.single.shaderLocation, 2);
    });

    test('skips a name the stage does not declare', () {
      final library = WebGpuShaderLibrary(_Compiler(), (
        vertex: <String, WebGpuStage>{
          'Sparse': _stage(
            'wgsl',
            attributes: const <WebGpuAttribute>[
              WebGpuAttribute(
                name: 'position',
                location: 0,
                format: VertexFormat.float32x3,
              ),
            ],
          ),
        },
        fragment: <String, WebGpuStage>{'Pbr': fragmentStage},
      ));
      final pipeline =
          createWebGpuPipeline(
                library['Sparse']!,
                library['Pbr']!,
                layout: const VertexLayoutSpec(<BufferLayout>[
                  BufferLayout(
                    strideInBytes: 32,
                    attributes: <InputAttribute>[
                      InputAttribute(
                        name: 'position',
                        format: VertexFormat.float32x3,
                      ),
                      InputAttribute(
                        name: 'colour_the_compiler_dropped',
                        format: VertexFormat.float32x4,
                      ),
                    ],
                  ),
                ]),
              ).backend
              as WebGpuPipeline;
      expect(
        pipeline.buffers.single.attributes
            .map((WebGpuVertexAttribute a) => a.name)
            .toList(),
        <String>['position'],
      );
    });

    test('refuses a layout that feeds no buffer to an input', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      expect(
        () => createWebGpuPipeline(
          library['MeshVertex']!,
          library['Pbr']!,
          layout: const VertexLayoutSpec(<BufferLayout>[
            BufferLayout(
              strideInBytes: 12,
              attributes: <InputAttribute>[
                InputAttribute(
                  name: 'position',
                  format: VertexFormat.float32x3,
                ),
              ],
            ),
          ]),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(
              contains('MeshVertex'),
              contains('texcoord'),
              contains('i_offset'),
            ),
          ),
        ),
      );
    });
  });

  group('a pipeline refuses what it cannot pair', () {
    test('two stages the wrong way round', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      expect(
        () => createWebGpuPipeline(library['Pbr']!, library['MeshVertex']!),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(contains('vertex'), contains('Pbr')),
          ),
        ),
      );
    });

    test('a stage another backend compiled', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      expect(
        () => createWebGpuPipeline(
          const ShaderHandle(backend: 'not a WGSL module', name: 'Foreign'),
          library['Pbr']!,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Foreign'),
          ),
        ),
      );
    });
  });

  group('reflection over the pair', () {
    test('blocks and samplers of both stages answer by name', () {
      final library = WebGpuShaderLibrary(_Compiler(), sidecar);
      final pipeline =
          createWebGpuPipeline(library['MeshVertex']!, library['Pbr']!).backend
              as WebGpuPipeline;
      expect(
        pipeline.blocks.keys,
        unorderedEquals(<String>['FrameInfo', 'FragInfo']),
      );
      expect(pipeline.blocks['FrameInfo']!.group, 0);
      expect(pipeline.blocks['FragInfo']!.binding, 0);
      expect(
        pipeline.samplers.keys,
        unorderedEquals(<String>['morph_texture', 'base_color_texture']),
      );
      expect(pipeline.samplers['base_color_texture']!.samplerBinding, 2);
    });

    test('a block one name puts in two places is refused', () {
      // Not hypothetical: `VertexTextureProbeVertex` binds `ProbeInfo` at group
      // 0 and `ProbePrefilter` binds a block of that name at group 1. The
      // engine never pairs those two, so nothing draws wrong today — and a
      // backend that took the first of the two silently would draw wrong the
      // day something did.
      final library = WebGpuShaderLibrary(_Compiler(), engineShaders);
      expect(
        () => createWebGpuPipeline(
          library['VertexTextureProbeVertex']!,
          library['ProbePrefilter']!,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(contains('ProbeInfo'), contains('bound by name')),
          ),
        ),
      );
    });

    test('a sampler one name puts in two places is refused', () {
      final library = WebGpuShaderLibrary(_Compiler(), (
        vertex: <String, WebGpuStage>{
          'V': _stage('v', samplers: <WebGpuSampler>[_sampler('shared', 0, 1)]),
        },
        fragment: <String, WebGpuStage>{
          'F': _stage('f', samplers: <WebGpuSampler>[_sampler('shared', 1, 5)]),
        },
      ));
      expect(
        () => createWebGpuPipeline(library['V']!, library['F']!),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('shared'),
          ),
        ),
      );
    });

    test('a block both stages agree about merges to itself', () {
      final library = WebGpuShaderLibrary(_Compiler(), (
        vertex: <String, WebGpuStage>{
          'V': _stage('v', blocks: <WebGpuBlock>[_block('FogInfo', 1, 0, 48)]),
        },
        fragment: <String, WebGpuStage>{
          'F': _stage('f', blocks: <WebGpuBlock>[_block('FogInfo', 1, 0, 48)]),
        },
      ));
      final pipeline =
          createWebGpuPipeline(library['V']!, library['F']!).backend
              as WebGpuPipeline;
      expect(pipeline.blocks.keys, <String>['FogInfo']);
    });
  });

  group('the engine\'s own shaders', () {
    test('every stage the sidecar names compiles and knows its kind', () {
      final compiler = _Compiler();
      final library = WebGpuShaderLibrary(compiler, engineShaders);
      for (final name in engineShaders.vertex.keys) {
        expect((library[name]!.backend as WebGpuShader).isVertex, isTrue);
      }
      for (final name in engineShaders.fragment.keys) {
        expect((library[name]!.backend as WebGpuShader).isVertex, isFalse);
      }
      expect(
        library.debugTrackedModuleCount,
        engineShaders.vertex.length + engineShaders.fragment.length,
      );
    });

    test('the instanced layout the renderer declares resolves', () {
      // The five call sites that hand a layout in are the reason both paths
      // exist; this is the shape of the one in `renderer_resources.dart`.
      final library = WebGpuShaderLibrary(_Compiler(), engineShaders);
      final pipeline =
          createWebGpuPipeline(
                library['MeshInstancedVertex']!,
                library['Pbr']!,
                layout: VertexLayoutSpec(<BufferLayout>[
                  BufferLayout(
                    strideInBytes: 64,
                    attributes: <InputAttribute>[
                      for (final (String name, VertexFormat format, int at)
                          in const <(String, VertexFormat, int)>[
                            ('position', VertexFormat.float32x3, 0),
                            ('normal', VertexFormat.float32x3, 12),
                            ('texcoord', VertexFormat.float32x2, 24),
                            ('tangent', VertexFormat.float32x4, 32),
                            ('color', VertexFormat.float32x4, 48),
                          ])
                        InputAttribute(
                          name: name,
                          format: format,
                          offsetInBytes: at,
                        ),
                    ],
                  ),
                  const BufferLayout(
                    strideInBytes: 64,
                    stepMode: VertexStepMode.instance,
                    attributes: <InputAttribute>[
                      InputAttribute(
                        name: 'i_row0',
                        format: VertexFormat.float32x4,
                      ),
                      InputAttribute(
                        name: 'i_row1',
                        format: VertexFormat.float32x4,
                        offsetInBytes: 16,
                      ),
                      InputAttribute(
                        name: 'i_row2',
                        format: VertexFormat.float32x4,
                        offsetInBytes: 32,
                      ),
                      InputAttribute(
                        name: 'i_color',
                        format: VertexFormat.float32x4,
                        offsetInBytes: 48,
                      ),
                    ],
                  ),
                ]),
              ).backend
              as WebGpuPipeline;
      expect(pipeline.buffers.first.attributes, hasLength(5));
      expect(pipeline.buffers.last.stepMode, VertexStepMode.instance);
      expect(
        pipeline.buffers.last.attributes
            .map((WebGpuVertexAttribute a) => a.shaderLocation)
            .toList(),
        <int>[5, 6, 7, 8],
      );
    });

    test('the particle mesh layout resolves against its own stage', () {
      final library = WebGpuShaderLibrary(_Compiler(), engineShaders);
      final pipeline =
          createWebGpuPipeline(
                library['ParticleMeshVertex']!,
                library['ParticleMesh']!,
                layout: const VertexLayoutSpec(<BufferLayout>[
                  BufferLayout(
                    strideInBytes: 64,
                    attributes: <InputAttribute>[
                      InputAttribute(
                        name: 'position',
                        format: VertexFormat.float32x3,
                      ),
                      InputAttribute(
                        name: 'normal',
                        format: VertexFormat.float32x3,
                        offsetInBytes: 12,
                      ),
                    ],
                  ),
                  BufferLayout(
                    strideInBytes: 32,
                    stepMode: VertexStepMode.instance,
                    attributes: <InputAttribute>[
                      InputAttribute(
                        name: 'i_position',
                        format: VertexFormat.float32x3,
                      ),
                      InputAttribute(
                        name: 'i_color',
                        format: VertexFormat.float32x4,
                        offsetInBytes: 12,
                      ),
                      InputAttribute(
                        name: 'i_scale',
                        format: VertexFormat.float32,
                        offsetInBytes: 28,
                      ),
                    ],
                  ),
                ]),
              ).backend
              as WebGpuPipeline;
      expect(
        pipeline.buffers.last.attributes
            .map((WebGpuVertexAttribute a) => a.shaderLocation)
            .toList(),
        <int>[2, 3, 4],
      );
    });
  });
}
