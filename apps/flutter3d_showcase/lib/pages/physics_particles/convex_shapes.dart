/// The core's shapes past boxes, balls and capsules, on a floor that is a
/// triangle mesh: a cylinder rolling down its ramp, a cone and a hull of
/// six points dropped on it, and a rounded box thrown tumbling.
///
/// Quoted by `convex_shapes.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// The bodies, in the order the scene draws them, and the hull's offset.
typedef _Bodies = ({
  NativeWorld world,
  NativeBody cylinder,
  NativeBody cone,
  NativeBody rock,
  NativeBody box,
  Vector3 rockOffset,
});

final class ConvexShapesDemo extends ShowcaseDemo {
  _Bodies? _bodies;

  /// Why nothing moves: the core would not start. Null when it did.
  String? unavailable;

  final List<SceneNode> _nodes = <SceneNode>[];
  double _age = 0.0;

  static const double _step = 1 / 60;

  static const double _cylinderRadius = 0.3, _cylinderHalf = 0.4;
  static const double _coneRadius = 0.35, _coneHeight = 0.6;
  static const double _boxHalf = 0.25, _rounding = 0.08;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 11.0
      ..pitch = 0.4
      ..yaw = 0.25;
    context.orbit.target.setValues(-0.5, 0.4, 0.0);
  }

  // #region ground
  /// The ground as one triangle mesh: a ramp from x = −6, 1.5 m up, down
  /// to x = −3, and the floor from there to x = 6, four metres wide. Four
  /// triangles, wound counter-clockwise seen from above, the side bodies
  /// touch. The ramp and the floor share the vertices at its foot, so that
  /// edge is internal and a body rolls over it without a bump.
  static final List<Vector3> _groundPoints = <Vector3>[
    Vector3(-6.0, 1.5, -2.0),
    Vector3(-6.0, 1.5, 2.0),
    Vector3(-3.0, 0.0, -2.0),
    Vector3(-3.0, 0.0, 2.0),
    Vector3(6.0, 0.0, -2.0),
    Vector3(6.0, 0.0, 2.0),
  ];
  static const List<int> _groundTriangles = <int>[
    0, 1, 2, 2, 1, 3, //
    2, 3, 4, 4, 3, 5,
  ];
  // #endregion ground

  // #region rock
  /// A rock of six points: four round its middle in a level plane, one
  /// above it and one below, not quite over each other. Its faces are the
  /// eight triangles from the top and the bottom to each edge of the
  /// middle; the core finds the same hull from the points alone.
  static final List<Vector3> _rockPoints = <Vector3>[
    Vector3(0.08, 0.4, 0.05),
    Vector3(-0.05, -0.3, 0.02),
    Vector3(0.5, 0.0, 0.05),
    Vector3(0.05, 0.0, 0.4),
    Vector3(-0.45, 0.0, 0.0),
    Vector3(0.0, 0.0, -0.35),
  ];
  static const List<int> _rockTriangles = <int>[
    0, 2, 3, 0, 3, 4, 0, 4, 5, 0, 5, 2, //
    1, 3, 2, 1, 4, 3, 1, 5, 4, 1, 2, 5,
  ];
  // #endregion rock

  _Bodies? _build() {
    unavailable = null;
    if (!physicsCoreLoaded) {
      unavailable = 'the core is not loaded in this browser yet';
      return null;
    }
    final NativeWorld w;
    try {
      w = NativeWorld();
    } on Object catch (e) {
      unavailable = '$e';
      return null;
    }
    // #region mesh
    // The world keeps the mesh; a fixed body is shaped as it.
    final NativeMesh mesh = w.createMesh(_groundPoints, _groundTriangles);
    final NativeBody ground = w.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    w.setMesh(ground, mesh);
    // #endregion mesh

    // #region cylinder
    // A cylinder stands along its body's y. Turned a quarter about x, it
    // lies across the ramp, set a little above the slope near the top.
    final double slope = math.atan2(1.5, 3.0);
    final Vector3 up = Vector3(math.sin(slope), math.cos(slope), 0.0);
    final NativeBody cylinder = w.addBody(
      position: Vector3(-5.5, 1.25, -1.2) + up * (_cylinderRadius + 0.02),
      mass: 3.0,
    );
    w
      ..setShape(
        cylinder,
        const NativeShape.cylinder(_cylinderRadius, _cylinderHalf),
      )
      ..setOrientation(
        cylinder,
        Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
      )
      // Nothing here resists rolling, so a cylinder on a level floor would
      // roll on to its end. Damping its spin stands in for that.
      ..setDamping(cylinder, angular: 1.5);
    // #endregion cylinder

    // #region cone
    // A cone's origin is its centre of mass, a quarter of its height above
    // its base.
    final NativeBody cone = w.addBody(
      position: Vector3(0.0, 0.6, 0.8),
      mass: 2.0,
    );
    w.setShape(cone, const NativeShape.cone(_coneRadius, _coneHeight));
    // #endregion cone

    // #region hull
    // The hull is built from the points and moved so its centre of mass is
    // the body's origin; hullOffset says by how much, and the mesh drawn
    // for it has to be moved by the same.
    final NativeHull hull = w.createHull(_rockPoints);
    final NativeBody rock = w.addBody(
      position: Vector3(2.0, 1.0, 0.5),
      mass: 3.0,
    );
    w
      ..setHull(rock, hull)
      ..setOrientation(
        rock,
        Quaternion.axisAngle(Vector3(1.0, 0.0, 1.0).normalized(), 0.7),
      );
    // #endregion hull

    // #region rounded
    // A box rounded by eight centimetres: the box grown by a ball, so its
    // edges and corners are round and it stands 0.33 m from its centre to
    // each face. Thrown spinning, it tumbles before it settles.
    final NativeBody box = w.addBody(
      position: Vector3(4.0, 1.2, -0.5),
      mass: 2.0,
    );
    w
      ..setShape(box, NativeShape.box(Vector3.all(_boxHalf)))
      ..setRounding(box, _rounding)
      ..setAngularVelocity(box, Vector3(3.0, 1.0, 5.0))
      ..setVelocity(box, Vector3(-1.0, 0.0, 0.0));
    // #endregion rounded

    return (
      world: w,
      cylinder: cylinder,
      cone: cone,
      rock: rock,
      box: box,
      rockOffset: w.hullOffset(hull),
    );
  }

  void _restart() {
    _bodies?.world.dispose();
    _bodies = _build();
    _age = 0.0;
  }

  @override
  void dispose() => _bodies?.world.dispose();

  /// Triangles with a normal of their own each, so the faces are drawn
  /// flat; each wound to face away from [inside].
  static MeshData _faceted(
    List<Vector3> points,
    List<int> triangles, {
    Vector3? inside,
  }) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    for (var t = 0; t < triangles.length; t += 3) {
      final Vector3 a = points[triangles[t]];
      Vector3 b = points[triangles[t + 1]];
      Vector3 c = points[triangles[t + 2]];
      Vector3 normal = (b - a).cross(c - a)..normalize();
      if (inside != null && normal.dot(a - inside) < 0) {
        (b, c) = (c, b);
        normal = -normal;
      }
      builder.addTriangle(
        builder.addVertex(position: a, normal: normal),
        builder.addVertex(position: b, normal: normal),
        builder.addVertex(position: c, normal: normal),
      );
    }
    return builder.build();
  }

  @override
  Scene build(DemoContext context) {
    _bodies = _build();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      );
    DeviceMesh upload(MeshData data) => DeviceMesh.upload(context.device, data);
    RenderMaterial paint(String name, double r, double g, double b) =>
        RenderMaterial(
          name: name,
          baseColor: LinearColor.fromSrgb(r, g, b, 1.0),
          roughness: 0.6,
        );

    scene.add(
      MeshNode(
        upload(_faceted(_groundPoints, _groundTriangles)),
        paint('ground', 0.45, 0.47, 0.5),
        name: 'ground',
      ),
    );
    // #region draw
    // The cone's mesh has its middle at its origin, half its height above
    // the base; the body's origin is a quarter above it. A node at the body
    // holds the mesh a quarter of the height up.
    final cone = SceneNode(name: 'cone')
      ..add(
        MeshNode(
          upload(
            const ConeShape(radius: _coneRadius, height: _coneHeight).build(),
          ),
          paint('cone', 0.8, 0.6, 0.3),
          name: 'cone mesh',
        )..setPosition(0.0, _coneHeight / 4, 0.0),
      );
    // The rock's mesh is its points less the offset the hull was moved by.
    final Vector3 offset = _bodies?.rockOffset ?? Vector3.zero();
    final List<Vector3> moved = <Vector3>[
      for (final Vector3 p in _rockPoints) p - offset,
    ];
    final Vector3 middle =
        moved.fold(Vector3.zero(), (Vector3 sum, Vector3 p) => sum + p) /
        moved.length.toDouble();
    _nodes.addAll(<SceneNode>[
      MeshNode(
        upload(
          const CylinderShape(
            radiusTop: _cylinderRadius,
            radiusBottom: _cylinderRadius,
            height: 2 * _cylinderHalf,
          ).build(),
        ),
        paint('cylinder', 0.35, 0.55, 0.8),
        name: 'cylinder',
      ),
      cone,
      MeshNode(
        upload(_faceted(moved, _rockTriangles, inside: middle)),
        paint('rock', 0.55, 0.5, 0.45),
        name: 'rock',
      ),
      // Drawn as a plain cube of the rounded box's outer size.
      MeshNode(
        upload(
          CuboidShape(size: Vector3.all(2 * (_boxHalf + _rounding))).build(),
        ),
        paint('rounded box', 0.75, 0.4, 0.45),
        name: 'rounded box',
      ),
    ]);
    // #endregion draw
    _nodes.forEach(scene.add);
    _place();
    return scene;
  }

  void _place() {
    final _Bodies? b = _bodies;
    if (b == null) return;
    final List<NativeBody> bodies = <NativeBody>[
      b.cylinder,
      b.cone,
      b.rock,
      b.box,
    ];
    for (var i = 0; i < bodies.length; i++) {
      _nodes[i]
        ..setPositionFrom(b.world.localPositionOf(bodies[i]))
        ..setRotation(b.world.orientationOf(bodies[i]));
    }
  }

  @override
  void update(DemoContext context, double dt) {
    final _Bodies? b = _bodies;
    if (b == null) return;
    b.world.step(_step);
    _age += dt;
    if (_age > 10.0) _restart();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      unavailable == null
          ? 'Drop again'
          : 'Drop again (the core is unavailable: $unavailable)',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    if (unavailable != null) return;
    // #region check
    // Ten seconds from the drop.
    _restart();
    final _Bodies b = _bodies!;
    final NativeWorld w = b.world;
    for (var i = 0; i < 600; i++) {
      w.step(_step);
    }
    Vector3 axisOf(NativeBody body) =>
        w.orientationOf(body).asRotationMatrix().transformed(Vector3(0, 1, 0));
    void rests(String what, double height, double at) {
      if ((height - at).abs() > 0.01) {
        throw StateError('$what rests at $height m, not $at');
      }
    }

    // The cylinder rolled off the ramp, at least a metre past its foot,
    // and lies on its side, its axis level and its centre a radius up.
    final Vector3 cylinder = w.localPositionOf(b.cylinder);
    if (cylinder.x < -2.0) throw StateError('the cylinder stayed on the ramp');
    if (axisOf(b.cylinder).y.abs() > 0.02) {
      throw StateError('the cylinder is not on its side');
    }
    rests('the cylinder', cylinder.y, _cylinderRadius);
    // The cone stands on its base, its centre of mass a quarter of its
    // height up.
    if (axisOf(b.cone).y < 0.999) throw StateError('the cone fell over');
    rests('the cone', w.localPositionOf(b.cone).y, _coneHeight / 4);
    // The rock rests on a face: its lowest corner on the floor.
    final Matrix3 turn = w.orientationOf(b.rock).asRotationMatrix();
    final Vector3 at = w.localPositionOf(b.rock);
    final double lowest = _rockPoints
        .map((Vector3 p) => (at + turn.transformed(p - b.rockOffset)).y)
        .reduce(math.min);
    rests('the rock\'s lowest corner', lowest, 0.0);
    // The rounded box lies on a face, its half size plus the rounding up.
    rests('the rounded box', w.localPositionOf(b.box).y, _boxHalf + _rounding);
    for (final NativeBody body in <NativeBody>[b.cone, b.rock, b.box]) {
      if (!w.isAsleep(body)) throw StateError('a shape never came to rest');
    }
    // #endregion check
  }
}
