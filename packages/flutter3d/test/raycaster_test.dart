import 'dart:math' as math;

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A unit cube on the CPU: no GPU anywhere in this file, which is the point of
/// [MeshGeometry].
MeshNode cubeNode({String? name, Vector3? size}) => MeshNode(
  CpuMesh(CuboidShape(size: size ?? Vector3.all(1.0)).build()),
  Material(),
  name: name,
);

/// A single triangle in the z = 0 plane, with UVs that make the hit point
/// readable straight off the texture coordinate.
MeshNode triangleNode({String? name}) {
  final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
  final a = builder.addVertex(
    position: Vector3(0.0, 0.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(0.0, 0.0),
  );
  final b = builder.addVertex(
    position: Vector3(1.0, 0.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(1.0, 0.0),
  );
  final c = builder.addVertex(
    position: Vector3(0.0, 1.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(0.0, 1.0),
  );
  builder.addTriangle(a, b, c);
  return MeshNode(CpuMesh(builder.build()), Material(), name: name);
}

/// A camera at +Z looking at the origin, the arrangement the demo starts in.
CameraNode cameraAt(Scene scene, double distance) {
  final camera = scene.add(CameraNode(name: 'camera'));
  camera.setPosition(0.0, 0.0, distance);
  return camera;
}

void main() {
  group('picking a ray from the screen', () {
    test('the centre of the viewport aims down the camera forward axis', () {
      final scene = Scene();
      final camera = cameraAt(scene, 5.0);

      final caster = Raycaster()
        ..setFromScreen(camera, 400.0, 300.0, width: 800.0, height: 600.0);

      expect(caster.ray.direction.x, closeTo(0.0, 1e-6));
      expect(caster.ray.direction.y, closeTo(0.0, 1e-6));
      expect(caster.ray.direction.z, closeTo(-1.0, 1e-6));
      expect(caster.ray.direction.length, closeTo(1.0, 1e-6));
    });

    test('the top of the viewport aims upwards, not downwards', () {
      // The Y flip is the single easiest thing to get backwards, and getting it
      // backwards still produces a plausible-looking ray.
      final scene = Scene();
      final camera = cameraAt(scene, 5.0);

      final caster = Raycaster()
        ..setFromScreen(camera, 400.0, 10.0, width: 800.0, height: 600.0);
      expect(caster.ray.direction.y, greaterThan(0.0));

      caster.setFromScreen(camera, 400.0, 590.0, width: 800.0, height: 600.0);
      expect(caster.ray.direction.y, lessThan(0.0));
    });

    test('the right of the viewport aims right', () {
      final scene = Scene();
      final camera = cameraAt(scene, 5.0);
      final caster = Raycaster()
        ..setFromScreen(camera, 790.0, 300.0, width: 800.0, height: 600.0);
      expect(caster.ray.direction.x, greaterThan(0.0));
    });

    test(
      'an orthographic ray starts at the pixel rather than at the camera',
      () {
        final scene = Scene();
        final camera = cameraAt(scene, 5.0)
          ..projection = const OrthographicProjection(height: 4.0);

        final caster = Raycaster()
          ..setFromScreen(camera, 800.0, 300.0, width: 800.0, height: 600.0);

        // Right edge of a 4-unit-tall, 4:3 volume: x = +2.666…
        expect(caster.ray.origin.x, closeTo(8.0 / 3.0, 1e-5));
        expect(caster.ray.direction.z, closeTo(-1.0, 1e-6));
        expect(caster.ray.direction.x, closeTo(0.0, 1e-6));
      },
    );

    test('a zero-sized viewport is refused rather than dividing by zero', () {
      final scene = Scene();
      final camera = cameraAt(scene, 5.0);
      expect(
        () => Raycaster().setFromScreen(
          camera,
          0.0,
          0.0,
          width: 0.0,
          height: 600.0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('intersecting a scene', () {
    test('a ray down the middle hits the cube on its near face', () {
      final scene = Scene();
      final node = scene.add(cubeNode(name: 'cube'));
      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));

      final hit = caster.intersectScene(scene);
      expect(hit, isNotNull);
      expect(hit!.node, same(node));
      expect(hit.distance, closeTo(4.5, 1e-5));
      expect(hit.point.z, closeTo(0.5, 1e-5));
      expect(hit.normal.z, closeTo(1.0, 1e-5));
      expect(hit.approximate, isFalse);
      expect(hit.triangleIndex, greaterThanOrEqualTo(0));
    });

    test('a ray that misses everything returns null', () {
      final scene = Scene()..add(cubeNode());
      final caster = Raycaster()
        ..ray.setFrom(Vector3(5.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene), isNull);
    });

    test('the nearest of several overlapping nodes wins', () {
      final scene = Scene();
      // Added far-to-near, so a first-match implementation would pick the wrong
      // one and look correct in a single-object test.
      final far = scene.add(cubeNode(name: 'far'))..setPosition(0.0, 0.0, -4.0);
      final near = scene.add(cubeNode(name: 'near'))
        ..setPosition(0.0, 0.0, 2.0);

      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, -1.0));
      final hit = caster.intersectScene(scene);

      expect(hit!.node, same(near));
      expect(hit.node, isNot(same(far)));
      expect(hit.distance, closeTo(7.5, 1e-5));
    });

    test('a rotated and scaled node is hit where it actually is', () {
      final scene = Scene();
      final node = scene.add(cubeNode(name: 'cube'))
        ..setPosition(3.0, 0.0, 0.0)
        ..setRotationYawPitchRoll(math.pi / 4, 0.0, 0.0)
        ..setScale(2.0, 2.0, 2.0);

      // A cube of side 2 turned 45 degrees about Y presents a corner towards
      // +Z at distance sqrt(2) from its centre.
      final caster = Raycaster()
        ..ray.setFrom(Vector3(3.0, 0.0, 10.0), Vector3(0.0, 0.0, -1.0));
      final hit = caster.intersectScene(scene);

      expect(hit, isNotNull);
      expect(hit!.node, same(node));
      expect(hit.distance, closeTo(10.0 - math.sqrt2, 1e-4));
    });

    test('a parented node inherits its parent transform', () {
      final scene = Scene();
      final pivot = scene.add(SceneNode(name: 'pivot'))
        ..setPosition(0.0, 4.0, 0.0);
      final node = cubeNode(name: 'child');
      pivot.add(node);

      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 4.0, 5.0), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene)!.node, same(node));

      // And the un-parented position is now empty.
      caster.ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene), isNull);
    });

    test('a ray starting inside a mesh hits its far wall from the inside', () {
      final scene = Scene()..add(cubeNode(name: 'cube'));
      final caster = Raycaster()
        ..ray.setFrom(Vector3.zero(), Vector3(0.0, 0.0, -1.0));

      final hit = caster.intersectScene(scene);
      expect(hit, isNotNull);
      // The only surface ahead is the -Z face at 0.5 away, seen from behind.
      expect(hit!.distance, closeTo(0.5, 1e-5));
      expect(hit.point.z, closeTo(-0.5, 1e-5));
      expect(hit.normal.z, closeTo(-1.0, 1e-5));
    });

    test('back-face culling makes an inside ray miss entirely', () {
      final scene = Scene()..add(cubeNode());
      final caster = Raycaster()
        ..cullBackFaces = true
        ..ray.setFrom(Vector3.zero(), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene), isNull);
    });

    test('the UV at the hit interpolates the triangle corners', () {
      final scene = Scene()..add(triangleNode(name: 'tri'));
      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.25, 0.5, 3.0), Vector3(0.0, 0.0, -1.0));

      final hit = caster.intersectScene(scene);
      expect(hit, isNotNull);
      // UVs were authored to equal the xy position on this triangle.
      expect(hit!.uv.x, closeTo(0.25, 1e-5));
      expect(hit.uv.y, closeTo(0.5, 1e-5));
      expect(hit.triangleIndex, 0);
    });

    test('the normal follows the inverse transpose under non-uniform scale', () {
      final scene = Scene();
      // The surface has to be tilted *within* its own space: a normal that
      // happens to lie along a scale axis is transformed identically by the
      // world matrix and by its inverse transpose, so an axis-aligned quad
      // cannot tell a correct implementation from a wrong one.
      final node = scene.add(
        MeshNode(
          CpuMesh(
            triangleNode().mesh.source!.transformed(Matrix4.rotationX(0.9)),
          ),
          Material(),
          name: 'tilted',
        ),
      )..setScale(1.0, 4.0, 1.0);

      // Aim at the triangle's centroid, wherever the transform put it, so the
      // test is about the normal rather than about hitting a corner.
      final centroid = node.worldMatrix.transformed3(
        Vector3(1.0 / 3.0, 1.0 / 3.0, 0.0),
      );
      final caster = Raycaster()
        ..ray.setFrom(
          Vector3(centroid.x, centroid.y, centroid.z + 3.0),
          Vector3(0.0, 0.0, -1.0),
        );
      final hit = caster.intersectScene(scene);

      expect(hit, isNotNull);
      expect(hit!.normal.length, closeTo(1.0, 1e-5));

      // The right answer is the inverse transpose applied to the mesh's own
      // normal, and it is measurably different from the world matrix applied to
      // the same vector.
      final localNormal = Matrix4.rotationX(
        0.9,
      ).rotated3(Vector3(0.0, 0.0, 1.0))..normalize();
      final byNormalMatrix = node.worldNormalMatrix.rotated3(localNormal)
        ..normalize();
      final byWorldMatrix = node.worldMatrix.rotated3(localNormal)..normalize();

      expect(hit.normal.dot(byNormalMatrix).abs(), closeTo(1.0, 1e-4));
      expect(byNormalMatrix.dot(byWorldMatrix).abs(), lessThan(0.999));
    });

    test('invisible nodes and masked-out layers are skipped', () {
      // Three cubes in a line away from the camera: the nearest is hidden, the
      // middle one sits on a different layer, the far one is ordinary.
      final scene = Scene();
      final hidden = scene.add(cubeNode(name: 'hidden'))..visible = false;
      final layered = scene.add(cubeNode(name: 'layered'))
        ..setPosition(0.0, 0.0, -2.0)
        ..layerMask = 1 << 3;
      final plain = scene.add(cubeNode(name: 'plain'))
        ..setPosition(0.0, 0.0, -4.0);

      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));

      // Everything visible: the hidden one is skipped, so the layered one wins.
      expect(caster.intersectScene(scene)!.node, same(layered));
      // Default layer only: the layered one drops out too.
      expect(caster.intersectScene(scene, layerMask: 1)!.node, same(plain));
      // Visibility ignored: the nearest cube of all comes back.
      expect(
        caster.intersectScene(scene, visibleOnly: false)!.node,
        same(hidden),
      );
    });

    test('maxDistance rejects anything further away', () {
      final scene = Scene()..add(cubeNode());
      final caster = Raycaster()
        ..maxDistance = 2.0
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene), isNull);

      caster.maxDistance = 10.0;
      expect(caster.intersectScene(scene), isNotNull);
    });

    test('an empty mesh is not a candidate', () {
      final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
      final scene = Scene()
        ..add(MeshNode(CpuMesh(builder.build()), Material(), name: 'empty'));
      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));
      expect(caster.intersectScene(scene), isNull);
    });

    test('the result object is reused between casts', () {
      // Documented behaviour, and the reason picking allocates nothing: a caller
      // that keeps the object rather than copying what it needs will see it
      // change underneath them.
      final scene = Scene()..add(cubeNode());
      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));

      final first = caster.intersectScene(scene);
      final second = caster.intersectScene(scene);
      expect(first, same(second));
    });
  });

  group('meshes with no CPU geometry', () {
    test('fall back to the bounding box and say so', () {
      final scene = Scene();
      scene.add(MeshNode(_BoundsOnlyMesh(), Material(), name: 'streamed'));

      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0));
      final hit = caster.intersectScene(scene);

      expect(hit, isNotNull);
      expect(hit!.approximate, isTrue);
      expect(hit.triangleIndex, -1);
      expect(hit.distance, closeTo(4.5, 1e-5));
    });
  });
}

/// Geometry that reports bounds but has no triangles, the way a mesh uploaded
/// with `keepSourceData: false` behaves.
final class _BoundsOnlyMesh implements MeshGeometry {
  @override
  final Aabb3 bounds = Aabb3.minMax(
    Vector3(-0.5, -0.5, -0.5),
    Vector3(0.5, 0.5, 0.5),
  );

  @override
  int get vertexCount => 8;

  @override
  int get indexCount => 36;

  @override
  MeshData? get source => null;

  @override
  double get boundingRadius => math.sqrt(0.75);
}
