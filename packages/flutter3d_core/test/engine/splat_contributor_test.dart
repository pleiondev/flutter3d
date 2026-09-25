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

  group('N5: splats without sorting', () {
    FakePass encode(
      SplatContributor contributor, {
      required bool temporal,
      int frameIndex = 0,
      FramebufferOrigin origin = FramebufferOrigin.topLeft,
    }) {
      final pass = FakePass(
        const RenderPassDescriptor(colors: <ColorTarget>[]),
      );
      contributor.encode(
        ContributorFrame(
          encoder: pass,
          device: FakeBackend(framebufferOrigin: origin),
          services: _NoServices(),
          state: FramePassState(),
          settings: const RenderSettings(),
          width: 320,
          height: 200,
          view: RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 5.0)),
          viewProjection: vm.Matrix4.identity(),
          frameIndex: frameIndex,
          temporal: temporal,
        ),
      );
      return pass;
    }

    test('under a temporal resolve a cloud is hashed: depth written, '
        'unblended, never sorted', () {
      // Mutation: make `automatic` answer `false` — the draw goes back to the
      // blended, sorted state and all three expectations fail.
      final contributor = SplatContributor(_cloud(4));
      final pass = encode(contributor, temporal: true, frameIndex: 70);

      expect(pass.recordedOf<RecordedDepthWrite>().single.enabled, isTrue);
      expect(pass.recordedOf<RecordedBlend>().single.state, isNull);
      expect(contributor.quads.sorts, 0);
      // The frame's slice of the blue noise reaches the stage, which is what
      // turns the noise for the resolve to average: 70 wraps to 6 of 32.
      final hash = pass.recordedOf<RecordedUniformBlock>().singleWhere(
        (b) => b.block == 'SplatHashInfo',
      );
      expect(hash.members['frame']![0], 6.0);
      // The camera sits at z 5 looking down -z: the eye and the view axis
      // each splat measures its distance along.
      expect(hash.members['eye']!.sublist(0, 3), <double>[0.0, 0.0, 5.0]);
      expect(hash.members['forward']!.sublist(0, 3), <double>[0.0, 0.0, -1.0]);
      expect(
        pass.recordedOf<RecordedTexture>().map((t) => t.slot),
        contains('blue_noise_texture'),
      );
    });

    test('the hashed stage is told the rows where row zero is the bottom, '
        'and nought where it is the top', () {
      // Mutation: leave `frame[1]` at nought — WebGL2 reads the noise tile
      // upside down against every other backend, and the first expectation
      // fails.
      double rows(FramebufferOrigin origin) =>
          encode(SplatContributor(_cloud(4)), temporal: true, origin: origin)
              .recordedOf<RecordedUniformBlock>()
              .singleWhere((b) => b.block == 'SplatHashInfo')
              .members['frame']![1];

      expect(rows(FramebufferOrigin.bottomLeft), 200.0);
      expect(rows(FramebufferOrigin.topLeft), 0.0);
    });

    test('without one it sorts and blends exactly as before', () {
      final contributor = SplatContributor(_cloud(4));
      final pass = encode(contributor, temporal: false);

      expect(pass.recordedOf<RecordedDepthWrite>().single.enabled, isFalse);
      expect(
        pass.recordedOf<RecordedBlend>().single.state,
        BlendState.alphaBlend,
      );
      expect(contributor.quads.sorts, 1);
      expect(
        pass.recordedOf<RecordedUniformBlock>().map((b) => b.block),
        isNot(contains('SplatHashInfo')),
      );
    });

    test('an explicit choice outranks the temporal setting', () {
      final sorted = SplatContributor(
        _cloud(4),
        composite: SplatComposite.sorted,
      );
      expect(
        encode(
          sorted,
          temporal: true,
        ).recordedOf<RecordedDepthWrite>().single.enabled,
        isFalse,
      );

      final hashed = SplatContributor(
        _cloud(4),
        composite: SplatComposite.hashed,
      );
      expect(
        encode(
          hashed,
          temporal: false,
        ).recordedOf<RecordedDepthWrite>().single.enabled,
        isTrue,
      );
      expect(hashed.quads.sorts, 0);
    });
  });

  test('unsorted quads come out in the cloud order', () {
    // The first splat's first corner leads the buffer when nothing sorts. The
    // eye sits on the first splat's side, so a sort — furthest first — would
    // have led with the last splat (x 0.6) and ended with the first.
    final quads = SplatQuads(_cloud(3))
      ..build(
        eye: vm.Vector3(-5.0, 0.0, 0.0),
        right: vm.Vector3(0.0, 0.0, 1.0),
        up: vm.Vector3(0.0, 1.0, 0.0),
        sorted: false,
      );
    expect(quads.sorts, 0);
    final lastCorner = (quads.vertexCount - 1) * kSplatFloatsPerVertex;
    expect(quads.vertices[lastCorner], closeTo(0.6, 1e-6));
    expect(quads.vertices[0], closeTo(0.0, 1e-6));
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
