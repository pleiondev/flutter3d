/// `mat-23`'s own row: a project's own lighting, and the commands that
/// change it.
///
///     dart test test/lighting_commands_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('adding and removing a light', () {
    test('AddLight appends, RemoveLight collapses', () {
      final history = ModelHistory(const ModelProject());

      expect(history.run(const AddLight()), isNull);
      expect(history.project.lighting.lights, hasLength(1));

      expect(history.run(const RemoveLight(0)), isNull);
      expect(history.project.lighting.lights, isEmpty);
    });

    test('removing a light that is not there is refused', () {
      final history = ModelHistory(const ModelProject());

      final said = history.run(const RemoveLight(0));

      expect(said, contains('no light'));
    });
  });

  group('setting a light field', () {
    test("mat-23's own acceptance: SetLightField('intensity', 'много') is "
        'rejected', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());

      final said = history.run(
        const SetLightField(index: 0, field: 'intensity', value: 'много'),
      );

      expect(said, isNotNull);
      // Refused, not silently ignored: the light's own field is unchanged.
      expect(history.project.lighting.lights.single.intensity, 1.0);
    });

    test('a real number is accepted', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());

      expect(
        history.run(
          const SetLightField(index: 0, field: 'intensity', value: 2.5),
        ),
        isNull,
      );
      expect(history.project.lighting.lights.single.intensity, 2.5);
    });

    test('a colour takes three numbers', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());

      expect(
        history.run(
          const SetLightField(
            index: 0,
            field: 'color',
            value: <double>[0.2, 0.4, 0.6],
          ),
        ),
        isNull,
      );
      // Vector3's own storage is a Float32List, so a double literal loses
      // precision on the way in — 1e-6 is this codebase's own established
      // tolerance for that, not a loose assertion.
      final Vector3 color = history.project.lighting.lights.single.color;
      expect(color.x, closeTo(0.2, 1e-6));
      expect(color.y, closeTo(0.4, 1e-6));
      expect(color.z, closeTo(0.6, 1e-6));
    });

    test('a field that is not a light field is refused', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());

      final said = history.run(
        const SetLightField(index: 0, field: 'notAField', value: 1.0),
      );

      expect(said, isNotNull);
    });

    test('a type name switches the light kind', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());

      expect(
        history.run(
          const SetLightField(index: 0, field: 'type', value: 'point'),
        ),
        isNull,
      );
      expect(
        history.project.lighting.lights.single.type,
        ProjectLightType.point,
      );
    });
  });

  group('placing a light', () {
    test('ProjectLight defaults to identity, at the origin', () {
      final light = ProjectLight();
      expect(light.transform, Matrix4.identity());
    });

    test('copyWith replaces the transform and leaves everything else', () {
      final moved = Matrix4.identity()..setTranslationRaw(1, 2, 3);
      final light = ProjectLight(intensity: 2.0).copyWith(transform: moved);

      expect(light.transform, moved);
      expect(light.intensity, 2.0);
    });

    test('SetLightTransform moves a light, and is one undo step', () {
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());
      final to = Matrix4.identity()..setTranslationRaw(1, 2, 3);

      expect(history.run(SetLightTransform(index: 0, to: to)), isNull);
      expect(history.project.lighting.lights.single.transform, to);
      expect(history.undoSays, 'move a light');

      history.undo();
      expect(
        history.project.lighting.lights.single.transform,
        Matrix4.identity(),
      );
    });

    test('SetLightTransform on a light that is not there is refused', () {
      final history = ModelHistory(const ModelProject());

      final said = history.run(
        SetLightTransform(index: 0, to: Matrix4.identity()),
      );

      expect(said, contains('no light'));
    });
  });

  group('the environment and scene-wide fields', () {
    test('SetEnvironment sets the preset', () {
      final history = ModelHistory(const ModelProject());

      expect(
        history.run(const SetEnvironment(SceneEnvironmentPreset.daylight)),
        isNull,
      );
      expect(
        history.project.lighting.environment,
        SceneEnvironmentPreset.daylight,
      );
    });

    test(
      'SetSceneLightingField accepts ambientIntensity, shadows, exposure',
      () {
        final history = ModelHistory(const ModelProject());

        expect(
          history.run(
            const SetSceneLightingField(field: 'ambientIntensity', value: 0.5),
          ),
          isNull,
        );
        expect(history.project.lighting.ambientIntensity, 0.5);

        expect(
          history.run(
            const SetSceneLightingField(field: 'shadows', value: true),
          ),
          isNull,
        );
        expect(history.project.lighting.shadows, isTrue);

        expect(
          history.run(
            const SetSceneLightingField(field: 'exposure', value: 2.0),
          ),
          isNull,
        );
        expect(history.project.lighting.exposure, 2.0);
      },
    );

    test(
      "SetSceneLightingField also accepts bloomEnabled, on ScenePostSettings",
      () {
        final history = ModelHistory(const ModelProject());

        expect(
          history.run(
            const SetSceneLightingField(field: 'bloomEnabled', value: false),
          ),
          isNull,
        );
        expect(history.project.lighting.post.bloomEnabled, isFalse);
      },
    );

    test('a bad value for a scene-wide field is refused', () {
      final history = ModelHistory(const ModelProject());

      final said = history.run(
        const SetSceneLightingField(field: 'shadows', value: 'yes'),
      );

      expect(said, isNotNull);
      expect(history.project.lighting.shadows, isFalse);
    });
  });

  group('lighting survives edits that rebuild the project', () {
    // The same "every field belongs in copyWith" bug `RenderSettings`'s own
    // test file already documents having caught seven of: a project method
    // that rebuilds `ModelProject` by hand and forgets one field silently
    // resets it. `withObject`, `added`, `removed` and `RemoveMaterial` all
    // build a `ModelProject` by hand rather than through `copyWith` — this
    // is the regression test for all four forgetting `lighting`.
    test('adding, removing and editing an object keeps the lighting', () {
      var project = const ModelProject().copyWith(
        lighting: const SceneLighting(ambientIntensity: 0.7),
      );

      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      expect(project.lighting.ambientIntensity, 0.7);

      final object = project.objects.single;
      project = project.withObject(object.copyWith(name: 'b'));
      expect(project.lighting.ambientIntensity, 0.7);

      project = project.removed(object.id);
      expect(project.lighting.ambientIntensity, 0.7);
    });

    test('removing a material keeps the lighting', () {
      final history = ModelHistory(
        const ModelProject().copyWith(
          lighting: const SceneLighting(ambientIntensity: 0.9),
        ),
      );
      history.run(const AddMaterial());

      expect(history.run(const RemoveMaterial(0)), isNull);
      expect(history.project.lighting.ambientIntensity, 0.9);
    });
  });
}
