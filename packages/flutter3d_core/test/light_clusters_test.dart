/// The light clusters enter a light in the cells it reaches and in no
/// others — `L6`.
///
///     dart test test/light_clusters_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_core/src/engine/render/light_clusters.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

({LightClusters clusters, CameraNode camera}) _build(List<LightNode> lights) {
  final camera = CameraNode()
    ..setPosition(0.0, 1.0, 5.0)
    ..lookAt(Vector3(0.0, 1.0, 0.0));
  final table = LightBuffer()..gather(lights);
  final clusters = LightClusters()
    ..build(
      table,
      camera.viewProjection(16 / 9),
      near: camera.projection.near,
      far: camera.projection.far,
    );
  return (clusters: clusters, camera: camera);
}

LightNode _point(Vector3 at, double range) =>
    LightNode(type: LightType.point, range: range)
      ..setPosition(at.x, at.y, at.z);

Set<int> _cellsOf(LightClusters clusters, int light) => <int>{
  for (var c = 0; c < LightClusters.count; c++)
    if (clusters.lightsAt(c).contains(light)) c,
};

void main() {
  test('a light is in the cell it stands in, and not across the view', () {
    final it = _build(<LightNode>[
      _point(Vector3(-2.0, 1.0, 0.0), 0.5),
      _point(Vector3(2.0, 1.0, 0.0), 0.5),
    ]);
    final left = it.clusters.clusterOf(Vector3(-2.0, 1.0, 0.0));
    final right = it.clusters.clusterOf(Vector3(2.0, 1.0, 0.0));
    expect(left, isNot(right));
    // Mutation: enter every light in every cell. Each side has both.
    expect(it.clusters.lightsAt(left), <int>[0]);
    expect(it.clusters.lightsAt(right), <int>[1]);
  });

  test('its cells are the box its sphere covers, and few of the grid', () {
    final it = _build(<LightNode>[_point(Vector3(0.0, 1.0, 0.0), 1.0)]);
    final cells = _cellsOf(it.clusters, 0);
    // Every point of the sphere's surface lands in a listed cell.
    for (var i = 0; i < 64; i++) {
      final a = i * 0.39269908;
      for (final at in <Vector3>[
        Vector3(math.cos(a), 1.0 + math.sin(a), 0.0),
        Vector3(math.cos(a), 1.0, math.sin(a)),
        Vector3(0.0, 1.0 + math.cos(a), math.sin(a)),
      ]) {
        expect(cells, contains(it.clusters.clusterOf(at)));
      }
    }
    // Mutation: widen the box to the whole view. It would be every cell.
    expect(cells.length, lessThan(LightClusters.count ~/ 8));
  });

  test('behind the camera or off the side, a light is in no cell', () {
    final it = _build(<LightNode>[
      _point(Vector3(0.0, 1.0, 20.0), 1.0),
      _point(Vector3(60.0, 1.0, 0.0), 1.0),
    ]);
    expect(it.clusters.total, 0);
  });

  test('no range is every cell; a directional light is none', () {
    final it = _build(<LightNode>[
      _point(Vector3(0.0, 1.0, 0.0), 0.0),
      LightNode(),
    ]);
    expect(_cellsOf(it.clusters, 0).length, LightClusters.count);
    expect(_cellsOf(it.clusters, 1), isEmpty);
  });

  test('the payload is headers then entries, sixteen floats a row', () {
    final it = _build(<LightNode>[
      _point(Vector3(-2.0, 1.0, 0.0), 0.5),
      _point(Vector3(2.0, 1.0, 0.0), 0.5),
    ]);
    final out = Float32List(it.clusters.floats);
    it.clusters.write(out, 0);
    final cell = it.clusters.clusterOf(Vector3(2.0, 1.0, 0.0));
    final offset = out[cell * 4].toInt();
    expect(out[cell * 4 + 1], 1.0);
    expect(out[LightClusters.headerRows * 16 + offset], 1.0);
  });
}
