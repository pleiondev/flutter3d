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

import 'package:flutter3d_core/formats.dart' hide EnumHint;
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'lod_spec.dart';
import 'material.dart';
import 'modifier_slot.dart';
import 'param_hint.dart';
import 'project_animation.dart';
import 'project_morphs.dart';
import 'scene_lighting.dart';
import 'selection.dart';
import 'shape_driver.dart';
import 'simulation_cache.dart';
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
    this.texelsPerMeter,
    this.fps = 30.0,
    this.frameSnap = false,
    this.sculptTriangleLimitWeb = 300000,
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

  /// The texel density every textured object is measured against — how many
  /// pixels of its texture should cover one metre of its own surface — or
  /// null for no check at all, the same "nothing measured yet" null
  /// [maxTextureBytes] already uses. **A single number for the whole
  /// project, not a memo pinned to one asset**: what breaks the illusion of
  /// one scene is not that a box's texture is blurry in isolation, but that
  /// it is visibly coarser or crisper than the box next to it, and the
  /// cheapest way to catch that is one shared target every object is held
  /// to. Read by `ExportReadiness.check`, which is silent about an object
  /// with no UV of its own — there is no area to measure a density over.
  final double? texelsPerMeter;

  /// The time base a keyframe is authored against — `syn-03`'s own gap:
  /// `KeyShape` (`anim-19`) and every other frame-facing command take a
  /// time in seconds directly rather than a frame number, because nothing
  /// on the project converted one to the other. [KeyTable.frameOfTime] and
  /// [KeyTable.timeOfFrame] are that conversion; this is where the number
  /// they need comes from. Defaults to 30, the same rate `KeyShape`'s own
  /// test already assumed before this field existed.
  final double fps;

  /// Whether an edit that moves a key in time lands on a frame boundary
  /// rather than wherever the pointer happened to be — off by default, the
  /// same "a new field does not change old behaviour" rule every other
  /// field on this class already follows. Read by whichever command or
  /// tool actually drags a key; this class only carries the setting.
  final bool frameSnap;

  /// How many triangles a sculpt may carry in a browser — `pro-sc-09`.
  ///
  /// **A measured number, not the desktop one scaled by a guess.** The web
  /// build runs the same Dart through wasm with one thread and no way to
  /// ask for a second, so the ceiling that matters there is not
  /// [maxTriangles] — which is about what a game engine will draw — but
  /// what a stroke can move and re-upload inside a frame. Three hundred
  /// thousand is what `pro-sc-01` measured as the largest mesh whose
  /// stroke stays under sixteen milliseconds on wasm; a project that wants
  /// a different answer says so here rather than in code.
  ///
  /// Read by the sculpt mode before it opens a mesh, not by the document:
  /// nothing about a file changes because it is being edited in a browser,
  /// and a project written on a desktop and opened on the web has to say
  /// the same thing to both.
  final int sculptTriangleLimitWeb;

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
    // 4, not the 8 this used to say: a vertex's own storage is four slots —
    // `VertexAttributes`, `mesh-60`'s own subject — and a hint that offered
    // a fifth was offering a control for a value nothing downstream could
    // actually hold.
    'maxInfluences': const IntHint(min: 1, max: 4),
    'maxTextureSize': const IntHint(min: 64, max: 8192, step: 64),
    'maxTextureBytes': const IntHint(min: 0),
    'requireTriangles': const BoolHint(),
    'requireManifold': const BoolHint(),
    'texelsPerMeter': const DoubleHint(min: 0, unit: 'texels/m'),
    'fps': const DoubleHint(min: 1, unit: 'fps'),
    'frameSnap': const BoolHint(),
    'sculptTriangleLimitWeb': const IntHint(
      min: 10000,
      max: 2000000,
      step: 10000,
    ),
  };

  /// [this], with named fields replaced.
  ProjectProfile copyWith({
    String? name,
    ProfileTarget? target,
    int? maxTriangles,
    int? maxJoints,
    int? maxInfluences,
    int? maxTextureSize,
    int? maxTextureBytes,
    bool clearMaxTextureBytes = false,
    bool? requireTriangles,
    bool? requireManifold,
    TextureBudget? textures,
    double? texelsPerMeter,
    bool clearTexelsPerMeter = false,
    double? fps,
    bool? frameSnap,
    int? sculptTriangleLimitWeb,
  }) => ProjectProfile(
    name: name ?? this.name,
    target: target ?? this.target,
    maxTriangles: maxTriangles ?? this.maxTriangles,
    maxJoints: maxJoints ?? this.maxJoints,
    maxInfluences: maxInfluences ?? this.maxInfluences,
    maxTextureSize: maxTextureSize ?? this.maxTextureSize,
    maxTextureBytes: clearMaxTextureBytes
        ? null
        : (maxTextureBytes ?? this.maxTextureBytes),
    requireTriangles: requireTriangles ?? this.requireTriangles,
    requireManifold: requireManifold ?? this.requireManifold,
    textures: textures ?? this.textures,
    texelsPerMeter: clearTexelsPerMeter
        ? null
        : (texelsPerMeter ?? this.texelsPerMeter),
    fps: fps ?? this.fps,
    frameSnap: frameSnap ?? this.frameSnap,
    sculptTriangleLimitWeb:
        sculptTriangleLimitWeb ?? this.sculptTriangleLimitWeb,
  );

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
      other.textures == textures &&
      other.texelsPerMeter == texelsPerMeter &&
      other.fps == fps &&
      other.frameSnap == frameSnap &&
      other.sculptTriangleLimitWeb == sculptTriangleLimitWeb;

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
    texelsPerMeter,
    fps,
    frameSnap,
    sculptTriangleLimitWeb,
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

  /// How many vertices this draws as, for the status line's own "N vertices" —
  /// [triangleCount]'s own twin, cached and computed the same way case by
  /// case.
  int get vertexCount;
}

