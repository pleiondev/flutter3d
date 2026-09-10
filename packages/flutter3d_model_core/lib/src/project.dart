/// What a model project holds: objects, what each of them is made of, and the
/// limits it is being built against.
///
/// **A value, replaced rather than mutated, sharing everything it did not
/// touch.** Undo is the reason. A history that has to remember how to reverse
/// each edit is a history where every new command is a second chance to get the
/// reversal wrong; a history that keeps the document as it was is a history
/// that cannot be wrong about anything, and costs whatever the copy costs. So
/// the copy is made cheap instead: [ModelProject.withObject] hands back a
/// project whose other objects are the very same objects, `identical` to the
/// ones before it, and the list is the only thing rebuilt. A project of two
/// hundred objects with one moved is two hundred pointers and one new object.
///
/// **Ids are numbers and they are never reused.** A selection, a command's
/// arguments and a step of history all name objects, and all three outlive the
/// object being deleted and put back by an undo. A name would be renamed and an
/// index would shift the moment anything above it went; a counter that only
/// ever goes up is the one thing that survives both.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'selection.dart';

/// The limits a project is being built against.
///
/// **A profile rather than a set of warnings, because the same model is fine
/// for one target and impossible for another.** Sixty thousand triangles is a
/// hero prop on a desktop and the whole scene on a handset, and a modeller that
/// warns by one fixed number is a modeller that either cries wolf or says
/// nothing. `ExportReadiness` measures the project against this.
final class ProjectProfile {
  const ProjectProfile({
    this.name = 'desktop',
    this.maxTriangles = 500000,
    this.maxJoints = 128,
    this.maxInfluences = 4,
    this.maxTextureSize = 4096,
  });

  /// What a handset can be asked for, which is the tightest of the three the
  /// plan names and the one worth having as a constant so a test and a chip in
  /// the interface agree.
  static const ProjectProfile mobile = ProjectProfile(
    name: 'mobile',
    maxTriangles: 100000,
    maxJoints: 64,
    maxTextureSize: 2048,
  );

  final String name;
  final int maxTriangles;
  final int maxJoints;
  final int maxInfluences;
  final int maxTextureSize;

  @override
  bool operator ==(Object other) =>
      other is ProjectProfile &&
      other.name == name &&
      other.maxTriangles == maxTriangles &&
      other.maxJoints == maxJoints &&
      other.maxInfluences == maxInfluences &&
      other.maxTextureSize == maxTextureSize;

  @override
  int get hashCode =>
      Object.hash(name, maxTriangles, maxJoints, maxInfluences, maxTextureSize);
}

/// What an object is made of.
///
/// **Three cases and a compiler that asks about all of them.** A cylinder that
/// still knows it is a cylinder can have its segment count changed; the same
/// cylinder after somebody has pulled one of its faces cannot, and there is no
/// honest way to answer "set segments to 32" for it. A model read out of a glTF
/// is a third thing again: it has vertex buffers and no topology, so it can be
/// drawn and transformed and not edited until somebody asks for it to be, which
/// is a conversion that costs and therefore has to be asked for.
///
/// The alternative — one geometry class with three nullable fields — is a class
/// where every operation begins by working out which of the three it is holding
/// and half of them get it wrong.
sealed class Geometry {
  const Geometry();

  /// How many triangles this draws as, for the budget.
  ///
  /// Free for an imported mesh, a pass over the faces for an edited one, and a
  /// whole rebuild the first time for a parametric one — which is why that case
  /// remembers its answer. A budget is read on every change to the project and
  /// a lathe of two hundred segments is not something to rebuild for a number
  /// in the corner.
  int get triangleCount;
}

/// A shape that still knows its own parameters.
final class ParametricGeometry extends Geometry {
  ParametricGeometry(this.shape);

  final ParametricShape shape;

  int? _triangles;

  @override
  int get triangleCount => _triangles ??= shape.drawn.build().triangleCount;
}

/// A mesh with its topology, being edited.
final class EditedGeometry extends Geometry {
  const EditedGeometry(this.mesh);

  final EditMesh mesh;

  /// Faces rather than triangles would be the cheaper answer and the wrong one:
  /// a budget is spent on what the GPU draws, and a quad is two triangles.
  /// An n-gon fans into n − 2, which is what every triangulator here does.
  @override
  int get triangleCount {
    var triangles = 0;
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      var sides = 0;
      mesh.forEachHalfEdge(face, (int _) => sides++);
      triangles += sides - 2;
    }
    return triangles;
  }
}

/// Buffers as they arrived, with no topology behind them.
final class ImportedGeometry extends Geometry {
  const ImportedGeometry(this.data);

  final MeshData data;

  @override
  int get triangleCount => data.triangleCount;
}

