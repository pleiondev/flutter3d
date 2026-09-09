/// The one place a modeller's world is assembled.
///
/// **A file with this name in every application here, and the reason is a
/// rule.** `no test builds its own world` in `tool/structure.dart` refuses a
/// test that stands up its own scene: a harness that is not the application
/// agrees with any bug the application has, and the pictures it takes are
/// pictures of the harness. So the scene, the light and the camera are built
/// once, here, and the tests ask for the same thing the window does.
///
/// What is deliberately *not* here: the device, the renderer and the frame
/// clock. Those belong to whatever is driving — a window, or a test with a
/// software rasteriser — and handing one in is what lets a test draw the real
/// frame with no GPU anywhere.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// The world the modeller draws, and everything that can be asked about it.
final class ModelerStage {
  ModelerStage._(this.scene, this.camera, this.orbit, this.subject);

  /// What is in front of the camera: a model that was opened, or the cube a
  /// project starts as.
  ///
  /// Held so a test can say the picture followed the document rather than
  /// finding a node by walking the scene, which is the shape of assertion that
  /// passes after somebody stops adding the node at all.
  final SceneNode subject;

  final Scene scene;
  final CameraNode camera;
  final OrbitController orbit;

  /// The colour behind everything, and a decision rather than a default.
  ///
  /// Flat, not a sky. A modeller is looked at for hours and every judgement
  /// made in it — is that face dark because it is unlit or because its normal
  /// is inverted — is a judgement against the background. A gradient makes the
  /// same surface read as two different values depending on where in the
  /// viewport it happens to be. `#0E1112` is the design's own, and it is dark
  /// enough that an unlit face is still visibly a face.
  static Vector4 get background => Vector4(0.055, 0.067, 0.071, 1.0);

  /// A stage with one object in it.
  ///
  /// [asset] is a model that has been opened and uploaded; with none, the
  /// subject is the cube `flutter3d_mesh` builds — which is also what a new
  /// project starts as, so the empty case and the first primitive are one path
  /// rather than two.
  /// [stressTriangles] replaces the subject with a mesh of about that many
  /// triangles, split across [stressObjects] draws — the stand `p0-01` asks
  /// for. Zero, which is the default, builds the cube.
  factory ModelerStage.build({
    required GraphicsDevice device,
    ModelAsset? asset,
    int stressTriangles = 0,
    int stressObjects = 1,
  }) {
    final scene = Scene();

    final SceneNode subject;
    if (stressTriangles > 0) {
      subject = _stress(
        device,
        scene,
        triangles: stressTriangles,
        objects: stressObjects < 1 ? 1 : stressObjects,
      );
    } else if (asset != null) {
      subject = asset.instantiate(scene).root;
    } else {
      final mesh = EditMesh.cuboid().toMeshData();
      subject = MeshNode(
        DeviceMesh.upload(device, mesh),
        Material(
          name: 'clay',
          lighting: LightingModel.pbr,
          // The colour of unpainted clay, which is what an object with no
          // material yet should look like: a shape being judged by its form.
          baseColor: Vector4(0.72, 0.70, 0.67, 1.0),
          roughness: 0.65,
        ),
        name: 'cube',
      );
      scene.add(subject);
    }

    // **Two lights and no shadow.** A single light leaves half of every object
    // black, and an object half black is an object whose silhouette cannot be
    // read — which is the one thing a modeller is for. The key is above and to
    // the left of the camera's home, the fill is opposite and a third as
    // bright, and neither casts: a shadow across the subject would be one more
    // thing to mistake for a hole in the mesh.
    scene.add(
      LightNode(type: LightType.directional, name: 'key')
        ..intensity = 3.2
        ..setLocalForward(Vector3(-0.5, -1.0, -0.6)),
    );
    scene.add(
      LightNode(type: LightType.directional, name: 'fill')
        ..intensity = 1.1
        ..setLocalForward(Vector3(0.7, -0.3, 0.8)),
    );

    final camera = CameraNode(name: 'viewport');
    scene.add(camera);
    final orbit = OrbitController(camera, distance: 3.2, yaw: 0.6, pitch: 0.45);

    return ModelerStage._(scene, camera, orbit, subject);
  }

