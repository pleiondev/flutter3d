/// `anim-21`: `buildSkeleton` against its own row's three acceptance
/// clauses — bone count, left/right mirroring, and `inverseBind·worldRest
/// = I` — checked against the actual [ModelObject]s and [ProjectSkeleton]
/// it returns, not against the algorithm's own internal state.
///
///     dart test test/rig_template_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final _humanoidBounds = Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 2, 1));

final _humanoidMarkers = <String, Vector3>{
  'hips': Vector3(0, 1.0, 0),
  'spine': Vector3(0, 1.2, 0),
  'chest': Vector3(0, 1.4, 0),
  'neck': Vector3(0, 1.6, 0),
  'head': Vector3(0, 1.75, 0),
  'leftShoulder': Vector3(0.2, 1.4, 0),
  'leftElbow': Vector3(0.5, 1.4, 0),
  'leftWrist': Vector3(0.8, 1.4, 0),
  'leftHip': Vector3(0.1, 1.0, 0),
  'leftKnee': Vector3(0.1, 0.5, 0),
  'leftAnkle': Vector3(0.1, 0.05, 0),
};

final _quadrupedBounds = Aabb3.minMax(
  Vector3(-1.5, -1, -1.5),
  Vector3(1.5, 1, 1.5),
);

final _quadrupedMarkers = <String, Vector3>{
  'pelvis': Vector3(0, 0.5, -0.5),
  'spine1': Vector3(0, 0.55, 0),
  'chest': Vector3(0, 0.6, 0.5),
  'neck': Vector3(0, 0.65, 0.8),
  'head': Vector3(0, 0.7, 1.0),
  'tailBase': Vector3(0, 0.55, -0.8),
  'tailTip': Vector3(0, 0.5, -1.2),
  'leftFrontShoulder': Vector3(0.2, 0.6, 0.4),
  'leftFrontPaw': Vector3(0.2, 0.0, 0.4),
  'leftBackHip': Vector3(0.2, 0.5, -0.6),
  'leftBackPaw': Vector3(0.2, 0.0, -0.6),
};

/// [rig]'s own [BuiltRig.objects], added to an empty project in order —
/// the shape any real caller would put them in before trusting
/// [rig]'s own [BuiltRig.skeleton] to address them.
ModelProject _projectOf(BuiltRig rig) {
  var project = const ModelProject();
  for (final object in rig.objects) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: object.name,
        geometry: object.geometry,
        transform: object.transform,
        parent: object.parent,
      ),
    );
  }
  return project;
}

