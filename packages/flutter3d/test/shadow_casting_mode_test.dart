/// How a mesh takes part in the shadow passes.
///
///     flutter test test/shadow_casting_mode_test.dart
///
/// Two states were one too few in both directions: a single-sided wall leaks
/// light along its seam when only its lit face is recorded, and a proxy
/// occluder has to cast without being drawn. Neither was expressible.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

CpuMesh _cube() => CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build());

void main() {
  group('the boolean is a view of the mode', () {
    test('and reads whether it casts at all', () {
      final node = MeshNode(_cube(), Material());

      expect(node.castsShadow, isTrue);

      node.shadowCasting = ShadowCastingMode.shadowsOnly;
      expect(
        node.castsShadow,
        isTrue,
        reason: 'a proxy occluder casts, whatever else it does not do',
      );

      node.shadowCasting = ShadowCastingMode.off;
      expect(node.castsShadow, isFalse);
    });

    test('and writing it moves between on and off', () {
      // Every level document and every application in this repository writes
      // the boolean, so it has to keep meaning what it meant.
      final node = MeshNode(_cube(), Material())..castsShadow = false;

      expect(node.shadowCasting, ShadowCastingMode.off);

      node.castsShadow = true;

      expect(node.shadowCasting, ShadowCastingMode.on);
    });
  });

  group('the colour pass', () {
    test('draws everything except a shadows-only proxy', () {
      final scene = Scene();
      final camera = CameraNode();
      scene.root.add(camera);
      final drawn = MeshNode(_cube(), Material());
      final proxy = MeshNode(_cube(), Material())
        ..shadowCasting = ShadowCastingMode.shadowsOnly;
      scene.root
        ..add(drawn)
        ..add(proxy);

      final list = RenderList();
      final view = RenderView(camera: camera);
      final projection = PerspectiveProjection().toMatrix(1.0);
      final viewMatrix = Matrix4.identity();
      list.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: Frustum.matrix(projection * viewMatrix),
      );

      final nodes = <MeshNode>[
        for (var i = 0; i < list.length; i++) list.itemAt(i).node!,
      ];

      expect(nodes, contains(drawn));
      expect(
        nodes,
        isNot(contains(proxy)),
        reason: 'a proxy occluder is never seen',
      );
    });
  });

  group('a static caster that changes how it casts', () {
    test('asks for the static atlas to be drawn again', () {
      // The bake is drawn once and kept for as long as the atlas rows stay with
      // the same lights, so nothing else in a frame would notice.
      final scene = Scene();
      final wall = MeshNode(_cube(), Material())..shadowIsStatic = true;
      scene.root.add(wall);
      final before = scene.staticShadowGeneration;

      wall.shadowCasting = ShadowCastingMode.doubleSided;

      expect(scene.staticShadowGeneration, greaterThan(before));
    });

    test('and setting the same mode asks for nothing', () {
      final scene = Scene();
      final wall = MeshNode(_cube(), Material())
        ..shadowIsStatic = true
        ..shadowCasting = ShadowCastingMode.doubleSided;
      final after = scene.staticShadowGeneration;

      wall.shadowCasting = ShadowCastingMode.doubleSided;

      expect(scene.staticShadowGeneration, after);
    });

    test('while a mover changes nothing, because it is redrawn anyway', () {
      final scene = Scene();
      final door = MeshNode(_cube(), Material());
      scene.root.add(door);
      final before = scene.staticShadowGeneration;

      door.shadowCasting = ShadowCastingMode.doubleSided;

      expect(scene.staticShadowGeneration, before);
    });
  });
}
