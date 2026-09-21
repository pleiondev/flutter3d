/// Where an agent can stand, baked once from the level's architecture into a
/// lattice a step can query in one array lookup.
///
/// Quoted by `nav_grid.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class NavGridDemo extends ShowcaseDemo {
  late final NavGrid _grid;

  bool sweeping = true;
  double _clock = 0.0;

  /// Where the probe is, in metres.
  final Vector2 _probe = Vector2(2.0, 2.0);

  @override
  Scene build(DemoContext context) {
    _grid = _bake();
    final material = Material(
      name: 'floor',
      baseColor: Vector4(0.5, 0.55, 0.6, 1.0),
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

  // #region brushes
  /// Two floor slabs joined by a narrow bridge, so most of the gap between
  /// them is not walkable but the bridge is.
  static List<Brush> _brushes() => <Brush>[
    Brush(centre: Vector3(2, 0, 2), size: Vector3(4, 1, 4)),
    Brush(centre: Vector3(5.5, 0, 3.5), size: Vector3(3, 1, 1)),
    Brush(centre: Vector3(9, 0, 2), size: Vector3(4, 1, 4)),
  ];
  // #endregion brushes

  // #region bake
  static NavGrid _bake() => NavGrid.bake(_brushes(), cellSize: 0.5);
  // #endregion bake

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (sweeping) {
      // Across both slabs and the gap between, and over the edge.
      _probe.setValues(
        5.5 + 5.5 * math.sin(_clock * 0.5),
        2.4 + 2.2 * math.sin(_clock * 0.83 + 1.0),
      );
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Sweep the probe',
      value: () => sweeping,
      onChanged: (bool v) => sweeping = v,
    ),
  ];

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    // #region live
    // Asking the baked grid about one point: which cell it falls in, and
    // whether an agent could stand there.
    final int cell = _grid.cellAtPoint(_probe.x, _probe.y);
    final bool walkable = _grid.isWalkable(cell);
    // #endregion live
    return ColoredBox(
      color: const Color(0xFF14161A),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'probe at (${_probe.x.toStringAsFixed(1)}, '
              '${_probe.y.toStringAsFixed(1)}): '
              '${walkable ? 'walkable' : 'not walkable'}. Tap the map to '
              'put it somewhere.',
              style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 15),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _grid.columns / _grid.rows,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints box) =>
                        GestureDetector(
                          onTapDown: (TapDownDetails d) {
                            sweeping = false;
                            _probe.setValues(
                              d.localPosition.dx /
                                  box.maxWidth *
                                  _grid.columns *
                                  _grid.cellSize,
                              d.localPosition.dy /
                                  box.maxHeight *
                                  _grid.rows *
                                  _grid.cellSize,
                            );
                          },
                          child: CustomPaint(
                            painter: _GridPainter(_grid, _probe, walkable),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the floor marker was not drawn');
    }
    // #region query
    final onFirstSlab = _grid.isWalkable(_grid.cellAtPoint(2.0, 2.0));
    final inTheGap = _grid.isWalkable(_grid.cellAtPoint(4.5, 0.5));
    final onBridge = _grid.isWalkable(_grid.cellAtPoint(5.0, 3.5));
    // #endregion query
    if (!onFirstSlab || inTheGap || !onBridge) {
      throw StateError(
        'the slabs and the bridge should be walkable and the open gap '
        'should not',
      );
    }
  }
}

/// Draws the grid from above: light for a walkable cell, dark for not.
final class _GridPainter extends CustomPainter {
  const _GridPainter(this.grid, this.probe, this.walkable);

  final NavGrid grid;
  final Vector2 probe;
  final bool walkable;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / grid.columns;
    final cellH = size.height / grid.rows;
    final paint = Paint();
    for (var index = 0; index < grid.cellCount; index++) {
      final cx = grid.cellX(index);
      final cz = grid.cellZ(index);
      paint.color = grid.isWalkable(index)
          ? const Color(0xFF7FB0FF)
          : const Color(0xFF2A2C33);
      canvas.drawRect(
        Rect.fromLTWH(cx * cellW, cz * cellH, cellW, cellH),
        paint,
      );
    }
    final Offset at = Offset(
      probe.x / grid.cellSize * cellW,
      probe.y / grid.cellSize * cellH,
    );
    canvas.drawCircle(
      at,
      cellW * 1.6,
      Paint()
        ..color = walkable ? const Color(0xFF6CE07C) : const Color(0xFFE5665A),
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