void main() {
  group('bone count matches this row\'s own documented table', () {
    test('humanoid', () {
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        firstObjectId: 1,
      );
      expect(rig.objects.length, 17);
      expect(rig.skeleton.jointCount, 17);
      expect(rig.objects.length, lessThanOrEqualTo(64));
    });

    test('quadruped', () {
      final rig = buildSkeleton(
        RigTemplate.quadruped,
        _quadrupedMarkers,
        bounds: _quadrupedBounds,
        firstObjectId: 1,
      );
      expect(rig.objects.length, 15);
      expect(rig.skeleton.jointCount, 15);
      expect(rig.objects.length, lessThanOrEqualTo(64));
    });
  });

  group('left/right joints mirror within 1e-6', () {
    /// Name pairs this row's own table mirrors, keyed left → right.
    const humanoidPairs = <String, String>{
      'leftShoulder': 'rightShoulder',
      'leftElbow': 'rightElbow',
      'leftWrist': 'rightWrist',
      'leftHip': 'rightHip',
      'leftKnee': 'rightKnee',
      'leftAnkle': 'rightAnkle',
    };

    const quadrupedPairs = <String, String>{
      'leftFrontShoulder': 'rightFrontShoulder',
      'leftFrontPaw': 'rightFrontPaw',
      'leftBackHip': 'rightBackHip',
      'leftBackPaw': 'rightBackPaw',
    };

    void checkMirrored(
      RigTemplate template,
      Map<String, Vector3> markers,
      Aabb3 bounds,
      Map<String, String> pairs,
    ) {
      final rig = buildSkeleton(
        template,
        markers,
        bounds: bounds,
        firstObjectId: 1,
      );
      final project = _projectOf(rig);
      final byName = <String, int>{
        for (final object in rig.objects) object.name: object.id,
      };

      for (final entry in pairs.entries) {
        final leftWorld = worldTransformOf(project, byName[entry.key]!);
        final rightWorld = worldTransformOf(project, byName[entry.value]!);
        final leftPos = leftWorld.getTranslation();
        final rightPos = rightWorld.getTranslation();
        expect(
          rightPos.x,
          closeTo(-leftPos.x, 1e-6),
          reason: '${entry.key} / ${entry.value} x',
        );
        expect(
          rightPos.y,
          closeTo(leftPos.y, 1e-6),
          reason: '${entry.key} / ${entry.value} y',
        );
        expect(
          rightPos.z,
          closeTo(leftPos.z, 1e-6),
          reason: '${entry.key} / ${entry.value} z',
        );
      }
    }

    test('humanoid', () {
      checkMirrored(
        RigTemplate.humanoid,
        _humanoidMarkers,
        _humanoidBounds,
        humanoidPairs,
      );
    });

    test('quadruped', () {
      checkMirrored(
        RigTemplate.quadruped,
        _quadrupedMarkers,
        _quadrupedBounds,
        quadrupedPairs,
      );
    });

    test('a centerline joint is snapped onto the mirror plane', () {
      // An off-plane hips marker (x = 0.03, a plausible real-world wobble)
      // must not leak into the rig: everything hung under it would
      // otherwise be off-plane too, and the mirror check above would be
      // comparing two joints that were never actually symmetric.
      final wobbled = Map<String, Vector3>.of(_humanoidMarkers)
        ..['hips'] = Vector3(0.03, 1.0, 0);
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        wobbled,
        bounds: _humanoidBounds,
        firstObjectId: 1,
      );
      final project = _projectOf(rig);
      final hipsId = rig.objects.firstWhere((o) => o.name == 'hips').id;
      final world = worldTransformOf(project, hipsId);
      expect(world.getTranslation().x, closeTo(0, 1e-9));
    });
  });

  group('inverseBind · worldRest = I for every joint', () {
    void checkIdentity(
      RigTemplate template,
      Map<String, Vector3> markers,
      Aabb3 bounds,
    ) {
      final rig = buildSkeleton(
        template,
        markers,
        bounds: bounds,
        firstObjectId: 1,
      );
      final project = _projectOf(rig);

      for (var i = 0; i < rig.skeleton.jointCount; i++) {
        final worldRest = worldTransformOf(project, rig.skeleton.joints[i]);
        final composed = Matrix4.copy(rig.skeleton.inverseBindMatrices[i])
          ..multiply(worldRest);
        for (var e = 0; e < 16; e++) {
          final expected = Matrix4.identity().storage[e];
          expect(
            composed.storage[e],
            closeTo(expected, 1e-6),
            reason: 'joint ${rig.objects[i].name}, element $e',
          );
        }
      }
    }

    test('humanoid', () {
      checkIdentity(RigTemplate.humanoid, _humanoidMarkers, _humanoidBounds);
    });

    test('quadruped', () {
      checkIdentity(RigTemplate.quadruped, _quadrupedMarkers, _quadrupedBounds);
    });
  });

  group('refusals', () {
    test('a missing marker throws', () {
      final incomplete = Map<String, Vector3>.of(_humanoidMarkers)
        ..remove('leftWrist');
      expect(
        () => buildSkeleton(
          RigTemplate.humanoid,
          incomplete,
          bounds: _humanoidBounds,
          firstObjectId: 1,
        ),
        throwsArgumentError,
      );
    });

    test('a marker outside bounds throws', () {
      final outOfBounds = Map<String, Vector3>.of(_humanoidMarkers)
        ..['head'] = Vector3(0, 50, 0);
      expect(
        () => buildSkeleton(
          RigTemplate.humanoid,
          outOfBounds,
          bounds: _humanoidBounds,
          firstObjectId: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  test('required markers list matches the table exactly', () {
    expect(
      requiredMarkers(RigTemplate.humanoid).toSet(),
      _humanoidMarkers.keys.toSet(),
    );
    expect(
      requiredMarkers(RigTemplate.quadruped).toSet(),
      _quadrupedMarkers.keys.toSet(),
    );
  });

  test('object ids start at firstObjectId and are consecutive', () {
    final rig = buildSkeleton(
      RigTemplate.humanoid,
      _humanoidMarkers,
      bounds: _humanoidBounds,
      firstObjectId: 40,
    );
    expect(rig.objects.first.id, 40);
    expect(rig.objects.last.id, 40 + rig.objects.length - 1);
    expect(rig.skeleton.joints, rig.objects.map((o) => o.id).toList());
  });

  // -------------------------------------------------------------- anim-33d
  //
  // `RigBuildOptions` — screen 16's rig-composition switches, given a
  // backend: spineCount, fingers, toes, faceBones, ikChains, controllers.

  group('anim-33d acceptance table (cumulative RigBuildOptions)', () {
    void expectHumanoidCount(RigBuildOptions options, int expectedJoints) {
      final preview = previewRig(RigTemplate.humanoid, options: options);
      expect(preview.jointCount, expectedJoints, reason: '$options');
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        options: options,
        firstObjectId: 1,
      );
      expect(rig.skeleton.jointCount, expectedJoints, reason: '$options');
      expect(rig.objects.length, expectedJoints, reason: '$options');
    }

    test('base: 17', () {
      expectHumanoidCount(const RigBuildOptions(), 17);
    });

    test('+fingers: 47', () {
      expectHumanoidCount(const RigBuildOptions(fingers: true), 47);
    });

    test('+fingers+spine3: 49', () {
      expectHumanoidCount(
        const RigBuildOptions(fingers: true, spineCount: 3),
        49,
      );
    });

    test('+fingers+spine3+toes: 51', () {
      expectHumanoidCount(
        const RigBuildOptions(fingers: true, spineCount: 3, toes: true),
        51,
      );
    });

    test('+fingers+spine3+toes+face: 54', () {
      expectHumanoidCount(
        const RigBuildOptions(
          fingers: true,
          spineCount: 3,
          toes: true,
          faceBones: true,
        ),
        54,
      );
    });

    test('quadruped stays 15 — the new flags are humanoid-only', () {
      const options = RigBuildOptions(
        fingers: true,
        spineCount: 3,
        toes: true,
        faceBones: true,
      );
      final preview = previewRig(RigTemplate.quadruped, options: options);
      expect(preview.jointCount, 15);
      final rig = buildSkeleton(
        RigTemplate.quadruped,
        _quadrupedMarkers,
        bounds: _quadrupedBounds,
        options: options,
        firstObjectId: 1,
      );
      expect(rig.skeleton.jointCount, 15);
    });
  });

  test('previewRig(...).jointCount == buildSkeleton(...).skeleton.jointCount '
      'for several option combinations', () {
    final combos = <RigBuildOptions>[
      const RigBuildOptions(),
      const RigBuildOptions(fingers: true),
      const RigBuildOptions(toes: true),
      const RigBuildOptions(spineCount: 2),
      const RigBuildOptions(spineCount: 3),
      const RigBuildOptions(faceBones: true),
      const RigBuildOptions(controllers: true),
      const RigBuildOptions(ikChains: true),
      const RigBuildOptions(
        fingers: true,
        toes: true,
        spineCount: 3,
        faceBones: true,
        ikChains: true,
        controllers: true,
      ),
    ];
    for (final options in combos) {
      final preview = previewRig(RigTemplate.humanoid, options: options);
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        options: options,
        firstObjectId: 1,
      );
      expect(rig.skeleton.jointCount, preview.jointCount, reason: '$options');
    }

    final quadPreview = previewRig(RigTemplate.quadruped);
    final quadRig = buildSkeleton(
      RigTemplate.quadruped,
      _quadrupedMarkers,
      bounds: _quadrupedBounds,
      firstObjectId: 1,
    );
    expect(quadRig.skeleton.jointCount, quadPreview.jointCount);
  });

  test('anim-33d: every left/right pair mirrors within 1e-6 and '
      'inverseBind·worldRest = I, for a full cross-product of the six '
      'humanoid RigBuildOptions knobs', () {
    // 3 spineCounts × 2^5 booleans = 96 combinations — cheap: each is
    // pure arithmetic over at most 54 joints, no I/O.
    for (final spineCount in const <int>[1, 2, 3]) {
      for (final fingers in const <bool>[false, true]) {
        for (final toes in const <bool>[false, true]) {
          for (final faceBones in const <bool>[false, true]) {
            for (final ikChains in const <bool>[false, true]) {
              for (final controllers in const <bool>[false, true]) {
                _checkSymmetryAndInverseBind(
                  RigBuildOptions(
                    spineCount: spineCount,
                    fingers: fingers,
                    toes: toes,
                    faceBones: faceBones,
                    ikChains: ikChains,
                    controllers: controllers,
                  ),
                );
              }
            }
          }
        }
      }
    }
  });

  group('anim-33d refusals', () {
    test('an unreasonably large spineCount pushes deformingCount past 64 and '
        'is refused', () {
      const options = RigBuildOptions(spineCount: 50);
      expect(
        previewRig(RigTemplate.humanoid, options: options).deformingCount,
        greaterThan(64),
      );
      expect(
        () => buildSkeleton(
          RigTemplate.humanoid,
          _humanoidMarkers,
          bounds: _humanoidBounds,
          options: options,
          firstObjectId: 1,
        ),
        throwsArgumentError,
      );
    });

    test('every combination this row actually ships stays at or under 64', () {
      const options = RigBuildOptions(
        fingers: true,
        spineCount: 3,
        toes: true,
        faceBones: true,
        ikChains: true,
        controllers: true,
      );
      expect(
        previewRig(RigTemplate.humanoid, options: options).deformingCount,
        lessThanOrEqualTo(64),
      );
      expect(
        () => buildSkeleton(
          RigTemplate.humanoid,
          _humanoidMarkers,
          bounds: _humanoidBounds,
          options: options,
          firstObjectId: 1,
        ),
        returnsNormally,
      );
    });
  });

  test('faceBones adds two non-deforming eyes: deformingCount is jointCount '
      'minus 2', () {
    final preview = previewRig(
      RigTemplate.humanoid,
      options: const RigBuildOptions(faceBones: true),
    );
    expect(preview.jointCount, 20);
    expect(preview.deformingCount, 18);
  });

  group('RigBuildOptions.controllers', () {
    test('adds one socket-parent object above the root, not counted as a '
        'joint', () {
      final preview = previewRig(
        RigTemplate.humanoid,
        options: const RigBuildOptions(controllers: true),
      );
      expect(preview.controllerCount, 1);
      expect(preview.jointCount, 17);

      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        options: const RigBuildOptions(controllers: true),
        firstObjectId: 1,
      );
      expect(rig.objects.length, 18);
      expect(rig.skeleton.jointCount, 17);

      final controller = rig.objects.first;
      expect(controller.name, 'hipsControl');
      expect(controller.parent, isNull);
      expect(rig.skeleton.joints, isNot(contains(controller.id)));

      final hips = rig.objects.firstWhere((o) => o.name == 'hips');
      expect(hips.parent, controller.id);
      expect(hips.transform.getTranslation(), Vector3.zero());
    });

    test('without it, the root has no parent, same as before anim-33d', () {
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        firstObjectId: 1,
      );
      expect(rig.objects.first.name, 'hips');
      expect(rig.objects.first.parent, isNull);
      expect(previewRig(RigTemplate.humanoid).controllerCount, 0);
    });

    test('mirrors the quadruped root (pelvis) too, not just hips', () {
      final rig = buildSkeleton(
        RigTemplate.quadruped,
        _quadrupedMarkers,
        bounds: _quadrupedBounds,
        options: const RigBuildOptions(controllers: true),
        firstObjectId: 1,
      );
      final controller = rig.objects.first;
      expect(controller.name, 'pelvisControl');
      final pelvis = rig.objects.firstWhere((o) => o.name == 'pelvis');
      expect(pelvis.parent, controller.id);
    });
  });

  group('RigBuildOptions.ikChains', () {
    test('adds four two-bone IkConstraints on a humanoid', () {
      final preview = previewRig(
        RigTemplate.humanoid,
        options: const RigBuildOptions(ikChains: true),
      );
      expect(preview.ikChainCount, 4);

      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        options: const RigBuildOptions(ikChains: true),
        firstObjectId: 1,
      );
      expect(rig.skeleton.constraints, hasLength(4));

      final byName = <String, int>{
        for (final object in rig.objects) object.name: object.id,
      };
      final leftArm = rig.skeleton.constraints.firstWhere(
        (c) => c.rootJointId == byName['leftShoulder'],
      );
      expect(leftArm.midJointId, byName['leftElbow']);
      expect(leftArm.effectorJointId, byName['leftWrist']);

      // The target sits exactly at the effector's own rest position, so
      // solving this constraint immediately after building moves nothing.
      final project = _projectOf(rig);
      final wristWorld = worldTransformOf(
        project,
        byName['leftWrist']!,
      ).getTranslation();
      expect(leftArm.target.x, closeTo(wristWorld.x, 1e-6));
      expect(leftArm.target.y, closeTo(wristWorld.y, 1e-6));
      expect(leftArm.target.z, closeTo(wristWorld.z, 1e-6));
    });

    test('no constraints without ikChains', () {
      final rig = buildSkeleton(
        RigTemplate.humanoid,
        _humanoidMarkers,
        bounds: _humanoidBounds,
        firstObjectId: 1,
      );
      expect(rig.skeleton.constraints, isEmpty);
    });

    test('a no-op on the quadruped template: no elbow/knee to bend around', () {
      final preview = previewRig(
        RigTemplate.quadruped,
        options: const RigBuildOptions(ikChains: true),
      );
      expect(preview.ikChainCount, 0);

      final rig = buildSkeleton(
        RigTemplate.quadruped,
        _quadrupedMarkers,
        bounds: _quadrupedBounds,
        options: const RigBuildOptions(ikChains: true),
        firstObjectId: 1,
      );
      expect(rig.skeleton.constraints, isEmpty);
    });
  });
}

