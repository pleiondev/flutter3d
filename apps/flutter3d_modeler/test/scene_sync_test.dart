/// The seam between the document and the picture.
///
///     flutter test test/scene_sync_test.dart
///
/// **What this is for is the upload count.** Everything else here could be
/// checked by looking at the scene graph; the number that matters is how many
/// buffers were rebuilt, because that is the difference between a drag at sixty
/// frames a second and a drag that stutters on a model of any size.
// Draws real pixels: a scene through the software rasteriser, a reference
// picture, or both. Tagged so a run that only wants the logic skips the whole
// slow class at once:
//
//     very_good test -x golden
//
// Not optional in CI, which runs the suite without the flag.
@Tags(<String>['golden'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/scene_sync.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A device that refuses the first [refuseFirst] geometry uploads and then
/// behaves — `ux-02`'s own case, where a real backend answered
/// `DeviceBuffer creation failed` for one imported object.
///
/// **Counted rather than keyed on the object**, because a device is never
/// told which object it is uploading for: [SceneSync.apply] walks
/// `project.objects` in order, and a refusal comes out of the *first* of an
/// object's two uploads — its vertices, before its indices are ever asked
/// for — so refusing one call refuses exactly one object. Everything a device
/// does that is not an upload is left to `noSuchMethod`: `apply` touches no
/// other member, and a fake that pretends to is a fake that hides what it is
/// standing in for.
final class RefusingDevice implements GraphicsDevice {
  RefusingDevice(this.inner, {this.refuseFirst = 1});

  /// A `GraphicsDevice` rather than a `CpuDevice`: what this stands in front
  /// of is the upload, and it forwards everything else untouched, so the
  /// backend underneath is the caller's business. Narrowing it to the
  /// software rasteriser meant a test could not wrap a fake one.
  final GraphicsDevice inner;
  final int refuseFirst;
  int uploads = 0;

  /// Refuses everything from now on, whatever [refuseFirst] said — for a
  /// caller that needs a stage built before anything starts failing.
  bool refuseEverything = false;

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    uploads++;
    if (refuseEverything || uploads <= refuseFirst) {
      throw Exception('DeviceBuffer creation failed');
    }
    return inner.uploadGeometry(bytes, usage);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('a socket still gets a node, and it uploads nothing', () {
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'weapon mount',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
    );
    final sync = staged(project).stage.sync!;

    // Mutation: skip uploading a mesh for an object with nothing to draw —
    // the tempting cleanup — and the socket has no node to move, pick or
    // parent something under.
    expect(sync.nodeOf(1), isNotNull);
    expect(sync.nodeOf(1)!.mesh.source?.vertexCount, 0);
  });

  group('tut-06 — modifiers, live', () {
    // Neither modifier's own `mergeDistance` is set below, so
    // `MirrorModifier`/`ArrayModifier` weld nothing — every copy's vertices
    // stay distinct, which is what makes a plain vertex-count multiple the
    // right thing to assert rather than something the merge pass could
    // shrink back down.
    test('a mirror modifier is drawn without Apply', () {
      final bare = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final baseCount = staged(
        bare,
      ).stage.sync!.nodeOf(1)!.mesh.source!.vertexCount;

      final mirrored = bare.withObject(
        bare.objects.single.copyWith(
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );

      // Mutation: read `object.geometry` straight through regardless of
      // `object.modifiers`, the way this build did before `tut-06` — a
      // mirror added to the stack would then draw exactly the base mesh,
      // with no way to tell "not previewed" from "previewed and a no-op".
      expect(
        staged(mirrored).stage.sync!.nodeOf(1)!.mesh.source!.vertexCount,
        baseCount * 2,
      );
    });

    test('an array modifier is drawn without Apply', () {
      final bare = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final baseCount = staged(
        bare,
      ).stage.sync!.nodeOf(1)!.mesh.source!.vertexCount;

      final arrayed = bare.withObject(
        bare.objects.single.copyWith(
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: ArrayModifier(count: 3, offset: Vector3(2, 0, 0)),
            ),
          ],
        ),
      );

      expect(
        staged(arrayed).stage.sync!.nodeOf(1)!.mesh.source!.vertexCount,
        baseCount * 3,
      );
    });

    test('toggling a modifier reuploads even though the geometry never '
        'changes', () {
      var project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: MirrorModifier(normal: Vector3(1, 0, 0)),
              enabled: false,
            ),
          ],
        ),
      );
      final sync = staged(project).stage.sync!;
      final baseCount = sync.nodeOf(1)!.mesh.source!.vertexCount;

      // `ToggleModifier`'s own shape: a new `modifiers` list, the enabled
      // flag flipped, the same `EditedGeometry` instance as before — so
      // `identical(had.geometry, object.geometry)` alone would say nothing
      // changed.
      project = project.withObject(
        project.objects.single.copyWith(
          modifiers: <ModifierSlot>[
            project.objects.single.modifiers.single.copyWith(enabled: true),
          ],
        ),
      );
      final uploaded = sync.apply(project);

      expect(uploaded, 1);
      expect(sync.nodeOf(1)!.mesh.source!.vertexCount, baseCount * 2);
    });

    test('ApplyModifier still bakes the stack into the base mesh and empties '
        'it', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );
      final history = ModelHistory(project);
      final live = staged(history.project).stage.sync!;
      final liveCount = live.nodeOf(1)!.mesh.source!.vertexCount;

      expect(history.run(const ApplyModifier(id: 1, index: 0)), isNull);
      expect(history.project[1]!.modifiers, isEmpty);

      // The baked project draws the same picture the live preview
      // already did — Apply is a bake, not a second, different effect —
      // and it does so with no modifier stack left to evaluate.
      final applied = staged(history.project).stage.sync!;
      expect(applied.nodeOf(1)!.mesh.source!.vertexCount, liveCount);
    });
  });

  group('view-27d — skinning', () {
    test('binding an object to a skeleton uploads it skinned and hangs an '
        'engine skeleton off it', () {
      final project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'root',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity(),
          ),
          ModelObject(
            id: 2,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        ],
        nextId: 3,
      );
      final sync = staged(project).stage.sync!;

      // Unskinned so far: the ordinary layout, no engine skeleton.
      expect(sync.nodeOf(2)!.mesh.source!.layout, VertexLayout.standard);
      expect(sync.nodeOf(2)!.skeleton, isNull);

      final withSkeleton = project.copyWith(
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[1],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
      );
      // `BindSkin`'s own shape: only `skeletonIndex` moves, the same
      // `EditedGeometry` instance as before.
      final uploaded = sync.apply(
        withSkeleton.withObject(withSkeleton[2]!.copyWith(skeletonIndex: 0)),
      );

      // Mutation: gate the reupload on `identical(had.geometry,
      // object.geometry)` alone, the way "a changed mesh uploads once"
      // above already checks for a mesh command — a bind changes nothing
      // about the `Geometry` instance, so that check alone would leave
      // the mesh drawing as `VertexLayout.standard` forever.
      expect(uploaded, 1);
      expect(sync.nodeOf(2)!.mesh.source!.layout, VertexLayout.skinned);
      final skeleton = sync.nodeOf(2)!.skeleton;
      expect(skeleton, isNotNull);
      expect(skeleton!.joints, <SceneNode>[sync.nodeOf(1)!]);
    });

    test('adding a joint to a skeleton re-syncs it even though the skinned '
        'object itself never changes version', () {
      var project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'root',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity(),
          ),
          ModelObject(
            id: 2,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[1],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
        nextId: 3,
      );
      final sync = staged(project).stage.sync!;
      expect(sync.nodeOf(2)!.skeleton!.jointCount, 1);
      final versionBefore = project[2]!.version;

      // `AddJoint`'s own shape: a new object, and `project.skeletons[0]`
      // rewritten to name it — the skinned object itself is untouched.
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'tip',
          geometry: const SocketGeometry(),
          transform: Matrix4.translation(Vector3(0, 0.5, 0)),
          parent: 1,
        ),
      );
      project = project.copyWith(
        skeletons: <ProjectSkeleton>[
          project.skeletons.single.copyWith(
            joints: <int>[1, project.nextId - 1],
            inverseBindMatrices: <Matrix4>[
              Matrix4.identity(),
              Matrix4.identity(),
            ],
          ),
        ],
      );

      sync.apply(project);

      // Mutation: key the skeleton refresh off `ModelObject.version` the
      // way a geometry reupload already is — `AddJoint` never bumps the
      // skinned object's own version, so a check gated on that would
      // leave the engine `Skeleton` at one joint forever.
      expect(project[2]!.version, versionBefore);
      expect(sync.nodeOf(2)!.skeleton!.jointCount, 2);
    });

    test('a skeleton with more joints than the engine can skin is reported, '
        'never thrown', () {
      final jointIds = List<int>.generate(65, (int i) => i + 1);
      final project = ModelProject(
        objects: <ModelObject>[
          for (final int id in jointIds)
            ModelObject(
              id: id,
              name: 'joint$id',
              geometry: const SocketGeometry(),
              transform: Matrix4.identity(),
            ),
          ModelObject(
            id: 66,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: jointIds,
            inverseBindMatrices: <Matrix4>[
              for (final _ in jointIds) Matrix4.identity(),
            ],
          ),
        ],
        nextId: 67,
      );

      // Mutation: build the engine `Skeleton` regardless of joint count —
      // its own constructor throws past `Skeleton.maxJoints`, which would
      // bring down every `apply` call on a project this large rather than
      // leaving the mesh unskinned and a message on the status line.
      final sync = staged(project).stage.sync!;

      expect(sync.nodeOf(66)!.skeleton, isNull);
      expect(sync.skeletonOverflow, isNotNull);
      expect(sync.skeletonOverflow, contains('65'));
    });
  });

  group('ux-02: one object the device refuses', () {
    SceneSync syncOver(GraphicsDevice device) {
      final scene = Scene();
      final root = SceneNode(name: 'objects');
      scene.add(root);
      return SceneSync(device: device, scene: scene, root: root);
    }

    test('the rest of the project still draws, and the refusal is named', () {
      final project = cubes(3);
      final device = RefusingDevice(cpuTestDevice(width: 8, height: 8).device);
      final sync = syncOver(device);

      // Mutation: upload without catching. This call throws, and with it
      // goes every caller — the cubit's own re-sync, the MCP feed hook, and
      // the frame after them.
      sync.apply(project);

      expect(sync.nodeOf(1), isNull);
      expect(sync.nodeOf(2), isNotNull);
      expect(sync.nodeOf(3), isNotNull);
      expect(sync.unshowable.keys, <int>[1]);
      expect(sync.unshowable[1], contains('cube 1'));
      expect(sync.unshowable[1], contains('could not be shown'));
    });

    test('and a later pass that works clears the mark', () {
      final project = cubes(2);
      final device = RefusingDevice(cpuTestDevice(width: 8, height: 8).device);
      final sync = syncOver(device);
      sync.apply(project);
      expect(sync.unshowable, isNotEmpty);

      // Nothing refuses any more: the object that was skipped has no node
      // yet, so this pass is its first upload rather than a no-op.
      sync.apply(project);

      // Mutation: accumulate rather than rebuild. An object that uploaded
      // fine on the second try stays marked "could not be shown" for the
      // rest of the session, in the outliner and on the status line.
      expect(sync.unshowable, isEmpty);
      expect(sync.nodeOf(1), isNotNull);
    });

    test('a sentence names the first and counts the rest', () {
      expect(unshowableSaid(null), isNull);
      expect(unshowableSaid(<int, String>{}), isNull);
      expect(unshowableSaid(<int, String>{1: 'a'}), 'a');
      expect(unshowableSaid(<int, String>{1: 'a', 2: 'b'}), 'a (and 1 more)');
    });
  });
}
