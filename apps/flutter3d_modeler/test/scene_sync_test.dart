/// The seam between the document and the picture.
///
///     flutter test test/scene_sync_test.dart
///
/// **What this is for is the upload count.** Everything else here could be
/// checked by looking at the scene graph; the number that matters is how many
/// buffers were rebuilt, because that is the difference between a drag at sixty
/// frames a second and a drag that stutters on a model of any size.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A project of [count] cubes at the origin.
ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'cube $id',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

/// A stage over [project], and the device behind it.
({ModelerStage stage, GraphicsDevice device}) staged(ModelProject project) {
  final it = cpuTestDevice(width: 8, height: 8);
  return (
    stage: ModelerStage.fromProject(device: it.device, project: project),
    device: it.device,
  );
}

void main() {
  test('every object gets a node, and going away takes it away', () {
    final project = cubes(2);
    final made = staged(project);
    final sync = made.stage.sync!;

    expect(sync.nodeOf(1), isNotNull);
    expect(sync.nodeOf(2), isNotNull);

    sync.apply(project.removed(1));

    // Mutation: leave the node in the scene when its object goes. The renderer
    // keeps drawing an object the document no longer has, a click on it answers
    // with an id nothing looks up, and undo puts back a second copy.
    expect(sync.nodeOf(1), isNull);
    expect(made.stage.subject.children, hasLength(1));
  });

  test('a move uploads nothing', () {
    var project = cubes(1);
    final sync = staged(project).stage.sync!;

    // A hundred frames of a drag, as the history would make them: each one a
    // new object value with a new version and the same geometry.
    var uploaded = 0;
    for (var i = 0; i < 100; i++) {
      project = project.withObject(
        project.objects.single.copyWith(
          transform: Matrix4.translation(Vector3(i * 0.01, 0, 0)),
        ),
      );
      uploaded += sync.apply(project);
    }

    // Mutation: upload whenever the version moved, without asking whether the
    // geometry is the same object — which is the obvious reading of "the
    // version says it changed". A drag then rebuilds and re-uploads the mesh
    // on every frame, which on a large model is the whole frame budget spent
    // on a matrix.
    expect(uploaded, 0);
    expect(sync.nodeOf(1)!.localMatrix.getTranslation().x, closeTo(0.99, 1e-6));
  });

  test('a changed mesh uploads once', () {
    var project = cubes(1);
    final sync = staged(project).stage.sync!;
    final before = sync.nodeOf(1)!.mesh;

    final EditMesh mesh =
        (project.objects.single.geometry as EditedGeometry).mesh;
    project = project.withObject(
      // What a mesh command leaves behind: the same mesh, a new wrapper, a new
      // version — see `mesh_commands.dart`.
      project.objects.single.copyWith(geometry: EditedGeometry(mesh)),
    );

    expect(sync.apply(project), 1);
    // Mutation: ask whether the *mesh* is the same object rather than the
    // geometry that wraps it — which is the natural reading of "nothing to
    // upload, it is the same mesh", and is exactly wrong here. A mesh command
    // edits in place and hands back a new wrapper precisely because the mesh
    // cannot say it changed; comparing the mesh means an extrusion never
    // reaches the screen.
    expect(identical(sync.nodeOf(1)!.mesh, before), isFalse);
  });

  test('a node is found from the leaf that was rasterised', () {
    final sync = staged(cubes(1)).stage.sync!;
    final node = sync.nodeOf(1)!;
    final child = SceneNode(name: 'a part of it');
    node.add(child);

    // Mutation: look only at the node itself. One object is one node today and
    // is several the day an imported model keeps its material split, and a
    // pick answering with the leaf would then find nothing at all.
    expect(sync.objectOf(child), 1);
    expect(sync.objectOf(node), 1);
    expect(sync.objectOf(SceneNode()), isNull);
  });

  test('a child hangs under its parent whatever order they arrive in', () {
    var project = cubes(2);
    final sync = staged(project).stage.sync!;

    // The second object becomes the parent of the first, which is the order a
    // list walk meets them in the wrong way round.
    project = project.withObject(project.objects.first.copyWith(parent: 2));
    sync.apply(project);

    // Mutation: reparent inside the first pass instead of after it. The parent
    // has no node yet when the child is met, so the child stays at the top
    // level and moving the parent leaves it behind.
    expect(identical(sync.nodeOf(1)!.parent, sync.nodeOf(2)), isTrue);

    sync.apply(project.withObject(project[1]!.copyWith(clearParent: true)));
    expect(identical(sync.nodeOf(1)!.parent, sync.nodeOf(2)), isFalse);
  });

  test('a parametric object draws as its shape', () {
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cylinder',
        geometry: ParametricGeometry(ParametricCylinder(segments: 12)),
        transform: Matrix4.identity(),
      ),
    );
    final sync = staged(project).stage.sync!;

    // Drawn without being converted: a cylinder that still knows its parameters
    // is drawn from them, and `BakeToMesh` is what a person asks for when they
    // want to cut it.
    expect(sync.nodeOf(1), isNotNull);
    expect(sync.nodeOf(1)!.mesh.source, isNotNull);
  });
}
