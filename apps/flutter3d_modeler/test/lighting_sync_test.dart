/// `mat-23`'s own row: `LightingSync` pushes a project's [SceneLighting]
/// onto the runtime `Scene`.
///
///     flutter test test/lighting_sync_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/lighting_sync.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  test('a light in the project becomes a LightNode in the scene', () {
    final scene = Scene();
    final sync = LightingSync();
    final history = ModelHistory(const ModelProject());
    history.run(
      const AddLight(type: ProjectLightType.point),
    );

    sync.sync(scene, history.project.lighting);

    expect(scene.lights, hasLength(1));
    expect(scene.lights.single.type, LightType.point);
  });

  test(
    "mat-23's own acceptance: RemoveLight detaches the node on the next "
    'sync',
    () {
      final scene = Scene();
      final sync = LightingSync();
      final history = ModelHistory(const ModelProject());
      history.run(const AddLight());
      sync.sync(scene, history.project.lighting);
      expect(scene.lights, hasLength(1));
      final LightNode removedNode = scene.lights.single;

      expect(history.run(const RemoveLight(0)), isNull);
      sync.sync(scene, history.project.lighting);

      expect(scene.lights, isEmpty);
      // Mutation: `sync` clears `_managed` without calling `scene.remove` on
      // each node first — `scene.lights` would already be empty (a fresh
      // scene, nothing re-added), so this second assertion is the one that
      // actually catches it: the node this test held onto must no longer be
      // attached to anything.
      expect(removedNode.parent, isNull);
    },
  );

  test('two lights become two nodes, in order', () {
    final scene = Scene();
    final sync = LightingSync();
    final history = ModelHistory(const ModelProject());
    history.run(const AddLight(type: ProjectLightType.directional));
    history.run(const AddLight(type: ProjectLightType.spot));

    sync.sync(scene, history.project.lighting);

    expect(scene.lights, hasLength(2));
    expect(scene.lights[0].type, LightType.directional);
    expect(scene.lights[1].type, LightType.spot);
  });

  test('a light field change is reflected on the next sync', () {
    final scene = Scene();
    final sync = LightingSync();
    final history = ModelHistory(const ModelProject());
    history.run(const AddLight());
    sync.sync(scene, history.project.lighting);

    history.run(
      const SetLightField(index: 0, field: 'intensity', value: 4.5),
    );
    sync.sync(scene, history.project.lighting);

    expect(scene.lights.single.intensity, 4.5);
  });

  group('apply', () {
    test('exposure and shadows come from the lighting', () {
      final sync = LightingSync();
      const settings = RenderSettings();
      const lighting = SceneLighting(exposure: 3.0, shadows: true);

      final applied = sync.apply(settings, lighting);

      expect(applied.exposure, 3.0);
      expect(applied.shadows.enabled, isTrue);
    });
  });
}
