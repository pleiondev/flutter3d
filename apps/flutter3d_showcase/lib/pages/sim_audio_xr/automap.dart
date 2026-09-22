/// The level as the player has seen it, from above: floor where they walked,
/// walls where the floor stopped, nothing where they have not been.
///
/// Quoted by `automap.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class AutomapDemo extends ShowcaseDemo {
  late final NavGrid _grid;
  late Automap _map;

  double speed = 3.0;
  bool _forgetAsked = false;
  final Vector3 _walker = Vector3(2.0, 0.0, 2.0);
  int _leg = 0;

  /// The walk: room, doorway, corridor, second room, and round again.
  static final List<Vector3> _route = <Vector3>[
    Vector3(2.0, 0.0, 2.0),
    Vector3(8.0, 0.0, 8.0),
    Vector3(5.0, 0.0, 5.0),
    Vector3(13.0, 0.0, 5.0),
    Vector3(20.0, 0.0, 3.0),
    Vector3(23.0, 0.0, 8.0),
    Vector3(20.0, 0.0, 5.0),
    Vector3(13.0, 0.0, 5.0),
  ];

  @override
  Scene build(DemoContext context) {
    // #region grid
    // Two rooms and a corridor between them.
    _grid = NavGrid.bake(<Brush>[
      Brush(centre: Vector3(5, 0, 5), size: Vector3(10, 1, 10)),
      Brush(centre: Vector3(13, 0, 5), size: Vector3(6, 1, 2)),
      Brush(centre: Vector3(21, 0, 5), size: Vector3(10, 1, 10)),
    ], cellSize: 0.5);
    _map = Automap(_grid, revealRadius: 3.0);
    // #endregion grid

    final material = Material(
      name: 'walker',
      baseColor: Vector4(0.6, 0.9, 0.7, 1.0),
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

  // #region reveal
  void _walk() {
    _map.reveal(Vector3(1.0, 0.0, 1.0));
    _map.reveal(Vector3(3.0, 0.0, 1.0));
  }
  // #endregion reveal

  @override
  void update(DemoContext context, double dt) {
    if (_forgetAsked) {
      _forgetAsked = false;
      _map = Automap(_grid, revealRadius: 3.0);
    }
    // Walk the route at `speed`, a leg at a time.
    final Vector3 to = _route[(_leg + 1) % _route.length];
    final Vector3 way = to - _walker;
    final double step = speed * dt;
    if (way.length <= step) {
      _walker.setFrom(to);
      _leg = (_leg + 1) % _route.length;
    } else {
      _walker.add(way.normalized() * step);
    }
    // #region live
    // Every frame the player stands somewhere, and the map learns of it.
    _map.reveal(_walker);
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Walking speed',
      min: 1.0,
      max: 10.0,
      value: () => speed,
      onChanged: (double v) => speed = v,
      format: (double v) => '${v.toStringAsFixed(1)} m/s',
    ),
    ToggleControl(
      'Forget the map',
      value: () => false,
      onChanged: (bool v) {
        if (v) _forgetAsked = true;
      },
    ),
  ];

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      ColoredBox(
        color: const Color(0xFF14161A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: AspectRatio(
              aspectRatio: _grid.columns / _grid.rows,
              child: CustomPaint(
                painter: _MapPainter(_grid, _map, _walker),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the walker marker was not drawn');
    }
    _walk();
    // #region check
    final nearWhereWalked = _map.isFloor(_grid.cellAtPoint(2.0, 1.0));
    final farAcrossTheFloor = _map.isRevealed(_grid.cellAtPoint(9.0, 9.0));
    // #endregion check
    if (!nearWhereWalked) {
      throw StateError(
        'a cell the walk passed near should be revealed as floor',
      );
    }
    if (farAcrossTheFloor) {
      throw StateError(
        'the automap should not reveal floor nobody walked near',
      );
    }
  }
}

/// Draws revealed floor light, revealed walls dark, and everything else
/// blank.
final class _MapPainter extends CustomPainter {
  const _MapPainter(this.grid, this.map, this.walker);

  final NavGrid grid;
  final Automap map;
  final Vector3 walker;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / grid.columns;
    final cellH = size.height / grid.rows;
    final paint = Paint();
    for (var index = 0; index < grid.cellCount; index++) {
      if (!map.isRevealed(index)) continue;
      final cx = grid.cellX(index);
      final cz = grid.cellZ(index);
      paint.color = map.isFloor(index)
          ? const Color(0xFFB6E3B0)
          : const Color(0xFF3A2A2A);
      canvas.drawRect(
        Rect.fromLTWH(cx * cellW, cz * cellH, cellW, cellH),
        paint,
      );
    }
    // Where the player is, in the same cells.
    canvas.drawCircle(
      Offset(
        walker.x / grid.cellSize * cellW,
        walker.z / grid.cellSize * cellH,
      ),
      cellW * 1.4,
      Paint()..color = const Color(0xFFE8A33D),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
