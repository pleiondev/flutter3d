/// A split mesh's clusters are culled only where the GPU would have drawn
/// nothing of them, and repacked only when that changes — `C9`.
///
///     dart test test/engine/cluster_draws_test.dart
///
/// The splitter itself is `flutter3d_mesh`'s (`cluster_mesh_test.dart`) and
/// the rendered frame is `flutter3d_cpu`'s (`scan_chunks_test.dart`); here
/// the table, the tests it answers, the `.f3d` section and the buffers are
/// pinned without a device.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A sphere cut into runs of [perCluster] triangles in the order it was
/// built — along each ring in turn, so a run of eight is a patch four quads
/// wide, and a run of a whole ring would be a band facing every way.
MeshData _bandedSphere({int perCluster = 8}) {
  final sphere = const SphereShape(
    radius: 1.0,
    segments: 48,
    rings: 24,
  ).build();
  final triangles = sphere.triangleCount;
  final firstIndices = Uint32List.fromList(<int>[
    for (var t = 0; t < triangles; t += perCluster) t * 3,
    triangles * 3,
  ]);
  return MeshData(
    layout: sphere.layout,
    vertices: sphere.vertices,
    indices: sphere.indices,
    clusters: MeshClusters.measure(
      layout: sphere.layout,
      vertices: sphere.vertices,
      indices: sphere.indices,
      firstIndices: firstIndices,
    ),
  );
}

/// Whether every triangle of [cluster] has the eye strictly behind its plane,
/// by winding — what the rasteriser's back-face cull decides one by one.
bool _allFaceAway(MeshData mesh, int cluster, Vector3 eye) {
  final table = mesh.clusters!;
  final a = Vector3.zero(), b = Vector3.zero(), c = Vector3.zero();
  for (
    var i = table.firstIndex(cluster);
    i < table.firstIndex(cluster + 1);
    i += 3
  ) {
    mesh.positionAt(mesh.indices[i], a);
    mesh.positionAt(mesh.indices[i + 1], b);
    mesh.positionAt(mesh.indices[i + 2], c);
    final normal = (b - a).cross(c - a);
    if (normal.length2 == 0.0) continue;
    if (!(normal.dot(a - eye) > 0.0)) return false;
  }
  return true;
}

