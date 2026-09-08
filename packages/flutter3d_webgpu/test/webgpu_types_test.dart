/// The seam between the shader library's reflection and the browser's
/// descriptors.
///
///     flutter test --platform chrome test/webgpu_types_test.dart
///
/// **This file exists because of what a lost stage flag looks like.**
/// `webgpu_shaders.dart` states, for every binding of a stage pair, which of the
/// two stages declared it; `webgpu_types.dart` turns that pair of booleans into
/// the `GPUShaderStage` word a `GPUBindGroupLayoutEntry` wants. That is the one
/// line the library gives up by refusing to import a browser binding, and it is
/// the whole of the contract between the two halves.
///
/// A word dropped there does not throw and does not draw wrong. A bind group
/// layout that claims a fragment stage's texture is vertex-only is a perfectly
/// legal layout; the complaint arrives at `createRenderPipeline`, which accepts
/// the descriptor, hands back an object marked invalid, and lets every pass that
/// sets it draw nothing at all. What a test then sees is a black readback,
/// indistinguishable from a texture that never uploaded — which is how one
/// constant here once cost fifteen checks across two files, none of which said
/// the word "visibility".
///
/// So the flag word is asked for directly, and asked again of a whole stage
/// pair, in a file that needs no GPU: a browser without WebGPU runs all of it.
@TestOn('browser')
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_interop.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// A compiler that makes no module, because none of this needs one.
///
/// `createWebGpuPipeline` carries whatever a library handed it straight into the
/// pipeline and only the encoder ever casts it, so a stage pair's group shapes
/// can be built and read with no adapter in the browser at all.
final class _NoModules implements WgslModuleCompiler {
  @override
  Object compileModule(String name, String wgsl) => name;
}

WebGpuBlock _block(String name, int group, int binding) => WebGpuBlock(
  name: name,
  group: group,
  binding: binding,
  sizeInBytes: 16,
  members: const <WebGpuBlockMember>[
    WebGpuBlockMember(name: 'value', offsetInBytes: 0, sizeInBytes: 16),
  ],
);

WebGpuSampler _sampler(String name, int group, int texture) => WebGpuSampler(
  name: name,
  group: group,
  textureBinding: texture,
  samplerBinding: texture + 1,
  dimension: WebGpuTextureDimension.twoDimensional,
);

/// Which stages [shape] says a binding belongs to, as the flag word the layout
/// entry would be given.
///
/// Read back out of the group shape rather than out of the layout, because a
/// `GPUBindGroupLayout` answers no question about itself: the browser takes the
/// entries and never gives them back. What can be held is the value on its way
/// in, which is the value that was lost.
Map<String, int> _stageFlagsOf(WebGpuGroupShape shape) => <String, int>{
  for (final bound in shape.blocks)
    bound.block.name: gpuShaderStageOf(bound.visibility),
  for (final bound in shape.samplers)
    bound.sampler.name: gpuShaderStageOf(bound.visibility),
};

void main() {
  group('a visibility record as a stage flag word', () {
    test('names every stage that declared the binding and no other', () {
      // The four cases in full, because the failure that made this file worth
      // writing was a translation that answered one of them for all four and
      // was still the right answer for the case anyone looked at first.
      expect(
        gpuShaderStageOf((vertex: true, fragment: false)),
        GpuShaderStage.vertex,
      );
      expect(
        gpuShaderStageOf((vertex: false, fragment: true)),
        GpuShaderStage.fragment,
        reason:
            'a texture only the fragment stage samples must say so, or the '
            'pipeline built over the layout is invalid and every pass that '
            'sets it draws nothing',
      );
      expect(
        gpuShaderStageOf((vertex: true, fragment: true)),
        GpuShaderStage.vertex | GpuShaderStage.fragment,
        reason:
            'FrameInfo is declared by both stages of every lit shader, and a '
            'layout that named one would be refused by the other\'s use of it',
      );
      expect(gpuShaderStageOf((vertex: false, fragment: false)), 0);
    });
  });

  group('a stage pair\'s group shapes', () {
    // A pair shaped like the engine's own: one block both stages declare, one
    // each stage declares alone, and a texture-and-sampler pair in the fragment
    // stage only. Every combination the translation has to tell apart appears
    // once, so a flag word that came from anywhere but the record fails here.
    final library = WebGpuShaderLibrary(_NoModules(), (
      vertex: <String, WebGpuStage>{
        'PairVertex': WebGpuStage(
          wgsl: 'vertex wgsl',
          attributes: const <WebGpuAttribute>[
            WebGpuAttribute(
              name: 'position',
              location: 0,
              format: VertexFormat.float32x2,
            ),
          ],
          blocks: <WebGpuBlock>[
            _block('FrameInfo', 0, 0),
            _block('Placement', 0, 1),
          ],
          samplers: const <WebGpuSampler>[],
        ),
      },
      fragment: <String, WebGpuStage>{
        'PairFragment': WebGpuStage(
          wgsl: 'fragment wgsl',
          attributes: const <WebGpuAttribute>[],
          blocks: <WebGpuBlock>[
            _block('FrameInfo', 0, 0),
            _block('Tint', 0, 2),
          ],
          samplers: <WebGpuSampler>[_sampler('palette', 0, 3)],
        ),
      },
    ));
    final pipeline =
        createWebGpuPipeline(
              library['PairVertex']!,
              library['PairFragment']!,
            ).backend
            as WebGpuPipeline;

    test('reach the layout naming the stages that declared them', () {
      expect(pipeline.groups, hasLength(1));
      expect(_stageFlagsOf(pipeline.groups.single), <String, int>{
        'FrameInfo': GpuShaderStage.vertex | GpuShaderStage.fragment,
        'Placement': GpuShaderStage.vertex,
        'Tint': GpuShaderStage.fragment,
        'palette': GpuShaderStage.fragment,
      });
    });
  });
}
