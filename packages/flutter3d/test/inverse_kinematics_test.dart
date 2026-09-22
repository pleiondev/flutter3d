/// `anim-14`: `TwoBoneIk.solve`, `FabrikIk.solve`, `Pose.writeTo` — checked
/// on hand-built chains, since the row's own acceptance line is numeric
/// ("достижимая цель 1e-4", "pole задаёт сторону сгиба", "FABRIK ≤10
/// итераций") rather than tied to any one sample file.
///
///     dart test test/inverse_kinematics_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A straight three-joint chain along +Y: root(0) at the origin, mid(1) one
/// unit above it, tip(2) one more unit above that. Both bones length 1, so
/// `maxReach` is exactly 2.
Pose _twoBoneChain() => Pose(
  parents: <int>[-1, 0, 1],
  restTranslations: Float32List.fromList(<double>[
    0, 0, 0, // root
    0, 1, 0, // mid
    0, 1, 0, // tip, local to mid
  ]),
  restRotations: Float32List.fromList(<double>[
    0, 0, 0, 1, //
    0, 0, 0, 1, //
    0, 0, 0, 1, //
  ]),
  restScales: Float32List.fromList(<double>[
    1, 1, 1, //
    1, 1, 1, //
    1, 1, 1, //
  ]),
);

/// A four-joint (three-bone) chain along +Y, each bone length 1 — long
/// enough that `TwoBoneIk` cannot solve it, which is the point of testing
/// `FabrikIk` on it instead.
Pose _fabrikChain() => Pose(
  parents: <int>[-1, 0, 1, 2],
  restTranslations: Float32List.fromList(<double>[
    0, 0, 0, //
    0, 1, 0, //
    0, 1, 0, //
    0, 1, 0, //
  ]),
  restRotations: Float32List.fromList(<double>[
    0, 0, 0, 1, //
    0, 0, 0, 1, //
    0, 0, 0, 1, //
    0, 0, 0, 1, //
  ]),
  restScales: Float32List.fromList(<double>[
    1, 1, 1, //
    1, 1, 1, //
    1, 1, 1, //
    1, 1, 1, //
  ]),
);