void main() {
  group('the cluster table', () {
    test('refuses runs that do not tile the index buffer', () {
      expect(
        () => MeshClusters(
          firstIndices: Uint32List.fromList(<int>[3, 6]),
          data: Float32List(MeshClusters.floatsPerCluster),
        ),
        throwsArgumentError,
      );
      expect(
        () => MeshClusters(
          firstIndices: Uint32List.fromList(<int>[0, 4]),
          data: Float32List(MeshClusters.floatsPerCluster),
        ),
        throwsArgumentError,
      );
      final sphere = const SphereShape().build();
      expect(
        () => MeshData(
          layout: sphere.layout,
          vertices: sphere.vertices,
          indices: sphere.indices,
          clusters: MeshClusters(
            firstIndices: Uint32List.fromList(<int>[0, 3]),
            data: Float32List(MeshClusters.floatsPerCluster),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a cone faces away only where every triangle in it does', () {
      // Mutation: drop the sphere's radius from `facesAwayFrom`, or the
      // margin from the cone, and eyes near a band's rim find a triangle
      // still facing them.
      final mesh = _bandedSphere();
      final table = mesh.clusters!;
      final random = math.Random(9);
      var culled = 0;
      for (var trial = 0; trial < 400; trial++) {
        final eye = Vector3(
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
        )..scale(1.2 + random.nextDouble() * 8.0);
        for (var cluster = 0; cluster < table.length; cluster++) {
          if (!table.facesAwayFrom(cluster, eye.x, eye.y, eye.z)) continue;
          culled++;
          expect(
            _allFaceAway(mesh, cluster, eye),
            isTrue,
            reason: 'cluster $cluster culled from $eye',
          );
        }
      }
      // Not vacuous: from outside a sphere, the far bands face away.
      expect(culled, greaterThan(table.length * 400 ~/ 5));
    });

    test('a cluster whose normals spread past a right angle never culls', () {
      final mesh = _bandedSphere(perCluster: 100000);
      final table = mesh.clusters!;
      expect(table.length, 1);
      expect(table.facesAwayFrom(0, 0, 0, 50), isFalse);
      expect(table.facesAwayFrom(0, 0, 0, -50), isFalse);
    });
  });

  group('the eye of a view', () {
    test('is the camera, carried into the mesh', () {
      final camera = CameraNode()
        ..setPosition(3.0, 1.0, 6.0)
        ..lookAt(Vector3.zero());
      final world = Matrix4.translationValues(1.0, 0.0, -2.0)
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);
      final eye = clusterEye(camera.viewProjection(1.5), world)!;
      expect(eye.x, closeTo(1.0, 1e-4));
      expect(eye.y, closeTo(0.5, 1e-4));
      expect(eye.z, closeTo(4.0, 1e-4));
    });

    test('is nowhere for an orthographic view', () {
      final camera = CameraNode(projection: const OrthographicProjection())
        ..setPosition(0.0, 0.0, 6.0)
        ..lookAt(Vector3.zero());
      expect(
        clusterEye(camera.viewProjection(1.0), Matrix4.identity()),
        isNull,
      );
    });
  });

  group('the selection', () {
    test('keeps what the frustum holds and faces the eye', () {
      final mesh = _bandedSphere();
      final table = mesh.clusters!;
      // Close to the sphere and looking at its side: the far side faces
      // away and the top and bottom bands leave the frustum.
      final camera =
          CameraNode(
              projection: const PerspectiveProjection(fovYRadians: 0.5),
            )
            ..setPosition(0.0, 0.0, 2.2)
            ..lookAt(Vector3.zero());
      final viewProjection = camera.viewProjection(1.0);
      final visible = Uint8List(table.length);
      final frustumOnly = selectVisibleClusters(
        clusters: table,
        world: Matrix4.identity(),
        frustum: Frustum.matrix(viewProjection),
        visible: visible,
      );
      final both = selectVisibleClusters(
        clusters: table,
        world: Matrix4.identity(),
        frustum: Frustum.matrix(viewProjection),
        visible: visible,
        eye: clusterEye(viewProjection, Matrix4.identity()),
      );
      expect(frustumOnly, lessThan(table.length));
      expect(both, lessThan(frustumOnly));
      expect(both, greaterThan(0));
    });
  });

  group('the buffers', () {
    late FakeBackend device;
    late DeviceMesh mesh;
    late MeshNode node;
    setUp(() {
      device = FakeBackend();
      mesh = DeviceMesh.upload(device, _bandedSphere());
      node = MeshNode(mesh, Material());
      device.uploads.clear();
    });

    ({GeometryBuffer buffer, int count})? draw(
      ClusterDraws draws,
      CameraNode camera, {
      int view = 0,
    }) {
      final viewProjection = camera.viewProjection(1.0);
      return draws.indicesFor(
        node: node,
        mesh: mesh,
        view: view,
        frustum: Frustum.matrix(viewProjection),
        eye: clusterEye(viewProjection, node.worldMatrix),
      );
    }

    CameraNode at(double x, double z) => CameraNode()
      ..setPosition(x, 0.0, z)
      ..lookAt(Vector3.zero());

    test('are repacked only when the visible clusters change', () {
      // Mutation: drop the `writtenMatches` check and the second frame
      // overwrites what it already holds.
      final draws = ClusterDraws(device);
      draws.beginFrame(0);
      final first = draw(draws, at(0.0, 4.0))!;
      expect(first.count, greaterThan(0));
      expect(first.count, lessThan(mesh.indexCount));
      expect(device.uploads, hasLength(1));
      expect(device.overwrites, isEmpty);

      draws.beginFrame(1);
      final same = draw(draws, at(0.0, 4.0))!;
      expect(same.count, first.count);
      expect(device.uploads, hasLength(1));
      expect(device.overwrites, isEmpty);

      draws.beginFrame(2);
      draw(draws, at(4.0, 0.0));
      expect(device.uploads, hasLength(1));
      expect(device.overwrites, hasLength(1));
    });

    test('a view that sees every cluster draws the mesh\'s own buffer', () {
      final draws = ClusterDraws(device)..beginFrame(0);
      final camera = CameraNode()
        ..setPosition(0.0, 0.0, 30.0)
        ..lookAt(Vector3.zero());
      node.material = Material(doubleSided: true);
      final viewProjection = camera.viewProjection(1.0);
      expect(
        draws.indicesFor(
          node: node,
          mesh: mesh,
          view: 0,
          frustum: Frustum.matrix(viewProjection),
        ),
        isNull,
      );
      expect(device.uploads, isEmpty);
    });

    test('each view keeps its own, and an idle one is given back', () {
      // Mutation: key the slots by node alone, and the second view's
      // selection overwrites the first's buffer every frame.
      final draws = ClusterDraws(device, framesInFlight: 2);
      draws.beginFrame(0);
      draw(draws, at(0.0, 4.0));
      draw(draws, at(4.0, 0.0), view: 1);
      expect(draws.slotCount, 2);
      expect(device.uploads, hasLength(2));

      draws.beginFrame(1);
      draw(draws, at(0.0, 4.0));
      draw(draws, at(4.0, 0.0), view: 1);
      expect(device.overwrites, isEmpty);

      // The second view stops drawing; after the frames in flight its
      // buffer goes back and the first view's stays.
      for (var frame = 2; frame <= 4; frame++) {
        draws.beginFrame(frame);
        draw(draws, at(0.0, 4.0));
      }
      expect(draws.slotCount, 1);
      expect(device.releasedGeometry, hasLength(1));
    });
  });

  group('the .f3d section', () {
    test('carries the table through a round trip', () {
      final mesh = _bandedSphere();
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[ModelSurface(mesh: mesh)],
        nodes: <ModelNode>[
          ModelNode(surfaces: <int>[0]),
        ],
      );
      final reread = F3dDocument.parse(F3dWriter(document).write());
      final table = reread.surfaces.single.mesh.clusters!;
      expect(table.firstIndices, mesh.clusters!.firstIndices);
      expect(table.data, mesh.clusters!.data);
      expect(compareModelDocuments(document, reread), isEmpty);
    });

    test('is not written for a mesh nobody split', () {
      // Mutation: write the section unconditionally, and every converted
      // asset changes on disk for a feature it does not use.
      final sphere = const SphereShape().build();
      final plain = PlainModelDocument(
        surfaces: <ModelSurface>[ModelSurface(mesh: sphere)],
      );
      final bytes = F3dWriter(plain).write();
      final view = ByteData.sublistView(bytes);
      final sections = view.getUint32(8, Endian.little);
      final kinds = <int>[
        for (var i = 0; i < sections; i++)
          view.getUint32(
            kF3dHeaderBytes + i * kF3dSectionEntryBytes,
            Endian.little,
          ),
      ];
      expect(kinds, isNot(contains(F3dSection.clusters)));
      expect(F3dDocument.parse(bytes).surfaces.single.mesh.clusters, isNull);
    });

    test('a lost table is a difference', () {
      final mesh = _bandedSphere();
      final split = PlainModelDocument(
        surfaces: <ModelSurface>[ModelSurface(mesh: mesh)],
      );
      final whole = PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(
            mesh: MeshData(
              layout: mesh.layout,
              vertices: mesh.vertices,
              indices: mesh.indices,
            ),
          ),
        ],
      );
      expect(compareModelDocuments(split, whole), isNotEmpty);
    });
  });
}
