/// The occlusion methods hide only what is behind something — `C2`, `C3`.
///
///     dart test test/engine/occlusion_test.dart
///
/// The rasteriser, the box test, the tree's early rejection and the render
/// list are pinned here without a device; `flutter3d/test/occlusion_test.dart`
/// is where a rendered frame is held to the same picture with occlusion on.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _aspect = 2.0;

/// A camera at (0, 0, 10) looking down -Z, the grid's aspect.
CameraNode _camera() => CameraNode()
  ..setPosition(0.0, 0.0, 10.0)
  ..lookAt(Vector3.zero());

/// A quad facing +Z, counter-clockwise from the front, [w] by [h] at depth
/// [z], as two triangles sharing the diagonal from (-,-) to (+,+).
MeshData _quad(double w, double h, {double z = 0.0, bool reversed = false}) {
  final x = w / 2, y = h / 2;
  return MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List.fromList(<double>[
      -x, -y, z, //
      x, -y, z, //
      x, y, z, //
      -x, y, z, //
    ]),
    indices: Uint32List.fromList(
      reversed ? <int>[0, 2, 1, 0, 3, 2] : <int>[0, 1, 2, 0, 2, 3],
    ),
  );
}

/// Where a world point lands on [buffer]'s grid.
(double, double) _project(OcclusionBuffer buffer, Vector3 p) {
  final clip = buffer.viewProjection.transformed(Vector4(p.x, p.y, p.z, 1.0));
  return (
    (clip.x / clip.w * 0.5 + 0.5) * buffer.width,
    (0.5 - clip.y / clip.w * 0.5) * buffer.height,
  );
}

/// Pixels strictly inside the projection of the rectangle from [low] to
/// [high], held a pixel away from its edges.
Iterable<(int, int)> _inside(
  OcclusionBuffer buffer,
  Vector3 low,
  Vector3 high,
) sync* {
  final (x0, y1) = _project(buffer, low);
  final (x1, y0) = _project(buffer, high);
  for (var y = y0.ceil() + 1; y < y1.floor() - 1; y++) {
    for (var x = x0.ceil() + 1; x < x1.floor() - 1; x++) {
      yield (x, y);
    }
  }
}

Aabb3 _box(double x, double y, double z, [double half = 0.5]) => Aabb3.minMax(
  Vector3(x - half, y - half, z - half),
  Vector3(x + half, y + half, z + half),
);

