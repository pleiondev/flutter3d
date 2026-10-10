/// Glassware on the physics core: two tubes joined at the bottom by a short
/// pipe, filled to different heights, which swing and settle level; a
/// wooden block floating in a basin; and a test tube tipped over another,
/// pouring a stream that the other catches.
///
/// Quoted by `liquids.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// A straight tube [radius] wide and [height] tall with a flat floor, its
/// floor at the origin of its own frame.
RevolvedVessel _tube(double radius, double height) => RevolvedVessel(<Vector2>[
  Vector2(0.0, 0.0),
  Vector2(radius, 0.0),
  Vector2(radius, height),
]);

/// One vessel as it is drawn: its glass, the liquid in it, and where it
/// stands.
final class _Glass {
  _Glass(this.body, this.radius, this.height, this.at, this.glass, this.fill);

  final LiquidBody body;
  final double radius;
  final double height;
  final Vector3 at;
  final MeshNode glass;
  final MeshNode fill;

  /// Turned this far about x, radians: the pouring tube tips.
  double tilt = 0.0;

  Matrix3 get turn => Matrix3.rotationX(tilt);
}

final class LiquidsDemo extends ShowcaseDemo {
  /// The U-tube and the basin, at a hundred and twentieth of a second.
  late FluidWorld _vessels;

  /// The pour, at the finer step a stream in the air needs.
  late FluidWorld _pouring;

  late Dynamics _dynamics;
  late RigidBody _block;
  late _Glass _left, _right, _basin, _source, _target;
  late Pipe _pipe;
  late double _pourTotal;

  final List<MeshNode> _drops = <MeshNode>[];
  late MeshNode _blockNode;
  late MeshNode _pipeNode;

  /// Why the liquids are on the reference, or null when they are on the
  /// core.
  String? fallback;

  /// Whether to ask for the core. Off, both worlds are the reference.
  bool onCore = true;

  double _age = 0.0;

  static const double _frame = 1 / 60;

  /// The one gravity both worlds on this page are made with.
  static Vector3 get _gravity => standardGravityVector;

  /// Half the block: six by four centimetres and two and a half thick.
  static Vector3 get _half => Vector3(0.03, 0.012, 0.02);

