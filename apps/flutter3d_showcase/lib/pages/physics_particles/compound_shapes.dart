/// A table, a dumbbell and a hammer, each one body made of several shapes,
/// dropped onto a floor by the physics core. They land and rest on their
/// parts: the table on its four legs, the dumbbell on its two weights, the
/// hammer on its head and the end of its handle.
///
/// Quoted by `compound_shapes.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// One part: the shape as the core takes it, and the mesh that draws it.
typedef _Piece = ({NativeCompoundPart part, MeshData mesh});

/// One body made of [pieces], and what the core moved them by so that the
/// body's origin is their centre of mass.
final class _Thing {
  _Thing(this.name, this.body, this.offset, this.pieces);

  final String name;
  final NativeBody body;
  final Vector3 offset;
  final List<_Piece> pieces;
}

final class CompoundShapesDemo extends ShowcaseDemo {
  NativeWorld? _world;
  List<_Thing> _things = const <_Thing>[];
  final List<SceneNode> _nodes = <SceneNode>[];

  /// Why nothing falls, or null when the core is running.
  String? unavailable;

  double _age = 0.0;

  static const double _step = 1 / 60;

  /// The quarter turn that lays a part made upright along y along x.
  static Quaternion get _alongX =>
      Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.5
      ..pitch = 0.45
      ..yaw = 0.35;
    context.orbit.target.setValues(0.2, 0.3, 0.0);
  }

  // #region parts
  /// A top and four legs, all boxes. The compound's origin is on the floor
  /// under the middle of the table, where the legs end.
  static List<_Piece> _table() => <_Piece>[
    (
      part: NativeCompoundPart(
        NativeShape.box(Vector3(0.6, 0.025, 0.4)),
        at: Vector3(0.0, 0.725, 0.0),
      ),
      mesh: CuboidShape(size: Vector3(1.2, 0.05, 0.8)).build(),
    ),
    for (final (double x, double z) in const <(double, double)>[
      (-0.55, -0.35),
      (0.55, -0.35),
      (-0.55, 0.35),
      (0.55, 0.35),
    ])
      (
        part: NativeCompoundPart(
          NativeShape.box(Vector3(0.03, 0.35, 0.03)),
          at: Vector3(x, 0.35, z),
        ),
        mesh: CuboidShape(size: Vector3(0.06, 0.7, 0.06)).build(),
      ),
  ];

  /// Two balls and the bar between them. A capsule stands along y, so the
  /// bar is turned a quarter round z to lie along x.
  static List<_Piece> _dumbbell() => <_Piece>[
    for (final double x in const <double>[-0.35, 0.35])
      (
        part: NativeCompoundPart(
          const NativeShape.sphere(0.16),
          at: Vector3(x, 0.0, 0.0),
        ),
        mesh: const SphereShape(radius: 0.16).build(),
      ),
    (
      part: NativeCompoundPart(
        const NativeShape.capsule(0.035, 0.3),
        turn: _alongX,
      ),
      mesh: const CapsuleShape(radius: 0.035, height: 0.6).build(),
    ),
  ];

  /// A handle, a cylinder laid along x, and a head that is a hull: a block
  /// that narrows towards its striking face. The world keeps the hull, and
  /// moved its points so that its centre of mass is at its origin;
  /// `hullOffset` says by how much, and the part is placed with it so the
  /// head sits where its points say.
  static List<_Piece> _hammer(NativeWorld world) {
    final NativeHull head = world.createHull(_headPoints);
    final Vector3 shift = world.hullOffset(head);
    return <_Piece>[
      (
        part: NativeCompoundPart(
          const NativeShape.cylinder(0.03, 0.3),
          turn: _alongX,
        ),
        mesh: const CylinderShape(
          radiusTop: 0.03,
          radiusBottom: 0.03,
          height: 0.6,
        ).build(),
      ),
      (
        part: NativeCompoundPart.hull(
          head,
          at: Vector3(0.36, 0.0, 0.0) + shift,
        ),
        mesh: _headMesh(shift),
      ),
    ];
  }
  // #endregion parts

  /// The head's eight corners: 12 cm square at the back, 7 cm at the face,
  /// 30 cm long along z.
  static final List<Vector3> _headPoints = <Vector3>[
    for (final double z in const <double>[-0.15, 0.15])
      for (final double x in <double>[-1.0, 1.0])
        for (final double y in <double>[-1.0, 1.0])
          Vector3(
            x * (z < 0.0 ? 0.06 : 0.035),
            y * (z < 0.0 ? 0.06 : 0.035),
            z,
          ),
  ];

  /// The head drawn from the same corners, less what the hull was moved by,
  /// one flat face at a time.
  static MeshData _headMesh(Vector3 shift) {
    final List<Vector3> p = <Vector3>[
      for (final Vector3 v in _headPoints) v - shift,
    ];
    final Vector3 middle = p.fold(Vector3.zero(), (a, v) => a + v) / 8.0;
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    for (final List<int> f in const <List<int>>[
      <int>[0, 2, 3, 1],
      <int>[4, 6, 7, 5],
      <int>[0, 1, 5, 4],
      <int>[2, 6, 7, 3],
      <int>[0, 4, 6, 2],
      <int>[1, 3, 7, 5],
    ]) {
      final Vector3 n = (p[f[1]] - p[f[0]]).cross(p[f[2]] - p[f[0]])
        ..normalize();
      final Vector3 center =
          (p[f[0]] + p[f[1]] + p[f[2]] + p[f[3]]) / 4.0 - middle;
      final bool outward = n.dot(center) > 0.0;
      final List<int> order = outward ? f : f.reversed.toList();
      final Vector3 normal = outward ? n : -n;
      final List<int> at = <int>[
        for (final int i in order)
          builder.addVertex(position: p[i], normal: normal),
      ];
      builder.addQuad(at[0], at[1], at[2], at[3]);
    }
    return builder.build();
  }

  // #region body
  /// One body shaped as [pieces], [mass] kilograms, with the compound's own
  /// origin put at [at] and turned by [turn]. The core moved the parts by
  /// `compoundOffset` to put their centre of mass on the body's origin, so
  /// the body goes that much further along.
  static _Thing _add(
    NativeWorld world,
    String name,
    List<_Piece> pieces, {
    required Vector3 at,
    required Quaternion turn,
    required double mass,
  }) {
    final NativeCompound compound = world.createCompound(<NativeCompoundPart>[
      for (final _Piece p in pieces) p.part,
    ]);
    final Vector3 offset = world.compoundOffset(compound);
    final NativeBody body = world.addBody(
      position: at + turn.asRotationMatrix().transformed(offset),
      mass: mass,
    );
    world
      ..setCompound(body, compound)
      ..setOrientation(body, turn);
    return _Thing(name, body, offset, pieces);
  }
  // #endregion body

  /// A floor and the three things over it, a little tilted, so each lands
  /// on one part first and settles onto the rest.
  static (NativeWorld, List<_Thing>) _drop() {
    final NativeWorld world = NativeWorld();
    final NativeBody floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(4.0, 0.5, 3.0)));
    final List<_Thing> things = <_Thing>[
      _add(
        world,
        'table',
        _table(),
        at: Vector3(-1.8, 0.4, 0.0),
        turn: Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 0.12),
        mass: 20.0,
      ),
      _add(
        world,
        'dumbbell',
        _dumbbell(),
        at: Vector3(0.2, 1.0, 0.0),
        turn: Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 0.25),
        mass: 8.0,
      ),
      _add(
        world,
        'hammer',
        _hammer(world),
        at: Vector3(1.9, 1.2, 0.0),
        turn:
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 0.5) *
            Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 0.3),
        mass: 1.5,
      ),
    ];
    return (world, things);
  }

  /// Starts the core, or keeps the reason it would not start.
  void _start() {
    _world?.dispose();
    _world = null;
    _age = 0.0;
    if (!physicsCoreLoaded) {
      unavailable = 'the core is not loaded in this browser yet';
      return;
    }
    try {
      final (NativeWorld world, List<_Thing> things) = _drop();
      _world = world;
      _things = things;
      unavailable = null;
    } on Object catch (e) {
      unavailable = '$e';
    }
  }

  @override
  void dispose() {
    _world?.dispose();
    _world = null;
  }

  @override
  Scene build(DemoContext context) {
    _start();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(8.0, 1.0, 6.0)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.42, 0.45, 0.48, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.5, 0.0),
      );
    // #region draw
    // A node follows each body; under it, a mesh for every part, where the
    // part sits once the core has moved it by the offset.
    for (final (int i, _Thing thing) in _things.indexed) {
      final material = RenderMaterial(
        name: thing.name,
        baseColor: LinearColor.fromSrgb(
          0.55 + 0.35 * math.sin(i * 1.3 + 0.4),
          0.45 + 0.3 * math.sin(i * 2.1 + 1.5),
          0.35 + 0.3 * math.sin(i * 0.7 + 2.6),
          1.0,
        ),
        roughness: 0.6,
      );
      final node = SceneNode(name: thing.name);
      for (final (int j, _Piece piece) in thing.pieces.indexed) {
        node.add(
          MeshNode(
              DeviceMesh.upload(context.device, piece.mesh),
              material,
              name: '${thing.name} part $j',
            )
            ..setPositionFrom(piece.part.at - thing.offset)
            ..setRotation(piece.part.turn),
        );
      }
      _nodes.add(node);
      scene.add(node);
    }
    // #endregion draw
    _follow();
    return scene;
  }

  // #region follow
  /// Each node takes its body's place and turn from the core.
  void _follow() {
    final NativeWorld? world = _world;
    if (world == null) return;
    for (final (int i, _Thing thing) in _things.indexed) {
      _nodes[i]
        ..setPositionFrom(world.localPositionOf(thing.body))
        ..setRotation(world.orientationOf(thing.body));
    }
  }
  // #endregion follow

  @override
  void update(DemoContext context, double dt) {
    final NativeWorld? world = _world;
    if (world == null) return;
    world.step(_step);
    _age += dt;
    if (_age > 6.0) _start();
    _follow();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      unavailable == null
          ? 'Drop again'
          : 'Drop again (unavailable: $unavailable)',
      value: () => false,
      onChanged: (bool v) {
        if (v) _start();
      },
    ),
  ];

  /// Where [local], a point in [thing]'s compound frame, is in the world.
  @visibleForTesting
  Vector3 pointOf(String thing, Vector3 local) {
    final NativeWorld world = _world!;
    final _Thing t = _things.firstWhere((t) => t.name == thing);
    return world.localPositionOf(t.body) +
        world
            .orientationOf(t.body)
            .asRotationMatrix()
            .transformed(local - t.offset);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (unavailable != null) {
      throw StateError('the core did not start: $unavailable');
    }
    final NativeWorld world = _world!;
    // #region check
    for (var i = 0; i < 240; i++) {
      world.step(_step);
    }
    for (final _Thing t in _things) {
      if (!world.isAsleep(t.body)) {
        throw StateError('the ${t.name} never came to rest');
      }
    }
    // The table: its legs end at the compound's origin, so standing on them
    // that origin is on the floor, a centimetre at most either way, and the
    // top is level.
    final Vector3 feet = pointOf('table', Vector3.zero());
    final Vector3 top = pointOf('table', Vector3(0.0, 0.75, 0.0));
    if (feet.y.abs() > 0.01 || (top.y - 0.75).abs() > 0.01) {
      throw StateError('the table is not on its legs: feet $feet, top $top');
    }
    // The dumbbell: both balls on the floor, so the bar lies level at their
    // radius.
    for (final double x in const <double>[-0.35, 0.35]) {
      final Vector3 ball = pointOf('dumbbell', Vector3(x, 0.0, 0.0));
      if ((ball.y - 0.16).abs() > 0.01) {
        throw StateError('a dumbbell ball rests at $ball, not on the floor');
      }
    }
    // The hammer: the far end of its handle on the floor at the handle's
    // radius, and its head low beside it, not propped up on the head alone.
    final Vector3 end = pointOf('hammer', Vector3(-0.3, 0.0, 0.0));
    final Vector3 head = pointOf('hammer', Vector3(0.36, 0.0, 0.0));
    if ((end.y - 0.03).abs() > 0.01 || head.y > 0.07) {
      throw StateError('the hammer rests at handle $end, head $head');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
