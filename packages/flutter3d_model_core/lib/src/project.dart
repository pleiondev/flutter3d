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

import 'package:flutter3d_formats/flutter3d_formats.dart' hide EnumHint;
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'material.dart';
import 'modifier_slot.dart';
import 'param_hint.dart';
import 'selection.dart';
import 'texture_budget.dart';

/// What kind of machine a profile is written for.
///
/// **Alongside [ProjectProfile.name], not instead of it.** The name is what a
/// person typed — "Store demo build" — and a rule that wants to know whether
/// it is looking at a phone has no business parsing that string. `target` is
/// the three words a rule can switch on; the name is the one a person reads.
enum ProfileTarget { desktop, mobile, web }

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
    this.target = ProfileTarget.desktop,
    this.maxTriangles = 500000,
    // 64 rather than a rounder number: it is `Skeleton.maxJoints` in the
    // engine, the size of the per-draw joint array the skinning shader holds,
    // and a profile promising more than the shader can hold is a profile
    // whose promise nothing downstream can keep. `profile_limits_test.dart`
    // in `apps/flutter3d_modeler` mirrors the two constants so they cannot
    // drift apart unnoticed.
    this.maxJoints = 64,
    this.maxInfluences = 4,
    this.maxTextureSize = 4096,
    // Null rather than a guessed number: nothing reads this yet, and a figure
    // presented as a budget with no measurement behind it is worse than
    // admitting none has been taken. `mat-28`'s `TextureBudget` (below) is
    // the real one, on top of an actual format and device measurement —
    // this stays null even now that `textures` exists, since the two are not
    // the same number: this one is a flat cap `doc-14` already reads, that
    // one a re-encode estimate `measure` computes.
    this.maxTextureBytes,
    this.requireTriangles = true,
    this.requireManifold = false,
    this.textures = TextureBudget.desktop,
  });

  /// What a handset can be asked for, which is the tightest of the three the
  /// plan names and the one worth having as a constant so a test and a chip in
  /// the interface agree.
  static const ProjectProfile mobile = ProjectProfile(
    name: 'mobile',
    target: ProfileTarget.mobile,
    maxTriangles: 100000,
    maxJoints: 64,
    maxTextureSize: 2048,
    textures: TextureBudget.mobile,
  );

  final String name;
  final ProfileTarget target;
  final int maxTriangles;
  final int maxJoints;
  final int maxInfluences;
  final int maxTextureSize;

  /// A budget in bytes across every texture at once, or null for none
  /// declared. See the constructor for why nothing sets one yet.
  final int? maxTextureBytes;

  /// How big a texture may be and what it should end up encoded as, for
  /// `mat-28`'s `measure`. Defaults to [TextureBudget.desktop] rather than
  /// null — a profile with no budget at all is a state nothing in this plan
  /// asks for — the same way [target] defaults to [ProfileTarget.desktop];
  /// a profile built for [ProfileTarget.web] wants [TextureBudget.web] set
  /// alongside it explicitly, the way [mobile] sets every one of its own
  /// fields together rather than deriving them from `target`.
  final TextureBudget textures;

  /// Whether the target format can hold a face with more than three corners.
  /// Read by `ExportReadiness.check` when its own `trianglesOnly` is not
  /// given explicitly.
  final bool requireTriangles;

  /// Whether a mesh pinched to a point stops the export rather than merely
  /// spoiling it. Read by `ExportReadiness.check` the same way.
  final bool requireManifold;

  /// What control a profile editor should offer for each of this class's own
  /// fields, keyed by field name.
  ///
  /// **`doc-13`'s row asks for this "from `MaterialHint`"; that reference went
  /// stale the moment Г4/Ж2 (2026-09-09) closed `MaterialHint` to the material
  /// panel and put a new sealed `ParamHint` in core for everything else** —
  /// see `syn-01`. Built from `ParamHint` instead, the same type
  /// `ModelCommand.hints` uses, rather than the type the row names. Named
  /// `profileHints` rather than `hints` to match the plan row's own
  /// backticked name, even though `ModelCommand.hints` picked the shorter
  /// one for the same concept — the mechanical check in `verify_plan.dart`
  /// reads names literally.
  ///
  /// `maxJoints`'s ceiling is hard-coded to 64 rather than read from
  /// `Skeleton.maxJoints`: this package cannot depend on the engine that
  /// declares it (`flutter3d_model_core` is core, `flutter3d` is a genre
  /// package one layer up), so 64 is repeated here the same way the
  /// constructor's own default already repeats it — both are mirrored against
  /// the real constant by `apps/flutter3d_modeler/test/profile_limits_test.dart`,
  /// not by this file.
  ///
  /// **`textures` has no entry here.** Every other field is one number or one
  /// flag a `HintRow` shows as a single control; `textures` is four fields at
  /// once (`maxSide`, `maxBytesOnDevice`, `targetFormat`, `requirePowerOfTwo`)
  /// with no `ParamHint` variant that groups them — `mat-20`'s own stack panel
  /// is the precedent for what a compound value like this gets instead of a
  /// generic row: a small dedicated picker over the three presets, not a
  /// `HintRow` this map would have to invent a new `ParamHint` case for.
  Map<String, ParamHint> get profileHints => {
    'target': EnumHint([...ProfileTarget.values.map((t) => t.name)]),
    'maxTriangles': const IntHint(min: 1000, max: 2000000, step: 1000),
    'maxJoints': const IntHint(min: 1, max: 64),
    'maxInfluences': const IntHint(min: 1, max: 8),
    'maxTextureSize': const IntHint(min: 64, max: 8192, step: 64),
    'maxTextureBytes': const IntHint(min: 0),
    'requireTriangles': const BoolHint(),
    'requireManifold': const BoolHint(),
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectProfile &&
      other.name == name &&
      other.target == target &&
      other.maxTriangles == maxTriangles &&
      other.maxJoints == maxJoints &&
      other.maxInfluences == maxInfluences &&
      other.maxTextureSize == maxTextureSize &&
      other.maxTextureBytes == maxTextureBytes &&
      other.requireTriangles == requireTriangles &&
      other.requireManifold == requireManifold &&
      other.textures == textures;

  @override
  int get hashCode => Object.hash(
    name,
    target,
    maxTriangles,
    maxJoints,
    maxInfluences,
    maxTextureSize,
    maxTextureBytes,
    requireTriangles,
    requireManifold,
    textures,
  );
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
    this.modifiers = const <ModifierSlot>[],
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

  /// The modifier stack, top of the list evaluated first — see
  /// `ModifierEvaluationCache` for what actually runs it. Empty for almost
  /// every object today, since nothing yet writes to this list; `doc-23`'s
  /// commands are what will.
  final List<ModifierSlot> modifiers;

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
    List<ModifierSlot>? modifiers,
  }) => ModelObject(
    id: id,
    name: name ?? this.name,
    geometry: geometry ?? this.geometry,
    transform: transform ?? this.transform,
    parent: clearParent ? null : (parent ?? this.parent),
    version: version + 1,
    materialSlots: materialSlots ?? this.materialSlots,
    modifiers: modifiers ?? this.modifiers,
  );

  @override
  String toString() => 'ModelObject($id, "$name", v$version)';
}

