/// `anim-20`'s own row: a shape key driven by a joint's rotation, evaluated
/// live off a `ProjectClip`'s own rotation track and baked into a weights
/// track that samples to the same numbers.
///
///     dart test test/shape_driver_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A rotation-only [ProjectTrack] for [jointId], two keys: identity at t=0
/// and [angle] radians about [axis] at t=1, linear (slerped) between them.
ProjectTrack _bendTrack(
  int jointId, {
  required Vector3 axis,
  required double angle,
}) {
  final identity = Quaternion.identity();
  final bent = Quaternion.axisAngle(axis, angle);
  return ProjectTrack(
    objectId: jointId,
    track: AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0, 1]),
      values: Float32List.fromList(<double>[
        identity.x,
        identity.y,
        identity.z,
        identity.w,
        bent.x,
        bent.y,
        bent.z,
        bent.w,
      ]),
      componentCount: 4,
    ),
  );
}

void main() {
  group('ShapeDriver.evaluate — the row\'s own worked numbers', () {
    final driver = const ShapeDriver(
      shapeIndex: 0,
      jointId: 1,
      axis: DriverAxis.x,
      from: 0,
      to: math.pi / 2,
    );

    test('an elbow at 90 degrees drives the shape fully open', () {
      final rotation = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
      expect(driver.evaluate(rotation), closeTo(1.0, 1e-6));
    });

    test('an elbow at 45 degrees drives the shape to half', () {
      final rotation = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 4);
      expect(driver.evaluate(rotation), closeTo(0.5, 1e-6));
    });

    test('an unrotated joint drives nothing', () {
      expect(driver.evaluate(Quaternion.identity()), closeTo(0.0, 1e-6));
    });

    test('past `to`, the shape holds fully open rather than overshooting', () {
      final rotation = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi);
      expect(driver.evaluate(rotation), closeTo(1.0, 1e-6));
    });

    test(
      'a rotation about a different axis does not drive an x-axis driver',
      () {
        final rotation = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
        expect(driver.evaluate(rotation), closeTo(0.0, 1e-6));
      },
    );
  });

  group('evaluateShapeDriversLive — additive combination', () {
    test('two drivers naming the same shape add, not overwrite', () {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          _bendTrack(1, axis: Vector3(1, 0, 0), angle: math.pi / 2),
          _bendTrack(2, axis: Vector3(1, 0, 0), angle: math.pi / 2),
        ],
      );
      const drivers = <ShapeDriver>[
        ShapeDriver(
          shapeIndex: 0,
          jointId: 1,
          axis: DriverAxis.x,
          from: 0,
          to: math.pi / 2,
        ),
        ShapeDriver(
          shapeIndex: 0,
          jointId: 2,
          axis: DriverAxis.x,
          from: 0,
          to: math.pi / 2,
        ),
      ];

      // At t=0.5 each joint has slerped to a 45-degree bend (half of the
      // 90-degree span between the two keys, about one shared axis, which
      // slerps exactly linearly in angle — see this file's own bake test for
      // why that exactness matters), so each driver alone reads 0.5.
      final weights = evaluateShapeDriversLive(
        clip: clip,
        drivers: drivers,
        time: 0.5,
        shapeCount: 1,
      );
      expect(weights[0], closeTo(1.0, 1e-6));
    });

    test('a joint with no rotation track in the clip reads as unrotated', () {
      final clip = ProjectClip(tracks: const <ProjectTrack>[]);
      const drivers = <ShapeDriver>[
        ShapeDriver(
          shapeIndex: 0,
          jointId: 99,
          axis: DriverAxis.x,
          from: 0,
          to: math.pi / 2,
        ),
      ];
      final weights = evaluateShapeDriversLive(
        clip: clip,
        drivers: drivers,
        time: 0.5,
        shapeCount: 1,
      );
      expect(weights[0], closeTo(0.0, 1e-6));
    });
  });

  group('bakeShapeDrivers — baked equals live', () {
    test(
      'sampling the baked weights track matches the live driver everywhere',
      () {
        final clip = ProjectClip(
          tracks: <ProjectTrack>[
            _bendTrack(1, axis: Vector3(1, 0, 0), angle: math.pi / 2),
          ],
        );
        const driver = ShapeDriver(
          shapeIndex: 0,
          jointId: 1,
          axis: DriverAxis.x,
          from: 0,
          to: math.pi / 2,
        );

        final baked = bakeShapeDrivers(
          clip: clip,
          drivers: const <ShapeDriver>[driver],
          shapeTargetObjectId: 7,
          shapeCount: 1,
        );

        expect(baked.tracks, hasLength(clip.tracks.length + 1));
        final weightsTrack = baked.tracks.last;
        expect(weightsTrack.objectId, 7);
        expect(weightsTrack.track.path, AnimationPath.weights);

        final out = Float32List(1);
        for (final t in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
          weightsTrack.track.sample(t, out);
          final live = evaluateShapeDriversLive(
            clip: clip,
            drivers: const <ShapeDriver>[driver],
            time: t,
            shapeCount: 1,
          );
          expect(out[0], closeTo(live[0], 1e-5), reason: 'time $t');
        }
      },
    );

    test(
      'the source clip itself is returned unchanged when no joint moves',
      () {
        final clip = ProjectClip(tracks: const <ProjectTrack>[]);
        const driver = ShapeDriver(
          shapeIndex: 0,
          jointId: 1,
          axis: DriverAxis.x,
          from: 0,
          to: math.pi / 2,
        );
        final baked = bakeShapeDrivers(
          clip: clip,
          drivers: const <ShapeDriver>[driver],
          shapeTargetObjectId: 7,
          shapeCount: 1,
        );
        expect(baked.tracks, isEmpty);
      },
    );
  });

  group('DriverAxis and ShapeDriverCurve — value classes, not enums', () {
    test('each axis names its own unit vector', () {
      expect(DriverAxis.x.vector, Vector3(1, 0, 0));
      expect(DriverAxis.y.vector, Vector3(0, 1, 0));
      expect(DriverAxis.z.vector, Vector3(0, 0, 1));
    });

    test('the linear curve is the identity function', () {
      expect(ShapeDriverCurve.linear.apply(0.3), closeTo(0.3, 1e-12));
    });
  });
}
