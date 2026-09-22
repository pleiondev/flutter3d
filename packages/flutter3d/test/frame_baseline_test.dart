/// `gfx-01n`: what a frame costs, recorded, so a regression has to argue.
///
///     flutter test test/frame_baseline_test.dart
///
/// **With no numbers, every later renderer change is an impression.** That is
/// the plan row's own reason for putting this first, and this file is the
/// half of it that runs unattended: three fixtures drawn on the software
/// rasteriser, their draw calls and their per-pass breakdown written down.
/// A change that adds ten draw calls to a frame fails here by name, with the
/// pass that grew printed beside it, instead of turning up months later as
/// "the editor feels heavier than it did".
///
/// **Exact numbers, not a budget with slack in it.** A baseline that tolerates
/// nine extra draws is a baseline nobody keeps: the tenth arrives and the
/// number is already wrong by nine. Every one of these is deterministic —
/// same scene, same device, no GPU, no timing — so exactness costs nothing
/// and is the only version of this that stays true. A change that really does
/// need another draw edits the number here and says why in the commit, which
/// is the whole point.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two lit spheres and the composite's own full-screen triangle.
const int kPlainDrawCalls = 3;

/// One. Light count, light type and material values are uniforms, so a
/// second pipeline here means a permutation crept in where a uniform
/// belonged — see `FrameResult.pipelines`.
const int kPlainPipelines = 1;

/// Nine of these are the shadow map: three casters into three cascades.
///
/// **It read four until `gfx-01n` counted the passes.** The shadow pass drew
/// and reported nothing, so every measurement ever taken of this engine had
/// the cascade count for free. Three of the thirteen are the scene — the
/// floor arrived with the shadow — and one is the composite.
const int kDirectionalShadowDrawCalls = 13;

/// Nine of these are the bloom ladder: a threshold, four downsamples and
/// four upsamples. Three times what the scene itself costs, which is the
/// sort of thing worth knowing before enriching the post chain.
const int kBloomDrawCalls = 12;

CpuDevice _device() => CpuDevice(
  width: kParityWidth,
  height: kParityHeight,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Renderer _renderer(CpuDevice device) {
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
  )!;
  return Renderer.create(
    device: device,
    fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
    fallbackNormal: texel(<int>[128, 128, 255, 255]),
  );
}

FrameResult _draw(ParityScene which) {
  final device = _device();
  final renderer = _renderer(device);
  final built = buildParityScene(device, which: which);
  return renderer.render(
    width: kParityWidth,
    height: kParityHeight,
    scene: built.scene,
    views: <RenderView>[RenderView(camera: built.camera)],
    settings: paritySettingsFor(which),
  );
}

/// The pass list as one readable line, for a failure that has to say what
/// moved rather than only that something did.
String _breakdown(FrameResult frame) => frame.passes
    .map(
      (FramePass pass) =>
          '${pass.name}: ${pass.drawCalls} draws, ${pass.triangles} tri, '
          '${pass.pipelineSwitches} switches',
    )
    .join('\n  ');

void main() {
  group('the recorded cost of a frame', () {
    test('plain: two lit spheres and the composite', () {
      final frame = _draw(ParityScene.plain);
      expect(
        frame.drawCalls,
        kPlainDrawCalls,
        reason: 'the plain fixture changed cost:\n  ${_breakdown(frame)}',
      );
      expect(frame.pipelines, kPlainPipelines);
    });

    test('directionalShadow: the shadow pass is a pass of its own', () {
      final frame = _draw(ParityScene.directionalShadow);
      expect(
        frame.drawCalls,
        kDirectionalShadowDrawCalls,
        reason: 'the shadow fixture changed cost:\n  ${_breakdown(frame)}',
      );
    });

    test('bloom: the post chain is the expensive one and says so', () {
      final frame = _draw(ParityScene.bloom);
      expect(
        frame.drawCalls,
        kBloomDrawCalls,
        reason: 'the bloom fixture changed cost:\n  ${_breakdown(frame)}',
      );
    });
  });

  group('the breakdown is per pass, not one number', () {
    test('a frame names its passes and each one owns its draws', () {
      final frame = _draw(ParityScene.directionalShadow);

      expect(
        frame.passes,
        isNotEmpty,
        reason: 'a frame that reports no passes cannot be profiled at all',
      );
      // The whole point of `gfx-01n`: the parts add up to the total the
      // renderer already reported, so nothing is counted twice and nothing
      // draws outside a pass.
      expect(
        frame.passes.fold<int>(0, (int sum, FramePass p) => sum + p.drawCalls),
        frame.drawCalls,
      );
      expect(
        frame.passes.fold<int>(0, (int sum, FramePass p) => sum + p.triangles),
        frame.triangles,
      );
      expect(
        frame.passes.fold<int>(
          0,
          (int sum, FramePass p) => sum + p.pipelineSwitches,
        ),
        frame.pipelineSwitches,
      );
    });

    test('a scene with shadows shows the shadow pass separately', () {
      final withShadow = _draw(ParityScene.directionalShadow);
      final without = _draw(ParityScene.plain);

      final shadowNames = withShadow.passes.map((FramePass p) => p.name);
      expect(
        shadowNames.length,
        greaterThan(without.passes.length),
        reason:
            'shadows on and off gave the same pass list, so the breakdown is '
            'not describing the frame:\n  ${_breakdown(withShadow)}',
      );
      // And the extra passes are where the extra draws went, rather than
      // being folded into the scene's own number.
      expect(
        withShadow.passes
            .where(
              (FramePass p) =>
                  !without.passes.any((FramePass q) => q.name == p.name),
            )
            .fold<int>(0, (int sum, FramePass p) => sum + p.drawCalls),
        greaterThan(0),
      );
    });
  });
}
