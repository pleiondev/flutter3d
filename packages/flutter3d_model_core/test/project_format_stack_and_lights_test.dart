/// What a person set up and closed the file on: a modifier stack and lights.
///
///     dart test test/project_format_stack_and_lights_test.dart
///
/// Neither was written. `ModifierSlot` had a `toJson` and a `fromJson` that
/// the format never called, and `ModelProject.lighting`'s own doc comment said
/// a reopened project comes back unlit. Both were true, and what they meant to
/// somebody using the modeller was a mirror and three lamps gone on the first
/// save and reopen, with no warning, because the file that came back was a
/// valid file.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject _cube({List<ModifierSlot> modifiers = const <ModifierSlot>[]}) =>
    const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
        modifiers: modifiers,
      ),
    );

ProjectOpened _reopened(Uint8List bytes) => switch (readProject(bytes)) {
  final ProjectOpened opened => opened,
  final ProjectRefused refused => fail('refused: ${refused.because}'),
};

void main() {
  group('a modifier stack', () {
    test('comes back in the order it was built, switches and all', () {
      final before = _cube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: MirrorModifier(normal: Vector3(1.0, 0.0, 0.0)),
            enabled: true,
          ),
          ModifierSlot(
            modifier: ArrayModifier(count: 4, offset: Vector3(0.0, 2.0, 0.0)),
            enabled: false,
            inExport: false,
          ),
        ],
      );

      final after = _reopened(writeProject(before)).project.objects.single;

      expect(after.modifiers, hasLength(2));
      expect(after.modifiers[0].modifier, isA<MirrorModifier>());
      expect(after.modifiers[0].enabled, isTrue);
      expect(after.modifiers[0].inExport, isTrue);
      final array = after.modifiers[1].modifier as ArrayModifier;
      expect(array.count, 4);
      expect(array.offset, Vector3(0.0, 2.0, 0.0));
      expect(after.modifiers[1].enabled, isFalse);
      expect(after.modifiers[1].inExport, isFalse);
    });

    test('and so the file it exports afterwards is the one it showed', () {
      final before = _cube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 3, offset: Vector3(3.0, 0.0, 0.0)),
            enabled: true,
          ),
        ],
      );
      final after = _reopened(writeProject(before)).project;

      int triangles(ModelProject project) =>
          toModelDocument(project).surfaces.single.mesh.triangleCount;
      expect(triangles(after), triangles(before));
      expect(triangles(after), triangles(_cube()) * 3);
    });

    test('an object with none writes the bytes it always wrote', () {
      expect(
        writeProject(_cube()),
        writeProject(_cube(modifiers: const <ModifierSlot>[])),
      );
      final manifest = String.fromCharCodes(writeProject(_cube()));
      expect(manifest, isNot(contains('"modifiers"')));
    });
  });

  group('the lights', () {
    ModelProject lit() {
      final history = ModelHistory(_cube())
        ..run(AddLight(type: ProjectLightType.spot, at: Vector3(1.0, 4.0, 2.0)))
        ..run(const AddLight())
        ..run(const SetEnvironment(SceneEnvironmentPreset.sunset));
      return history.project;
    }

    test('come back where they were put, with the scene around them', () {
      final before = lit();
      final after = _reopened(writeProject(before)).project.lighting;

      expect(after.lights, hasLength(2));
      expect(after.lights[0].type, ProjectLightType.spot);
      expect(
        after.lights[0].transform.getTranslation(),
        before.lighting.lights[0].transform.getTranslation(),
      );
      expect(
        after.lights[0].outerConeAngle,
        before.lighting.lights[0].outerConeAngle,
      );
      expect(after.lights[1].type, ProjectLightType.directional);
      expect(after.environment, SceneEnvironmentPreset.sunset);
      expect(after.exposure, before.lighting.exposure);
      expect(after.post.bloomEnabled, before.lighting.post.bloomEnabled);
    });

    test('a project nobody has lit writes no lighting at all', () {
      final manifest = String.fromCharCodes(writeProject(_cube()));
      expect(manifest, isNot(contains('"lighting"')));
      expect(_reopened(writeProject(_cube())).project.lighting.lights, isEmpty);
    });

    test('an undo after reopening puts back the lighting of that step', () {
      // The history is written as what each step changed. Lighting was not
      // among the things a step could have changed, so every step read back
      // carried the default, and undoing anything at all turned the lamps
      // off.
      final history = ModelHistory(_cube())
        ..run(const AddLight())
        ..run(const SetEnvironment(SceneEnvironmentPreset.studio))
        ..run(const Rename(id: 1, to: 'box'));

      final opened = _reopened(writeProject(history.project, history: history));
      final again = ModelHistory.withSteps(opened.project, opened.history);

      expect(again.project.lighting.environment, SceneEnvironmentPreset.studio);
      again.undo(); // the rename
      expect(again.project.lighting.lights, hasLength(1));
      expect(again.project.lighting.environment, SceneEnvironmentPreset.studio);
      again.undo(); // the environment
      expect(again.project.lighting.lights, hasLength(1));
      expect(again.project.lighting.environment, SceneEnvironmentPreset.none);
      again.undo(); // the light
      expect(again.project.lighting.lights, isEmpty);
    });

    test('a lit project opens with nothing to warn about', () {
      // The reader drops a light it cannot read and says so. A file this
      // build wrote must never reach that sentence.
      expect(_reopened(writeProject(lit())).warnings, isEmpty);
    });
  });
}
