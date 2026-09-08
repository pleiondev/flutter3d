/// `openWebGpu` against the engine's own stages, in a browser with a GPU.
///
///     flutter test --platform chrome test/open_test.dart
///
/// **The first time the generated WGSL meets a browser.**
/// `tool/generate_shaders.dart` holds every stage to `glslangValidator` and to
/// naga, and naga round-trips its own output — which says the text is WGSL, not
/// that this implementation will take it. A module compiles whether or not the
/// code was valid, so the only way to ask is to compile all thirty-nine and
/// then ask what the browser thought, which is what
/// `WebGpuDevice.debugDrainErrors` is for.
///
/// The pipelines are the second half of the same question. A `GPUPipelineLayout`
/// is built from the bundle's reflection alone — the group and binding numbers
/// the packer wrote — so a pipeline that validates is the reflection agreeing
/// with the code the browser parsed. That is the one check that would catch a
/// binding number the translator moved and the packer did not.
@TestOn('browser')
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pairs the renderer builds, one per kind of thing this engine draws: a lit
/// mesh, a skinned one, an instanced one, the full-screen chain, both skies and
/// the shadow pass.
const List<(String, String)> _pairs = <(String, String)>[
  ('MeshVertex', 'Pbr'),
  ('MeshVertex', 'Unlit'),
  ('MeshSkinnedVertex', 'Lambert'),
  ('MeshInstancedVertex', 'BlinnPhong'),
  ('MeshLightmappedVertex', 'Toon'),
  ('MeshVertex', 'ShadowDepth'),
  ('FullscreenVertex', 'Composite'),
  ('FullscreenVertex', 'BloomThreshold'),
  ('FullscreenVertex', 'Ssao'),
  ('SkyVertex', 'Sky'),
  ('SkyCubeVertex', 'SkyCube'),
  ('ParticleVertex', 'ParticleTextured'),
  ('DebugLineVertex', 'DebugLine'),
];

void main() {
  test('opens with the engine\'s stages, and none of them is refused', () async {
    final GraphicsDevice device;
    try {
      device = await openWebGpu(width: 64, height: 64);
    } on StateError {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    final webgpu = device as WebGpuDevice;

    // The conventions, which are what the whole port turns on: a top-left
    // framebuffer origin and a zero-to-one depth range mean the engine's
    // projections need no correction here, and there is no wireframe.
    expect(device.framebufferOrigin, FramebufferOrigin.topLeft);
    expect(device.depthRange, DepthRange.zeroToOne);
    expect(device.supportsWireframe, isFalse);
    expect(device.supportsBlendColor, isFalse);
    expect(device.supportsCubeTextures, isTrue);

    for (final (String vertex, String fragment) in _pairs) {
      expect(
        device.shaders[vertex],
        isNotNull,
        reason: 'the bundle must answer to $vertex',
      );
      expect(
        device.shaders[fragment],
        isNotNull,
        reason: 'the bundle must answer to $fragment',
      );
    }

    // Every stage, and not only the thirteen pairs above. The library compiles
    // on first use, so asking for a name is what sends its WGSL to the browser
    // — and the question this test exists to ask is what the browser makes of
    // all thirty-nine.
    for (final name in <String>[
      ...engineShaders.vertex.keys,
      ...engineShaders.fragment.keys,
    ]) {
      expect(
        device.shaders[name],
        isNotNull,
        reason: 'the sidecar holds $name, so the library must answer it',
      );
    }

    // **This assertion used to be the number six, and the number is gone.**
    //
    // Six fragment stages — Lambert, BlinnPhong, Pbr, Toon, Reflections and
    // Ssao — produced WGSL this implementation refused, every one of them with
    // `'textureSample' must only be called from uniform control flow`. Each
    // shader sampled a texture under a branch the four invocations of a quad
    // need not take together — a light the surface faces away from, a cascade
    // that does not contain the fragment, a ray that has already left the
    // frame, a tangent too degenerate to build a frame from — and WGSL will
    // only derive a mip level where the whole quad agrees to be. The GLSL now
    // asks for level zero by name wherever the texture is a single-level render
    // target, and hoists the sample above the branch where the mip chain is
    // real; `lib/shadow.glsl`, `lib/surface.glsl`, `lib/material_maps.glsl`,
    // `post/reflections.frag` and `post/ssao.frag` each say which and why.
    //
    // **naga accepted all six**, which is why the shader pipeline was green
    // while this stood: `--input-kind wgsl` round-trips every stage, and the
    // uniformity rule is one a browser applies and naga does not. That is what
    // this test is for, and why it asserts the absence rather than a count — a
    // module compiles whether or not the code was valid, and the failure
    // otherwise arrives at the first pipeline as "invalid due to a previous
    // error", naming no line. Any stage that reacquires the fault fails here.
    final said = await webgpu.debugDrainErrors('compiling the engine');
    expect(
      said,
      isNull,
      reason: 'every stage must compile; see the note above',
    );
    webgpu.dispose();
  });

  test('builds a pipeline for every pair the renderer asks for', () async {
    final GraphicsDevice device;
    try {
      device = await openWebGpu(width: 64, height: 64);
    } on StateError {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    final webgpu = device as WebGpuDevice;
    final colour = device.createTexture(
      RenderTargetSpec(width: 8, height: 8, format: device.hdrColorFormat),
    );
    final depth = device.createTexture(
      RenderTargetSpec(
        width: 8,
        height: 8,
        format: device.defaultDepthStencilFormat,
      ),
    );
    // Every stage this test pairs, compiled and its verdict drained before the
    // loop below asks about layouts. The library compiles on first use, so
    // without this the six stages the test above holds as a known finding would
    // arrive inside the first pair's drain and be read as a bad bind group
    // layout — a compile complaint reported against the wrong thing.
    for (final (String vertex, String fragment) in _pairs) {
      expect(device.shaders[vertex], isNotNull);
      expect(device.shaders[fragment], isNotNull);
    }
    await webgpu.debugDrainErrors('targets and the stages drawn with them');

    for (final (String vertex, String fragment) in _pairs) {
      final pipeline = device.createPipeline(
        device.shaders[vertex]!,
        device.shaders[fragment]!,
      );
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[ColorTarget(texture: colour)],
          depth: DepthTarget(texture: depth),
        ),
      )..bindPipeline(pipeline);
      // The pipeline is built at the draw rather than here — that is the whole
      // shape of this backend — so the pass is submitted without one and the
      // layouts alone are what the browser is asked about.
      pass.submit();
      // A pipeline with no bindings at all is legitimate and one pair here is
      // exactly that — the procedural sky takes its parameters through no
      // uniform block — so what is asserted is that the browser accepted the
      // layouts, not that there were any.
      webgpu.bindingsFor(pipeline.backend as WebGpuPipeline);
      expect(
        await webgpu.debugDrainErrors('$vertex+$fragment'),
        isNull,
        reason:
            'the bind group layouts come out of the bundle\'s reflection '
            'alone, so one the browser refuses is the reflection disagreeing '
            'with the WGSL beside it',
      );
    }
    webgpu.dispose();
  });
}
