/// The same chain twice, side by side on the physics core: twelve light
/// links and a heavy weight on the end, laid out level and let go. The
/// left chain is held by ordinary hinge joints, the right one is a
/// multibody. Each link reddens as the joint above it opens.
///
/// Quoted by `multibody_chain.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class MultibodyChainDemo extends ShowcaseDemo {
  NativeWorld? _world;

  /// Each chain's bodies: its post, then its links, the weight last.
  List<NativeBody> _joints = const <NativeBody>[];
  List<NativeBody> _multibody = const <NativeBody>[];

  /// Why there are no chains, or null when there are.
  String? fallback;

  /// The weight on the end of each chain, kg. Every link is 0.1 kg.
  double weight = 10.0;

  double _age = 0.0;

  final List<MeshNode> _jointMeshes = <MeshNode>[];
  final List<MeshNode> _multibodyMeshes = <MeshNode>[];
  final List<RenderMaterial> _jointPaint = <RenderMaterial>[];
  final List<RenderMaterial> _multibodyPaint = <RenderMaterial>[];

  static const int _count = 12;
  static const double _half = 0.15;
  static const double _radius = 0.15;
  static const double _height = 5.0;

  /// Where each chain's post stands along x. Both are laid out to +x from
  /// their post, and this far apart they never swing into each other.
  static const double _left = -4.0;
  static const double _right = 4.0;
  static const double _step = 1 / 60;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 15.0
      ..pitch = 0.1
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 3.0, 0.0);
  }

  NativeWorld? _open() {
    fallback = null;
    if (!physicsCoreLoaded) {
      fallback = 'the core is not loaded in this browser yet';
      return null;
    }
    try {
      return NativeWorld()..setSleep(speed: 0.0, time: 0.0);
    } on Object catch (e) {
      fallback = '$e';
      return null;
    }
  }

  // #region lay
  /// A post at [x] and a chain laid out level from it to +x: twelve links
  /// 0.3 m long and 0.1 kg each, then a ball of [weight] kg. [join] holds
  /// each body to the one before it, link [parent] of [bodies], at
  /// [anchor].
  List<NativeBody> _lay(
    NativeWorld world,
    double x,
    void Function(List<NativeBody> bodies, int parent, Vector3 anchor) join,
  ) {
    final NativeBody post = world.addBody(
      position: Vector3(x, _height, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(post, NativeShape.box(Vector3.all(0.05)));
    final bodies = <NativeBody>[post];
    for (var k = 0; k <= _count; k++) {
      final bool last = k == _count;
      final double near = x + k * 2 * _half;
      final NativeBody body = world.addBody(
        position: Vector3(near + (last ? _radius : _half), _height, 0.0),
        mass: last ? weight : 0.1,
      );
      world.setShape(
        body,
        last
            ? const NativeShape.sphere(_radius)
            : NativeShape.box(Vector3(_half, 0.03, 0.03)),
      );
      bodies.add(body);
      join(bodies, k, Vector3(near, _height, 0.0));
    }
    return bodies;
  }
  // #endregion lay

  // #region both
  /// The left chain on ordinary hinges about z, each a constraint the
  /// solver pulls closed; the right one a multibody, rooted at its post,
  /// each link placed from its parent by one angle about z.
  void _restart() {
    _world?.dispose();
    final NativeWorld? world = _world = _open();
    _age = 0.0;
    if (world == null) return;
    final Vector3 z = Vector3(0.0, 0.0, 1.0);
    _joints = _lay(world, _left, (bodies, parent, at) {
      world.createJoint(
        NativeJointType.revolute,
        bodies[parent],
        bodies.last,
        anchor: at,
        axis: z,
      );
    });
    NativeMultibody? chain;
    _multibody = _lay(world, _right, (bodies, parent, at) {
      chain ??= world.createMultibody(bodies.first);
      world.addLink(
        chain!,
        bodies.last,
        parent: parent,
        type: NativeJointType.revolute,
        anchor: at,
        axis: z,
      );
    });
  }
  // #endregion both

  // #region gap
  /// How far apart the two sides of the joint above link [k] of [bodies]
  /// are, m: the parent's far end against the link's near end, each where
  /// its own body has it now. Nought for a joint that holds.
  double _gap(List<NativeBody> bodies, int k) {
    final NativeWorld world = _world!;
    Vector3 end(NativeBody body, double along) =>
        world.localPositionOf(body) +
        world
            .orientationOf(body)
            .asRotationMatrix()
            .transformed(Vector3(along, 0.0, 0.0));
    final NativeBody parent = bodies[k - 1];
    final NativeBody link = bodies[k];
    return (end(parent, k == 1 ? 0.0 : _half) -
            end(link, k == bodies.length - 1 ? -_radius : -_half))
        .length;
  }

  /// The widest joint of [bodies] now.
  double _widest(List<NativeBody> bodies) => <double>[
    for (var k = 1; k < bodies.length; k++) _gap(bodies, k),
  ].reduce(math.max);
  // #endregion gap

  @override
  void dispose() => _world?.dispose();

  @override
  Scene build(DemoContext context) {
    _restart();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.5)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(20.0, 0.2, 6.0)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.4, 0.42, 0.45, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.1, 0.0),
      );
    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.12, 5.2, 0.12)).build(),
    );
    final DeviceMesh link = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(2 * _half, 0.06, 0.06)).build(),
    );
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: _radius, segments: 24, rings: 12).build(),
    );
    for (final (
          double x,
          String side,
          List<MeshNode> meshes,
          List<RenderMaterial> paint,
        )
        in <(double, String, List<MeshNode>, List<RenderMaterial>)>[
          (_left, 'joints', _jointMeshes, _jointPaint),
          (_right, 'multibody', _multibodyMeshes, _multibodyPaint),
        ]) {
      scene.add(
        MeshNode(
          post,
          RenderMaterial(
            name: 'post',
            baseColor: LinearColor.fromSrgb(0.3, 0.3, 0.32, 1.0),
          ),
          name: 'post $side',
        )..setPosition(x, _height / 2, -0.1),
      );
      for (var k = 0; k <= _count; k++) {
        final material = RenderMaterial(
          name: '$side link $k',
          baseColor: LinearColor.fromSrgb(0.8, 0.8, 0.78, 1.0),
          roughness: 0.5,
        );
        final mesh = MeshNode(
          k == _count ? ball : link,
          material,
          name: '$side link $k',
        );
        paint.add(material);
        meshes.add(mesh);
        scene.add(mesh);
      }
    }
    _place();
    return scene;
  }

  // #region draw
  /// Every link where the core has it, reddening as the joint above it
  /// opens: fully red at three centimetres.
  void _place() {
    if (_world == null) return;
    for (final (List<NativeBody> bodies, List<MeshNode> meshes, paint)
        in <(List<NativeBody>, List<MeshNode>, List<RenderMaterial>)>[
          (_joints, _jointMeshes, _jointPaint),
          (_multibody, _multibodyMeshes, _multibodyPaint),
        ]) {
      for (var k = 1; k < bodies.length; k++) {
        meshes[k - 1]
          ..setPositionFrom(_world!.localPositionOf(bodies[k]))
          ..setRotation(_world!.orientationOf(bodies[k]));
        final double open = math.min(_gap(bodies, k) / 0.03, 1.0);
        paint[k - 1].baseColor = LinearColor.fromSrgb(
          0.8 + 0.15 * open,
          0.8 - 0.65 * open,
          0.78 - 0.65 * open,
          1.0,
        );
      }
    }
  }
  // #endregion draw

  @override
  void update(DemoContext context, double dt) {
    final NativeWorld? world = _world;
    if (world == null) return;
    world.step(_step);
    _age += _step;
    if (_age > 10.0) _restart();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Weight on the end',
      min: 1.0,
      max: 20.0,
      divisions: 19,
      value: () => weight,
      onChanged: (double v) {
        weight = v;
        _restart();
      },
      format: (double v) => '${v.toStringAsFixed(0)} kg',
    ),
    ToggleControl(
      fallback == null ? 'Let go again' : 'Unavailable: $fallback',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  /// The widest any joint of each chain opens over [steps] from a fresh
  /// start, m.
  @visibleForTesting
  ({double joints, double multibody}) widestOver(int steps) {
    _restart();
    var joints = 0.0;
    var multibody = 0.0;
    for (var i = 0; i < steps; i++) {
      _world!.step(_step);
      joints = math.max(joints, _widest(_joints));
      multibody = math.max(multibody, _widest(_multibody));
    }
    return (joints: joints, multibody: multibody);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    if (_world == null) throw StateError('no physics core: $fallback');
    // #region check
    // Two seconds from level with ten kilograms on the end. The core holds
    // every multibody joint to a thousandth of a millimetre, and lets an
    // ordinary one open by four centimetres.
    weight = 10.0;
    final (:double joints, :double multibody) = widestOver(120);
    if (multibody > 1e-3) {
      throw StateError('a multibody joint opened by $multibody m');
    }
    if (joints < 1e-2) {
      throw StateError('the ordinary chain held to $joints m');
    }
    // And the multibody has swung: its weight is well below its post.
    final double low = _world!.localPositionOf(_multibody.last).y;
    if (low > _height - 2.0) {
      throw StateError('the multibody weight is still at $low');
    }
    // #endregion check
  }
}
