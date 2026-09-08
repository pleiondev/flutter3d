/// What the pipeline cache tells apart, asserted without a GPU.
///
/// **The signature is the one piece of this backend whose mistakes are
/// invisible in a picture.** A key that is too narrow does not fail: it hands
/// back a pipeline built for other state and the browser draws with it. Two
/// vertex layouts over one stage pair is the case `GraphicsDevice.createPipeline`
/// spells out — the second draw reads instance data as vertices — and a per-draw
/// wrong pipeline looks like a modelling bug, not like a cache bug.
///
/// So the cache is generic over the pipeline object and this file instantiates
/// it over `String`, counting how often the builder ran. A browser would answer
/// the same questions more slowly and less clearly: `device.pipelines.length`
/// says how many were built and never says which two states the map thought
/// were one.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// One buffer of interleaved position and normal, stepping per vertex — the
/// layout every unskinned mesh in the engine has.
const VertexLayoutSpec _perVertex = VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: 24,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
      InputAttribute(
        name: 'normal',
        format: VertexFormat.float32x3,
        offsetInBytes: 12,
      ),
    ],
  ),
]);

/// The same vertices with a second buffer of per-instance transforms — what
/// mesh particles bind, and the layout whose signature must differ from
/// [_perVertex]'s.
const VertexLayoutSpec _perInstance = VertexLayoutSpec(<BufferLayout>[
  BufferLayout(
    strideInBytes: 24,
    attributes: <InputAttribute>[
      InputAttribute(name: 'position', format: VertexFormat.float32x3),
      InputAttribute(
        name: 'normal',
        format: VertexFormat.float32x3,
        offsetInBytes: 12,
      ),
    ],
  ),
  BufferLayout(
    strideInBytes: 16,
    stepMode: VertexStepMode.instance,
    attributes: <InputAttribute>[
      InputAttribute(name: 'i_row0', format: VertexFormat.float32x4),
    ],
  ),
]);

WebGpuPipelineSignature _signature({
  String pipeline = 'MeshVertex+PbrFragment',
  VertexLayoutSpec layout = _perVertex,
  String topology = 'triangle-list',
  String? stripIndexFormat,
  String cullMode = 'back',
  String frontFace = 'ccw',
  String depthCompare = 'less',
  bool depthWrite = true,
  StencilState? stencilFront,
  StencilState? stencilBack,
  List<BlendState?> blends = const <BlendState?>[null],
  List<String> colorFormats = const <String>['rgba16float'],
  String? depthFormat = 'depth24plus-stencil8',
  int sampleCount = 1,
}) => WebGpuPipelineSignature(
  pipeline: pipeline,
  vertexLayout: webgpuVertexLayoutFingerprint(layout),
  topology: topology,
  stripIndexFormat: stripIndexFormat,
  cullMode: cullMode,
  frontFace: frontFace,
  depthCompare: depthCompare,
  depthWrite: depthWrite,
  stencil: webgpuStencilFingerprint(stencilFront, stencilBack),
  blends: blends,
  colorFormats: colorFormats,
  depthFormat: depthFormat,
  sampleCount: sampleCount,
);

