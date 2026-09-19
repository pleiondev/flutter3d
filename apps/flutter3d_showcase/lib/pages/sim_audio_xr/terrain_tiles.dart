/// Ground cut into tiles, each buildable at several levels of detail, with a
/// skirt closing the seam between a fine tile and a coarse neighbour.
///
/// Quoted by `terrain_tiles.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class TerrainTilesDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'ground',
      baseColor: Vector4(0.5, 0.6, 0.4, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run() {
    // #region field
    // A gentle nine-by-nine slope, eight cells on a side.
    final heights = Float32List(9 * 9);
    for (var row = 0; row < 9; row++) {
      for (var col = 0; col < 9; col++) {
        heights[row * 9 + col] = (col + row) * 0.1;
      }
    }
    final field = Heightfield(
      columns: 9,
      rows: 9,
      cellSize: 1.0,
      heights: heights,
    );
    // #endregion field

    // #region tiles
    final tiles = HeightfieldTiles(field, tileCells: 4, levels: 2);
    final fine = tiles.build(0, 0, level: 0, material: 'ground');
    final coarse = tiles.build(0, 0, level: 1, material: 'ground');
    // #endregion tiles

    // #region lod
    final chooser = TileLevelChooser(nearest: 20.0, levels: 2);
    final near = chooser.choose(5.0, null);
    final far = chooser.choose(60.0, null);
    // #endregion lod

    return '${tiles.tilesX}x${tiles.tilesZ} tiles, skirt depth '
        '${tiles.skirtDepth.toStringAsFixed(3)} m\n'
        'the fine build has ${fine.positions.length ~/ 3} vertices, the '
        'coarse one has ${coarse.positions.length ~/ 3}\n'
        'a tile 5 m away chooses level $near, one 60 m away chooses level $far';
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ground marker was not drawn');
    }
    if (!_report.contains('chooses level 0') ||
        !_report.contains('chooses level 1')) {
      throw StateError(
        'a near tile should choose the fine level and a far '
        'one the coarse level',
      );
    }
  }
}