  /// A mesh of about [triangles] triangles, spread over [objects] nodes.
  ///
  /// **The stand, and what it is measuring is deliberately not a model.** What
  /// `p0-01` needs is a number of triangles on screen at a stated draw count,
  /// the same on a laptop, in a browser and on a handset — so it is a lattice
  /// of quads, generated rather than shipped, and the two knobs are the two
  /// things a viewport actually meets: one enormous mesh (a scanned asset), and
  /// many ordinary ones (a scene full of props). One `MeshData` is built and
  /// uploaded once, then instanced by node, because uploading `objects` copies
  /// of the same buffer would measure the driver's allocator instead.
  ///
  /// A sphere would have been prettier and would hide the thing worth seeing:
  /// a flat lattice fills the frame edge to edge, so every triangle is rastered
  /// rather than back-face culled, and the number on the screen is the number
  /// that was drawn.
  static SceneNode _stress(
    GraphicsDevice device,
    Scene scene, {
    required int triangles,
    required int objects,
  }) {
    // Two triangles per quad, `objects` copies: a side of n gives 2n² per copy.
    final perObject = (triangles / objects / 2).clamp(1, 1 << 30);
    final side = math.max(1, math.sqrt(perObject).round());

    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: (side + 1) * (side + 1),
      reserveIndices: side * side * 6,
    );
    for (var y = 0; y <= side; y++) {
      for (var x = 0; x <= side; x++) {
        // A gentle dome rather than a plane, so normals differ across the
        // lattice and the shading cost is a real one.
        final u = x / side - 0.5;
        final v = y / side - 0.5;
        final height = 0.15 * (1 - 4 * (u * u + v * v)).clamp(0.0, 1.0);
        builder.addVertex(
          position: Vector3(u, height, v),
          normal: Vector3(0, 1, 0),
          texcoord: Vector2(x / side, y / side),
        );
      }
    }
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final a = y * (side + 1) + x;
        final b = a + 1;
        final c = a + side + 1;
        final d = c + 1;
        builder
          ..addTriangle(a, c, b)
          ..addTriangle(b, c, d);
      }
    }

    final mesh = DeviceMesh.upload(device, builder.build());
    final material = Material(
      name: 'stress',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.62, 0.66, 0.72, 1.0),
      roughness: 0.5,
    );

    final root = SceneNode(name: 'stress');
    scene.add(root);
    // Laid out in a square, spaced by a little more than their own width so
    // nothing overlaps and every one of them is in front of the camera.
    final columns = math.max(1, math.sqrt(objects).ceil());
    for (var i = 0; i < objects; i++) {
      final column = i % columns;
      final row = i ~/ columns;
      root.add(
        MeshNode(mesh, material, name: 'stress-$i')..setPosition(
          (column - (columns - 1) / 2) * 1.1,
          0,
          (row - (columns - 1) / 2) * 1.1,
        ),
      );
    }
    return root;
  }

  /// Frames [subject] the way the F key will: close enough to fill the view,
  /// far enough that nothing is clipped.
  ///
  /// The bounds are gathered over the subtree rather than read off one node,
  /// because a model that was opened is a hierarchy — a node with no mesh on
  /// it and six children that have one — and framing the root's own box would
  /// frame a point.
  void frameSubject() {
    final bounds = subjectBounds();
    if (bounds == null) return;
    orbit.frameBounds(bounds);
  }

  /// The box every mesh under [subject] fits in, or null when none has one.
  Aabb3? subjectBounds() {
    Aabb3? total;
    subject.traverse((SceneNode node) {
      if (node is! MeshNode) return;
      final box = node.worldBounds;
      if (total == null) {
        total = Aabb3.copy(box);
      } else {
        total!.hull(box);
      }
    });
    return total;
  }

  /// The views a frame is drawn through.
  ///
  /// A list because the viewport is one of several — a second one arrives with
  /// the material preview and again with the LOD comparison — and because the
  /// renderer takes a list either way. One today.
  List<RenderView> views() => <RenderView>[
    RenderView(camera: camera, clearColor: background),
  ];
}
