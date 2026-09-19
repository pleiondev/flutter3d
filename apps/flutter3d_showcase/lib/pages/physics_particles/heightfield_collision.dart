/// A character controller falling onto sloped ground and walking across it,
/// its feet tracking a surface that is not flat.
///
/// Quoted by `heightfield_collision.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class HeightfieldCollisionDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final CollisionHeightfield _field;
  late final CharacterController _controller;
  late final MeshNode _body;

  static const int _columns = 6;
  static const int _rows = 3;
  static const double _cellSize = 1.0;
  static const double _step = 1 / 60;
  static const int _steps = 30;

  Float32List _heights() => Float32List.fromList(<double>[
    for (var row = 0; row < _rows; row++)
      for (var col = 0; col < _columns; col++) col * 0.15,
  ]);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.25
      ..yaw = 0.6;
  }

  @override
  Scene build(DemoContext context) {
    _world = CollisionWorld();
    final Float32List heights = _heights();

    // #region field
    // A gentle ramp: flat along z, rising a little more than eight degrees
    // along x. `CollisionHeightfield` is the fifth shape and the first that
    // is not one convex solid — it hands a query the triangles near it.
    _field = CollisionHeightfield(
      columns: _columns,
      rows: _rows,
      cellSize: _cellSize,
      heights: heights,
    );
    _world.add(Collider(shape: _field, position: Vector3.zero()));
    // #endregion field

    // #region walk
    _controller = CharacterController(
      world: _world,
      position: Vector3(-2.0, 1.0, 0.0),
    );
    for (var i = 0; i < _steps; i++) {
      _controller.step(_step, wishDirection: Vector3(1.0, 0.0, 0.0));
    }
    // #endregion walk

    _body = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.7, 1.8, 0.7)).build(),
      ),
      Material(name: 'walker', baseColor: Vector4(0.8, 0.5, 0.3, 1.0)),
      name: 'walker',
    )..setPositionFrom(_controller.position);

    return Scene()
      ..add(_terrain(context, heights))
      ..add(_body)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  /// A visual grid matching [heights], for the same reason the collision
  /// shape is: physics and rendering are separate packages here, so nothing
  /// draws a `CollisionShape` for you.
  MeshNode _terrain(DemoContext context, Float32List heights) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    final double width = (_columns - 1) * _cellSize;
    final double depth = (_rows - 1) * _cellSize;
    final double centre = (heights.reduce((a, b) => a > b ? a : b) + 0) / 2;
    final List<int> indices = <int>[];
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _columns; col++) {
        indices.add(
          builder.addVertex(
            position: Vector3(
              col * _cellSize - width * 0.5,
              heights[row * _columns + col] - centre,
              row * _cellSize - depth * 0.5,
            ),
            normal: Vector3(0.0, 1.0, 0.0),
          ),
        );
      }
    }
    for (var row = 0; row + 1 < _rows; row++) {
      for (var col = 0; col + 1 < _columns; col++) {
        final int tl = indices[row * _columns + col];
        final int tr = indices[row * _columns + col + 1];
        final int bl = indices[(row + 1) * _columns + col];
        final int br = indices[(row + 1) * _columns + col + 1];
        builder.addQuad(tl, bl, br, tr);
      }
    }
    return MeshNode(
      DeviceMesh.upload(context.device, builder.build()),
      Material(name: 'ground', baseColor: Vector4(0.6, 0.55, 0.4, 1.0)),
      name: 'ground',
    );
  }

  @override
  void update(DemoContext context, double dt) {
    _body.setPositionFrom(_controller.position);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_controller.isGrounded) {
      throw StateError('the walker should have landed on the slope');
    }
    final Vector3 at = _controller.position;
    final double ground = _field.heightAt(Vector3.zero(), at.x, at.z);
    final double feet = at.y - _controller.halfExtents.y;
    if ((feet - ground).abs() > 0.15) {
      throw StateError(
        'the walker\'s feet should track the slope: feet $feet, ground $ground',
      );
    }
    if (at.x <= -2.0) {
      throw StateError('the walker should have moved up the slope');
    }
    // #endregion check
    if (frame.drawCalls < 2) {
      throw StateError(
        'the ground and the walker did not both reach the frame',
      );
    }
  }
}
