/// A ragdoll of eleven capsules on ten joints, standing at the top of a
/// short flight of stairs and pushed down it.
///
/// Quoted by `ragdoll.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show SegmentMassShares, referenceBodyMass;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class RagdollDemo extends ShowcaseDemo {
  NativeWorld? _world;
  NativeRagdoll? _doll;

  /// Why nothing moves: the core would not start. Null when it did.
  String? unavailable;

  final List<MeshNode> _bones = <MeshNode>[];
  double _age = 0.0;

  static const double _step = 1 / 60;

  /// The stairs: four steps of [_rise] up and [_run] deep, the top one a
  /// landing that reaches back to x = −1.5.
  static const int _steps = 4;
  static const double _rise = 0.25;
  static const double _run = 0.45;

  /// Where the figure's feet stand: on the landing, a centimetre above it.
  static Vector3 get _feet => Vector3(-0.4, _steps * _rise + 0.01, 0.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.35
      ..yaw = 0.6;
    context.orbit.target.setValues(0.5, 0.7, 0.0);
  }

  // #region figure
  /// A figure standing with its feet at [o]: hips, chest, head, two arms
  /// and two legs, each bone from its head (where it meets its parent) to
  /// its tail, with a radius and a mass — the reference man's 73 kg shared
  /// as de Leva measured (`SegmentMassShares`), a forearm with its hand and a
  /// shin with its foot. Its spine and neck are ball joints
  /// in a narrow cone, the shoulders and hips wide ones, the elbows and
  /// knees hinges that bend one way.
  static List<RagdollBone> _figure(Vector3 o) {
    const spine = RagdollBall(cone: 0.5, twistLower: -0.4, twistUpper: 0.4);
    const shoulder = RagdollBall(cone: 1.5, twistLower: -1.0, twistUpper: 1.0);
    const hip = RagdollBall(cone: 1.2, twistLower: -0.5, twistUpper: 0.5);
    final elbow = RagdollHinge(axis: Vector3(1, 0, 0), lower: 0, upper: 2.4);
    final knee = RagdollHinge(axis: Vector3(1, 0, 0), lower: -2.4, upper: 0);
    double kg(double share) => referenceBodyMass * share;
    RagdollBone bone(
      String name,
      int parent,
      (double, double, double) head,
      (double, double, double) tail,
      double radius,
      double mass, [
      RagdollJoint? joint,
    ]) => RagdollBone(
      name: name,
      parent: parent,
      head: o + Vector3(head.$1, head.$2, head.$3),
      tail: o + Vector3(tail.$1, tail.$2, tail.$3),
      orientation: Quaternion.identity(),
      radius: radius,
      mass: mass,
      joint: joint,
    );
    return <RagdollBone>[
      bone(
        'hips',
        -1,
        (0, 0.92, 0),
        (0, 1.1, 0),
        0.13,
        kg(SegmentMassShares.lowerTrunk),
      ),
      bone(
        'chest',
        0,
        (0, 1.1, 0),
        (0, 1.55, 0),
        0.15,
        kg(SegmentMassShares.upperTrunk + SegmentMassShares.middleTrunk),
        spine,
      ),
      bone(
        'head',
        1,
        (0, 1.58, 0),
        (0, 1.82, 0),
        0.11,
        kg(SegmentMassShares.head),
        spine,
      ),
      bone(
        'arm.L',
        1,
        (-0.25, 1.5, 0),
        (-0.25, 1.2, 0),
        0.05,
        kg(SegmentMassShares.upperArm),
        shoulder,
      ),
      bone(
        'arm.R',
        1,
        (0.25, 1.5, 0),
        (0.25, 1.2, 0),
        0.05,
        kg(SegmentMassShares.upperArm),
        shoulder,
      ),
      bone(
        'forearm.L',
        3,
        (-0.25, 1.2, 0),
        (-0.25, 0.92, 0),
        0.045,
        kg(SegmentMassShares.forearm + SegmentMassShares.hand),
        elbow,
      ),
      bone(
        'forearm.R',
        4,
        (0.25, 1.2, 0),
        (0.25, 0.92, 0),
        0.045,
        kg(SegmentMassShares.forearm + SegmentMassShares.hand),
        elbow,
      ),
      bone(
        'thigh.L',
        0,
        (-0.1, 0.92, 0),
        (-0.1, 0.5, 0),
        0.07,
        kg(SegmentMassShares.thigh),
        hip,
      ),
      bone(
        'thigh.R',
        0,
        (0.1, 0.92, 0),
        (0.1, 0.5, 0),
        0.07,
        kg(SegmentMassShares.thigh),
        hip,
      ),
      bone(
        'shin.L',
        7,
        (-0.1, 0.5, 0),
        (-0.1, 0.06, 0),
        0.055,
        kg(SegmentMassShares.shank + SegmentMassShares.foot),
        knee,
      ),
      bone(
        'shin.R',
        8,
        (0.1, 0.5, 0),
        (0.1, 0.06, 0),
        0.055,
        kg(SegmentMassShares.shank + SegmentMassShares.foot),
        knee,
      ),
    ];
  }
  // #endregion figure

  /// The floor's and each step's box, as centre and half extents.
  static List<(Vector3, Vector3)> get _blocks => <(Vector3, Vector3)>[
    (Vector3(0.0, -0.5, 0.0), Vector3(6.0, 0.5, 3.0)),
    for (var i = 0; i < _steps; i++)
      (
        Vector3((-1.5 + (i + 1) * _run) / 2, (_steps - i) * _rise / 2, 0.0),
        Vector3(((i + 1) * _run + 1.5) / 2, (_steps - i) * _rise / 2, 1.2),
      ),
  ];

  // #region world
  /// A world with the floor and the stairs as fixed boxes, and the figure
  /// standing on the landing. Eight substeps a step, not four: at four, a
  /// limb struck on a stair's edge can swing past its cone for a step.
  void _build() {
    unavailable = null;
    _world = null;
    _doll = null;
    if (!physicsCoreLoaded) {
      unavailable = 'the core is not loaded in this browser yet';
      return;
    }
    final NativeWorld world;
    try {
      world = NativeWorld()..substeps = 8;
    } on Object catch (e) {
      unavailable = '$e';
      return;
    }
    for (final (Vector3 center, Vector3 half) in _blocks) {
      final NativeBody block = world.addBody(
        position: center,
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      world.setShape(block, NativeShape.box(half));
    }
    _world = world;
    // Every joint resists turning with two newton metres, the default;
    // without it a ragdoll on the floor never comes to rest.
    _doll = NativeRagdoll(world, _figure(_feet));
  }
  // #endregion world

  // #region push
  /// A shove to the chest, forward and a little to the side: ninety-five
  /// newton seconds on its 23.6 kilograms, four metres a second.
  void _push() {
    final NativeRagdoll? doll = _doll;
    if (doll == null) return;
    _world!.applyImpulse(doll.bodyOf(1), Vector3(95.0, 0.0, 12.5));
  }
  // #endregion push

  void _restart() {
    _world?.dispose();
    _build();
    _push();
    _age = 0.0;
  }

  @override
  void dispose() => _world?.dispose();

  @override
  Scene build(DemoContext context) {
    _build();
    _push();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.3)),
      );
    final stone = RenderMaterial(
      name: 'stone',
      baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.52, 1.0),
      roughness: 0.8,
    );
    for (final (Vector3 center, Vector3 half) in _blocks) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: half * 2.0).build(),
          ),
          stone,
          name: 'block',
        )..setPositionFrom(center),
      );
    }
    // #region bones
    // Each bone drawn as the capsule its body is: along the body's own y,
    // its straight part as long as the bone less its two rounded ends.
    final cloth = RenderMaterial(
      name: 'ragdoll',
      baseColor: LinearColor.fromSrgb(0.8, 0.55, 0.35, 1.0),
      roughness: 0.6,
    );
    for (final RagdollBone bone in _figure(_feet)) {
      final double length = bone.head.distanceTo(bone.tail);
      final double straight = math.max(0.02, length - 2 * bone.radius);
      final node = MeshNode(
        DeviceMesh.upload(
          context.device,
          CapsuleShape(radius: bone.radius, height: straight).build(),
        ),
        cloth,
        name: bone.name,
      );
      _bones.add(node);
      scene.add(node);
    }
    // #endregion bones
    _place();
    return scene;
  }

  void _place() {
    final NativeRagdoll? doll = _doll;
    if (doll == null) return;
    for (var i = 0; i < _bones.length; i++) {
      final NativeBody body = doll.bodyOf(i);
      _bones[i]
        ..setPositionFrom(doll.world.localPositionOf(body))
        ..setRotation(doll.world.orientationOf(body));
    }
  }

  @override
  void update(DemoContext context, double dt) {
    final NativeWorld? world = _world;
    if (world == null) return;
    world.step(_step);
    _age += dt;
    if (_age > 8.0) _restart();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      unavailable == null
          ? 'Push it again'
          : 'Push it again (the core is unavailable: $unavailable)',
      value: () => false,
      onChanged: (bool v) {
        if (!v) return;
        _push();
        _age = 0.0;
      },
    ),
    ToggleControl(
      'Stand it up again',
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
    // From the push until it sleeps, each bone's head read against its
    // parent's after every step: how far apart they are against how far
    // apart they were built.
    _restart();
    final NativeRagdoll doll = _doll!;
    final List<RagdollBone> bones = doll.bones;
    final double hipsFrom = doll.poseOf(0).position.y;
    var stretched = 0.0;
    var steps = 0;
    while (!doll.isAsleep && steps < 900) {
      _world!.step(_step);
      steps++;
      for (var i = 1; i < bones.length; i++) {
        final RagdollBone b = bones[i];
        final double built = b.head.distanceTo(bones[b.parent].head);
        final double now = doll
            .poseOf(i)
            .position
            .distanceTo(doll.poseOf(b.parent).position);
        stretched = math.max(stretched, (now - built).abs());
      }
    }
    if (!doll.isAsleep) throw StateError('it never came to rest');
    // No joint opens by more than 3 cm on the way down.
    if (stretched > 0.03) {
      throw StateError('a joint opened by ${stretched.toStringAsFixed(3)} m');
    }
    // It came down the stairs, and nothing ended inside the floor: a
    // capsule lying on it has its centre a radius up.
    if (doll.poseOf(0).position.y > hipsFrom - 0.5) {
      throw StateError('it never went down the stairs');
    }
    for (var i = 0; i < bones.length; i++) {
      final double y = _world!.localPositionOf(doll.bodyOf(i)).y;
      if (y < bones[i].radius - 0.01) {
        throw StateError('${bones[i].name} ended in the floor at $y');
      }
    }
    // #endregion check
  }
}
