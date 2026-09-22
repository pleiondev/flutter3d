/// The splat contributor, drawn against a fake pass — `gfx-80n`.
///
/// `flutter3d/test/splat_render_test.dart` proves the picture, through the
/// software rasteriser. The software rasteriser also tolerates a draw with
/// no index buffer bound, which is what let `SplatContributor.encode` go a
/// whole release binding vertices and never an index buffer while every
/// picture-based test still passed — `flutter3d_webgpu`'s own encoder does
/// not tolerate it, and the failure only ever showed up there, as "a draw
/// with no index buffer bound; every draw in this engine is indexed". This
/// checks the wiring a picture cannot show on the backend that tolerates
/// its absence.
///
///     dart test test/engine/splat_contributor_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

SplatCloud _cloud(int count) {
  final centres = Float32List(count * 3);
  final colours = Float32List(count * 4);
  final scales = Float32List(count * 3);
  final rotations = Float32List(count * 4);
  for (var i = 0; i < count; i++) {
    centres[i * 3] = i * 0.3;
    colours[i * 4 + 3] = 1.0;
    scales[i * 3] = 0.2;
    scales[i * 3 + 1] = 0.2;
    scales[i * 3 + 2] = 0.2;
    rotations[i * 4 + 3] = 1.0;
  }
  return SplatCloud(
    centres: centres,
    colours: colours,
    scales: scales,
    rotations: rotations,
  );
}

void main() {
  test('binds an index buffer, since this engine has no unindexed draw', () {
    // Mutation: drop the `bindIndexBuffer` call from `SplatContributor.
    // encode` — the fake pass records no `RecordedIndices` at all and the
    // `.single` below throws where the real WebGPU encoder throws instead.
    final device = FakeBackend();
    final pass = FakePass(const RenderPassDescriptor(colors: <ColorTarget>[]));
    final contributor = SplatContributor(_cloud(3));

    contributor.encode(
      ContributorFrame(
        encoder: pass,
        device: device,
        services: _NoServices(),
        state: FramePassState(),
        settings: const RenderSettings(),
        width: 320,
        height: 200,
        view: RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 5.0)),
        viewProjection: vm.Matrix4.identity(),
      ),
    );

    final vertices = pass.recordedOf<RecordedVertices>().single;
    final indices = pass.recordedOf<RecordedIndices>().single;
    expect(
      indices.count,
      vertices.count,
      reason: 'the identity sequence names exactly one index per vertex',
    );
    expect(indices.type, IndexType.int32);
  });
}

final class _NoServices implements RenderServices {
  @override
  void encodeScene({
    required NodeFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  }) => throw UnimplementedError();

  @override
  void drawFullscreen(FullscreenDraw draw) => throw UnimplementedError();
}
