/// A shelf hung on a wall by two brackets that break, and crates set on it
/// one at a time until a bracket lets go. Stepped by the physics core: the
/// brackets are fixed joints with a force they give way past.
///
/// Quoted by `breakable_joints.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class BreakableJointsDemo extends ShowcaseDemo {
  NativeWorld? _world;
  late NativeBody _wall;
  late NativeBody _shelf;
  List<NativeJoint> _brackets = const <NativeJoint>[];
  final List<NativeBody> _crates = <NativeBody>[];

  /// Every `jointBroken` event the steps raised since the drop began.
  @visibleForTesting
  final List<NativeEvent> broken = <NativeEvent>[];

  late SceneNode _shelfNode;
  final List<MeshNode> _bracketNodes = <MeshNode>[];
  final List<MeshNode> _crateNodes = <MeshNode>[];

  /// Why nothing moves, or null when the core is running.
  String? unavailable;

  /// What each bracket holds before it lets go, N.
  double breakForce = 150.0;

  int _steps = 0;

  static const double _step = 1 / 60;

  /// Where a crate is set down, one every fifty steps.
  static const List<double> _slots = <double>[0.28, -0.28, 0.56, 0.0, -0.56];

  /// Where the brackets hold the shelf, along x.
  static const List<double> _bracketsAt = <double>[-0.6, 0.6];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.3
      ..yaw = 0.45;
    context.orbit.target.setValues(0.0, 0.9, 0.0);
  }

  // #region hang
  /// A floor, a wall, and a four-kilogram shelf held to the wall by two
  /// fixed joints. Each joint gives way once it holds the shelf with more
  /// than [breakForce] newtons.
  void _hang(NativeWorld world) {
    final NativeBody floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(3.0, 0.5, 2.0)));
    _wall = world.addBody(
      position: Vector3(0.0, 1.2, -0.35),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(_wall, NativeShape.box(Vector3(1.2, 1.2, 0.1)));
    _shelf = world.addBody(position: Vector3(0.0, 1.4, 0.0), mass: 4.0);
    world.setShape(_shelf, NativeShape.box(Vector3(0.7, 0.03, 0.22)));
    _brackets = <NativeJoint>[
      for (final double x in _bracketsAt)
        world.createJoint(
          NativeJointType.fixed,
          _wall,
          _shelf,
          anchor: Vector3(x, 1.4, -0.22),
        ),
    ];
    for (final NativeJoint bracket in _brackets) {
      world.setJointBreak(bracket, force: breakForce);
    }
  }
  // #endregion hang

  // #region tick
  /// One step: a three-kilogram crate set down five centimetres over the
  /// shelf every fifty steps, the world stepped, and the breaks it raised
  /// kept. The other events are read and let go, so none pile up.
  void _tick(NativeWorld world) {
    if (_steps % 50 == 20 && _crates.length < _slots.length) {
      final NativeBody crate = world.addBody(
        position: Vector3(_slots[_crates.length], 1.6, 0.02),
        mass: 3.0,
      );
      world
        ..setShape(crate, NativeShape.box(Vector3.all(0.12)))
        ..setFriction(crate, 0.8);
      _crates.add(crate);
    }
    world.step(_step);
    _steps++;
    broken.addAll(
      world.readEvents().where((e) => e.kind == NativeEventKind.jointBroken),
    );
  }
  // #endregion tick

  /// Starts the core and hangs the shelf again, or keeps the reason the core
  /// would not start.
  void _start() {
    _world?.dispose();
    _world = null;
    _crates.clear();
    broken.clear();
    _steps = 0;
    if (!physicsCoreLoaded) {
      unavailable = 'the core is not loaded in this browser yet';
      return;
    }
    try {
      final world = NativeWorld();
      _hang(world);
      _world = world;
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
    MeshNode box(String name, Vector3 size, Vector4 color) => MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
      RenderMaterial(name: name, baseColor: _fromSrgb(color), roughness: 0.7),
      name: name,
    );
    _shelfNode = SceneNode(name: 'shelf')
      ..add(
        box(
          'shelf board',
          Vector3(1.4, 0.06, 0.44),
          Vector4(0.62, 0.45, 0.3, 1),
        ),
      );
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      )
      ..add(
        box('floor', Vector3(6.0, 1.0, 4.0), Vector4(0.42, 0.45, 0.48, 1))
          ..setPosition(0.0, -0.5, 0.0),
      )
      ..add(
        box('wall', Vector3(2.4, 2.4, 0.2), Vector4(0.7, 0.68, 0.62, 1))
          ..setPosition(0.0, 1.2, -0.35),
      )
      ..add(_shelfNode);
    for (final (int i, double x) in _bracketsAt.indexed) {
      final MeshNode bracket = box(
        'bracket $i',
        Vector3(0.06, 0.16, 0.08),
        Vector4(0.25, 0.27, 0.3, 1),
      )..setPosition(x, 1.35, -0.21);
      _bracketNodes.add(bracket);
      scene.add(bracket);
    }
    for (var i = 0; i < _slots.length; i++) {
      final MeshNode crate = box(
        'crate $i',
        Vector3.all(0.24),
        Vector4(
          0.55 + 0.35 * math.sin(i * 1.1),
          0.5 + 0.3 * math.sin(i * 1.9 + 1.0),
          0.35 + 0.25 * math.sin(i * 2.7 + 2.0),
          1,
        ),
      );
      _crateNodes.add(crate);
      scene.add(crate);
    }
    _place();
    return scene;
  }

  // #region show
  /// The shelf and the crates where the core has them; a bracket drawn for
  /// as long as its joint is still in the world.
  void _place() {
    final NativeWorld? world = _world;
    for (final (int i, MeshNode node) in _crateNodes.indexed) {
      node.isVisible = world != null && i < _crates.length;
      if (node.isVisible) {
        node
          ..setPositionFrom(world!.localPositionOf(_crates[i]))
          ..setRotation(world.orientationOf(_crates[i]));
      }
    }
    if (world == null) {
      _shelfNode.setPosition(0.0, 1.4, 0.0);
      return;
    }
    _shelfNode
      ..setPositionFrom(world.localPositionOf(_shelf))
      ..setRotation(world.orientationOf(_shelf));
    for (final (int i, NativeJoint bracket) in _brackets.indexed) {
      _bracketNodes[i].isVisible = world.containsJoint(bracket);
    }
  }
  // #endregion show

  @override
  void update(DemoContext context, double dt) {
    final NativeWorld? world = _world;
    if (world == null) return;
    _tick(world);
    if (_steps > 420) _start();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Bracket breaks past',
      min: 60.0,
      max: 250.0,
      divisions: 19,
      value: () => breakForce,
      onChanged: (double v) {
        breakForce = v;
        _start();
      },
      format: (double v) => '${v.round()} N',
    ),
    ToggleControl(
      unavailable == null
          ? 'Hang it again'
          : 'Hang it again (unavailable: $unavailable)',
      value: () => false,
      onChanged: (bool v) {
        if (v) _start();
      },
    ),
  ];

  /// Steps the drop on until [steps] steps have been taken since it began.
  @visibleForTesting
  void runTo(int steps) {
    final NativeWorld world = _world!;
    while (_steps < steps) {
      _tick(world);
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (unavailable != null) {
      throw StateError('the core did not start: $unavailable');
    }
    breakForce = 150.0;
    _start();
    final NativeWorld world = _world!;
    // #region check
    // Four crates on: 16 kg, held half by each bracket, 78.5 N apiece, and
    // under the 150 they break past.
    runTo(210);
    for (final NativeJoint bracket in _brackets) {
      if (!world.containsJoint(bracket)) {
        throw StateError('a bracket let go under four crates');
      }
      final double held = world.jointForce(bracket).y;
      if ((held - 78.5).abs() > 1.5) {
        throw StateError('a bracket holds ${held.toStringAsFixed(1)} N');
      }
    }
    // The fifth crate's landing takes both past it. Each break is an event
    // that names the wall and the shelf, and the shelf ends on the floor.
    runTo(300);
    if (_brackets.any(world.containsJoint)) {
      throw StateError('a bracket held under five crates');
    }
    if (broken.length != 2 ||
        broken.any((e) => e.body != _wall || e.other != _shelf)) {
      throw StateError('the breaks were told as $broken');
    }
    final double shelfAt = world.localPositionOf(_shelf).y;
    if (shelfAt > 0.1) {
      throw StateError('the shelf hangs at $shelfAt m with no brackets');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
