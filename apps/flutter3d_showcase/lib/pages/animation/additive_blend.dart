/// Three heads turn at the same steady rate. Every couple of seconds the
/// middle and right ones are nudged with the same quick nod: laid on top of
/// the turn additively on the middle head, replacing it on the right one —
/// `AnimationBlend.additive` and `AnimationClip.referenceTime`.
///
/// Quoted by `additive_blend.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AdditiveBlendDemo extends ShowcaseDemo {
  late final AnimationTrack _turnTrack;
  late final AnimationTrack _nodTrack;
  late final AnimationPlayer _plain;
  late final AnimationPlayer _additive;
  late final AnimationPlayer _override;
  late final MeshNode _additiveHead;
  late final MeshNode _overrideHead;
  AnimationLayer? _additiveNod;
  AnimationLayer? _overrideNod;

  double turnSpeed = 1.0;
  double _sinceNod = 0.0;

  /// How often the nod is played again, in seconds of the demo's own clock.
  static const double _period = 2.2;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.25
      ..yaw = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh box = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
    );
    final DeviceMesh nose = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.3, 0.3, 0.5)).build(),
    );
    MeshNode head(String name, Vector4 colour, double x) {
      final MeshNode node = MeshNode(
        box,
        Material(name: name, baseColor: colour, roughness: 0.6),
        name: name,
      )..setPosition(x, 0.0, 0.0);
      // A face, so a turn and a nod each read as one: a plain cube looks
      // the same after a quarter turn.
      node.add(
        MeshNode(
          nose,
          Material(name: '$name nose', baseColor: Vector4(0.95, 0.9, 0.8, 1.0)),
          name: '$name nose',
        )..setPosition(0.0, 0.0, 0.7),
      );
      return node;
    }

    final MeshNode plainHead = head(
      'turn only',
      Vector4(0.6, 0.6, 0.65, 1),
      -2.2,
    );
    _additiveHead = head('additive', Vector4(0.35, 0.75, 0.45, 1), 0.0);
    _overrideHead = head('override', Vector4(0.9, 0.5, 0.3, 1), 2.2);

    // #region clips
    _turnTrack = _turnAroundY();
    final AnimationClip turn = AnimationClip(
      name: 'turn',
      tracks: <AnimationTrack>[_turnTrack],
    );
    _nodTrack = _nodAroundX();
    final AnimationClip nod = AnimationClip(
      name: 'nod',
      tracks: <AnimationTrack>[_nodTrack],
      // The rest pose the nod is a difference from: at time zero it asks
      // for nothing, so laid on top of a turn it leaves the turn alone.
      referenceTime: 0.0,
    );
    // #endregion clips

    AnimationPlayer playerFor(MeshNode node) => AnimationPlayer(
      clips: <AnimationClip>[turn, nod],
      targets: <AnimationTarget?>[node],
    )..play(0);
    _plain = playerFor(plainHead);
    _additive = playerFor(_additiveHead);
    _override = playerFor(_overrideHead);

    _nodBoth();
    // Start a fifth of a second in, with the nod at its deepest, so the
    // first frame already shows the difference between the two blends.
    for (final AnimationPlayer player in <AnimationPlayer>[
      _plain,
      _additive,
      _override,
    ]) {
      player.update(0.2);
    }
    _sinceNod = 0.2;

    return Scene()
      ..add(plainHead)
      ..add(_additiveHead)
      ..add(_overrideHead)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      );
  }

  /// A full turn about Y in quarter turns, a keyframe each: a single
  /// keyframe pair from zero to a full turn would interpolate along the
  /// shortest path, which is no turn at all.
  static AnimationTrack _turnAroundY() {
    const int keys = 5;
    final Float32List values = Float32List(keys * 4);
    for (var i = 0; i < keys; i++) {
      final Quaternion q = Quaternion.axisAngle(
        Vector3(0.0, 1.0, 0.0),
        i * math.pi / 2,
      );
      values.setRange(i * 4, i * 4 + 4, <double>[q.x, q.y, q.z, q.w]);
    }
    return AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 1.5, 3.0, 4.5, 6.0]),
      values: values,
      componentCount: 4,
    );
  }

  /// Nothing, a nod forward, nothing again, over four tenths of a second.
  static AnimationTrack _nodAroundX() {
    final List<double> angles = <double>[0.0, 0.7, 0.0];
    final Float32List values = Float32List(angles.length * 4);
    for (var i = 0; i < angles.length; i++) {
      final Quaternion q = Quaternion.axisAngle(
        Vector3(1.0, 0.0, 0.0),
        angles[i],
      );
      values.setRange(i * 4, i * 4 + 4, <double>[q.x, q.y, q.z, q.w]);
    }
    return AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 0.2, 0.4]),
      values: values,
      componentCount: 4,
    );
  }

  /// Plays the nod once on the two heads that get one, each in its own blend
  /// mode, taking away the previous nod first.
  void _nodBoth() {
    // #region additive
    if (_additiveNod != null) _additive.layers.remove(_additiveNod);
    _additiveNod = _additive.playLayer(
      1,
      wrap: AnimationWrap.once,
      fadeIn: 0.0,
      blend: AnimationBlend.additive,
    );
    // #endregion additive
    if (_overrideNod != null) _override.layers.remove(_overrideNod);
    _overrideNod = _override.playLayer(
      1,
      wrap: AnimationWrap.once,
      fadeIn: 0.0,
      blend: AnimationBlend.override,
    );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _sinceNod += dt;
    if (_sinceNod >= _period) {
      _sinceNod -= _period;
      _nodBoth();
    }
    for (final AnimationPlayer player in <AnimationPlayer>[
      _plain,
      _additive,
      _override,
    ]) {
      player.speed = turnSpeed;
    }
    _plain.update(dt);
    _additive.update(dt);
    _override.update(dt);
    // A finished override layer would go on holding its last pose, which is
    // the head facing dead ahead: taking it off is what lets the turn resume.
    final AnimationLayer? finished = _overrideNod;
    if (finished != null && finished.isFinished) {
      _override.layers.remove(finished);
      _overrideNod = null;
    }
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Turn speed',
      min: 0,
      max: 2,
      value: () => turnSpeed,
      onChanged: (double v) => turnSpeed = v,
    ),
  ];

  Quaternion _sample(AnimationTrack track, double time) {
    final Float32List out = Float32List(4);
    track.sample(time, out);
    return Quaternion(out[0], out[1], out[2], out[3]);
  }

  static double _dot(Quaternion a, Quaternion b) =>
      (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w).abs();

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final AnimationLayer? nod = _additiveNod;
    if (nod == null) throw StateError('the additive head has no nod playing');

    final Quaternion turn = _sample(_turnTrack, _additive.time);
    final Quaternion delta =
        (_sample(_nodTrack, 0.0).conjugated() * _sample(_nodTrack, nod.time))
          ..normalize();
    if ((delta.w - 1.0).abs() < 1e-3) {
      throw StateError('the nod has not moved yet; nothing to add');
    }

    Quaternion rotationOf(MeshNode head) =>
        Quaternion.fromRotation(head.worldMatrix.getRotation());
    final Quaternion added = rotationOf(_additiveHead);
    if (_dot(added, (turn * delta)..normalize()) < 0.999) {
      throw StateError('the middle head is not the turn with the nod on top');
    }
    if (_dot(added, rotationOf(_overrideHead)) > 0.999) {
      throw StateError(
        'the right head should have had its turn replaced by the nod, and '
        'looks the same as the one that kept it',
      );
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('the heads were not drawn');
  }
}