void main() {
  group('the vertex layout fingerprint', () {
    test('is the same string for two equal layouts', () {
      expect(
        webgpuVertexLayoutFingerprint(_perVertex),
        webgpuVertexLayoutFingerprint(
          const VertexLayoutSpec(<BufferLayout>[
            BufferLayout(
              strideInBytes: 24,
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
          ]),
        ),
      );
    });

    test('separates a second buffer, a step mode, a stride and an offset', () {
      final seen = <String>{
        webgpuVertexLayoutFingerprint(_perVertex),
        webgpuVertexLayoutFingerprint(_perInstance),
        webgpuVertexLayoutFingerprint(
          const VertexLayoutSpec(<BufferLayout>[
            BufferLayout(
              strideInBytes: 24,
              stepMode: VertexStepMode.instance,
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
          ]),
        ),
        webgpuVertexLayoutFingerprint(
          const VertexLayoutSpec(<BufferLayout>[
            BufferLayout(
              strideInBytes: 32,
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
          ]),
        ),
        webgpuVertexLayoutFingerprint(
          const VertexLayoutSpec(<BufferLayout>[
            BufferLayout(
              strideInBytes: 24,
              attributes: <InputAttribute>[
                InputAttribute(
                  name: 'position',
                  format: VertexFormat.float32x3,
                ),
                InputAttribute(
                  name: 'normal',
                  format: VertexFormat.float32x3,
                  offsetInBytes: 16,
                ),
              ],
            ),
          ]),
        ),
      };
      expect(seen, hasLength(5));
    });
  });

  group('the stencil fingerprint', () {
    test('is null for a pass that never mentioned the stencil', () {
      expect(webgpuStencilFingerprint(null, null), isNull);
    });

    test('is null for the disabled state, which is the same thing', () {
      // A caller that turned the test on and then said `setStencil(disabled)`
      // must land on the pipeline the pass started with, not on a second one
      // that merely draws the same.
      expect(
        webgpuStencilFingerprint(StencilState.disabled, StencilState.disabled),
        isNull,
      );
    });

    test('separates a compare, an operation and a mask', () {
      final seen = <String?>{
        webgpuStencilFingerprint(
          const StencilState(compare: CompareFunction.equal),
          const StencilState(compare: CompareFunction.equal),
        ),
        webgpuStencilFingerprint(
          const StencilState(compare: CompareFunction.notEqual),
          const StencilState(compare: CompareFunction.notEqual),
        ),
        webgpuStencilFingerprint(
          const StencilState(
            compare: CompareFunction.equal,
            passOp: StencilOperation.setToReferenceValue,
          ),
          const StencilState(compare: CompareFunction.equal),
        ),
        webgpuStencilFingerprint(
          const StencilState(compare: CompareFunction.equal, writeMask: 0x0F),
          const StencilState(compare: CompareFunction.equal),
        ),
      };
      expect(seen, hasLength(4));
    });

    test('separates the two faces from each other', () {
      // WebGPU states front and back separately and has no way to say "as the
      // front", so a backend that folded the two together would build one
      // pipeline for a portal that marks on one face and tests on the other.
      expect(
        webgpuStencilFingerprint(
          const StencilState(compare: CompareFunction.equal),
          StencilState.disabled,
        ),
        isNot(
          webgpuStencilFingerprint(
            StencilState.disabled,
            const StencilState(compare: CompareFunction.equal),
          ),
        ),
      );
    });
  });

  group('the signature', () {
    test('is equal, and hashes equal, for two draws in the same state', () {
      expect(_signature(), _signature());
      expect(_signature().hashCode, _signature().hashCode);
    });

    test('separates two vertex layouts over one stage pair', () {
      // **The field the spike\'s ten-field key did not have.**
      // `GraphicsDevice.createPipeline` states the consequence outright: handing
      // the first pipeline back for the second is a draw that reads instance
      // data as vertices, which draws a picture rather than raising anything.
      //
      // Mutation: drop `vertexLayout` from `==` and from `hashCode`. These two
      // become one signature and the cache builds one pipeline for both.
      expect(_signature(), isNot(_signature(layout: _perInstance)));
    });

    test('separates a blend equation on the second attachment alone', () {
      // The thing this backend can do and the other three cannot: every colour
      // target carries its own equation, so two attachments blending
      // differently is two pipelines rather than a hint.
      expect(
        _signature(
          colorFormats: const <String>['rgba16float', 'rgba8unorm'],
          blends: const <BlendState?>[null, null],
        ),
        isNot(
          _signature(
            colorFormats: const <String>['rgba16float', 'rgba8unorm'],
            blends: const <BlendState?>[null, BlendState.additive],
          ),
        ),
      );
    });

    test('separates the stencil, which is pipeline state here', () {
      expect(
        _signature(),
        isNot(
          _signature(
            stencilFront: const StencilState(compare: CompareFunction.equal),
          ),
        ),
      );
    });

    test('separates the index width of a strip and ignores it for a list', () {
      // A strip settles its restart value when the pipeline is built; a list
      // does not care, so the same list draw with two index widths must not
      // cost two pipelines.
      expect(_signature(), _signature());
      expect(
        _signature(topology: 'triangle-strip', stripIndexFormat: 'uint16'),
        isNot(
          _signature(topology: 'triangle-strip', stripIndexFormat: 'uint32'),
        ),
      );
    });

    test('separates every other field WebGPU bakes in', () {
      final seen = <WebGpuPipelineSignature>{
        _signature(),
        _signature(pipeline: 'MeshVertex+UnlitFragment'),
        _signature(topology: 'line-list'),
        _signature(cullMode: 'none'),
        _signature(frontFace: 'cw'),
        _signature(depthCompare: 'always'),
        _signature(depthWrite: false),
        _signature(blends: const <BlendState?>[BlendState.alphaBlend]),
        _signature(colorFormats: const <String>['rgba8unorm']),
        _signature(depthFormat: null),
        _signature(sampleCount: 4),
      };
      expect(seen, hasLength(11));
    });
  });

  group('the cache', () {
    test('builds once for a repeated state and again for a new one', () {
      final cache = WebGpuPipelineCache<String>();
      var built = 0;
      String build() => 'pipeline ${built++}';

      expect(cache.get(_signature(), build), 'pipeline 0');
      expect(cache.get(_signature(), build), 'pipeline 0');
      expect(built, 1);
      expect(cache.length, 1);

      expect(cache.get(_signature(layout: _perInstance), build), 'pipeline 1');
      expect(built, 2);
      expect(cache.length, 2);
    });

    test('forgets everything when the device that owns it goes', () {
      final cache = WebGpuPipelineCache<String>()
        ..get(_signature(), () => 'one');
      expect(cache.length, 1);
      cache.clear();
      expect(cache.length, 0);
    });
  });
}
