/// Ground cut into tiles, each buildable at several levels of detail, with a
/// skirt closing the seam between a fine tile and a coarse neighbour.
///
/// Quoted by `terrain_tiles.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class TerrainTilesDemo extends ShowcaseDemo {
  late final String _report;

  double nearest = 8.0;
  bool moving = true;
  double eyeAngle = 0.0;

  late final HeightfieldTiles _tiles;
  late final MeshNode _eye;
  late final DemoContext _context;
  final List<MeshNode> _nodes = <MeshNode>[];
  final List<int?> _levels = <int?>[];
  late final List<Material> _paint;
  double _clock = 0.0;

  static const int _side = 33;
  static const int _tileCells = 8;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 42.0
      ..pitch = 0.95
      ..yaw = 0.0;
    context.orbit.target.setValues(16.0, 0.0, 16.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _context = context;

    // #region live
    // A hilly field of 32 by 32 cells, cut into sixteen tiles, each of which
    // can be drawn at three levels of detail. Which level is a question put
    // to the chooser, tile by tile, every time the eye moves.
    final Float32List heights = Float32List(_side * _side);
    for (var row = 0; row < _side; row++) {
      for (var col = 0; col < _side; col++) {
        heights[row * _side + col] =
            1.6 * math.sin(col * 0.28) * math.cos(row * 0.23) +
            0.35 * math.sin(col * 1.1 + row * 0.9);
      }
    }
    _tiles = HeightfieldTiles(
      Heightfield(columns: _side, rows: _side, cellSize: 1.0, heights: heights),
      tileCells: _tileCells,
      levels: 3,
    );
    // #endregion live

    // One colour a level, so the choice can be seen.
    _paint = <Material>[
      Material(name: 'fine', baseColor: Vector4(0.45, 0.75, 0.4, 1.0)),
      Material(name: 'middle', baseColor: Vector4(0.85, 0.8, 0.35, 1.0)),
      Material(name: 'coarse', baseColor: Vector4(0.85, 0.5, 0.35, 1.0)),
    ];
    for (var i = 0; i < _tiles.tilesX * _tiles.tilesZ; i++) {
      _levels.add(null);
      _nodes.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            MeshBuilder(VertexLayout.standard).build(),
          ),
          _paint[0],
          name: 'tile $i',
        ),
      );
    }
    _eye = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 16, radius: 0.6).build(),
      ),
      Material(name: 'eye', baseColor: Vector4(0.45, 0.65, 0.95, 1.0)),
      name: 'eye',
    );
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.35
      ..add(_eye);
    for (final MeshNode node in _nodes) {
      scene.add(node);
    }
    return scene..add(
      LightNode(name: 'sun', intensity: 2.6)
        ..setLocalForward(Vector3(-0.35, -1.0, -0.45)),
    );
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (moving) eyeAngle = _clock * 0.35;
    final double ex = 16.0 + 11.0 * math.cos(eyeAngle);
    final double ez = 16.0 + 11.0 * math.sin(eyeAngle);
    _eye.setPosition(ex, 2.5, ez);
    // #region choose
    // Rebuilt from the slider each frame; a tile only changes when the answer
    // does, and the band round each threshold keeps it from flickering.
    final TileLevelChooser chooser = TileLevelChooser(
      nearest: nearest,
      levels: 3,
    );
    // #endregion choose
    for (var tz = 0; tz < _tiles.tilesZ; tz++) {
      for (var tx = 0; tx < _tiles.tilesX; tx++) {
        final int i = tz * _tiles.tilesX + tx;
        final double dx = (tx + 0.5) * _tileCells - ex;
        final double dz = (tz + 0.5) * _tileCells - ez;
        // #region pick
        final int level = chooser.choose(
          math.sqrt(dx * dx + dz * dz),
          _levels[i],
        );
        // #endregion pick
        if (level == _levels[i]) continue;
        _levels[i] = level;
        final BrushSurface tile = _tiles.build(
          tx,
          tz,
          level: level,
          material: 'ground',
        );
        _nodes[i]
          ..mesh = DeviceMesh.upload(_context.device, _meshOf(tile))
          ..material = _paint[level];
      }
    }
  }

  MeshData _meshOf(BrushSurface tile) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    final Float32List p = tile.positions;
    final Float32List n = tile.normals;
    for (var v = 0; v < p.length ~/ 3; v++) {
      builder.addVertex(
        position: Vector3(p[3 * v], p[3 * v + 1], p[3 * v + 2]),
        normal: Vector3(n[3 * v], n[3 * v + 1], n[3 * v + 2]),
      );
    }
    for (var i = 0; i + 2 < tile.indices.length; i += 3) {
      builder.addTriangle(
        tile.indices[i],
        tile.indices[i + 1],
        tile.indices[i + 2],
      );
    }
    return builder.build();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Fine detail within',
      min: 4,
      max: 16,
      value: () => nearest,
      onChanged: (double v) => nearest = v,
      format: (double v) => '${v.toStringAsFixed(0)} m',
    ),
    ToggleControl(
      'Move the eye',
      value: () => moving,
      onChanged: (bool v) => moving = v,
    ),
    SliderControl(
      'Eye position',
      min: 0,
      max: 6.28,
      value: () => eyeAngle % 6.28,
      onChanged: (double v) {
        moving = false;
        eyeAngle = v;
      },
      format: (double v) => '${(v * 57.3).round()}°',
    ),
  ];

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
