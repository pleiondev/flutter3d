/// `anim-15`'s own row: `IkConstraint` solved after FK, and `BakeIk`.
///
///     dart test test/ik_constraint_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own — [localOffset] from [parent], or from
/// the origin when there is none.
ModelObject _joint(int id, {int? parent, required Vector3 localOffset}) =>
    ModelObject(
      id: id,
      name: 'joint$id',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(localOffset),
      parent: parent,
    );

/// A straight two-bone chain along +X: root at the origin, mid one unit out,
/// the effector one further unit past it — [upperLength] and [lowerLength]
/// both 1.
ModelProject _straightChain() => ModelProject(
  objects: <ModelObject>[
    _joint(1, localOffset: Vector3.zero()),
    _joint(2, parent: 1, localOffset: Vector3(1, 0, 0)),
    _joint(3, parent: 2, localOffset: Vector3(1, 0, 0)),
  ],
);

Vector3 _effectorPosition(
  ModelProject project,
  IkConstraint constraint,
  Quaternion root,
  Quaternion mid,
) => worldTransformOf(
  project,
  constraint.effectorJointId,
  rotationOverrides: <int, Quaternion>{
    constraint.rootJointId: root,
    constraint.midJointId: mid,
  },
).getTranslation();

void main() {
  group('resolveIkConstraint', () {
    test(
      'anim-15\'s own acceptance: the effector reaches a target within reach',
      () {
        final project = _straightChain();
        final constraint = IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: Vector3(1.5, 0.5, 0),
          pole: Vector3(0, 1, 0),
        );

        final solved = resolveIkConstraint(
          project: project,
          constraint: constraint,
        );
        final effector = _effectorPosition(
          project,
          constraint,
          solved.root,
          solved.mid,
        );

        expect((effector - constraint.target).length, lessThan(1e-3));
        expect(solved.reachError, lessThan(1e-3));
      },
    );

    test('the pole decides which side the middle joint bends to', () {
      final project = _straightChain();
      // Straight ahead, so the target alone gives the chain no preferred
      // bend plane — the pole is the only input left to decide it.
      final target = Vector3(1.9, 0, 0);

      final up = resolveIkConstraint(
        project: project,
        constraint: IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: target,
          pole: Vector3(0, 1, 0),
        ),
      );
      final down = resolveIkConstraint(
        project: project,
        constraint: IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: target,
          pole: Vector3(0, -1, 0),
        ),
      );

      final midUp = worldTransformOf(
        project,
        2,
        rotationOverrides: <int, Quaternion>{1: up.root, 2: up.mid},
      ).getTranslation();
      final midDown = worldTransformOf(
        project,
        2,
        rotationOverrides: <int, Quaternion>{1: down.root, 2: down.mid},
      ).getTranslation();

      expect(midUp.y, greaterThan(0.1));
      expect(midDown.y, lessThan(-0.1));
    });

    test(
      'a target farther than the chain can reach still gives a finite, fully-extended answer',
      () {
        final project = _straightChain();
        final constraint = IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: Vector3(50, 0, 0),
          pole: Vector3(0, 1, 0),
        );

        final solved = resolveIkConstraint(
          project: project,
          constraint: constraint,
        );

        expect(solved.root.x.isFinite, isTrue);
        expect(solved.root.y.isFinite, isTrue);
        expect(solved.mid.x.isFinite, isTrue);
        expect(solved.mid.y.isFinite, isTrue);

        final effector = _effectorPosition(
          project,
          constraint,
          solved.root,
          solved.mid,
        );
        // Fully extended: the chain's own two unit bones straightened toward
        // the target, not folded, not `NaN`, not left where they started.
        expect(effector.length, closeTo(2.0, 1e-3));
        expect(effector.x, greaterThan(1.9));
      },
    );

    test("anim-31n's own acceptance: sweeping the target past full extension "
        'gives no jitter — the elbow moves continuously, not in a jump', () {
      final project = _straightChain();
      Vector3? previousMid;
      // From well within reach (1.0) to well past it (3.0), through the
      // exact length (2.0) where a solver that special-cased "beyond reach"
      // could visibly snap.
      for (var x = 1.0; x <= 3.0; x += 0.05) {
        final constraint = IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: Vector3(x, 0.3, 0),
          pole: Vector3(0, 1, 0),
        );
        final solved = resolveIkConstraint(
          project: project,
          constraint: constraint,
        );
        final mid = worldTransformOf(
          project,
          constraint.midJointId,
          rotationOverrides: <int, Quaternion>{
            constraint.rootJointId: solved.root,
          },
        ).getTranslation();
        if (previousMid != null) {
          expect(
            (mid - previousMid).length,
            lessThan(0.2),
            reason:
                'the elbow jumped between target x=${x - 0.05} and x=$x, '
                'which is what a solver switching formulas at the reach '
                'limit looks like',
          );
        }
        previousMid = mid;
      }
    });

    test('a chain resting bent (not straight) still reaches a nearby target, '
        'exercising the real current-bend axis rather than the straight-chain '
        'fallback', () {
      // Bent 90° at rest, in the XZ plane this time (not XY, so this does
      // not share `bendAxis` with the already-covered Y-bent fixtures).
      final bent = ModelProject(
        objects: <ModelObject>[
          _joint(1, localOffset: Vector3.zero()),
          ModelObject(
            id: 2,
            name: 'mid',
            geometry: const SocketGeometry(),
            transform: (Matrix4.identity()
              ..setRotation(Matrix3.rotationY(-1.5707963267948966))
              ..setTranslation(Vector3(1, 0, 0))),
            parent: 1,
          ),
          _joint(3, parent: 2, localOffset: Vector3(1, 0, 0)),
        ],
      );
      final constraint = IkConstraint(
        rootJointId: 1,
        midJointId: 2,
        effectorJointId: 3,
        target: Vector3(1.2, 0, 0.6),
        pole: Vector3(0, 0, 1),
      );

      final solved = resolveIkConstraint(project: bent, constraint: constraint);
      final effector = _effectorPosition(
        bent,
        constraint,
        solved.root,
        solved.mid,
      );

      expect((effector - constraint.target).length, lessThan(1e-3));
    });

    test('a chain already bent keeps bending the same way, rather than folding '
        'back through straight to get there', () {
      // At rest, mid is bent 90° so the effector sits at (1, 1, 0) — the
      // interior angle at mid is 90°, not the 180° a straight chain gives.
      // Reaching a target that needs *less* bend (a wider interior angle)
      // means turning mid by a small amount in the *same* rotational sense
      // it is already turned, not by first unbending past straight and
      // then bending the other way to the same final angle — the two are
      // different rotations whenever the starting angle is not exactly
      // 180°, and only one of them is the "same sense" `TwoBoneIk.solve`'s
      // own doc comment promises.
      final bent = ModelProject(
        objects: <ModelObject>[
          _joint(1, localOffset: Vector3.zero()),
          ModelObject(
            id: 2,
            name: 'mid',
            geometry: const SocketGeometry(),
            transform: (Matrix4.identity()
              ..setRotation(Matrix3.rotationZ(1.5707963267948966))
              ..setTranslation(Vector3(1, 0, 0))),
            parent: 1,
          ),
          _joint(3, parent: 2, localOffset: Vector3(1, 0, 0)),
        ],
      );
      // Within reach (chain reaches 0..2) and off the rest position (1,1,0)
      // by only a little, so a same-sense bend and an opposite-sense bend
      // to the same final interior angle land the effector in two clearly
      // different places.
      final constraint = IkConstraint(
        rootJointId: 1,
        midJointId: 2,
        effectorJointId: 3,
        target: Vector3(1.3, 1.1, 0),
        pole: Vector3(0, 1, 0),
      );

      final solved = resolveIkConstraint(project: bent, constraint: constraint);
      final effector = _effectorPosition(
        bent,
        constraint,
        solved.root,
        solved.mid,
      );

      expect((effector - constraint.target).length, lessThan(1e-3));
    });
  });

  group('bakeIk', () {
    test(
      "anim-15's own acceptance, baked: the effector stays within 1e-3 across the clip",
      () {
        final project = _straightChain();
        final constraint = IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: Vector3(1.5, 0.5, 0),
          pole: Vector3(0, 1, 0),
        );

        // A clip a second long — root sits at identity the whole time, which is
        // enough to give the bake a duration to sample across; the point of
        // this test is what `bakeIk` writes, not what the source clip already
        // held.
        final identity = Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1]);
        final times = Float32List.fromList(<double>[0, 1]);
        final clip = ProjectClip(
          tracks: <ProjectTrack>[
            ProjectTrack(
              objectId: 1,
              track: AnimationTrack(
                nodeIndex: 0,
                path: AnimationPath.rotation,
                interpolation: AnimationInterpolation.linear,
                times: times,
                values: identity,
                componentCount: 4,
              ),
            ),
          ],
        );

        final baked = bakeIk(
          project: project,
          clip: clip,
          constraint: constraint,
          fps: 30,
        );

        final rootTrack = baked.tracks.firstWhere((t) => t.objectId == 1).track;
        final midTrack = baked.tracks.firstWhere((t) => t.objectId == 2).track;

        for (final time in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
          final rootOut = Float32List(4);
          final midOut = Float32List(4);
          rootTrack.sample(time, rootOut);
          midTrack.sample(time, midOut);
          final root = Quaternion(
            rootOut[0],
            rootOut[1],
            rootOut[2],
            rootOut[3],
          )..normalize();
          final mid = Quaternion(midOut[0], midOut[1], midOut[2], midOut[3])
            ..normalize();
          final effector = _effectorPosition(project, constraint, root, mid);
          expect(
            (effector - constraint.target).length,
            lessThan(1e-3),
            reason: 'at t=$time',
          );
        }
      },
    );

    test(
      'tracks for joints outside the constraint survive baking untouched',
      () {
        final project = ModelProject(
          objects: <ModelObject>[
            _joint(1, localOffset: Vector3.zero()),
            _joint(2, parent: 1, localOffset: Vector3(1, 0, 0)),
            _joint(3, parent: 2, localOffset: Vector3(1, 0, 0)),
            _joint(4, localOffset: Vector3(5, 5, 5)),
          ],
        );
        final constraint = IkConstraint(
          rootJointId: 1,
          midJointId: 2,
          effectorJointId: 3,
          target: Vector3(1.5, 0.5, 0),
          pole: Vector3(0, 1, 0),
        );
        final otherValues = Float32List.fromList(<double>[1, 2, 3]);
        final otherTimes = Float32List.fromList(<double>[0]);
        final otherTrack = AnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.translation,
          interpolation: AnimationInterpolation.step,
          times: otherTimes,
          values: otherValues,
          componentCount: 3,
        );
        final clip = ProjectClip(
          tracks: <ProjectTrack>[ProjectTrack(objectId: 4, track: otherTrack)],
        );

        final baked = bakeIk(
          project: project,
          clip: clip,
          constraint: constraint,
          fps: 30,
        );

        final kept = baked.tracks.where((t) => t.objectId == 4);
        expect(kept, hasLength(1));
        expect(kept.first.track, same(otherTrack));
      },
    );
  });
}