/// Builds [options] against the standard humanoid fixture and checks two
/// of this row's own invariants that must hold for *every* combination:
/// every `left…` object mirrors its `right…` counterpart within 1e-6 (an
/// object's own name is enough to find its pair — [_mirroredName] in
/// `rig_template.dart` builds every right-side name the same way), and
/// `inverseBind · worldRest = I` for every joint.
void _checkSymmetryAndInverseBind(RigBuildOptions options) {
  final rig = buildSkeleton(
    RigTemplate.humanoid,
    _humanoidMarkers,
    bounds: _humanoidBounds,
    options: options,
    firstObjectId: 1,
  );
  final project = _projectOf(rig);
  final byName = <String, int>{
    for (final object in rig.objects) object.name: object.id,
  };

  for (final object in rig.objects) {
    if (!object.name.startsWith('left')) continue;
    final rightId = byName['right${object.name.substring(4)}'];
    if (rightId == null) continue;
    final leftPos = worldTransformOf(project, object.id).getTranslation();
    final rightPos = worldTransformOf(project, rightId).getTranslation();
    expect(
      rightPos.x,
      closeTo(-leftPos.x, 1e-6),
      reason: '${object.name} x, options $options',
    );
    expect(
      rightPos.y,
      closeTo(leftPos.y, 1e-6),
      reason: '${object.name} y, options $options',
    );
    expect(
      rightPos.z,
      closeTo(leftPos.z, 1e-6),
      reason: '${object.name} z, options $options',
    );
  }

  for (var i = 0; i < rig.skeleton.jointCount; i++) {
    final jointId = rig.skeleton.joints[i];
    final worldRest = worldTransformOf(project, jointId);
    final composed = Matrix4.copy(rig.skeleton.inverseBindMatrices[i])
      ..multiply(worldRest);
    for (var e = 0; e < 16; e++) {
      expect(
        composed.storage[e],
        closeTo(Matrix4.identity().storage[e], 1e-6),
        reason: 'joint ${project[jointId]!.name}, element $e, options $options',
      );
    }
  }
}