/// A shape that still knows its own parameters.
final class ParametricGeometry extends Geometry {
  ParametricGeometry(this.shape);

  final ParametricShape shape;

  int? _triangles;
  int? _vertices;

  @override
  int get triangleCount => _triangles ??= shape.drawn.build().triangleCount;

  @override
  int get vertexCount => _vertices ??= shape.drawn.build().vertexCount;
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

  @override
  int get vertexCount => mesh.vertexCount;
}

/// Buffers as they arrived, with no topology behind them.
final class ImportedGeometry extends Geometry {
  const ImportedGeometry(this.data);

  final MeshData data;

  @override
  int get triangleCount => data.triangleCount;

  @override
  int get vertexCount => data.vertexCount;
}

/// No geometry at all — a named point for something else to hang off of, the
/// way an empty in Blender or a `Marker3D` in Godot works.
///
/// **The same shape an imported "group" already is.** `project_document.dart`
/// has always kept an object with nothing in it as a node with no surface —
/// "an arm with a forearm and a hand under it" — so a socket is that idea
/// given its own type rather than a second one: `AddSocket` builds one on
/// purpose, and a file's own empty group now reads back as one too, since
/// there is nothing left to tell the two apart once the mesh is gone.
final class SocketGeometry extends Geometry {
  const SocketGeometry();

  @override
  int get triangleCount => 0;

