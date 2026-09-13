/// `pickJointAt`: which joint a click near a skeleton overlay meant —
/// `anim-08`'s own worked example, "клик по суставу 7 выбирает 7".
///
///     flutter test test/joint_picking_test.dart
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, PerspectiveProjection;
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter3d_modeler/src/joint_picking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const Size _viewport = Size(800.0, 600.0);
const double _fovY = math.pi / 4.0;
const double _eyeZ = 5.0;

/// Where [world] lands on screen, worked out independently of `project` —
/// the same oracle `element_picking_test.dart`'s own `screenOf` is, so a
/// bug shared between the two would not cancel itself out here either.
Offset _screenOf(Vector3 world) {
  final focal = 1.0 / math.tan(_fovY / 2.0);
  final depth = _eyeZ - world.z;
  final aspect = _viewport.width / _viewport.height;
  return Offset(
    ((world.x * focal / (aspect * depth)) + 1.0) * _viewport.width / 2.0,
    (1.0 - world.y * focal / depth) * _viewport.height / 2.0,
  );
}

PickingView _view() => PickingView(
  camera: CameraNode(
    projection: PerspectiveProjection(
      fovYRadians: _fovY,
      near: 0.1,
      far: 100.0,
    ),
  )..setPosition(0.0, 0.0, _eyeZ),
  size: _viewport,
);

void main() {
  test('a click at joint 7\'s own screen position picks joint 7 — the '
      'row\'s own worked example', () {
    final view = _view();
    // Eight joints spread out enough that none is within radius of another
    // one's own screen position.
    final joints = <int, Vector3>{
      for (var i = 0; i < 8; i++) i: Vector3((i - 4) * 0.3, 0.0, 0.0),
    };

    final at = _screenOf(joints[7]!);
    expect(pickJointAt(view, at, joints: joints), 7);
  });

  test('nothing is picked past the radius', () {
    final view = _view();
    final joints = <int, Vector3>{0: Vector3.zero()};
    final at = _screenOf(Vector3.zero()).translate(20.0, 0.0);

    expect(pickJointAt(view, at, joints: joints, radius: 8.0), isNull);
  });

  test('the nearer of two joints within radius wins', () {
    final view = _view();
    final centre = Vector3(0.1, 0.0, 0.0);
    final near = _screenOf(centre);
    // A second joint a few pixels further from the click than joint 0, both
    // within an 8-pixel radius of it.
    final joints = <int, Vector3>{0: centre, 1: Vector3(0.1, 0.02, 0.0)};

    expect(pickJointAt(view, near, joints: joints, radius: 8.0), 0);
  });

  test('a joint behind the camera is never picked, however close its own '
      'projection would land', () {
    final view = _view();
    final joints = <int, Vector3>{0: Vector3(0.0, 0.0, _eyeZ + 1.0)};

    expect(
      pickJointAt(view, const Offset(400.0, 300.0), joints: joints),
      isNull,
    );
  });

  test('an empty skeleton picks nothing', () {
    final view = _view();
    expect(
      pickJointAt(view, const Offset(400.0, 300.0), joints: const {}),
      isNull,
    );
  });
}
