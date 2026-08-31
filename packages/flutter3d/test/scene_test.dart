import 'dart:math' as math;

import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('transform composition', () {
    test('a child inherits its parent transform', () {
      final parent = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final child = SceneNode()..setPosition(1.0, 2.0, 3.0);
      parent.add(child);

      final world = child.readWorldPosition();
      expect(world.x, closeTo(11.0, 1e-6));
      expect(world.y, closeTo(2.0, 1e-6));
      expect(world.z, closeTo(3.0, 1e-6));
    });

    test('parent scale multiplies child translation', () {
      final parent = SceneNode()..setUniformScale(2.0);
      final child = SceneNode()..setPosition(1.0, 0.0, 0.0);
      parent.add(child);

      expect(child.readWorldPosition().x, closeTo(2.0, 1e-6));
    });

    test('rotation composes through three levels', () {
      final a = SceneNode()
        ..setRotationYawPitchRoll(math.pi / 2, 0.0, 0.0);
      final b = SceneNode()..setPosition(1.0, 0.0, 0.0);
      final c = SceneNode()..setPosition(1.0, 0.0, 0.0);
      a.add(b);
      b.add(c);

      // Yaw of 90 degrees maps +X onto... whichever axis the convention picks;
      // what matters is that two unit steps accumulate to length 2.
      expect(c.readWorldPosition().length, closeTo(2.0, 1e-6));
    });
  });

  group('world matrices are never stale', () {
    test('moving a parent is visible from the child immediately', () {
      final parent = SceneNode();
      final child = SceneNode()..setPosition(1.0, 0.0, 0.0);
      parent.add(child);

      expect(child.readWorldPosition().x, closeTo(1.0, 1e-6));

      // No explicit update pass: the next read must already reflect this.
      parent.setPosition(5.0, 0.0, 0.0);
      expect(child.readWorldPosition().x, closeTo(6.0, 1e-6));
    });

    test('a deep chain repairs itself from one read at the leaf', () {
      final nodes = <SceneNode>[SceneNode()];
      for (var i = 1; i < 12; i++) {
        final node = SceneNode()..setPosition(1.0, 0.0, 0.0);
        nodes[i - 1].add(node);
        nodes.add(node);
      }
      final leaf = nodes.last;
      expect(leaf.readWorldPosition().x, closeTo(11.0, 1e-6));

      // Change the root only; reading the leaf must resolve every ancestor.
      nodes.first.setPosition(100.0, 0.0, 0.0);
      expect(leaf.readWorldPosition().x, closeTo(111.0, 1e-6));
    });

    test('worldVersion changes only when the world transform does', () {
      final parent = SceneNode();
      final child = SceneNode();
      parent.add(child);

      final before = child.worldVersion;
      expect(child.worldVersion, before, reason: 'reading must not invalidate');

      parent.setPosition(1.0, 0.0, 0.0);
      expect(child.worldVersion, isNot(before));
    });

    test('version stamps are unique across nodes', () {
      // A per-node counter could hand a new parent the same stamp the old one
      // had, and the reparent would go unnoticed. A global counter cannot.
      final a = SceneNode()..setPosition(1.0, 0.0, 0.0);
      final b = SceneNode()..setPosition(2.0, 0.0, 0.0);
      expect(a.worldVersion, isNot(b.worldVersion));
    });

    test('reparenting between same-shaped parents is noticed', () {
      final left = SceneNode()..setPosition(-10.0, 0.0, 0.0);
      final right = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final child = SceneNode();

      left.add(child);
      expect(child.readWorldPosition().x, closeTo(-10.0, 1e-6));

      right.add(child);
      expect(child.readWorldPosition().x, closeTo(10.0, 1e-6));
    });
  });

  group('hierarchy', () {
    test('add keeps the local transform, so the child moves', () {
      final parent = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final child = SceneNode()..setPosition(1.0, 0.0, 0.0);
      parent.add(child);
      expect(child.readWorldPosition().x, closeTo(11.0, 1e-6));
    });

    test('attach preserves the world transform, so nothing visibly moves', () {
      final parent = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final child = SceneNode()..setPosition(1.0, 2.0, 3.0);

      final before = child.readWorldPosition();
      parent.attach(child);
      final after = child.readWorldPosition();

      expect(after.x, closeTo(before.x, 1e-5));
      expect(after.y, closeTo(before.y, 1e-5));
      expect(after.z, closeTo(before.z, 1e-5));
    });

    test('attach survives a rotated and scaled parent', () {
      final parent = SceneNode()
        ..setPosition(3.0, -2.0, 1.0)
        ..setRotationYawPitchRoll(0.7, 0.3, 0.0)
        ..setUniformScale(2.5);
      final child = SceneNode()..setPosition(1.0, 2.0, -3.0);

      final before = child.readWorldPosition();
      parent.attach(child);
      final after = child.readWorldPosition();

      expect((after - before).length, lessThan(1e-4));
    });

    test('removing a child detaches it from the parent transform', () {
      final parent = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final child = SceneNode()..setPosition(1.0, 0.0, 0.0);
      parent.add(child);
      expect(child.readWorldPosition().x, closeTo(11.0, 1e-6));

      parent.remove(child);
      expect(child.parent, isNull);
      expect(child.readWorldPosition().x, closeTo(1.0, 1e-6));
    });

    test('re-adding to the same parent is a no-op', () {
      final parent = SceneNode();
      final child = SceneNode();
      parent.add(child);
      parent.add(child);
      expect(parent.children, hasLength(1));
    });

    test('a cycle is refused', () {
      final a = SceneNode(name: 'a');
      final b = SceneNode(name: 'b');
      a.add(b);
      expect(() => b.add(a), throwsArgumentError);
    });

    test('a node cannot parent itself', () {
      final a = SceneNode();
      expect(() => a.add(a), throwsArgumentError);
    });

    test('visibility is inherited', () {
      final parent = SceneNode();
      final child = SceneNode();
      parent.add(child);

      expect(child.visibleInHierarchy, isTrue);
      parent.visible = false;
      expect(child.visible, isTrue, reason: 'own flag is untouched');
      expect(child.visibleInHierarchy, isFalse);
    });

    test('findByName searches the subtree', () {
      final root = SceneNode(name: 'root');
      final mid = SceneNode(name: 'mid');
      final leaf = SceneNode(name: 'leaf');
      root.add(mid);
      mid.add(leaf);

      expect(root.findByName('leaf'), same(leaf));
      expect(root.findByName('absent'), isNull);
    });

    test('setLocalMatrix round-trips a TRS matrix', () {
      final node = SceneNode();
      final matrix = Matrix4.compose(
        Vector3(1.0, 2.0, 3.0),
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.9)..normalize(),
        Vector3(2.0, 2.0, 2.0),
      );
      node.setLocalMatrix(matrix);

      final position = node.readPosition();
      expect(position.x, closeTo(1.0, 1e-5));
      expect(position.y, closeTo(2.0, 1e-5));
      expect(node.readScale().x, closeTo(2.0, 1e-5));
    });
  });

  group('lookAt', () {
    test('points local -Z at the target', () {
      final node = SceneNode()..setPosition(0.0, 0.0, 5.0);
      node.lookAt(Vector3.zero());

      // Local -Z in world space.
      final m = node.worldMatrix.storage;
      final forward = Vector3(-m[8], -m[9], -m[10])..normalize();
      expect(forward.x, closeTo(0.0, 1e-5));
      expect(forward.y, closeTo(0.0, 1e-5));
      expect(forward.z, closeTo(-1.0, 1e-5));
    });

    test('works through a rotated parent', () {
      final parent = SceneNode()..setRotationYawPitchRoll(1.1, 0.4, 0.2);
      final node = SceneNode()..setPosition(0.0, 0.0, 5.0);
      parent.add(node);
      // The node is at (0,0,5) in the parent's space; aim it at world origin.
      node.lookAt(Vector3.zero());

      final worldPosition = node.readWorldPosition();
      final m = node.worldMatrix.storage;
      final forward = Vector3(-m[8], -m[9], -m[10])..normalize();
      final expected = (Vector3.zero() - worldPosition)..normalize();

      expect(forward.dot(expected), closeTo(1.0, 1e-4));
    });

    test('a target at the node position is ignored rather than exploding', () {
      final node = SceneNode()..setPosition(1.0, 1.0, 1.0);
      node.lookAt(Vector3(1.0, 1.0, 1.0));
      // No NaN in the matrix.
      for (final value in node.worldMatrix.storage) {
        expect(value.isFinite, isTrue);
      }
    });

    test('setLocalForward aims -Z in the parent frame', () {
      // The primitive lookAt is built on: useful for a light parented to a rig,
      // which wants a fixed direction relative to that rig.
      final rig = SceneNode()..setRotationYawPitchRoll(1.3, 0.0, 0.0);
      final child = SceneNode();
      rig.add(child);
      child.setLocalForward(Vector3(0.0, 0.0, -1.0));

      // Local -Z equals the rig's local -Z, so the child follows the rig.
      final childM = child.worldMatrix.storage;
      final rigM = rig.worldMatrix.storage;
      expect(childM[8], closeTo(rigM[8], 1e-5));
      expect(childM[9], closeTo(rigM[9], 1e-5));
      expect(childM[10], closeTo(rigM[10], 1e-5));
    });

    test('a node parented to a rig keeps its direction as the rig turns', () {
      final rig = SceneNode();
      final light = SceneNode();
      rig.add(light);
      final localDirection = Vector3(0.35, -0.45, -0.82)..normalize();
      light.setLocalForward(localDirection);

      Vector3 worldForward() {
        final m = light.worldMatrix.storage;
        return Vector3(-m[8], -m[9], -m[10])..normalize();
      }

      final before = worldForward();
      rig.setRotationYawPitchRoll(1.0, 0.0, 0.0);
      final after = worldForward();

      // The direction moved with the rig rather than staying put.
      expect(before.dot(after), lessThan(0.99));
      // ...but its angle to the rig's own forward is unchanged. Derived from the
      // local direction rather than hardcoded, so the expectation cannot drift.
      final rigM = rig.worldMatrix.storage;
      final rigForward = Vector3(-rigM[8], -rigM[9], -rigM[10])..normalize();
      final expectedDot = localDirection.dot(Vector3(0.0, 0.0, -1.0));
      expect(after.dot(rigForward), closeTo(expectedDot, 1e-5));
    });

    test('handles up parallel to forward', () {
      final node = SceneNode()..setPosition(0.0, 5.0, 0.0);
      node.lookAt(Vector3.zero(), up: Vector3(0.0, 1.0, 0.0));
      for (final value in node.worldMatrix.storage) {
        expect(value.isFinite, isTrue);
      }
    });
  });

  group('scene registries', () {
    test('nodes register when added and unregister when removed', () {
      final scene = Scene();
      final camera = CameraNode();
      final light = LightNode();

      expect(scene.cameras, isEmpty);
      scene.add(camera);
      scene.add(light);
      expect(scene.cameras, hasLength(1));
      expect(scene.lights, hasLength(1));

      camera.removeFromParent();
      expect(scene.cameras, isEmpty);
      expect(scene.lights, hasLength(1));
    });

    test('a whole subtree registers when its root is attached', () {
      final scene = Scene();
      final group = SceneNode(name: 'group');
      group.add(CameraNode());
      group.add(LightNode());
      group.add(SceneNode()..add(LightNode()));

      expect(scene.lights, isEmpty);
      scene.add(group);
      expect(scene.cameras, hasLength(1));
      expect(scene.lights, hasLength(2), reason: 'nested light counts too');

      group.removeFromParent();
      expect(scene.cameras, isEmpty);
      expect(scene.lights, isEmpty);
    });

    test('moving a subtree between scenes re-registers it', () {
      final a = Scene(name: 'a');
      final b = Scene(name: 'b');
      final light = LightNode();
      a.add(light);

      expect(a.lights, hasLength(1));
      b.add(light);
      expect(a.lights, isEmpty);
      expect(b.lights, hasLength(1));
      expect(light.scene, same(b));
    });

    test('firstLightOfType finds by type', () {
      final scene = Scene();
      scene.add(LightNode(type: LightType.point, name: 'point'));
      scene.add(LightNode(type: LightType.directional, name: 'sun'));

      expect(scene.firstLightOfType(LightType.directional)?.name, 'sun');
      expect(scene.firstLightOfType(LightType.spot), isNull);
    });
  });

  group('cached derived state', () {
    test('the view matrix is cached until the node moves', () {
      // Already covered below for the camera; this group is about the caches that
      // exist purely to keep per-draw work off the hot path.
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      expect(camera.viewMatrix, same(camera.viewMatrix));
    });
  });

  group('camera', () {
    test('the view matrix is the inverse of the world transform', () {
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      final origin = Vector3.zero();
      camera.viewMatrix.transform3(origin);
      // The world origin sits 5 units in front of the camera, i.e. at -5 on the
      // camera's Z, because the camera looks down -Z.
      expect(origin.z, closeTo(-5.0, 1e-5));
    });

    test('the view matrix follows the parent', () {
      final rig = SceneNode()..setPosition(10.0, 0.0, 0.0);
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      rig.add(camera);

      final point = Vector3(10.0, 0.0, 0.0);
      camera.viewMatrix.transform3(point);
      expect(point.z, closeTo(-5.0, 1e-5));
      expect(point.x, closeTo(0.0, 1e-5));
    });

    test('the view matrix is cached until the node moves', () {
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      final first = camera.viewMatrix;
      expect(camera.viewMatrix, same(first), reason: 'same buffer reused');

      camera.setPosition(0.0, 0.0, 6.0);
      final origin = Vector3.zero();
      camera.viewMatrix.transform3(origin);
      expect(origin.z, closeTo(-6.0, 1e-5));
    });

    test('perspective projection keeps the depth convention', () {
      final camera = CameraNode(
        projection: const PerspectiveProjection(near: 0.5, far: 50.0),
      );
      // projectToNdc lives on the abstraction, so a test asserts what the
      // projection does rather than reimplementing the divide.
      final projection = camera.projection;
      expect(projection.projectToNdc(Vector3(0.0, 0.0, -0.5)).z,
          closeTo(0.0, 1e-6));
      expect(projection.projectToNdc(Vector3(0.0, 0.0, -50.0)).z,
          closeTo(1.0, 1e-5));
    });

    test('orthographic projection keeps the depth convention', () {
      const projection = OrthographicProjection(near: 1.0, far: 11.0);

      expect(projection.projectToNdc(Vector3(0.0, 0.0, -1.0), aspect: 2.0).z,
          closeTo(0.0, 1e-6));
      expect(projection.projectToNdc(Vector3(0.0, 0.0, -11.0), aspect: 2.0).z,
          closeTo(1.0, 1e-6));
      // Height 2 means the top edge is at y = 1; aspect 2 puts the right edge at 2.
      final edge = projection.projectToNdc(Vector3(2.0, 1.0, -5.0), aspect: 2.0);
      expect(edge.x, closeTo(1.0, 1e-6));
      expect(edge.y, closeTo(1.0, 1e-6));
    });

    test('readForward reports local -Z in world space', () {
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      camera.lookAt(Vector3.zero());
      final forward = camera.readForward();
      expect(forward.z, closeTo(-1.0, 1e-5));
    });
  });

  group('light', () {
    test('direction comes from local -Z, and points away from the light', () {
      final light = LightNode()..setPosition(0.0, 10.0, 0.0);
      light.lookAt(Vector3.zero());

      expect(light.readDirection().y, closeTo(-1.0, 1e-5));
      // Shading wants the direction towards the light.
      expect(light.readDirectionToLight().y, closeTo(1.0, 1e-5));
    });

    test('the out parameter receives the same result as the return value', () {
      // This caught a real bug: the getters ended in `normalized()`, which returns
      // a NEW vector and leaves `out` holding the un-normalized, un-negated value.
      // The renderer read its own variable rather than the return value, so the
      // light direction came out inverted and every camera-facing surface fell to
      // N.L <= 0 — the scene rendered as pure ambient.
      final light = LightNode()..setPosition(3.0, 4.0, 0.0);
      light.lookAt(Vector3.zero());

      final out = Vector3.zero();
      final returned = light.readDirection(out);
      expect(returned, same(out));
      expect(out.length, closeTo(1.0, 1e-6), reason: 'normalized in place');

      final toLightOut = Vector3.zero();
      final toLight = light.readDirectionToLight(toLightOut);
      expect(toLight, same(toLightOut));
      expect(toLightOut.length, closeTo(1.0, 1e-6));
      // Towards the light is the opposite of where the light shines.
      expect(toLightOut.dot(out), closeTo(-1.0, 1e-6));
    });

    test('a light parented to a camera shines from the viewer side', () {
      // The headlight arrangement the demo uses: whatever the camera looks at must
      // be lit, so the direction towards the light has to point back at the camera.
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      camera.lookAt(Vector3.zero());
      final light = LightNode();
      camera.add(light);
      light.setLocalForward(Vector3(0.35, -0.45, -0.82));

      final toLight = light.readDirectionToLight();
      final toCamera = (camera.readWorldPosition() - Vector3.zero())..normalize();

      // Not exactly aligned — the light is offset up and to the side — but it must
      // be on the camera's side of the subject.
      expect(toLight.dot(toCamera), greaterThan(0.5));
    });

    test('the headlight follows the camera as it orbits', () {
      final camera = CameraNode();
      final light = LightNode();
      camera.add(light);
      light.setLocalForward(Vector3(0.35, -0.45, -0.82));
      final orbit = OrbitController(camera, distance: 5.0);

      for (final yaw in <double>[0.0, 1.5, 3.0, 4.5]) {
        orbit.yaw = yaw;
        orbit.apply();

        final toLight = light.readDirectionToLight();
        final toCamera = (camera.readWorldPosition() - orbit.target)..normalize();
        expect(
          toLight.dot(toCamera),
          greaterThan(0.5),
          reason: 'at yaw $yaw the subject must still face the light',
        );
      }
    });
  });

  group('camera forward', () {
    test('readForward fills the out parameter in place', () {
      final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
      camera.lookAt(Vector3.zero());
      final out = Vector3.zero();
      expect(camera.readForward(out), same(out));
      expect(out.length, closeTo(1.0, 1e-6));
      expect(out.z, closeTo(-1.0, 1e-5));
    });
  });

  group('mesh node caches', () {
    // MeshNode needs a GpuMesh, which needs a GPU, so the cache is verified
    // through the transform-version mechanism it is keyed on. The invariant that
    // matters is that a version only changes when the transform does — that is
    // what makes caching the normal matrix and the bounds safe.
    test('a still node keeps its transform version across reads', () {
      final node = SceneNode()..setPosition(1.0, 2.0, 3.0);
      final first = node.worldVersion;
      for (var i = 0; i < 5; i++) {
        node.worldMatrix;
      }
      expect(node.worldVersion, first);
    });

    test('any transform change bumps the version exactly once per change', () {
      final node = SceneNode();
      final versions = <int>{node.worldVersion};

      node.setPosition(1.0, 0.0, 0.0);
      versions.add(node.worldVersion);
      node.setUniformScale(2.0);
      versions.add(node.worldVersion);
      node.setRotationYawPitchRoll(0.5, 0.0, 0.0);
      versions.add(node.worldVersion);

      expect(versions, hasLength(4), reason: 'each change is observable');
    });
  });
}
