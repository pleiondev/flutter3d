/// The five collision shapes, standing in a row, each with the flutter3d
/// mesh that draws roughly the same volume beside it.
///
/// Quoted by `collision_shapes.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CollisionShapesDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final Collider _sphereCollider;

  final List<Collider> _hits = <Collider>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.2
      ..yaw = 0.5;
  }

  /// A box with one edge cut away, matching `CollisionWedge(halfExtents,
  /// uphill: WedgeUphill.positiveX)`: full height at `+x`, tapering to an
  /// edge at `-x`.
  MeshData _wedgeMesh(Vector3 half) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    Vector3 v(double x, double y, double z) => Vector3(x, y, z);
    final int a = builder.addVertex(position: v(-half.x, -half.y, -half.z));
    final int b = builder.addVertex(position: v(half.x, -half.y, -half.z));
    final int c = builder.addVertex(position: v(half.x, half.y, -half.z));
    final int d = builder.addVertex(position: v(-half.x, -half.y, half.z));
    final int e = builder.addVertex(position: v(half.x, -half.y, half.z));
    final int g = builder.addVertex(position: v(half.x, half.y, half.z));
    builder
      ..addTriangle(a, c, b) // back
      ..addTriangle(d, e, g) // front
      ..addQuad(a, b, e, d) // floor
      ..addQuad(b, c, g, e) // top wall
      ..addQuad(a, d, g, c); // slope
    return builder.build();
  }

  /// A small bumpy grid, matching the heights fed to a `CollisionHeightfield`
  /// of the same `columns`, `rows` and `cellSize`.
  MeshData _terrainMesh(
    int columns,
    int rows,
    double cellSize,
    Float32List heights,
  ) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    final double width = (columns - 1) * cellSize;
    final double depth = (rows - 1) * cellSize;
    final List<int> indices = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        indices.add(
          builder.addVertex(
            position: Vector3(
              column * cellSize - width * 0.5,
              heights[row * columns + column],
              row * cellSize - depth * 0.5,
            ),
            normal: Vector3(0.0, 1.0, 0.0),
          ),
        );
      }
    }
    for (var row = 0; row + 1 < rows; row++) {
      for (var column = 0; column + 1 < columns; column++) {
        final int tl = indices[row * columns + column];
        final int tr = indices[row * columns + column + 1];
        final int bl = indices[(row + 1) * columns + column];
        final int br = indices[(row + 1) * columns + column + 1];
        builder.addQuad(tl, bl, br, tr);
      }
    }
    return builder.build();
  }

  MeshNode _node(
    DemoContext context,
    MeshData mesh,
    Material material,
    Vector3 position,
  ) => MeshNode(
    DeviceMesh.upload(context.device, mesh),
    material,
    name: material.name,
  )..setPositionFrom(position);

  @override
  Scene build(DemoContext context) {
    // #region shapes
    _world = CollisionWorld();
    final Collider box = _world.add(
      Collider(
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3(-6, 0, 0),
      ),
    );
    _sphereCollider = _world.add(
      Collider(shape: CollisionSphere(0.5), position: Vector3(-3, 0, 0)),
    );
    final Collider capsule = _world.add(
      Collider(
        shape: CollisionCapsule(radius: 0.35, halfHeight: 0.4),
        position: Vector3(0, 0, 0),
      ),
    );
    final Collider wedge = _world.add(
      Collider(
        shape: CollisionWedge(Vector3(0.6, 0.5, 0.5)),
        position: Vector3(3, 0, 0),
      ),
    );
    final Float32List heights = Float32List.fromList(<double>[
      0.0,
      0.1,
      0.0,
      -0.1,
      0.1,
      0.3,
      0.2,
      0.0,
      0.0,
      0.2,
      0.4,
      0.1,
      -0.1,
      0.0,
      0.1,
      0.0,
    ]);
    final Collider field = _world.add(
      Collider(
        shape: CollisionHeightfield(
          columns: 4,
          rows: 4,
          cellSize: 0.5,
          heights: heights,
        ),
        position: Vector3(6, 0, 0),
      ),
    );
    // #endregion shapes

    final Scene scene = Scene()
      ..add(
        _node(
          context,
          CuboidShape(size: Vector3(1, 1, 1)).build(),
          Material(name: 'box', baseColor: Vector4(0.8, 0.4, 0.3, 1.0)),
          box.position,
        ),
      )
      ..add(
        _node(
          context,
          SphereShape(segments: 24, rings: 12).build(),
          Material(name: 'sphere', baseColor: Vector4(0.3, 0.6, 0.8, 1.0)),
          _sphereCollider.position,
        ),
      )
      ..add(
        _node(
          context,
          const CapsuleShape(radius: 0.35, height: 0.8).build(),
          Material(name: 'capsule', baseColor: Vector4(0.5, 0.8, 0.4, 1.0)),
          capsule.position,
        ),
      )
      ..add(
        _node(
          context,
          _wedgeMesh(Vector3(0.6, 0.5, 0.5)),
          Material(name: 'wedge', baseColor: Vector4(0.8, 0.7, 0.3, 1.0)),
          wedge.position,
        ),
      )
      ..add(
        _node(
          context,
          _terrainMesh(4, 4, 0.5, heights),
          Material(name: 'field', baseColor: Vector4(0.6, 0.55, 0.4, 1.0)),
          field.position,
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // A probe placed exactly at the sphere's own centre should find the
    // sphere, and nothing else: the shapes are spaced apart on purpose.
    // #region probe
    _world.overlap(
      CollisionBox(Vector3(0.1, 0.1, 0.1)),
      _sphereCollider.position,
      _hits,
    );
    // #endregion probe
    if (_hits.length != 1 || !identical(_hits.first, _sphereCollider)) {
      throw StateError('the probe should have found only the sphere');
    }
    // #endregion check
    if (frame.drawCalls < 5) {
      throw StateError('all five shapes should have drawn');
    }
  }
}
