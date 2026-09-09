/// A weights track reaching the mesh it is about, and the deltas reaching the
/// shader in the order it reads them.
///
/// **The two ends the morph work left open**, and they are separate questions.
/// A glTF weights channel used to be decoded and dropped, because
/// `AnimationTarget` is three setters and a fourth would break every
/// implementer of a published interface — so the player takes an optional
/// second list instead, index-aligned with the targets it already has. And the
/// deltas have to arrive in the texture the way `lib/morph.glsl` reads them,
/// which is a contract no compiler checks: three rows a target, positions
/// first, and a target that morphs nothing but positions leaving two rows of
/// zeros behind it.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what a weights track wrote, standing in for a mesh on screen.
final class _Sink implements MorphSink {
  List<double>? last;

  @override
  void setWeights(List<double> values) => last = List<double>.of(values);
}

/// A clip driving node [node]'s weights from all-nought to [to] over a second.
AnimationClip _weightsClip(int node, List<double> to) => AnimationClip(
  name: 'expression',
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: node,
      path: AnimationPath.weights,
      interpolation: AnimationInterpolation.linear,
      componentCount: to.length,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(<double>[
        for (var i = 0; i < to.length; i++) 0.0,
        ...to,
      ]),
    ),
  ],
);

const VertexLayout _layout = VertexLayout(<VertexAttribute>[
  VertexLayout.position,
  VertexLayout.normal,
  VertexLayout.tangent,
]);

MeshData _mesh(List<MorphTarget> targets) => MeshData(
  layout: _layout,
  vertices: Float32List(2 * _layout.floatsPerVertex),
  indices: Uint32List.fromList(<int>[0, 1, 0]),
  morphTargets: targets,
);

MorphTarget _target({
  required double dx,
  double? dNormal,
  double? dTangent,
  String? name,
}) => MorphTarget(
  vertexCount: 2,
  name: name,
  positions: Float32List.fromList(<double>[dx, 0, 0, dx, 0, 0]),
  normals: dNormal == null
      ? null
      : Float32List.fromList(<double>[0, dNormal, 0, 0, dNormal, 0]),
  tangents: dTangent == null
      ? null
      : Float32List.fromList(<double>[0, 0, dTangent, 0, 0, dTangent]),
);

void main() {
  group('a weights track', () {
    test('reaches the sink the caller wired for that node', () {
      final sink = _Sink();
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          _weightsClip(1, <double>[1.0, 0.5]),
        ],
        targets: <AnimationTarget?>[null, null],
        morphs: <MorphSink?>[null, sink],
      );
      player.play(0);
      player.seek(1.0);

      expect(sink.last, <double>[1.0, 0.5]);
    });

    test('and is interpolated on the way, not switched at the end', () {
      final sink = _Sink();
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          _weightsClip(0, <double>[1.0]),
        ],
        targets: <AnimationTarget?>[null],
        morphs: <MorphSink?>[sink],
      );
      player.play(0);
      player.seek(0.5);

      expect(sink.last!.first, closeTo(0.5, 1e-6));
    });

    test('goes nowhere when the caller wired nothing, and does not throw', () {
      // Which is every model that morphs nothing, and was every model until
      // now: the track is decoded and there is no sink, so the clip plays and
      // the mesh draws its base shape.
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          _weightsClip(0, <double>[1.0]),
        ],
        targets: <AnimationTarget?>[null],
      );
      player.play(0);
      expect(() => player.seek(1.0), returnsNormally);
    });

    test('to a node past the end of the list is ignored', () {
      final sink = _Sink();
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          _weightsClip(7, <double>[1.0]),
        ],
        targets: <AnimationTarget?>[null],
        morphs: <MorphSink?>[sink],
      );
      player.play(0);
      player.seek(1.0);

      expect(sink.last, isNull);
    });
  });

  group('the delta texture', () {
    test('is three rows a target, positions first', () {
      // The contract `lib/morph.glsl` reads and no compiler checks. Mutation:
      // swap the normal and tangent rows and every morphed model shades
      // itself with a tangent — a picture that is wrong in a way only a
      // golden would catch.
      final packed = MorphTexture.pack(
        _mesh(<MorphTarget>[_target(dx: 2.0, dNormal: 3.0, dTangent: 4.0)]),
      );

      expect(packed, isNotNull);
      expect(packed!.width, 2, reason: 'one column a vertex');
      expect(packed.height, 3, reason: 'three rows for one target');
      expect(packed.targetCount, 1);

      double texel(int row, int vertex, int component) =>
          packed.pixels[(row * packed.width + vertex) * 4 + component];

      expect(texel(0, 0, 0), 2.0, reason: 'position delta x');
      expect(texel(1, 0, 1), 3.0, reason: 'normal delta y');
      expect(texel(2, 0, 2), 4.0, reason: 'tangent delta z');
    });

    test('leaves zeros where a target carries no normals or tangents', () {
      // Which is most of them: an exporter that leaves normals out is making
      // a judgement, and the shader adding nothing is the same answer.
      final packed = MorphTexture.pack(_mesh(<MorphTarget>[_target(dx: 1.0)]))!;

      final normalRow = packed.pixels.sublist(
        packed.width * 4,
        packed.width * 4 * 2,
      );
      expect(normalRow.every((double v) => v == 0.0), isTrue);
    });

    test('stacks targets in the order the file had them', () {
      final packed = MorphTexture.pack(
        _mesh(<MorphTarget>[_target(dx: 1.0), _target(dx: 9.0)]),
      )!;

      expect(packed.height, 6, reason: 'two targets, three rows each');
      expect(packed.pixels[0], 1.0, reason: 'first target, first vertex');
      final second = (MorphTexture.rowsPerTarget * packed.width) * 4;
      expect(packed.pixels[second], 9.0, reason: 'second target');
    });

    test('packs up to the limit and says what it left out', () {
      // A model with more expressions than the shader can blend at once is a
      // face missing one, not a model that will not load.
      final mesh = _mesh(<MorphTarget>[
        for (var i = 0; i < 10; i++) _target(dx: i.toDouble()),
      ]);
      final packed = MorphTexture.pack(mesh, limit: 8)!;

      expect(packed.targetCount, 8);
      expect(packed.dropped(mesh), 2);
    });

    test('is nothing at all for a mesh with no targets', () {
      expect(MorphTexture.pack(_mesh(const <MorphTarget>[])), isNull);
    });
  });
}
