// What the core hands back as more than one value is a class with named
// getters, not a record: a class can gain a field in a minor release, a
// record's shape cannot change without breaking every caller. Maths pairs
// (a size, a range, a jitter) stay records.
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a step of the playhead is a PlayheadStep', () {
    final step = advanceTime(
      time: 0.9,
      deltaSeconds: 0.2,
      length: 1.0,
      wrap: AnimationWrap.once,
      reversing: false,
    );
    expect(step, isA<PlayheadStep>());
    expect(step.time, 1.0);
    expect(step.stopped, isTrue);
    expect(step.reversing, isFalse);
  });

  test('a vertex fetch order is a VertexFetchOrder', () {
    final order = optimizeVertexFetch(Uint32List.fromList([2, 0, 1]), 3);
    expect(order, isA<VertexFetchOrder>());
    expect(order.indices, <int>[0, 1, 2]);
    expect(order.oldToNew, <int>[1, 2, 0]);
  });

  test('a ray through a mesh tree hits a TriangleHit', () {
    final mesh = const PlaneShape(width: 2, depth: 2).build();
    final hit = TriangleBvh.fromMesh(
      mesh,
    ).raycast(LocalRay(Vector3(0.1, 1.0, 0.2), Vector3(0.0, -1.0, 0.0)));
    expect(hit, isA<TriangleHit>());
    expect(hit!.distance, closeTo(1.0, 1e-9));
    expect(hit.point.y, closeTo(0.0, 1e-9));
  });

  test('a lens is a ThinLens', () {
    final lens = const DepthOfFieldSettings(
      focalLength: 0.05,
    ).lensFor(verticalFieldOfView: null, aspect: 1.0);
    expect(lens, const ThinLens(focalLength: 0.05, sensorWidth: 0.036));
  });

  test('a probe field packs into an IrradianceAtlas', () {
    final atlas = IrradianceField(
      origin: Vector3.zero(),
      spacing: Vector3.all(1.0),
      countX: 2,
      countY: 2,
      countZ: 2,
      tile: 4,
      depthTile: 4,
    ).toAtlas();
    expect(atlas, isA<IrradianceAtlas>());
    expect(atlas.texels.length, atlas.width * atlas.height * 4);
  });

  test('a photo works out PhotoPlan', () {
    final chosen = photoSettings(const RenderSettings(), PhotoFilter.none, 1.0);
    expect(chosen, isA<PhotoPlan>());
    expect(chosen.tile.renderScale, 1.0);
  });
}