/// One thing in the project.
///
/// **[version] is not [id] and the difference matters every frame.** The id
/// says which object this is and never changes; the version says how many times
/// it has changed, and a viewport uploads again exactly when it moves. Without
/// it a viewport either re-uploads everything every frame or compares meshes to
/// find out, and the second is more expensive than the upload.
final class ModelObject {
  const ModelObject({
    required this.id,
    required this.name,
    required this.geometry,
    required this.transform,
    this.parent,
    this.version = 1,
    this.materialSlots = const <int>[],
  });

  /// Stable for the life of the object, and not reused after a delete.
  final int id;

  final String name;
  final Geometry geometry;

  /// Local to [parent], or to the world when there is none.
  final Matrix4 transform;

  /// The object this hangs under, by id.
  final int? parent;

  /// Bumped by every change. See the class comment.
  final int version;

  /// Which material each of the geometry's slots is drawn with, by index into
  /// the project's materials.
  final List<int> materialSlots;

  /// A copy with some fields replaced and [version] moved on.
  ///
  /// **The version moves here rather than at the call sites**, so that an edit
  /// which forgets to bump it is an edit that cannot be written: there is no
  /// other way to make a changed object.
  ModelObject copyWith({
    String? name,
    Geometry? geometry,
    Matrix4? transform,
    int? parent,
    bool clearParent = false,
    List<int>? materialSlots,
  }) => ModelObject(
    id: id,
    name: name ?? this.name,
    geometry: geometry ?? this.geometry,
    transform: transform ?? this.transform,
    parent: clearParent ? null : (parent ?? this.parent),
    version: version + 1,
    materialSlots: materialSlots ?? this.materialSlots,
  );

  @override
  String toString() => 'ModelObject($id, "$name", v$version)';
}

/// The document.
final class ModelProject implements ModelProjectView {
  const ModelProject({
    this.profile = const ProjectProfile(),
    this.objects = const <ModelObject>[],
    this.nextId = 1,
  });

  final ProjectProfile profile;

  /// In the order they were added, which is the order the outliner shows and
  /// the order an export writes. A map by id would make a lookup cheaper and
  /// would leave the order to whatever the hash function does, which is not a
  /// thing a person can be shown.
  final List<ModelObject> objects;

  /// The id the next object added will take. Only ever goes up.
  final int nextId;

  @override
  bool holds(int id) => this[id] != null;

  /// The object with [id], or null.
  ModelObject? operator [](int id) {
    for (final ModelObject object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  int get triangleCount => objects.fold(
    0,
    (int sum, ModelObject o) => sum + o.geometry.triangleCount,
  );

  /// This project with [object] in place of the one with its id.
  ///
  /// Everything else comes across by reference, so a caller — and a test — can
  /// ask `identical` and get a true answer about what the edit touched. An
  /// unknown id is a fault rather than an add: adding through the same door as
  /// replacing is how an object ends up in the project twice under one id.
  ModelProject withObject(ModelObject object) {
    var found = false;
    final next = List<ModelObject>.of(objects);
    for (var i = 0; i < next.length; i++) {
      if (next[i].id != object.id) continue;
      next[i] = object;
      found = true;
      break;
    }
    if (!found) {
      throw ArgumentError(
        'no object ${object.id} in this project. Adding is `added`, which '
        'takes the id from `nextId`; replacing an object that is not there '
        'would put it in twice under one id and no lookup would say which.',
      );
    }
    return ModelProject(profile: profile, objects: next, nextId: nextId);
  }

  /// This project with a new object built from [nextId].
  ///
  /// The id is handed to [build] rather than taken from the object, because an
  /// object that chose its own id is an object that can choose one already in
  /// use — and the caller has no way to know what is free.
  ModelProject added(ModelObject Function(int id) build) => ModelProject(
    profile: profile,
    objects: <ModelObject>[...objects, build(nextId)],
    nextId: nextId + 1,
  );

  /// This project without the object [id], and without anything under it.
  ///
  /// **The children go too, and they go by walking rather than by one pass.**
  /// A child of a child is as orphaned as a child, and a single pass over the
  /// list would leave it pointing at a parent that is gone — which is a project
  /// that draws an arm floating where the body used to be.
  ModelProject removed(int id) {
    final doomed = <int>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final ModelObject each in objects) {
        if (each.parent != null &&
            doomed.contains(each.parent) &&
            doomed.add(each.id)) {
          grew = true;
        }
      }
    }
    return ModelProject(
      profile: profile,
      objects: <ModelObject>[
        for (final ModelObject each in objects)
          if (!doomed.contains(each.id)) each,
      ],
      // Unchanged on purpose: an id belonging to something deleted must not
      // come back, or a step of history that names it starts naming something
      // else the moment it is undone and redone.
      nextId: nextId,
    );
  }

  ModelProject copyWith({ProjectProfile? profile}) => ModelProject(
    profile: profile ?? this.profile,
    objects: objects,
    nextId: nextId,
  );

  @override
  String toString() =>
      'ModelProject(${objects.length} objects, next id $nextId)';
}
