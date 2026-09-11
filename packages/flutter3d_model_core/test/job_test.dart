/// Heavy work on one object's mesh, described as values rather than run in
/// place.
///
///     dart test test/job_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject withOneEditedObject({
  List<ModifierSlot> modifiers = const <ModifierSlot>[],
}) => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
    modifiers: modifiers,
  ),
);

void main() {
  group('jobRequestFor', () {
    test('captures the object\'s own version, mesh and modifiers', () {
      final project = withOneEditedObject(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final request = jobRequestFor(project, 1, 0);

      expect(request, isNotNull);
      expect(request!.objectId, 1);
      expect(request.baseVersion, project[1]!.version);
      expect(request.modifiers, hasLength(1));
      expect(request.modifiers.single, isA<ArrayModifier>());
    });

    test(
      'folds in a disabled modifier at uptoIndex, matching ApplyModifier',
      () {
        final project = withOneEditedObject(
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
              enabled: false,
            ),
          ],
        );
        final request = jobRequestFor(project, 1, 0);

        // Mutation: skip a disabled slot even at `uptoIndex` — this is the
        // same "apply switches it on" rule `ApplyModifier` itself keeps, and a
        // job built for a disabled modifier that silently did nothing would
        // disagree with what applying it synchronously does.
        expect(request!.modifiers, hasLength(1));
      },
    );

    test('null for an object that does not exist', () {
      final project = withOneEditedObject();
      expect(jobRequestFor(project, 99, 0), isNull);
    });

    test('null for a modifier index that is not there', () {
      final project = withOneEditedObject();
      expect(jobRequestFor(project, 1, 0), isNull);
    });

    test('null for an object with no edited mesh', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'lathe',
          geometry: ParametricGeometry(const ParametricCylinder()),
          transform: Matrix4.identity(),
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: ArrayModifier(count: 2, offset: Vector3(1, 0, 0)),
            ),
          ],
        ),
      );
      expect(jobRequestFor(project, 1, 0), isNull);
    });
  });

  group('JobRequest.run', () {
    test('folds the modifiers the same way ApplyModifier would', () async {
      final project = withOneEditedObject(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final request = jobRequestFor(project, 1, 0)!;

      final result = await request.run();

      expect(result.objectId, 1);
      expect(result.baseVersion, request.baseVersion);
      final baked = EditMesh.fromBytes(result.meshBytes);
      // Mutation: fold the modifiers over the wrong mesh, or not fold them
      // at all and hand `meshBytes` straight back — a base cube array-ed
      // twice has 16 vertices, not the base's own 8.
      expect(baked.vertexCount, 16);
    });
  });

  group('JobRequest and JobResult JSON', () {
    test('JobRequest round-trips, modifiers included', () {
      final project = withOneEditedObject(
        modifiers: <ModifierSlot>[
          ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
        ],
      );
      final request = jobRequestFor(project, 1, 0)!;
      final restored = JobRequest.fromJson(request.toJson());

      expect(restored, isNotNull);
      expect(restored!.objectId, request.objectId);
      expect(restored.baseVersion, request.baseVersion);
      expect(restored.meshBytes, request.meshBytes);
      expect(restored.modifiers.single, isA<MirrorModifier>());
    });

    test('JobRequest.fromJson is null for a modifier this build does not '
        'know', () {
      final json = <String, Object?>{
        'objectId': 1,
        'baseVersion': 1,
        'meshBytes': 'AA==',
        'modifiers': <Object?>[
          <String, Object?>{'kind': 'future'},
        ],
      };
      expect(JobRequest.fromJson(json), isNull);
    });

    test('JobRequest.fromJson is null for a missing field', () {
      expect(JobRequest.fromJson(<String, Object?>{'objectId': 1}), isNull);
    });

    test('JobResult round-trips', () {
      final result = JobResult(
        objectId: 3,
        baseVersion: 7,
        meshBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final restored = JobResult.fromJson(result.toJson());
      expect(restored, isNotNull);
      expect(restored!.objectId, 3);
      expect(restored.baseVersion, 7);
      expect(restored.meshBytes, <int>[1, 2, 3]);
    });
  });
}