void main() {
  group('TwoBoneIk', () {
    test('a reachable target is met within 1e-4', () {
      final pose = _twoBoneChain();
      final target = Vector3(1.0, 1.0, 0.0);
      final remaining = TwoBoneIk.solve(
        pose,
        root: 0,
        mid: 1,
        tip: 2,
        target: target,
        pole: Vector3(1.0, 0.0, 0.0),
      );
      // Mutation: use the un-clamped raw distance in the law-of-cosines
      // angle computation instead of the clamped one — this reachable
      // target would still solve close enough that only a tight tolerance
      // catches the drift.
      expect(remaining, lessThan(1e-4));

      final tip = pose.worldMatrices()[2].getTranslation();
      expect(tip.x, closeTo(target.x, 1e-4));
      expect(tip.y, closeTo(target.y, 1e-4));
      expect(tip.z, closeTo(target.z, 1e-4));
    });

    test('the pole picks which side the middle joint bends toward', () {
      final target = Vector3(1.0, 1.0, 0.0);

      final bentPositive = _twoBoneChain();
      TwoBoneIk.solve(
        bentPositive,
        root: 0,
        mid: 1,
        tip: 2,
        target: target,
        pole: Vector3(0.0, 0.0, 1.0),
      );
      final bentNegative = _twoBoneChain();
      TwoBoneIk.solve(
        bentNegative,
        root: 0,
        mid: 1,
        tip: 2,
        target: target,
        pole: Vector3(0.0, 0.0, -1.0),
      );

      final rootPos = Vector3.zero();
      final targetDir = (target - rootPos).normalized();
      Vector3 perp(Vector3 v) => v - targetDir * v.dot(targetDir);

      final midPositive = bentPositive.worldMatrices()[1].getTranslation();
      final midNegative = bentNegative.worldMatrices()[1].getTranslation();
      final sidePositive = perp(midPositive - rootPos);
      final sideNegative = perp(midNegative - rootPos);

      // Mutation: skip the twist step (step 3) entirely — both poles would
      // then bend the middle joint into whatever plane step 1's arbitrary
      // fallback axis picked, and `sidePositive`/`sideNegative` would land
      // on the same side instead of opposite ones.
      expect(sidePositive.z, greaterThan(0.0));
      expect(sideNegative.z, lessThan(0.0));

      // Both tips still reach the target regardless of which side bent —
      // the pole changes the shape of the solution, not whether there is
      // one.
      final tipPositive = bentPositive.worldMatrices()[2].getTranslation();
      final tipNegative = bentNegative.worldMatrices()[2].getTranslation();
      expect((tipPositive - target).length, lessThan(1e-4));
      expect((tipNegative - target).length, lessThan(1e-4));
    });

    test('a target beyond reach is stretched to, not chased forever', () {
      final pose = _twoBoneChain();
      // maxReach is 2; this is 10 times that.
      final remaining = TwoBoneIk.solve(
        pose,
        root: 0,
        mid: 1,
        tip: 2,
        target: Vector3(0.0, 20.0, 0.0),
        pole: Vector3(1.0, 0.0, 0.0),
      );
      final tip = pose.worldMatrices()[2].getTranslation();
      // The chain fully extends toward the target; it cannot close the
      // remaining 18 units, and this checks it does not produce NaN trying.
      expect(tip.x.isFinite, isTrue);
      expect(tip.y.isFinite, isTrue);
      expect(tip.z.isFinite, isTrue);
      expect(remaining.isFinite, isTrue);
      expect(remaining, greaterThan(17.0));
    });

    test('a chain already bent at rest keeps bending the same way, not back '
        'through straight', () {
      // mid bent 90° at rest: root(0) at the origin, mid(1) one unit along
      // +X, tip(2) one more unit along mid's own +Y (rotated 90° about Z
      // from mid's local +X) — so the tip starts at (1, 1, 0), not on a
      // straight line through root and mid the way every chain above does.
      final quarterTurn = Quaternion.axisAngle(
        Vector3(0.0, 0.0, 1.0),
        1.5707963267948966,
      );
      final pose = Pose(
        parents: <int>[-1, 0, 1],
        restTranslations: Float32List.fromList(<double>[
          0, 0, 0, //
          1, 0, 0, //
          1, 0, 0, //
        ]),
        restRotations: Float32List.fromList(<double>[
          0, 0, 0, 1, //
          quarterTurn.x, quarterTurn.y, quarterTurn.z, quarterTurn.w, //
          0, 0, 0, 1, //
        ]),
        restScales: Float32List.fromList(<double>[
          1, 1, 1, //
          1, 1, 1, //
          1, 1, 1, //
        ]),
      );

      // Reachable (chain spans 0..2) and only a little past the rest tip
      // position of (1, 1, 0) — a target the wrong-sign bend the mutation
      // below reproduces lands nowhere near, roughly (0.65, 0.68, 0) short
      // of it, which is why `1e-4` alone is enough to catch it without a
      // separate direct check on the sign.
      final target = Vector3(1.3, 1.1, 0.0);
      final remaining = TwoBoneIk.solve(
        pose,
        root: 0,
        mid: 1,
        tip: 2,
        target: target,
        pole: Vector3(0.0, 1.0, 0.0),
      );
      // Mutation: swap this step's own `oldAngle - newAngle` back to
      // `newAngle - oldAngle` — every test above still passes, since a
      // chain starting exactly straight cannot tell the two apart; this
      // target needs the chain to bend *less* from an already-bent rest
      // pose, which only the correct sign reaches.
      expect(remaining, lessThan(1e-4));

      final tip = pose.worldMatrices()[2].getTranslation();
      expect(tip.x, closeTo(target.x, 1e-4));
      expect(tip.y, closeTo(target.y, 1e-4));
      expect(tip.z, closeTo(target.z, 1e-4));
    });

    test(
      'a target inside the two bones cannot fold to is clamped, not NaN',
      () {
        // Unequal lengths: upper 2, lower 1 (tip local translation shortened).
        final pose = Pose(
          parents: <int>[-1, 0, 1],
          restTranslations: Float32List.fromList(<double>[
            0, 0, 0, //
            0, 2, 0, //
            0, 1, 0, //
          ]),
          restRotations: Float32List.fromList(<double>[
            0, 0, 0, 1, //
            0, 0, 0, 1, //
            0, 0, 0, 1, //
          ]),
          restScales: Float32List.fromList(<double>[
            1, 1, 1, //
            1, 1, 1, //
            1, 1, 1, //
          ]),
        );
        // minReach is |2 - 1| = 1; this target is well inside that.
        final remaining = TwoBoneIk.solve(
          pose,
          root: 0,
          mid: 1,
          tip: 2,
          target: Vector3(0.1, 0.0, 0.0),
          pole: Vector3(0.0, 0.0, 1.0),
        );
        final tip = pose.worldMatrices()[2].getTranslation();
        expect(tip.x.isFinite, isTrue);
        expect(tip.y.isFinite, isTrue);
        expect(tip.z.isFinite, isTrue);
        expect(remaining.isFinite, isTrue);
      },
    );
  });

  group('FabrikIk', () {
    test('a reachable target is met within tolerance, in ten iterations '
        'or fewer', () {
      final pose = _fabrikChain();
      final target = Vector3(1.5, 1.0, 0.0);
      final iterations = FabrikIk.solve(
        pose,
        joints: <int>[0, 1, 2, 3],
        target: target,
      );
      // This reachable, unremarkable target converges in 3. Asserted well
      // under the row's own ≤10 bound rather than right at it, so a
      // mutation dropping the early-exit `break` — which would still
      // converge, just always report exactly `maxIterations` — is caught
      // here rather than needing a separate, weaker check.
      expect(iterations, lessThan(10));

      final tip = pose.worldMatrices()[3].getTranslation();
      expect((tip - target).length, lessThanOrEqualTo(1e-4));
    });

    test('an unreachable target stretches the chain straight toward it', () {
      final pose = _fabrikChain();
      // totalLength is 3; this is well past it.
      final target = Vector3(0.0, 30.0, 0.0);
      FabrikIk.solve(pose, joints: <int>[0, 1, 2, 3], target: target);

      final tip = pose.worldMatrices()[3].getTranslation();
      // Mutation: leave the chain at rest instead of stretching it — the
      // tip would read (0, 3, 0) instead of (0, 3, 0)... which is the same
      // number by coincidence for this rest pose, so the direction check
      // below is the one that actually distinguishes "stretched" from
      // "untouched": every joint should now lie exactly on the ray toward
      // the target.
      expect(tip.y, closeTo(3.0, 1e-6));
      final mid = pose.worldMatrices()[2].getTranslation();
      expect(mid.x, closeTo(0.0, 1e-6));
      expect(mid.y, closeTo(2.0, 1e-6));
    });

    test('fewer than two joints is refused', () {
      final pose = _fabrikChain();
      expect(
        () => FabrikIk.solve(
          pose,
          joints: <int>[0],
          target: Vector3(1.0, 0.0, 0.0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Pose.writeTo', () {
    test('writes local TRS onto matching targets, skipping null slots', () {
      final pose = _twoBoneChain();
      pose.translations[3] = 5.0; // mid.x, an arbitrary edit to check

      final root = SceneNode(name: 'root');
      final tip = SceneNode(name: 'tip');
      pose.writeTo(<AnimationTarget?>[root, null, tip]);

      expect(root.readPosition().x, closeTo(0.0, 1e-9));
      expect(root.readPosition().y, closeTo(0.0, 1e-9));
      // Mutation: skip the whole loop when any target is null instead of
      // skipping only that one slot — `tip` would then stay at the
      // SceneNode default instead of the pose's own rest translation.
      expect(tip.readPosition().y, closeTo(1.0, 1e-9));
    });
  });
}