  @override
  int get vertexCount => 0;
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
    this.skeletonIndex,
    this.shapeSet = const ShapeSet(),
    this.shapeDrivers = const <ShapeDriver>[],
    this.lods = const <LodSpec>[],
    this.simulationCache,
    this.visible = true,
    this.locked = false,
    this.source,
    this.credit,
  });

  /// The file this object's geometry was imported from, and what that file
  /// looked like at the time — `ux-48`. Null for an object built here, and
  /// for one imported as a copy rather than as a link.
  ///
  /// **A link, not an ownership claim.** Everything else about the object —
  /// where it stands, what it is painted with, what modifiers are stacked on
  /// it, which shape keys it carries — belongs to this project and survives a
  /// re-import; only the geometry comes from the file. That is the whole
  /// distinction between this and opening the file again, and it is why a
  /// re-import is worth having at all: the work done *around* an imported
  /// mesh is the work nobody wants to do twice.
  ///
  /// [SourceLink.sha] is what the file said when it was last read, so a
  /// caller can tell "the file has changed" from "the file is as it was"
  /// without diffing meshes.
  final SourceLink? source;

  /// Who this object is owed a credit to, when it came from somewhere
  /// that asks for one — `gal-05`.
  ///
  /// **On the object rather than on the project.** A credit is owed for
  /// what is in the file, and an object deleted before the export is not
  /// in it: a project-level list would go on crediting somebody whose
  /// chair nobody kept. Deleting the object takes the obligation with it,
  /// which is the honest arithmetic.
  ///
  /// Null for everything built here and for anything under a licence that
  /// asks for nothing — most of a document, most of the time.
  final ModelCredit? credit;

  /// Whether this object is drawn — `ux-14`.
  ///
  /// **A fact about the document, not about the session.** Hiding the walls
  /// to get at what is inside them is something a person does once and comes
  /// back to tomorrow, and an exporter has to know: a hidden object is one
  /// the person has said they are not working on, and writing it into the
  /// GLB anyway is writing something they cannot see.
  ///
  /// A hidden parent hides its children — see [ModelProject.isVisible]. That
  /// is what makes it a hierarchy toggle rather than a per-object one, and
  /// the reason the flag is stored per object rather than resolved on the
  /// way in: unhiding the parent brings back exactly the children that were
  /// visible before, rather than all of them.
  final bool visible;

  /// Whether this object refuses to be picked or transformed — `ux-14`.
  ///
  /// **Locked is not hidden.** The floor a person keeps clicking by accident
  /// while aiming at what stands on it has to stay on screen — that is what
  /// it is for — and has to stop answering the pointer. Hiding it answers a
  /// different question.
  final bool locked;

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
  /// `ModifierEvaluationCache` for what actually runs it. Edited by
  /// `AddModifier` and its six siblings, folded into an export by
  /// `ProjectModelDocument` for the slots marked `inExport`, and written to
  /// the project file for an object that has one.
  final List<ModifierSlot> modifiers;

  /// Which of [ModelProject.skeletons] this object's own mesh is skinned
  /// to, when it is skinned at all — `anim-03`'s own row, the project-side
  /// [ModelSurface.skinIndex]. Null for almost every object, the ordinary
  /// case of a mesh that is not a character.
  final int? skeletonIndex;

  /// This object's own shape keys and their current preview weights —
  /// `anim-19`'s own row. Empty for almost every object, the ordinary case
  /// of a mesh with no sculpted alternate shapes.
  final ShapeSet shapeSet;

  /// Shape keys of this object's own [shapeSet] driven by how far some
  /// joint has turned, rather than by a person's own slider — `anim-34d`'s
  /// own row, [ShapeDriver.shapeIndex] indexing this same [shapeSet]'s own
  /// [ShapeSet.keys]. Empty for almost every object, the ordinary case of a
  /// shape key nobody has wired to a bone yet; [bakeShapeDrivers] is what
  /// freezes these into an ordinary weights track.
  final List<ShapeDriver> shapeDrivers;

  /// This object's own levels of detail, finest declared first —
  /// `pro-lod-03`'s own row. Empty for almost every object, the ordinary
  /// case of a mesh nobody has asked to simplify; `LodMeshCache` is what
  /// turns one of these into an actual mesh, keyed by [version] so an edit
  /// to [geometry] regenerates exactly the entries that are now stale.
  final List<LodSpec> lods;

  /// This object's own baked simulation frames — `pro-sim-03`'s own row.
  /// Null for almost every object, the ordinary case of one nobody has run
  /// `BakeClothJobRequest`/`ApplySimulationCache` against; a project saved
  /// and reopened comes back with the same null a fresh object starts with,
  /// the same honest gap [ModelProject.lighting]'s own doc comment already
  /// keeps — a bake is derived, re-runnable data, not something the file
  /// format commits to carrying yet.
  final SimulationCache? simulationCache;

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
    int? skeletonIndex,
    bool clearSkeletonIndex = false,
    ShapeSet? shapeSet,
    List<ShapeDriver>? shapeDrivers,
    List<LodSpec>? lods,
    SimulationCache? simulationCache,
    bool clearSimulationCache = false,
    bool? visible,
    bool? locked,
    SourceLink? source,
    bool clearSource = false,
    ModelCredit? credit,
    bool clearCredit = false,
  }) => ModelObject(
    id: id,
    name: name ?? this.name,
    geometry: geometry ?? this.geometry,
    transform: transform ?? this.transform,
    parent: clearParent ? null : (parent ?? this.parent),
    version: version + 1,
    materialSlots: materialSlots ?? this.materialSlots,
    modifiers: modifiers ?? this.modifiers,
    skeletonIndex: clearSkeletonIndex
        ? null
        : (skeletonIndex ?? this.skeletonIndex),
    shapeSet: shapeSet ?? this.shapeSet,
    shapeDrivers: shapeDrivers ?? this.shapeDrivers,
    lods: lods ?? this.lods,
    simulationCache: clearSimulationCache
        ? null
        : (simulationCache ?? this.simulationCache),
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    source: clearSource ? null : (source ?? this.source),
    credit: clearCredit ? null : (credit ?? this.credit),
  );

  @override
  String toString() => 'ModelObject($id, "$name", v$version)';
}