  /// Pine, at six hundred kilograms a cubic metre.
  static const double _density = 600.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 0.75
      ..pitch = 0.4
      ..yaw = 0.25;
    context.orbit.target.setValues(0.0, 0.07, 0.0);
  }

  // #region solver
  /// The core's fluid solver where the core starts, the reference where it
  /// does not, and the reason kept to say so. A game that called
  /// `startPhysics()` would leave this out: a `FluidWorld` made without a
  /// solver takes the run's, `usePhysics().fluid`.
  FluidSolver _solver() {
    fallback = null;
    if (!onCore) return const DartFluid();
    if (!physicsCoreLoaded) {
      fallback = 'the core is not loaded in this browser yet';
      return const DartFluid();
    }
    try {
      NativeWorld().dispose();
      return const NativeLiquid();
    } on Object catch (e) {
      fallback = '$e';
      return const DartFluid();
    }
  }
  // #endregion solver

  /// The liquids and the glass that draws them, built afresh.
  void _fill(DemoContext context, Scene scene) {
    final FluidSolver solver = _solver();
    // #region utube
    // Two tubes four centimetres across, one filled to twelve centimetres and
    // one to six, joined at their floors by a pipe of eight millimetres bore
    // and three centimetres long.
    _vessels = FluidWorld(gravity: _gravity, step: 1 / 120, solver: solver);
    LiquidBody water(RevolvedVessel shape, double radius, double level) =>
        LiquidBody(
          shape: shape,
          medium: FluidMedium.water,
          volume: math.pi * radius * radius * level,
          modes: 2,
        );
    final LiquidBody left = water(_tube(0.02, 0.2), 0.02, 0.12);
    final LiquidBody right = water(_tube(0.02, 0.2), 0.02, 0.06);
    _pipe = Pipe(
      from: left,
      at: Vector3(0.0, 0.002, 0.0),
      to: right,
      toAt: Vector3(0.0, 0.002, 0.0),
      radius: 0.004,
      length: 0.03,
    );
    _vessels.bodies.addAll(<LiquidBody>[left, right]);
    _vessels.pipes.add(_pipe);
    // #endregion utube

    // #region float
    // A basin twenty centimetres across, six deep, and a block of pine let go
    // a centimetre over it. The block is an ordinary rigid body; the world
    // lifts it by the water it displaces and drags it as it moves.
    final LiquidBody basin = water(_tube(0.1, 0.12), 0.1, 0.06);
    _vessels.bodies.add(basin);
    _dynamics = Dynamics(world: CollisionWorld(), gravity: _gravity);
    _block = RigidBody(
      world: _dynamics.world,
      shape: CollisionBox(_half),
      position: Vector3(0.0, 0.06 + _half.y + 0.01, 0.0),
      mass: _density * 8.0 * _half.x * _half.y * _half.z,
    );
    _dynamics.add(_block);
    _vessels.float(_block);
    // #endregion float

    // #region pour
    // A narrow test tube seven tenths full, tipped over a wider empty one.
    // What runs over its lip is a stream the world flies, and what the wide
    // tube catches is added to it; what misses lands on the bench as
    // particles.
    _pouring = FluidWorld(
      gravity: _gravity,
      floor: <JetObstacle>[
        PlaneObstacle(normal: Vector3(0.0, 1.0, 0.0), offset: 0.0),
      ],
      solver: solver,
    );
    final source = LiquidBody(
      shape: _tube(0.008, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * 0.008 * 0.008 * 0.07,
      modes: 6,
      wallThickness: 0.0008,
    );
    final target = LiquidBody(
      shape: _tube(0.012, 0.1),
      medium: FluidMedium.water,
      volume: 0.0,
      modes: 6,
      wallThickness: 0.0008,
    );
    _pouring.bodies.addAll(<LiquidBody>[source, target]);
    _pourTotal = _pouring.volume;
    // #endregion pour

    final RenderMaterial glassLook = RenderMaterial(
      name: 'glass',
      baseColor: LinearColor.fromSrgb(0.85, 0.92, 1.0, 0.18),
      roughness: 0.1,
      alphaMode: MaterialAlphaMode.blend,
      doubleSided: true,
    );
    final RenderMaterial waterLook = RenderMaterial(
      name: 'water',
      baseColor: LinearColor.fromSrgb(0.2, 0.45, 0.85, 1.0),
      roughness: 0.2,
    );
    final DeviceMesh cylinder = DeviceMesh.upload(
      context.device,
      const CylinderShape(radiusTop: 1.0, radiusBottom: 1.0).build(),
    );
    _Glass glass(LiquidBody body, double radius, double height, Vector3 at) {
      final g = _Glass(
        body,
        radius,
        height,
        at,
        MeshNode(cylinder, glassLook, name: 'glass'),
        MeshNode(cylinder, waterLook, name: 'water'),
      );
      // The water first, so the glass round it blends over it.
      scene
        ..add(g.fill)
        ..add(g.glass);
      return g;
    }

    _left = glass(left, 0.02, 0.2, Vector3(-0.235, 0.0, 0.0));
    _right = glass(right, 0.02, 0.2, Vector3(-0.165, 0.0, 0.0));
    _basin = glass(basin, 0.1, 0.12, Vector3(0.0, 0.0, 0.0));
    _source = glass(source, 0.008, 0.1, Vector3(0.2, 0.1, -0.1045));
    _target = glass(target, 0.012, 0.1, Vector3(0.2, 0.0, 0.0));
    _pipeNode = MeshNode(cylinder, waterLook, name: 'pipe')
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2))
      ..setPosition(-0.2, 0.004, 0.0)
      ..setScale(0.004, 0.07, 0.004);
    _blockNode = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: _half * 2.0).build()),
      RenderMaterial(
        name: 'pine',
        baseColor: LinearColor.fromSrgb(0.8, 0.62, 0.38, 1.0),
      ),
      name: 'block',
    );
    scene
      ..add(_pipeNode)
      ..add(_blockNode);
    final DeviceMesh drop = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: 0.0015, segments: 8, rings: 4).build(),
    );
    for (var i = 0; i < 160; i++) {
      final node = MeshNode(drop, waterLook, name: 'drop $i')
        ..isVisible = false;
      _drops.add(node);
      scene.add(node);
    }
    _age = 0.0;
  }

  // #region step
  /// One frame: each world run on by its own whole steps, every vessel put
  /// where it stands before each, and the block stepped with the vessels'
  /// world so it is pushed once for every step it falls.
  void _run(double seconds) {
    _runVessels(seconds);
    _runPour(seconds);
  }

  void _runVessels(double seconds) {
    for (var i = 0; i < (seconds / _vessels.step).round(); i++) {
      for (final _Glass g in <_Glass>[_left, _right, _basin]) {
        g.body.place(g.turn, g.at, time: _vessels.time);
      }
      _vessels.advance(_vessels.step);
      _dynamics.step(_vessels.step);
    }
  }

  void _runPour(double seconds) {
    for (var i = 0; i < (seconds / _pouring.step).round(); i++) {
      // Tipped over half a second, to seventy-five degrees.
      _source.tilt = math.min(1.3, 2.6 * _pouring.time);
      for (final _Glass g in <_Glass>[_source, _target]) {
        g.body.place(g.turn, g.at, time: _pouring.time);
      }
      _pouring.advance(_pouring.step);
    }
  }
  // #endregion step

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.55, 0.6, 0.7)
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.7, 0.02, 0.35)).build(),
          ),
          RenderMaterial(
            name: 'bench',
            baseColor: LinearColor.fromSrgb(0.3, 0.3, 0.32, 1.0),
          ),
          name: 'bench',
        )..setPosition(0.0, -0.011, 0.0),
      );
    _fill(context, scene);
    _context = context;
    _scene = scene;
    _place();
    return scene;
  }

  late DemoContext _context;
  late Scene _scene;

  /// Every glass and its liquid where the worlds have them, and the drops in
  /// the air and on the bench.
  void _place() {
    for (final _Glass g in <_Glass>[_left, _right, _basin, _source, _target]) {
      final Quaternion q = Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), g.tilt);
      final Vector3 axis = g.turn.transformed(Vector3(0.0, 1.0, 0.0));
      g.glass
        ..setRotation(q)
        ..setPositionFrom(g.at + axis * (0.5 * g.height))
        ..setScale(g.radius, g.height, g.radius);
      // Upright, the liquid is a column to the surface the world keeps. The
      // tipped tube's is drawn as the same volume along its axis, which is
      // where it is not, but near enough to see it empty.
      final double depth = g.tilt == 0.0
          ? g.body.height
          : g.body.volume / (math.pi * g.radius * g.radius);
      final double shown = depth.clamp(0.0, g.height);
      g.fill
        ..isVisible = shown > 1e-4
        ..setRotation(q)
        ..setPositionFrom(g.at + axis * (0.5 * shown))
        ..setScale(0.97 * g.radius, shown, 0.97 * g.radius);
    }
    _blockNode
      ..setPositionFrom(_block.position)
      ..setRotation(_block.orientation);
    final List<Vector3> airborne = <Vector3>[
      for (final Jet jet in _pouring.jets.values)
        for (final List<JetSample> run in jet.runs)
          for (final JetSample s in run) s.position,
      for (final ParticleFluid fluid in _pouring.particles.values)
        ...fluid.positions,
    ];
    for (var i = 0; i < _drops.length; i++) {
      final bool shown = i < airborne.length;
      _drops[i].isVisible = shown;
      if (shown) _drops[i].setPositionFrom(airborne[i]);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    _run(_frame);
    _age += _frame;
    if (_age > 8.0) _restart();
    _place();
  }

  void _restart() {
    for (final MeshNode n in <MeshNode>[
      for (final _Glass g in <_Glass>[
        _left,
        _right,
        _basin,
        _source,
        _target,
      ]) ...<MeshNode>[g.glass, g.fill],
      _pipeNode,
      _blockNode,
      ..._drops,
    ]) {
      _scene.remove(n);
    }
    _drops.clear();
    _fill(_context, _scene);
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      fallback == null
          ? 'Liquids on the core'
          : 'Liquids on the core (unavailable: $fallback)',
      value: () => onCore && fallback == null,
      onChanged: (bool v) {
        onCore = v;
        _restart();
      },
    ),
    ToggleControl(
      'Fill again',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  /// The solver both worlds are stepped by, for a test that checks it.
  @visibleForTesting
  FluidSolver get solver => _vessels.solver;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (fallback == null && _vessels.solver is! NativeLiquid) {
      throw StateError('the liquids are not on the core');
    }
    // #region check
    // Two and a half seconds. The block bobs for longer than that, so what
    // is held is the share of it under water on average over the last one
    // and a quarter: the weight of the water it displaces is its own, so
    // that share is its density over water's.
    final double volume = 8.0 * _half.x * _half.y * _half.z;
    var under = 0.0;
    var samples = 0;
    for (var i = 0; i < 150; i++) {
      _runVessels(_frame);
      // The pour is the dear part: a second and a quarter of it is enough
      // for the stream to reach the wide tube.
      if (i < 75) _runPour(_frame);
      if (i >= 75) {
        under += _vessels.floating.single.submergedIn(_basin.body) / volume;
        samples++;
      }
    }
    // The U-tube has swung from six centimetres apart to level.
    final double apart = (_left.body.height - _right.body.height).abs();
    if (apart > 0.003) {
      throw StateError('the U-tube is ${apart * 1000} mm out of level');
    }
    final double share = under / samples;
    if ((share - _density / FluidMedium.water.density).abs() > 0.05) {
      throw StateError('the block floats ${share.toStringAsFixed(3)} under');
    }
    // The pour has reached the other tube, and not a drop is lost: what is
    // in the two tubes, in the air and on the bench is what there was.
    if (_target.body.volume <= 0.0) throw StateError('nothing was poured');
    if ((_pouring.volume - _pourTotal).abs() > _pourTotal * 1e-9) {
      throw StateError('the pour lost ${_pourTotal - _pouring.volume} m³');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
