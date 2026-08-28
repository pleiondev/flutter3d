import 'dart:math' as math;

import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Reads slot [index] of one of the buffer's arrays as a Vector4.
Vector4 slot(List<double> array, int index) => Vector4(
  array[index * 4],
  array[index * 4 + 1],
  array[index * 4 + 2],
  array[index * 4 + 3],
);

void main() {
  group('gathering', () {
    test('a directional light stores its aim, not a position', () {
      final scene = Scene();
      final light = scene.add(
        LightNode(
          type: LightType.directional,
          color: Vector3(1.0, 0.5, 0.25),
          intensity: 2.0,
          name: 'key',
        ),
      );
      // Local -Z is the forward axis, so aiming down means -Y.
      light.setLocalForward(Vector3(0.0, -1.0, 0.0));

      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, 1);

      expect(slot(buffer.positions, 0).w, ShaderLightType.directional);

      final colour = slot(buffer.colors, 0);
      expect(colour.x, closeTo(1.0, 1e-6));
      expect(colour.y, closeTo(0.5, 1e-6));
      expect(colour.w, closeTo(2.0, 1e-6));

      final direction = slot(buffer.directions, 0);
      expect(direction.y, closeTo(-1.0, 1e-5));
      expect(direction.w, 0.0); // range unset means unbounded
    });

    test('a point light stores its world position', () {
      final scene = Scene();
      final pivot = scene.add(SceneNode())..setPosition(1.0, 0.0, 0.0);
      final light = LightNode(type: LightType.point, range: 12.0)
        ..setPosition(0.0, 2.0, 0.0);
      pivot.add(light);

      final buffer = LightBuffer()..gather(scene.lights);
      final position = slot(buffer.positions, 0);

      // World, not local: the parent's offset has to be included or a light on
      // a moving rig stays behind.
      expect(position.x, closeTo(1.0, 1e-6));
      expect(position.y, closeTo(2.0, 1e-6));
      expect(position.w, ShaderLightType.point);
      expect(slot(buffer.directions, 0).w, closeTo(12.0, 1e-6));
    });

    test('cone angles are stored as cosines, widest first', () {
      final scene = Scene();
      scene.add(
        LightNode(
          type: LightType.spot,
          innerConeAngle: 0.2,
          outerConeAngle: 0.6,
        ),
      );

      final buffer = LightBuffer()..gather(scene.lights);
      final cone = slot(buffer.cones, 0);

      expect(cone.x, closeTo(math.cos(0.2), 1e-6));
      expect(cone.y, closeTo(math.cos(0.6), 1e-6));
      // cos is decreasing, so the inner cone always has the larger cosine.
      expect(cone.x, greaterThan(cone.y));
    });

    test(
      'equal cone angles are separated so the falloff cannot divide by zero',
      () {
        final scene = Scene();
        scene.add(
          LightNode(
            type: LightType.spot,
            innerConeAngle: 0.5,
            outerConeAngle: 0.5,
          ),
        );

        final buffer = LightBuffer()..gather(scene.lights);
        final cone = slot(buffer.cones, 0);
        expect(cone.x - cone.y, greaterThan(0.0));
      },
    );

    test('an inner cone wider than the outer one is clamped', () {
      final scene = Scene();
      scene.add(
        LightNode(
          type: LightType.spot,
          innerConeAngle: 1.2,
          outerConeAngle: 0.3,
        ),
      );

      final buffer = LightBuffer()..gather(scene.lights);
      final cone = slot(buffer.cones, 0);
      expect(cone.x, greaterThanOrEqualTo(cone.y));
    });
  });

  group('what is skipped', () {
    test('an invisible light contributes nothing', () {
      final scene = Scene();
      scene.add(LightNode(name: 'on'));
      scene.add(LightNode(name: 'off')..visible = false);

      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, 1);
    });

    test('a light under an invisible parent contributes nothing', () {
      final scene = Scene();
      final pivot = scene.add(SceneNode())..visible = false;
      pivot.add(LightNode());

      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, 0);
    });

    test('zero intensity is treated as off', () {
      final scene = Scene();
      scene.add(LightNode(intensity: 0.0));
      expect((LightBuffer()..gather(scene.lights)).count, 0);
    });

    test('lights past the limit are counted rather than silently dropped', () {
      final scene = Scene();
      for (var i = 0; i < LightBuffer.maxLights + 3; i++) {
        scene.add(LightNode(name: 'light $i'));
      }

      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, LightBuffer.maxLights);
      expect(buffer.overflow, 3);
    });

    test('re-gathering resets the count instead of accumulating', () {
      final scene = Scene();
      final light = scene.add(LightNode());
      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, 1);

      light.visible = false;
      buffer.gather(scene.lights);
      expect(buffer.count, 0);
      expect(buffer.overflow, 0);
    });
  });

  group('the default light', () {
    test('is a single directional light so an unlit scene is not black', () {
      final buffer = LightBuffer()..useDefaultLight();
      expect(buffer.count, 1);
      expect(slot(buffer.positions, 0).w, ShaderLightType.directional);
      expect(slot(buffer.colors, 0).w, greaterThan(0.0));

      final direction = slot(buffer.directions, 0);
      expect(
        Vector3(direction.x, direction.y, direction.z).length,
        closeTo(1.0, 1e-6),
      );
    });

    test('replaces whatever was gathered before it', () {
      final scene = Scene();
      for (var i = 0; i < 4; i++) {
        scene.add(LightNode());
      }
      final buffer = LightBuffer()..gather(scene.lights);
      expect(buffer.count, 4);

      buffer.useDefaultLight();
      expect(buffer.count, 1);
    });
  });

  test('the type codes match what the shader compares against', () {
    // The shader classifies with `type < 0.5` and `type > 1.5`, so these values
    // are a contract with GLSL, not an implementation detail.
    expect(ShaderLightType.of(LightType.directional), 0.0);
    expect(ShaderLightType.of(LightType.point), 1.0);
    expect(ShaderLightType.of(LightType.spot), 2.0);
  });
}
