/// `mat-23`'s own row: `LightingSync` pushes a project's [SceneLighting]
/// onto the runtime `Scene`.
///
///     dart test test/lighting_sync_test.dart
///
/// **Moved here from `apps/flutter3d_modeler` by `tut-07`'s own fix**, along
/// with the class itself — see `lighting_sync.dart`'s own doc comment for
/// why. Nothing about this file changed beyond its imports: `Scene`/
/// `LightNode`/`LightType`/`RenderSettings` from `flutter3d_core` are the
/// identical types the app used to reach through `flutter3d`'s own
/// re-export.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

SceneLighting _lighting(int count) => SceneLighting(
  lights: List<ProjectLight>.generate(count, (int i) => ProjectLight()),
);

void main() {
  test('a light in the project becomes a LightNode in the scene', () {
    final scene = Scene();
    final sync = LightingSync();
    final history = ModelHistory(const ModelProject());
    history.run(const AddLight(type: ProjectLightType.point));

    sync.sync(scene, history.project.lighting);

    expect(scene.lights, hasLength(1));
    expect(scene.lights.single.type, LightType.point);
  });

  test("mat-23's own acceptance: RemoveLight detaches the node on the next "
      'sync', () {
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
  });

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

    history.run(const SetLightField(index: 0, field: 'intensity', value: 4.5));
    sync.sync(scene, history.project.lighting);

    expect(scene.lights.single.intensity, 4.5);
  });

  test("mat-24's own acceptance: a light away from the origin syncs to its "
      'own place, not the origin', () {
    final scene = Scene();
    final sync = LightingSync();
    final history = ModelHistory(const ModelProject());
    history.run(const AddLight(type: ProjectLightType.point));
    history.run(
      SetLightTransform(
        index: 0,
        to: Matrix4.identity()..setTranslationRaw(2, 3, 4),
      ),
    );

    sync.sync(scene, history.project.lighting);

    final LightNode node = scene.lights.single;
    expect(node.readPosition(), Vector3(2, 3, 4));
  });

  test("tut-07's own acceptance: sync is additive, over whatever the scene "
      'already carries', () {
    final scene = Scene()
      ..add(LightNode(type: LightType.directional, name: 'key'));
    final sync = LightingSync();

    sync.sync(scene, _lighting(2));

    expect(scene.lights, hasLength(3));
    sync.sync(scene, _lighting(1));
    // Only the two this sync itself added are ever removed again.
    expect(scene.lights, hasLength(2));
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

    test('bloom follows the lighting\'s own post settings', () {
      final sync = LightingSync();
      const settings = RenderSettings();
      const lighting = SceneLighting(
        post: ScenePostSettings(bloomEnabled: false),
      );

      expect(sync.apply(settings, lighting).bloom.enabled, isFalse);
    });
  });

  group('lightOverflowOf', () {
    test('eight lights all fit, nothing dropped', () {
      expect(lightOverflowOf(_lighting(8)), 0);
    });

    test("mat-24's own acceptance: a ninth light is one dropped", () {
      expect(lightOverflowOf(_lighting(9)), 1);
    });

    test('a project with no lights drops nothing', () {
      expect(lightOverflowOf(const SceneLighting()), 0);
    });
  });
}
