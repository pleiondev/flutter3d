/// `mat-24`'s own pure logic: the status line's text, when it warns, and
/// which lights are pickable.
///
///     flutter test test/scene_mode_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/scene_mode.dart';
import 'package:flutter_test/flutter_test.dart';

List<ProjectLight> _lights(int count, {bool shadowed = false}) =>
    List<ProjectLight>.generate(
      count,
      (int i) => ProjectLight(castsShadow: shadowed),
    );

void main() {
  group('the status text', () {
    test('names the light count and the shadowed count out of the cap', () {
      final status = computeSceneStatus(
        lights: _lights(3, shadowed: true),
      );

      // Mutation: swap the two numbers, or hard-code the cap as something
      // other than what `kSceneShadowCap` names.
      expect(status.text, 'Источников 3 · теневых 3 из 6');
    });

    test('a project with no lights reads zero of six, not a blank line', () {
      final status = computeSceneStatus(lights: const <ProjectLight>[]);

      expect(status.text, 'Источников 0 · теневых 0 из 6');
      expect(status.warning, isFalse);
    });
  });

  group('the shadowed count is capped, never counted past it', () {
    test('eight shadow-casting lights still read six of six', () {
      final status = computeSceneStatus(lights: _lights(8, shadowed: true));

      // Mutation: report `requested` uncapped — the renderer itself never
      // shadows more than `kSceneShadowCap` lights in one frame, so a status
      // line claiming eight of six would be naming a shadow nobody drew.
      expect(status.shadowedCount, 6);
      expect(status.lightCount, 8);
    });

    test('lights that do not ask for a shadow do not count towards it', () {
      final status = computeSceneStatus(
        lights: <ProjectLight>[
          ...(_lights(2, shadowed: true)),
          ...(_lights(4)),
        ],
      );

      expect(status.shadowedCount, 2);
      expect(status.lightCount, 6);
    });
  });

  group('the warning follows the frame the renderer drew, not a guess at '
      'the light count', () {
    test('a ninth light that the renderer actually dropped goes orange', () {
      // `mat-24`'s own acceptance: "девятый источник → оранжевый статус".
      // What makes it orange is the renderer's own report that a light was
      // dropped drawing the frame — passed in here exactly as `Renderer
      // .render` would hand it back on its `FrameResult` — not a threshold
      // this file invents from `lights.length` alone.
      final status = computeSceneStatus(
        lights: _lights(9),
        lightsDropped: 1,
      );

      expect(status.warning, isTrue);
    });

    test('eight lights and nothing dropped stays green', () {
      final status = computeSceneStatus(lights: _lights(8), lightsDropped: 0);

      // Mutation: warn whenever `lights.length > 8` regardless of what the
      // frame actually reported. Eight lights that all fit in one draw
      // report zero dropped, and a status line that went orange anyway
      // would be warning about a frame that drew exactly what it was asked.
      expect(status.warning, isFalse);
    });

    test('a denied shadow warns even with every light drawn', () {
      final status = computeSceneStatus(
        lights: _lights(2, shadowed: true),
        shadowsDenied: 1,
      );

      expect(status.warning, isTrue);
    });

    test('neither dropped nor denied leaves the status green', () {
      final status = computeSceneStatus(
        lights: _lights(6, shadowed: true),
      );

      expect(status.warning, isFalse);
    });
  });

  group('pickable light markers', () {
    test('every light is pickable, named by its own index', () {
      final lighting = SceneLighting(
        lights: <ProjectLight>[
          ProjectLight(type: ProjectLightType.point),
          ProjectLight(type: ProjectLightType.spot),
          ProjectLight(),
        ],
      );

      expect(pickableLightIndices(lighting), <int>[0, 1, 2]);
    });

    test('no lights, no pickable markers', () {
      expect(pickableLightIndices(const SceneLighting()), isEmpty);
    });
  });
}
