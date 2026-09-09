/// Blending a mesh towards the shapes it carries.
///
/// **Deltas, summed, from the base every time.** A face has to be able to smile
/// and blink at once, which is why targets are deltas rather than poses: adding
/// two of them composes and interpolating between two absolute shapes does not.
/// And the blend restarts from the base on every change rather than undoing the
/// last one, because deltas accumulate rounding and a face that has smiled a
/// thousand times would drift away from the shape it was modelled as.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';

/// Two vertices carrying position and normal, and nothing else.
const VertexLayout _layout = VertexLayout(<VertexAttribute>[
  VertexLayout.position,
  VertexLayout.normal,
]);

MeshData _mesh({List<MorphTarget> targets = const <MorphTarget>[]}) => MeshData(
  layout: _layout,
  vertices: Float32List.fromList(<double>[
    // position        normal
    0, 0, 0, /*        */ 0, 1, 0,
    1, 0, 0, /*        */ 0, 1, 0,
    0, 1, 0, /*        */ 0, 1, 0,
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2]),
  morphTargets: targets,
);

/// A target that moves every vertex by [dx] along X.
MorphTarget _slide(double dx, {String? name, double dNormalY = 0.0}) =>
    MorphTarget(
      vertexCount: 3,
      name: name,
      positions: Float32List.fromList(<double>[dx, 0, 0, dx, 0, 0, dx, 0, 0]),
      normals: dNormalY == 0.0
          ? null
          : Float32List.fromList(<double>[
              0, dNormalY, 0, //
              0, dNormalY, 0,
              0, dNormalY, 0,
            ]),
    );

double _positionX(MorphBlend blend, int vertex) =>
    blend.vertices[vertex * _layout.floatsPerVertex];

double _normalY(MorphBlend blend, int vertex) =>
    blend.vertices[vertex * _layout.floatsPerVertex + 4];

void main() {
  group('a mesh with no weights applied', () {
    test('draws exactly its base vertices', () {
      final blend = MorphBlend(_mesh(targets: <MorphTarget>[_slide(5.0)]));
      expect(blend.vertices, _mesh().vertices);
    });

    test('and a mesh with no targets at all is untouched by any weights', () {
      final blend = MorphBlend(_mesh());
      expect(blend.blend(<double>[1.0, 1.0]), isFalse);
      expect(blend.vertices, _mesh().vertices);
    });
  });

  group('one target', () {
    test('at full weight is the whole delta', () {
      final blend = MorphBlend(_mesh(targets: <MorphTarget>[_slide(2.0)]));
      expect(blend.blend(<double>[1.0]), isTrue);
      expect(_positionX(blend, 0), closeTo(2.0, 1e-6));
      expect(_positionX(blend, 1), closeTo(3.0, 1e-6));
    });

    test('at half weight is half of it', () {
      final blend = MorphBlend(_mesh(targets: <MorphTarget>[_slide(2.0)]));
      blend.blend(<double>[0.5]);
      expect(_positionX(blend, 0), closeTo(1.0, 1e-6));
    });

    test('and a normal delta moves the normal, not only the position', () {
      // Mutation: skip the normal branch. The position still moves and the
      // model still deforms, so only this catches a face that changes shape
      // and keeps its old shading.
      final blend = MorphBlend(
        _mesh(targets: <MorphTarget>[_slide(1.0, dNormalY: -0.5)]),
      );
      blend.blend(<double>[1.0]);
      expect(_normalY(blend, 0), closeTo(0.5, 1e-6));
    });
  });

  group('two targets', () {
    test('add, which is the whole reason they are deltas', () {
      // A smile and a blink at once. Poses would have to choose.
      final blend = MorphBlend(
        _mesh(targets: <MorphTarget>[_slide(2.0), _slide(10.0)]),
      );
      blend.blend(<double>[1.0, 0.5]);
      expect(_positionX(blend, 0), closeTo(7.0, 1e-6));
    });

    test('in either order give the same shape', () {
      final one = MorphBlend(
        _mesh(targets: <MorphTarget>[_slide(2.0), _slide(10.0)]),
      )..blend(<double>[0.25, 0.75]);
      final other = MorphBlend(
        _mesh(targets: <MorphTarget>[_slide(10.0), _slide(2.0)]),
      )..blend(<double>[0.75, 0.25]);

      expect(_positionX(one, 0), closeTo(_positionX(other, 0), 1e-9));
    });
  });

  group('going back', () {
    test('to nothing returns the base exactly', () {
      // Not nearly: the blend restarts from the base, so a face that has been
      // through a hundred expressions is the shape it was modelled as and not
      // a hundred roundings away from it.
      final blend = MorphBlend(_mesh(targets: <MorphTarget>[_slide(0.1)]));
      for (var i = 0; i < 100; i++) {
        blend.blend(<double>[i / 100.0]);
      }
      blend.blend(<double>[0.0]);
      expect(blend.vertices, _mesh().vertices);
    });
  });

  group('the work it skips', () {
    test('says no when the weights have not moved', () {
      final blend = MorphBlend(_mesh(targets: <MorphTarget>[_slide(1.0)]));
      expect(blend.blend(<double>[0.4]), isTrue);
      expect(blend.blend(<double>[0.4]), isFalse, reason: 'nothing changed');
      expect(blend.blend(<double>[0.41]), isTrue);
    });

    test('and a weight list shorter than the targets reads as nought', () {
      // A clip authored against a model with fewer shapes. Drawing the ones
      // that exist beats refusing the model.
      final blend = MorphBlend(
        _mesh(targets: <MorphTarget>[_slide(1.0), _slide(4.0)]),
      );
      blend.blend(<double>[1.0]);
      expect(_positionX(blend, 0), closeTo(1.0, 1e-6));
      expect(blend.appliedWeights, <double>[1.0, 0.0]);
    });
  });

  group('what a mesh refuses', () {
    test('a target that does not cover every vertex', () {
      // It would blend part of the model and leave the rest, which draws as
      // something torn in half rather than as an error anybody can read.
      expect(
        () => MeshData(
          layout: _layout,
          // Four vertices against a target that covers three.
          vertices: Float32List(6 * 4),
          indices: Uint32List.fromList(<int>[0, 1, 2]),
          morphTargets: <MorphTarget>[_slide(1.0)],
        ),
        throwsArgumentError,
      );
    });

    test(
      'and a target whose deltas are the wrong length for its own count',
      () {
        expect(
          () => MorphTarget(
            vertexCount: 3,
            positions: Float32List.fromList(<double>[1, 0, 0]),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
