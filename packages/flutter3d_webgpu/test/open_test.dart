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
  test('opens with the engine\'s stages, and six of them are refused', () async {
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

    // **A finding, held here so it cannot grow quietly.**
    //
    // Six of the engine's fragment stages produce WGSL this implementation
    // refuses, and every one of them refuses it for the same reason:
    // `'textureSample' must only be called from uniform control flow`. The
    // translated GLSL samples a texture inside an `if` whose condition comes
    // from a uniform block — a material flag — and WGSL requires the implicit
    // derivative a `textureSample` takes to be computed where every invocation
    // in the quad agrees to be. `textureSampleLevel` and `textureSampleGrad`
    // carry no such requirement, and hoisting the sample above the branch has
    // none either; which of the two the shaders want is a decision about the
    // GLSL and about `tool/generate_shaders.dart`, not about this backend.
    //
    // **naga accepts all six**, which is why the shader pipeline is green:
    // `--input-kind wgsl` round-trips every stage, and the uniformity rule is
    // one a browser applies and naga does not. That makes this the first check
    // in the repository that could have found it — a module compiles whether
    // or not the code was valid, and the failure otherwise arrives at the first
    // pipeline as "invalid due to a previous error", naming no line.
    //
    // The count is asserted rather than the absence, so that the day the
    // shaders are fixed this test fails and is tightened to `isNull` — and so
    // that a seventh stage acquiring the same fault is a red line rather than a
    // number nobody recounted.
    final said = await webgpu.debugDrainErrors('compiling the engine');
    expect(
      said,
      isNotNull,
      reason: 'six stages are known to be refused; see the note above',
    );
    for (final stage in const <String>[
      'Lambert',
      'BlinnPhong',
      'Pbr',
      'Toon',
      'Reflections',
      'Ssao',
    ]) {
      expect(said, contains('the WGSL of "$stage"'));
    }
    expect(
      RegExp('the WGSL of').allMatches(said!).length,
      6,
      reason: 'six and no more; a seventh is a new fault, not this one',
    );
    expect(
      RegExp('uniform control flow').allMatches(said).length,
      6,
      reason: 'all six are the same rule, and no other kind of refusal',
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
    await webgpu.debugDrainErrors('targets');

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
      webgpu.bindingsFor(pipeline.backend as WebGpuPipelineProgram);
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