/// Where an object's geometry came from, and what that file looked like when
/// it was last read — `ux-48`'s own "link to source".
///
/// **A hash rather than a timestamp.** A file copied out of a version-control
/// checkout, or restored from a backup, has a modification time that says
/// nothing about whether its contents moved; the digest of the bytes says
/// exactly that and nothing else. Which digest it is belongs to whoever
/// writes it — this record only promises that two equal strings mean two
/// identical files.
typedef SourceLink = ({String path, String sha});

/// What an export owes somebody for one object — `gal-05`.
///
/// **Four fields, because a credit that cannot be checked is not a
/// credit.** A name alone leaves whoever reads the exported file unable to
/// find the original or the terms; the licence and its URL are what make
/// the line answerable.
typedef ModelCredit = ({
  /// What the thing is called where it came from.
  String title,

  /// Who to credit. Never empty — `gal-01` refuses an item that asks for
  /// a credit and names nobody.
  String author,

  /// The licence's own name, as the card showed it.
  String licence,

  /// Where the licence text is.
  String url,
});

/// The document.
final class ModelProject implements ModelProjectView {
  const ModelProject({
    this.profile = const ProjectProfile(),
    this.objects = const <ModelObject>[],
    this.materials = const <ProjectMaterial>[],
    this.images = const <EncodedImage>[],
    this.nextId = 1,
    this.skeletons = const <ProjectSkeleton>[],
    this.clips = const <ProjectClip>[],
    this.lighting = const SceneLighting(),
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

  /// What the objects are skinned to. [ModelObject.skeletonIndex] indexes
  /// this — `anim-03`'s own row.
  final List<ProjectSkeleton> skeletons;

  /// Animation clips, each track naming an object by id.
  final List<ProjectClip> clips;

  /// The project's own lights, environment, ambient level, shadow request
  /// and post-processing — `mat-23`'s own row. Written to the file when it is
  /// not the default, and into each step of a saved history that changed it,
  /// so a project reopened is lit the way it was closed and an undo after
  /// reopening puts back the lighting of that step. This comment said for a
  /// while that it was not written at all, which was true.
  final SceneLighting lighting;

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

  /// Whether [id] is drawn, counting its parents — `ux-14`.
  ///
  /// **A hidden parent hides its children.** That is what people mean by
  /// hiding a group, and it is the only rule under which the toggle is worth
  /// having: an outliner where hiding a rig's root left forty bones on
  /// screen would be one where the toggle has to be pressed forty-one times.
  ///
  /// A cycle cannot form — [SetParent] refuses to make one — but the walk is
  /// bounded anyway by the number of objects, because a project read from a
  /// file somebody edited by hand is a project this has to survive rather
  /// than hang in.
  bool isVisible(int id) {
    var at = this[id];
    for (var steps = 0; at != null && steps <= objects.length; steps++) {
      if (!at.visible) return false;
      final int? up = at.parent;
      if (up == null) return true;
      at = this[up];
    }
    return true;
  }

  int get triangleCount => objects.fold(
    0,
    (int sum, ModelObject o) => sum + o.geometry.triangleCount,
  );

  /// The status line's own "N vertices" — [triangleCount]'s own twin.
  int get vertexCount =>
      objects.fold(0, (int sum, ModelObject o) => sum + o.geometry.vertexCount);

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
      skeletons: skeletons,
      clips: clips,
      lighting: lighting,
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
    skeletons: skeletons,
    clips: clips,
    lighting: lighting,
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
      // not asked to lose the steel. A skeleton or a clip stays for the same
      // reason; a joint left dangling by this is `anim-29`'s own row
      // (`RemoveJoint`), not something this method reaches into a skeleton
      // to repair.
      materials: materials,
      images: images,
      skeletons: skeletons,
      clips: clips,
      lighting: lighting,
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
    List<ProjectSkeleton>? skeletons,
    List<ProjectClip>? clips,
    SceneLighting? lighting,
  }) => ModelProject(
    profile: profile ?? this.profile,
    objects: objects,
    materials: materials ?? this.materials,
    images: images ?? this.images,
    nextId: nextId,
    skeletons: skeletons ?? this.skeletons,
    clips: clips ?? this.clips,
    lighting: lighting ?? this.lighting,
  );

  @override
  String toString() =>
      'ModelProject(${objects.length} objects, ${materials.length} materials, '
      'next id $nextId)';
}
