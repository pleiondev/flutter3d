/// A sheet pinned along one edge, sagging under gravity and draping around
/// an obstacle it is not allowed to pass through.
///
/// Quoted by `xpbd_cloth.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class XpbdClothDemo extends ShowcaseDemo {
  late final ClothMesh _cloth;
  late final ClothObstacle _obstacle;

  static const int _cols = 6;
  static const int _rows = 6;
  static const double _spacing = 0.12;
  static const double _step = 1 / 60;
  static const int _steps = 180;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..pitch = 0.1
      ..yaw = 0.5;
    context.orbit.target.setValues(0.15, 0.8, 0.2);
  }

  @override
  Scene build(DemoContext context) {
    // #region cloth
    // Row zero is pinned, which is what stops the sheet falling forever:
    // everything else hangs from it and settles under gravity.
    _cloth = ClothMesh.grid(
      cols: _cols,
      rows: _rows,
      spacing: _spacing,
      height: 1.0,
    );
    _obstacle = ClothObstacle(CollisionSphere(0.15), Vector3(0.3, 0.75, 0.3));
    // #endregion cloth

    // #region settle
    const ClothSettings settings = ClothSettings();
    for (var i = 0; i < _steps; i++) {
      stepCloth(_cloth, settings, _step, obstacles: <ClothObstacle>[_obstacle]);
    }
    // #endregion settle

    return Scene()
      ..add(_sheet(context))
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(segments: 20, rings: 10, radius: 0.15).build(),
          ),
          Material(name: 'ball', baseColor: Vector4(0.4, 0.5, 0.7, 1.0)),
          name: 'ball',
        )..setPositionFrom(_obstacle.position),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      );
  }

  /// A mesh from the settled particle positions and the triangles
  /// `ClothMesh.grid` laid out for them. Nothing here draws a `ClothMesh`
  /// for you; that is the same gap the heightfield page's own terrain fills.
  MeshNode _sheet(DemoContext context) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    for (var i = 0; i < _cloth.particleCount; i++) {
      builder.addVertex(
        position: Vector3(
          _cloth.positions[3 * i],
          _cloth.positions[3 * i + 1],
          _cloth.positions[3 * i + 2],
        ),
        normal: Vector3(0.0, 0.3, 1.0)..normalize(),
      );
    }
    for (var i = 0; i + 2 < _cloth.triangles.length; i += 3) {
      builder.addTriangle(
        _cloth.triangles[i],
        _cloth.triangles[i + 1],
        _cloth.triangles[i + 2],
      );
    }
    return MeshNode(
      DeviceMesh.upload(context.device, builder.build()),
      Material(
        name: 'cloth',
        baseColor: Vector4(0.8, 0.3, 0.35, 1.0),
        doubleSided: true,
      ),
      name: 'cloth',
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The pinned row never moves: its inverse mass is zero, so no force and
    // no correction ever reaches it.
    if (_cloth.positions[1] != 1.0) {
      throw StateError('the pinned row should not have moved');
    }
    // The free edge should have sagged well below where it started.
    final int lastRow = (_rows - 1) * _cols;
    for (var col = 0; col < _cols; col++) {
      if (_cloth.positions[3 * (lastRow + col) + 1] > 0.9) {
        throw StateError('the free edge should have sagged under gravity');
      }
    }
    // Nothing should have ended up inside the obstacle.
    for (var i = 0; i < _cloth.particleCount; i++) {
      final Vector3 at = Vector3(
        _cloth.positions[3 * i],
        _cloth.positions[3 * i + 1],
        _cloth.positions[3 * i + 2],
      );
      if (at.distanceTo(_obstacle.position) < 0.13) {
        throw StateError('a particle passed through the obstacle');
      }
    }
    // #endregion check
    if (frame.drawCalls < 2) {
      throw StateError(
        'the cloth and the obstacle did not both reach the frame',
      );
    }
  }
}