/// The document.
final class ModelProject implements ModelProjectView {
  const ModelProject({
    this.profile = const ProjectProfile(),
    this.objects = const <ModelObject>[],
    this.materials = const <ProjectMaterial>[],
    this.images = const <EncodedImage>[],
    this.nextId = 1,
  });

  final ProjectProfile profile;

  /// What the objects are painted with. [ModelObject.materialSlots] indexes
  /// this; a slot that indexes nothing is drawn in the viewport's own default,
  /// which is what an object nobody has painted yet looks like.
  final List<ProjectMaterial> materials;

  /// The images [materials] sample, addressed by index from their
  /// [TextureBinding]s. See `material.dart` for why they are a table of their
  /// own rather than fields inside a material.
  final List<EncodedImage> images;

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
    return ModelProject(
      profile: profile,
      objects: next,
      materials: materials,
      images: images,
      nextId: nextId,
    );
  }

  /// This project with a new object built from [nextId].
  ///
  /// The id is handed to [build] rather than taken from the object, because an
  /// object that chose its own id is an object that can choose one already in
  /// use — and the caller has no way to know what is free.
  ModelProject added(ModelObject Function(int id) build) => ModelProject(
    profile: profile,
    objects: <ModelObject>[...objects, build(nextId)],
    materials: materials,
    images: images,
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
      // The tables stay whole. A material is shared, so deleting the last
      // object that used one is not a reason to throw the material away —
      // undo would have to put it back, and a person who deletes a bolt has
      // not asked to lose the steel.
      materials: materials,
      images: images,
      // Unchanged on purpose: an id belonging to something deleted must not
      // come back, or a step of history that names it starts naming something
      // else the moment it is undone and redone.
      nextId: nextId,
    );
  }

  ModelProject copyWith({
    ProjectProfile? profile,
    List<ProjectMaterial>? materials,
    List<EncodedImage>? images,
  }) => ModelProject(
    profile: profile ?? this.profile,
    objects: objects,
    materials: materials ?? this.materials,
    images: images ?? this.images,
    nextId: nextId,
  );

  @override
  String toString() =>
      'ModelProject(${objects.length} objects, ${materials.length} materials, '
      'next id $nextId)';
}
