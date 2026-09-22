/// A crowd that plays clips baked into a table, not a skeleton apiece.
///
/// A skinned draw hands the GPU one array of joint matrices, and that array
/// is the same for every instance of the draw. A thousand copies would all
/// stand in the same pose. `BakedPoses` samples every clip once into a table
/// instead, so each instance only needs which clip and how far into it, the
/// two numbers instancing already carries. This page fakes the "read a row of
/// the table" step on the CPU, since no draw path in this engine samples the
/// table on the GPU yet, but the table itself, and what a row of it means, are
/// exactly what a real one would read.
///
/// Quoted by `baked_crowd.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BakedCrowdDemo extends ShowcaseDemo {
  double _time = 0.0;
  static const int _framesPerClip = 32;
  static const int _people = 6;

  late final BakedPoses _table;
  late final List<double> _phase;
  late final List<int> _clip;
  late final List<SceneNode> _arms;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.3;
  }

  @override
  Scene build(DemoContext context) {
    // #region rig
    // The rig every clip is baked against: a shoulder with an arm hanging off
    // it. `BakedPoses` samples it once per clip and needs no scene of its own
    // afterwards.
    final Scene rig = Scene();
    final SceneNode shoulder = rig.add(SceneNode(name: 'shoulder'));
    final SceneNode arm = SceneNode(name: 'arm')..setPosition(0.0, -0.8, 0.0);
    shoulder.add(arm);
    final Skeleton skeleton = Skeleton(
      name: 'wave',
      joints: <SceneNode>[shoulder, arm],
      inverseBindMatrices: <Matrix4>[
        Matrix4.copy(shoulder.worldMatrix)..invert(),
        Matrix4.copy(arm.worldMatrix)..invert(),
      ],
    );
    // #endregion rig

    // #region bake
    // Two clips, a slow wave and a fast one, baked into one table. A crowd
    // wearing both is one sampler, not two.
    final AnimationPlayer player = AnimationPlayer(
      clips: <AnimationClip>[_wave(seconds: 1.6), _wave(seconds: 0.5)],
      targets: <AnimationTarget?>[shoulder, null],
    );
    _table = BakedPoses.of(
      player,
      skeleton: skeleton,
      meshWorld: Matrix4.identity(),
      framesPerClip: _framesPerClip,
    );
    // #endregion bake

    // A capsule-and-sphere silhouette rather than bare boxes — still a rigid
    // part per joint, which is what lets the table drive a whole mesh with
    // one matrix (see `{{code read}}`), but one a crowd actually reads as
    // people rather than furniture.
    final Scene scene = Scene();
    final Material torso = Material(
      name: 'torso',
      baseColor: Vector4(0.55, 0.6, 0.68, 1.0),
    );
    final Material limb = Material(
      name: 'arm',
      baseColor: Vector4(0.85, 0.5, 0.3, 1.0),
    );
    final Material skin = Material(
      name: 'head',
      baseColor: Vector4(0.85, 0.68, 0.55, 1.0),
    );
    final DeviceMesh torsoMesh = DeviceMesh.upload(
      context.device,
      CapsuleShape(radius: 0.22, height: 0.6).build(),
    );
    final DeviceMesh headMesh = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.18, segments: 16, rings: 12).build(),
    );
    final DeviceMesh armMesh = DeviceMesh.upload(
      context.device,
      CapsuleShape(radius: 0.09, height: 0.5).build(),
    );

    _phase = <double>[];
    _clip = <int>[];
    _arms = <SceneNode>[];
    for (var i = 0; i < _people; i++) {
      final int clip = i.isEven ? 0 : 1;
      _clip.add(clip);
      _phase.add(i / _people);
      final double x = (i - (_people - 1) / 2) * 1.1;
      scene.add(
        MeshNode(torsoMesh, torso, name: 'person $i')..setPosition(x, 0.0, 0.0),
      );
      scene.add(
        MeshNode(headMesh, skin, name: 'head $i')..setPosition(x, 0.68, 0.0),
      );
      final SceneNode shoulderNode = SceneNode(name: 'shoulder $i')
        ..setPosition(x, 0.55, 0.0);
      final SceneNode armNode = MeshNode(armMesh, limb, name: 'arm $i')
        ..setPosition(0.0, -0.4, 0.0);
      shoulderNode.add(armNode);
      scene.add(shoulderNode);
      _arms.add(armNode);
    }
    return scene;
  }

  AnimationClip _wave({required double seconds}) => AnimationClip(
    name: 'wave $seconds',
    tracks: <AnimationTrack>[
      AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, seconds / 2, seconds]),
        values: Float32List.fromList(<double>[
          0.0, 0.0, 0.0, 1.0, //
          ..._quarterZ(0.6),
          0.0, 0.0, 0.0, 1.0,
        ]),
        componentCount: 4,
      ),
    ],
  );

  static List<double> _quarterZ(double radians) {
    final Quaternion q = Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), radians)
      ..normalize();
    return <double>[q.x, q.y, q.z, q.w];
  }

  @override
  void update(DemoContext context, double dt) {
    _time += dt;
    // #region read
    // What a shader would do per instance: pick a clip's rows, blend the two
    // the current time falls between, and use the joint matrix that came out.
    // Nothing here touches a skeleton; the table already has the answer.
    //
    // A joint matrix is a delta from rest, not a place in the world — the
    // shoulder is joint 0, and its matrix is identity when the shoulder has
    // not turned. Composing it with the arm's own rest offset turns that
    // delta back into "where the arm hangs now, relative to its shoulder".
    for (var i = 0; i < _people; i++) {
      final int clip = _clip[i];
      final double duration = _table.durations[clip];
      final double t = ((_time + _phase[i] * duration) % duration) / duration;
      final double row = t * _framesPerClip;
      final int a = row.floor() % _framesPerClip;
      final int b = (a + 1) % _framesPerClip;
      final double f = row - row.floor();
      final Matrix4 ma = _table.matrixAt(clip, a, 0);
      final Matrix4 mb = _table.matrixAt(clip, b, 0);
      final Matrix4 shoulderDelta = Matrix4.zero();
      for (var e = 0; e < 16; e++) {
        shoulderDelta.storage[e] = ma.storage[e] * (1 - f) + mb.storage[e] * f;
      }
      _arms[i].setLocalMatrix(
        shoulderDelta.multiplied(Matrix4.translation(Vector3(0.0, -0.4, 0.0))),
      );
    }
    // #endregion read
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_table.clips != 2) throw StateError('two clips were baked');
    if (_table.frames != _framesPerClip) {
      throw StateError('the table samples $_framesPerClip frames a clip');
    }
    // A joint matrix is worldMatrix * inverseBindMatrix: at the shoulder's own
    // rest pose the two cancel, so row 0 of every clip has to read back as the
    // identity, or a crowd reading the table wears the wrong pose from frame
    // one.
    final Matrix4 rest = _table.matrixAt(0, 0, 0);
    if ((rest.clone()..sub(Matrix4.identity())).storage.any(
      (double v) => v.abs() > 0.01,
    )) {
      throw StateError('frame 0 is not the shoulder at rest');
    }
    if (frame.drawCalls < 1) throw StateError('the crowd was not drawn');
  }
}