void main() {
  group('OcclusionBuffer', () {
    test('an empty grid hides nothing', () {
      final buffer = OcclusionBuffer()
        ..begin(_camera().viewProjection(_aspect));
      expect(buffer.mayBeVisible(_box(0, 0, -20)), isTrue);
    });

    test('an occluder fills the pixels it covers and no others', () {
      final buffer = OcclusionBuffer()
        ..begin(_camera().viewProjection(_aspect));
      buffer.draw(_quad(4, 2), Matrix4.identity());

      final inside = _inside(buffer, Vector3(-2, -1, 0), Vector3(2, 1, 0));
      expect(inside, isNotEmpty);
      for (final (x, y) in inside) {
        expect(buffer.depthAt(x, y), lessThan(1.0), reason: 'pixel $x, $y');
      }
      // Far outside the quad, top-left and bottom-right.
      expect(buffer.depthAt(0, 0), double.infinity);
      expect(
        buffer.depthAt(buffer.width - 1, buffer.height - 1),
        double.infinity,
      );
      // A pixel just past the right edge: nothing of the quad reaches it.
      final (right, _) = _project(buffer, Vector3(2, 0, 0));
      expect(
        buffer.depthAt(right.ceil() + 1, buffer.height ~/ 2),
        double.infinity,
      );
    });

    test('two triangles sharing an edge leave no seam along it', () {
      // Mutation: resolve the corner scratch after every triangle instead of
      // after the mesh (call `_resolveMesh` inside the loop in `draw`). Each
      // triangle alone leaves every pixel the diagonal crosses empty, and
      // this finds them.
      final buffer = OcclusionBuffer()
        ..begin(_camera().viewProjection(_aspect));
      buffer.draw(_quad(6, 3), Matrix4.identity());
      final empty = <(int, int)>[
        for (final (x, y) in _inside(
          buffer,
          Vector3(-3, -1.5, 0),
          Vector3(3, 1.5, 0),
        ))
          if (buffer.depthAt(x, y) == double.infinity) (x, y),
      ];
      expect(empty, isEmpty);
    });

    test('a triangle through the near plane is clipped, not dropped', () {
      // A floor running from far ahead to behind the eye. Mutation: return
      // from `_triangle` whenever any corner is behind — the bottom of the
      // grid, which only the part near the eye reaches, comes back empty.
      final camera = CameraNode()..setPosition(0.0, 0.0, 0.0);
      final buffer = OcclusionBuffer()..begin(camera.viewProjection(_aspect));
      final floor = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List.fromList(<double>[
          -50, -1, 50, //
          50, -1, 50, //
          50, -1, -50, //
          -50, -1, -50, //
        ]),
        indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
      );
      buffer.draw(floor, Matrix4.identity());
      expect(
        buffer.depthAt(buffer.width ~/ 2, buffer.height - 1),
        lessThan(1.0),
      );
      expect(buffer.depthAt(buffer.width ~/ 2, 0), double.infinity);
    });

    test('a back face hides nothing unless culling is off', () {
      final vp = _camera().viewProjection(_aspect);
      final centre = (
        OcclusionBuffer().width ~/ 2,
        OcclusionBuffer().height ~/ 2,
      );

      final culled = OcclusionBuffer()..begin(vp);
      culled.draw(_quad(4, 2, reversed: true), Matrix4.identity());
      expect(culled.depthAt(centre.$1, centre.$2), double.infinity);

      final both = OcclusionBuffer()..begin(vp);
      both.draw(
        _quad(4, 2, reversed: true),
        Matrix4.identity(),
        cullBackFaces: false,
      );
      expect(both.depthAt(centre.$1, centre.$2), lessThan(1.0));

      // A mirroring transform turns the front quad over on screen, and the
      // scene pass flips its winding for it: it is still a front face.
      // Mutation: ignore `mirrored` in `_raster` and this one goes empty.
      final mirrored = OcclusionBuffer()..begin(vp);
      mirrored.draw(_quad(4, 2), Matrix4.diagonal3Values(-1.0, 1.0, 1.0));
      expect(mirrored.depthAt(centre.$1, centre.$2), lessThan(1.0));
    });

    test(
      'a box behind the wall is hidden and anything short of that is not',
      () {
        final buffer = OcclusionBuffer()
          ..begin(_camera().viewProjection(_aspect));
        final wall = CuboidShape(size: Vector3(6, 4, 0.2)).build();
        buffer.draw(wall, Matrix4.identity());

        // Mutation: flip the comparison in `mayBeVisible` (`limit < depth`) and
        // the first two expectations swap.
        expect(buffer.mayBeVisible(_box(0, 0, -5)), isFalse, reason: 'behind');
        expect(buffer.mayBeVisible(_box(0, 0, 3)), isTrue, reason: 'in front');
        // Behind, but reaching past the wall's edge where nothing covers it.
        expect(
          buffer.mayBeVisible(_box(3.5, 0, -2)),
          isTrue,
          reason: 'past edge',
        );
        // The wall's own box: its face is its box's face.
        expect(
          buffer.mayBeVisible(
            Aabb3.minMax(Vector3(-3, -2, -0.1), Vector3(3, 2, 0.1)),
          ),
          isTrue,
          reason: 'itself',
        );
        // Around the eye: a corner behind the near plane decides nothing.
        expect(buffer.mayBeVisible(_box(0, 0, 10, 1)), isTrue, reason: 'eye');
      },
    );
  });

  group('SceneBvh.queryFrustumWhere', () {
    test('a refused node takes its whole subtree with it', () {
      const count = 64;
      final spheres = Float32List(count * 4);
      for (var i = 0; i < count; i++) {
        spheres
          ..[i * 4] = (i % 8) * 2.0 - 7.0
          ..[i * 4 + 1] = 0.0
          ..[i * 4 + 2] = -(i ~/ 8) * 2.0 - 5.0
          ..[i * 4 + 3] = 0.5;
      }
      final bvh = SceneBvh()..refresh(spheres, count, 1);
      final frustum = Frustum.matrix(_camera().viewProjection(_aspect));

      var asked = 0;
      final visited = <int>[];
      bvh.queryFrustumWhere(frustum, (box) {
        asked++;
        return false;
      }, visited.add);
      expect(visited, isEmpty);
      expect(asked, 1, reason: 'the root was refused, so nothing under it');

      final left = <int>[];
      bvh.queryFrustumWhere(frustum, (box) => box.min.x < 0.0, left.add);
      final all = <int>[];
      bvh.queryFrustum(frustum, all.add);
      expect(left.length, lessThan(all.length));
      expect(left, everyElement(predicate<int>((i) => spheres[i * 4] < 0.5)));
    });
  });

  group('RenderList with a software occlusion test', () {
    ({Scene scene, CameraNode camera}) street() {
      final scene = Scene();
      final wall = MeshNode(
        CpuMesh(CuboidShape(size: Vector3(8, 4, 0.2)).build()),
        Material(),
        name: 'wall',
      )..occluder = true;
      scene.add(wall);
      final cube = CpuMesh(CuboidShape().build());
      for (var i = 0; i < 6; i++) {
        scene
            .add(MeshNode(cube, Material(), name: 'behind $i'))
            .setPosition(-2.5 + i, 0.0, -4.0);
      }
      scene
        ..add(
          MeshNode(cube, Material(), name: 'front'),
        ).setPosition(0.0, 0.0, 3.0);
      final camera = scene.add(_camera());
      return (scene: scene, camera: camera);
    }

    Set<String> built(
      Scene scene,
      CameraNode camera,
      OcclusionTest? test, {
      int threshold = RenderList.defaultBvhThreshold,
    }) {
      final list = RenderList()..bvhThreshold = threshold;
      final vp = camera.viewProjection(_aspect);
      list.build(
        scene,
        RenderView(camera: camera),
        viewMatrix: camera.viewMatrix,
        frustum: Frustum.matrix(vp),
        occlusion: test,
      );
      return <String>{
        for (var i = 0; i < list.length; i++) list.itemAt(i).requireNode.name!,
      };
    }

    test(
      'what is behind a marked occluder is left out, by walk and by tree',
      () {
        final (:scene, :camera) = street();
        final vp = camera.viewProjection(_aspect);
        OcclusionTest occlusion() => SoftwareOcclusion().prepare(
          meshes: scene.meshes,
          viewProjection: vp,
          frustum: Frustum.matrix(vp),
          eye: camera.readWorldPosition(),
          layerMask: 0xFFFFFFFF,
        );

        expect(built(scene, camera, null), hasLength(8));
        // Mutation: drop the `occlusion` check from `consider` in
        // `RenderList.build` — the six cubes come back.
        expect(built(scene, camera, occlusion()), <String>{'wall', 'front'});
        expect(built(scene, camera, occlusion(), threshold: 0), <String>{
          'wall',
          'front',
        });
      },
    );

    test('an unmarked, transparent or skinned mesh occludes nothing', () {
      final (:scene, :camera) = street();
      final wall = scene.meshes.first;
      final vp = camera.viewProjection(_aspect);
      final software = SoftwareOcclusion();
      OcclusionTest occlusion() => software.prepare(
        meshes: scene.meshes,
        viewProjection: vp,
        frustum: Frustum.matrix(vp),
        eye: camera.readWorldPosition(),
        layerMask: 0xFFFFFFFF,
      );

      wall.occluder = false;
      expect(built(scene, camera, occlusion()), hasLength(8));
      wall
        ..occluder = true
        ..material.alphaMode = MaterialAlphaMode.blend;
      expect(built(scene, camera, occlusion()), hasLength(8));
      expect(software.occluders, 0);
      wall.material.alphaMode = MaterialAlphaMode.opaque;
      // A proxy stands in for a mesh with no triangles on the CPU.
      wall.occluderMesh = CuboidShape(size: Vector3(7, 3, 0.1)).build();
      expect(built(scene, camera, occlusion()), <String>{'wall', 'front'});
    });

    test('the triangle budget takes the largest occluders first', () {
      final (:scene, :camera) = street();
      final vp = camera.viewProjection(_aspect);
      for (final node in scene.meshes) {
        node.occluder = true;
      }
      final software = SoftwareOcclusion()
        ..prepare(
          meshes: scene.meshes,
          viewProjection: vp,
          frustum: Frustum.matrix(vp),
          eye: camera.readWorldPosition(),
          layerMask: 0xFFFFFFFF,
          budget: 12,
        );
      // Twelve triangles is one box: the wall, which is widest on screen,
      // rather than the front cube, which is nearer and smaller.
      expect(software.occluders, 1);
      expect(software.buffer.mayBeVisible(_box(2.5, 0, -4)), isFalse);
    });
  });

  group('HiZOcclusion', () {
    /// A reading of a flat wall filling the view at [depth] metres, with the
    /// cells whose x is below [emptyBelow] left undrawn.
    ByteData reading(double depth, double far, {int emptyBelow = 0}) {
      final bytes = ByteData(HiZOcclusion.width * HiZOcclusion.height * 4);
      final steps = (depth / far * HiZOcclusion.depthSteps).ceil();
      for (var y = 0; y < HiZOcclusion.height; y++) {
        for (var x = 0; x < HiZOcclusion.width; x++) {
          final o = (y * HiZOcclusion.width + x) * 4;
          bytes
            ..setUint8(o, steps >> 16)
            ..setUint8(o + 1, (steps >> 8) & 0xFF)
            ..setUint8(o + 2, steps & 0xFF)
            ..setUint8(o + 3, x < emptyBelow ? 0 : 255);
        }
      }
      return bytes;
    }

    void take(HiZOcclusion hiZ, CameraNode camera, ByteData bytes) =>
        hiZ.accept(
          bytes,
          viewProjection: camera.viewProjection(_aspect),
          eye: camera.readWorldPosition(),
          forward: camera.readForward(),
          far: camera.projection.far,
          camera: camera,
        );

    OcclusionTest? ask(HiZOcclusion hiZ, CameraNode camera) => hiZ.prepare(
      camera.viewProjection(_aspect),
      eye: camera.readWorldPosition(),
      forward: camera.readForward(),
      camera: camera,
    );

    test('nothing is hidden before the first reading', () {
      expect(ask(HiZOcclusion(), _camera()), isNull);
    });

    test(
      'a still camera hides what is behind the reading and nothing else',
      () {
        final camera = _camera();
        final hiZ = HiZOcclusion();
        take(hiZ, camera, reading(10.0, camera.projection.far));
        final test = ask(hiZ, camera)!;
        // The wall is ten metres out, at z = 0.
        expect(test.mayBeVisible(_box(0, 0, -5)), isFalse, reason: 'behind');
        expect(test.mayBeVisible(_box(0, 0, 3)), isTrue, reason: 'in front');
        // A box straddling the wall's plane reaches in front of it.
        expect(test.mayBeVisible(_box(0, 0, 0.2)), isTrue, reason: 'on it');
      },
    );

    test('a cell with an empty pixel under it is no occluder', () {
      final camera = _camera();
      final hiZ = HiZOcclusion();
      // The left half of the view saw sky.
      take(
        hiZ,
        camera,
        reading(
          10.0,
          camera.projection.far,
          emptyBelow: HiZOcclusion.width ~/ 2,
        ),
      );
      final test = ask(hiZ, camera)!;
      expect(test.mayBeVisible(_box(-3, 0, -5)), isTrue);
      expect(test.mayBeVisible(_box(3, 0, -5)), isFalse);
    });

    test(
      'a small step reprojects, a cut or another camera answers visible',
      () {
        final camera = _camera();
        final hiZ = HiZOcclusion();
        take(hiZ, camera, reading(10.0, camera.projection.far));

        // Half a metre sideways: the wall is still there, and a box well
        // behind its middle still hidden.
        camera.setPosition(0.5, 0.0, 10.0);
        expect(ask(hiZ, camera)!.mayBeVisible(_box(0.5, 0, -8)), isFalse);

        // Mutation: raise `cutDistance` past five metres — the reading is
        // reprojected across the jump and this is no longer null.
        camera.setPosition(0.0, 0.0, 15.0);
        expect(ask(hiZ, camera), isNull, reason: 'a jump');
        camera
          ..setPosition(0.0, 0.0, 10.0)
          ..lookAt(Vector3(10.0, 0.0, 10.0));
        expect(ask(hiZ, camera), isNull, reason: 'a turn');
        expect(ask(hiZ, _camera()), isNull, reason: 'another camera');
      },
    );
  });
}
