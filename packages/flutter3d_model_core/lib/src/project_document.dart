/// The seam between the document a person edits and the document every writer
/// in this repository takes.
///
/// **A pair of functions rather than a `ModelProject implements ModelDocument`,
/// because the two documents disagree about what a model is and both are
/// right.** A project holds objects that still know they are cylinders, an
/// undo stack behind them and a parent named by id; a `ModelDocument` holds
/// surfaces, a node tree addressed by index, and nothing that remembers how it
/// was made. Making one class answer both interfaces would mean either an
/// export that walks the objects on every call — `F3dWriter` reads `nodes` and
/// `surfaces` several times each — or a cache invalidated by every edit, and
/// the modeller would be paying for the file format while somebody drags a
/// vertex. Converting once, at the moment somebody exports, costs a walk of the
/// project and leaves both sides alone.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'material.dart';
import 'modifier_evaluation_cache.dart';
import 'modifier_slot.dart';
import 'project.dart';
import 'project_animation.dart';
import 'project_morphs.dart';

/// [project] as the document `F3dWriter` — and the glTF and OBJ writers when
/// they arrive — already accepts.
///
/// **The transform is carried on a node, not baked into the vertices.** This is
/// the `ApplyTransform` question, and the answer decides whether a game engine
/// loading the result sees the model where the modeller showed it. Baking would
/// give a file whose vertices are already in world space and whose nodes all
/// sit at the origin: it draws correctly the first time and it has thrown away
/// everything that made the placement a placement. Nothing could animate the
/// object afterwards, because an animation track says "move node 7" and a baked
/// node has nothing left to move; nothing could instance it, because two copies
/// of a chair baked to two places are two meshes rather than one mesh at two
/// nodes; and re-opening the file would hand the modeller a chair whose local
/// origin is wherever the world origin happened to be. A node costs sixteen
/// floats per object and keeps all of it.
///
/// Each surface *also* carries the object's world matrix, which is not a second
/// answer to the same question. It is what the glTF decoder already does — see
/// `gltf_loader_scene.dart` — and each of the two readers takes the one it
/// needs: `ModelInstance.instantiate` builds scene nodes from the hierarchy and
/// leaves the surface transform alone, saying so in its own comment, while
/// `ModelDocument.computeBounds` transforms local boxes by the surface matrix
/// and never looks at a node. A document that filled in only one of them would
/// be a document that either drew twice as far from the origin as it should or
/// framed a camera on a box the size of one unmoved object.
///
/// **An object with nothing in it keeps its node and gets no surface.** An
/// empty group is how a modeller makes a handle for a subtree — an "arm" with a
/// forearm and a hand under it — or a socket to hang an accessory off of, and
/// it is what an imported node with no mesh comes back as
/// ([SocketGeometry]). Dropping it would reparent its children onto the world
/// and move the model; giving it a surface with no triangles would put an
/// empty draw call in the file that every consumer downstream has to guard
/// against for the sake of a thing that draws nothing.
///
/// **The material and image tables are written across whole, and the slots stay
/// indices.** A project's table is already the shape a document wants, so two
/// objects painted the same steel come out naming one material rather than two
/// copies of it, and a material sampling an atlas still names the image it
/// named. Flattening a material into each surface instead would be the obvious
/// way to write this and would turn one steel into forty, one atlas into forty
/// uploads, and a re-import into a project nobody can recolour in one edit.
///
/// An object still writes one surface, so it writes one material — the first of
/// its slots. `EditMesh.toMeshData` already takes a `materialSlot`, so the day
/// an object draws two materials is the day it becomes two surfaces here; until
/// something can set a second slot there is nothing to split.
///
/// **A one-shot convenience over [ProjectModelDocument].** Every call here
/// starts a fresh cache, so two calls with the same unchanged project each
/// rebuild every mesh. A caller that exports the same project repeatedly as it
/// changes — a session behind an MCP `export` tool, an editor's "save" button —
/// should keep one [ProjectModelDocument] instead and call [ProjectModelDocument.of]
/// on it each time.
ModelDocument toModelDocument(ModelProject project) =>
    ProjectModelDocument().of(project);

/// A [ModelProject] seen as a [ModelDocument], with a cache that survives
/// repeated conversions of the project as it changes.
///
/// **The cache key is `(ObjectId, version)`, not identity or content.**
/// `ModelObject.version` is bumped by every edit — see its own doc comment —
/// so a hit means exactly "this object has not changed since the mesh in the
/// cache was built for it", which is a fact a version number can answer for
/// free where hashing a mesh's own vertices every call would cost as much as
/// rebuilding it. An object whose id was reused after a delete would be a
/// false hit; ids are not reused, which is `ModelObject.id`'s own contract.
///
/// **Why identity matters downstream.** `F3dWriter` and the GPU uploader both
/// deduplicate a document's geometry by `MeshData` identity — see `_nothing`
/// below and `ModelAsset.fromDocument`'s own mesh cache — so a converter that
/// handed back an equal-but-different `MeshData` for an object nobody touched
/// would upload it again, or write it twice into a file whose whole point is
/// that a shared mesh is written once. Reusing the exact instance is what lets
/// those caches work across an edit that touched a different object entirely.
final class ProjectModelDocument extends ModelDocument {
  final Map<(int, int), MeshData> _meshCache = <(int, int), MeshData>{};

  @override
  List<ModelSurface> surfaces = const <ModelSurface>[];

  @override
  List<ModelNode> nodes = const <ModelNode>[];

  @override
  List<int> roots = const <int>[];

  @override
  List<String> warnings = const <String>[];

  @override
  List<SurfaceMaterial> materials = const <SurfaceMaterial>[];

  @override
  List<EncodedImage> images = const <EncodedImage>[];

  @override
  List<ModelSkin> skins = const <ModelSkin>[];

  @override
  List<AnimationClip> animations = const <AnimationClip>[];

  /// The stack evaluator this document folds modifiers through — `ux-13`.
  ///
  /// Kept across calls for the reason the mesh cache is: exporting twice from
  /// a project nothing has touched should fold nothing twice.
  final ModifierEvaluationCache _modifiers = ModifierEvaluationCache();

  /// The mesh for [object], built once per `(id, version)` and reused after.
  ///
  /// **The modifier stack is folded in here — `ux-13`.** Before it, an export
  /// wrote the raw geometry and a mirror or an array simply was not in the
  /// file: the viewport showed one thing and the GLB held another, and the
  /// only way to get the modified mesh out was "Apply", which drops the
  /// stack and cannot be undone once saved.
  ///
  /// **What is folded is what [ModifierSlot.inExport] says, not what the
  /// viewport shows.** That is the whole of the row's second toggle: a
  /// subdivision a person keeps off while they work goes into the file, and
  /// a cage a boolean cuts with is drawn and left out of it.
  MeshData _meshFor(ModelProject project, ModelObject object) =>
      _meshCache.putIfAbsent((object.id, object.version), () {
        final EditMesh? folded = _foldedForExport(project, object);
        if (folded != null) return folded.toMeshData();
        return _meshOf(object.geometry, object.shapeSet);
      });

  /// [object]'s own mesh with the export-bound modifiers run over it, or null
  /// where there are none to run — which is almost every object.
  ///
  /// **A second object with the export slots on it, handed to the ordinary
  /// evaluator**, rather than a second evaluator that reads a different
  /// flag: the folding, the operand resolution and the cycle guard are all
  /// one piece of code, and duplicating them so that one copy reads
  /// `enabled` and the other `inExport` is exactly how the two would come to
  /// disagree about a boolean's operand.
  EditMesh? _foldedForExport(ModelProject project, ModelObject object) {
    if (object.geometry is! EditedGeometry) return null;
    final List<ModifierSlot> forExport = <ModifierSlot>[
      for (final ModifierSlot slot in object.modifiers)
        if (slot.inExport) slot.copyWith(enabled: true),
    ];
    if (forExport.isEmpty) return null;
    return _modifiers.evaluatedMesh(
      project,
      object.copyWith(modifiers: forExport),
    );
  }

  /// Rebuilds this document from [project] and returns it.
  ///
  /// Call again after every edit a caller means to export — this does not
  /// watch [project] for changes, and calling it twice on the identical
  /// project is exactly the case the cache is for: nothing has a different
  /// version, so nothing rebuilds.
  ModelDocument of(ModelProject project) {
    final objects = project.objects;
    final indexOfId = <int, int>{
      for (var i = 0; i < objects.length; i++) objects[i].id: i,
    };

    // Children by parent, in project order, so the node tree comes out in the
    // order the outliner shows rather than in whatever order the walk reaches
    // them. An object naming a parent that is not here gets no entry and is
    // swept up below.
    final childrenByParent = <int, List<int>>{};
    for (var i = 0; i < objects.length; i++) {
      final parent = objects[i].parent;
      if (parent == null) continue;
      final parentIndex = indexOfId[parent];
      if (parentIndex == null) continue;
      (childrenByParent[parentIndex] ??= <int>[]).add(i);
    }

    // A child's world matrix is its own transform under every parent above it,
    // computed downwards from the roots and never upwards from the child: an
    // upward walk repeats the whole ancestry for every object in a deep rig, and
    // an ancestry that loops walks for ever. Downwards, each object is reached at
    // most once — `world[child] != null` is the whole of the cycle protection —
    // and what a loop costs is that nothing in it is ever reached, which the
    // sweep below turns into a root and a sentence.
    final world = List<Matrix4?>.filled(objects.length, null);
    final children = <List<int>>[
      for (var i = 0; i < objects.length; i++) <int>[],
    ];
    final roots = <int>[];
    final warnings = <String>[];

    void descendFrom(int start) {
      final pending = <int>[start];
      while (pending.isNotEmpty) {
        final parent = pending.removeLast();
        for (final int child in childrenByParent[parent] ?? const <int>[]) {
          if (world[child] != null) continue;
          world[child] = world[parent]!.multiplied(objects[child].transform);
          // The edge is recorded here, where the child was actually reached,
          // rather than from `childrenByParent`. That is what makes the node
          // tree a forest whatever the project holds: every node is either one
          // node's child or a root, so an instantiating loader can trust it.
          children[parent].add(child);
          pending.add(child);
        }
      }
    }

    for (var i = 0; i < objects.length; i++) {
      if (objects[i].parent != null) continue;
      world[i] = objects[i].transform.clone();
      roots.add(i);
      descendFrom(i);
    }

    // Whatever the roots did not reach hangs from something that is not there or
    // from itself. Two faults, two sentences, one repair: it is written at the
    // top level, where the modeller can see it and put it back, because the
    // alternative is a file that silently lost an arm.
    for (var i = 0; i < objects.length; i++) {
      if (world[i] != null) continue;
      final object = objects[i];
      warnings.add(
        indexOfId.containsKey(object.parent)
            ? 'Object "${object.name}" hangs under itself through parent '
                  '${object.parent}. The loop is cut and it is written at the '
                  'top level.'
            : 'Object "${object.name}" names parent ${object.parent}, which is '
                  'not in this project. It is written at the top level.',
      );
      world[i] = object.transform.clone();
      roots.add(i);
      descendFrom(i);
    }

    final surfaces = <ModelSurface>[];
    final nodes = <ModelNode>[];

    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();

    for (var i = 0; i < objects.length; i++) {
      final object = objects[i];
      final placement = world[i]!;
      final mesh = _meshFor(project, object);

      final surfaceIndex = mesh.vertexCount == 0 ? null : surfaces.length;
      if (surfaceIndex != null) {
        // A skinned surface's vertices are already in the skin's own space,
        // so the placement must not be baked in a second time — the joints
        // place it. This is the identical rule `gltf_loader_scene.dart`'s
        // own scene walk follows for the same reason, stated there in full.
        final skinIndex = _skeletonIndexOf(object, project.skeletons.length);
        surfaces.add(
          ModelSurface(
            name: object.name,
            mesh: mesh,
            transform: skinIndex == null
                ? placement.clone()
                : Matrix4.identity(),
            // The slot names a row of the project's table, and the table is
            // written across whole — so two objects painted the same steel come
            // out pointing at one material rather than at two copies of it. A
            // slot pointing past the end of the table is dropped rather than
            // written: an index no material answers to is a dangling reference
            // in the file, and a reader given one either guesses or refuses.
            materialIndex: _slotOf(object, project.materials.length),
            skinIndex: skinIndex,
            // A mirrored object — a scale of −1 on one axis, which is how a
            // modeller makes the other glove — reverses on-screen winding, and
            // backface culling then discards exactly the faces meant to be seen.
            // The renderer flips for it when the surface says so — except for
            // a skinned one, where the joints (not this placement) decide it.
            flipWinding: skinIndex == null && placement.determinant() < 0.0,
            morphWeights: object.shapeSet.weights,
          ),
        );
      }

      // The node carries the object's *local* transform and the surface the
      // world matrix it composes to. Decomposing the world matrix onto the node
      // as well would place every child by its whole ancestry and then place it
      // again under a parent node that had already moved: a hand two units above
      // a shoulder three units up draws five units up and slides further with
      // every joint. The hierarchy is what composes them; the node's job is to
      // say only what this object does.
      object.transform.decompose(translation, rotation, scale);
      // A node is translate, rotate and scale, and a matrix is more than that: a
      // shear, or a scale of zero, has no TRS that reproduces it. Saying so is
      // worth more than silently writing the nearest one, because the surface
      // still carries the exact matrix and the two would then disagree — and a
      // modeller told which object it was can flatten it on purpose.
      if (!_matchesComposed(object.transform, translation, rotation, scale)) {
        warnings.add(
          'Object "${object.name}" has a transform that is not a translate, a '
          'rotate and a scale. Its node carries the closest one it can express; '
          'the surface keeps the exact matrix.',
        );
      }

      nodes.add(
        ModelNode(
          name: object.name,
          translation: translation.clone(),
          rotation: rotation.clone(),
          scale: scale.clone(),
          children: children[i],
          surfaces: surfaceIndex == null ? <int>[] : <int>[surfaceIndex],
        ),
      );
    }

    this.surfaces = surfaces;
    this.nodes = nodes;
    this.roots = roots;
    this.warnings = warnings;
    materials = <SurfaceMaterial>[
      for (final ProjectMaterial each in project.materials) each.surface,
    ];
    images = project.images;
    // `indexOfId` already maps an object id to its own output node index —
    // built above for the parent walk, and exactly the map a skin's joints
    // and a track's own target need too.
    skins = <ModelSkin>[
      for (final ProjectSkeleton skeleton in project.skeletons)
        ModelSkin(
          name: skeleton.name,
          joints: <int>[
            for (final int objectId in skeleton.joints)
              indexOfId[objectId] ?? -1,
          ],
          inverseBindMatrices: skeleton.inverseBindMatrices,
          skeletonRoot: skeleton.skeletonRoot == null
              ? null
              : indexOfId[skeleton.skeletonRoot!],
        ),
    ];
    animations = <AnimationClip>[
      for (final ProjectClip clip in project.clips)
        AnimationClip(
          name: clip.name,
          extras: clip.extras,
          tracks: <AnimationTrack>[
            for (final ProjectTrack track in clip.tracks)
              if (indexOfId[track.objectId] case final int nodeIndex)
                AnimationTrack(
                  nodeIndex: nodeIndex,
                  path: track.track.path,
                  interpolation: track.track.interpolation,
                  times: track.track.times,
                  values: track.track.values,
                  componentCount: track.track.componentCount,
                ),
          ],
        ),
    ];
    return this;
  }

  @override
  String toString() =>
      'ProjectModelDocument(${surfaces.length} surfaces, ${nodes.length} '
      'nodes, $triangleCount triangles)';
}

/// The material index [object]'s one surface is written with.
///
/// The first slot, because an object is one draw call today: `EditMesh` can cut
/// a mesh by material slot — `toMeshData` takes one — and the day an object
/// writes several surfaces is the day this returns one index per surface. Until
/// then a second slot is something nothing can have set.
int? _slotOf(ModelObject object, int materialCount) {
  if (object.materialSlots.isEmpty) return null;
  final slot = object.materialSlots.first;
  return slot >= 0 && slot < materialCount ? slot : null;
}

/// [object]'s own skeleton index, dropped rather than written when it
/// points past [skeletonCount] — the same "an index nothing answers to is
/// a dangling reference" rule [_slotOf] states for a material slot.
int? _skeletonIndexOf(ModelObject object, int skeletonCount) {
  final index = object.skeletonIndex;
  if (index == null || index < 0 || index >= skeletonCount) return null;
  return index;
}

/// [document] as a project of imported objects, which is what opening a glTF
/// becomes.
///
/// **Every mesh arrives as [ImportedGeometry] and stays that way.** Building
/// half-edge topology for it is what makes a mesh editable, and it costs a pass
/// over every triangle plus the welding decisions that come with it: two
/// vertices at the same position with different normals are one vertex to a
/// modeller and two to a renderer, and which one the file meant is a question
/// only the person opening it can answer. So it is an import option rather than
/// something done behind somebody's back — an object is drawn, moved and
/// exported as it arrived until somebody asks for it to be editable.
///
/// **The node hierarchy is the transform, and the surface matrix is ignored.**
/// A surface carries the world matrix its node composes to, so reading both
/// would place every child by its ancestry twice over. Local TRS per node is
/// also what a modeller then edits: dragging the shoulder has to take the hand
/// with it.
///
/// A node drawing several surfaces — one glTF mesh with a primitive per
/// material — keeps the first as its own geometry and gets the rest as children
/// at identity, so they draw exactly where they did and each can be given its
/// own material later. The alternative, an empty object with every primitive
/// under it, would double the outliner for the ordinary one-mesh node and
/// break the round trip for every document this file writes.
///
/// **The materials and images come across as tables and the surfaces keep
/// their indices into them**, so a file whose nine bolts share one steel opens
/// as nine objects holding one slot number, and darkening the steel is one
/// edit. A surface naming no material gets no slot rather than slot zero:
/// "unpainted" and "painted with the first material in the file" are different
/// things, and only one of them is what the file said.
///
/// Which way is up in the file being imported.
enum UpAxis {
  /// glTF's own convention, and this project's: no adjustment.
  y,

  /// Common in CAD and DCC exports (and STL, which specifies no convention at
  /// all but is Z-up in practice more often than not). The root is rotated
  /// −90° about X, which is the rotation that takes a Z-up model's "up" to Y.
  z,
}

/// How to interpret a file [fromModelDocument] is bringing in, for the two
/// facts a format's geometry does not settle on its own.
///
/// **Applied to every root object's own transform, not to the vertices.**
/// A mesh imported at the wrong scale or on the wrong axis is still exactly
/// the mesh the file had — [ImportedGeometry] keeps it byte for byte — so the
/// correction belongs where every other placement in this project already
/// lives. It composes for free with the existing hierarchy walk: a root's
/// children inherit the correction by inheriting the root's transform, the
/// same way they inherit everything else about where it sits.
final class ImportOptions {
  const ImportOptions({this.scale = 1.0, this.upAxis = UpAxis.y});

  /// Multiplies every root's translation and scale. STL carries no unit at
  /// all and is conventionally millimetres; `0.001` reads such a file as
  /// metres, the unit every other placement in this project is already in.
  final double scale;

  final UpAxis upAxis;
}

/// The profile does not come back, because a file does not record one: a
/// project is measured against the machine it is being built for, and that
/// belongs to the workspace rather than to the model.
ModelProject fromModelDocument(
  ModelDocument document, {
  ImportOptions options = const ImportOptions(),
}) {
  final nodes = document.nodes;
  final taken = List<bool>.filled(nodes.length, false);
  final pending = <(int node, int? parent)>[];

  // The tables come across whole and by index, so a material shared by nine
  // surfaces stays one material and every binding inside it still names the
  // image it named. Rebuilding them per object — a material each, an image
  // each — would turn a file's one atlas into nine uploads and lose the fact
  // that the nine were ever the same thing.
  var project = ModelProject(
    materials: <ProjectMaterial>[
      for (final SurfaceMaterial each in document.materials)
        ProjectMaterial(surface: each),
    ],
    images: document.images,
  );

  // A skin's own joints and a track's own target both name a document node
  // by index; a project names an object by id. This is the map between the
  // two, filled in as each node becomes an object below — `anim-03`'s own
  // row reads it once the walk is done, in `_skeletonsOf`/`_clipsOf`.
  final objectIdOfNode = <int, int>{};

  void drain() {
    while (pending.isNotEmpty) {
      final (int index, int? parentId) = pending.removeLast();
      if (index < 0 || index >= nodes.length || taken[index]) continue;
      taken[index] = true;

      final node = nodes[index];
      final drawn = <int>[
        for (final int surface in node.surfaces)
          if (surface >= 0 && surface < document.surfaces.length) surface,
      ];
      final name = node.name ?? _nameOfFirst(document, drawn) ?? 'node $index';

      // `nextId` rather than the id `added` hands the closure, because the
      // children below need it before the closure has run.
      final id = project.nextId;
      objectIdOfNode[index] = id;
      project = project.added(
        (int newId) => ModelObject(
          id: newId,
          name: name,
          // A node with no surface is a socket — see `SocketGeometry`'s own
          // doc comment for why that is not a second idea layered on the old
          // "empty group" one.
          geometry: drawn.isEmpty
              ? const SocketGeometry()
              : ImportedGeometry(document.surfaces[drawn.first].mesh),
          transform: node.toMatrix(),
          parent: parentId,
          // An object with no geometry draws nothing and so is painted with
          // nothing; giving a group a slot would put a material index on a
          // node the exporter writes no surface for.
          materialSlots: drawn.isEmpty
              ? const <int>[]
              : _slotsOf(document.surfaces[drawn.first]),
          // The skeleton index space is not remapped — `_skeletonsOf` builds
          // `project.skeletons` in the exact order of `document.skins`, so
          // the surface's own index into that list is already the right one.
          skeletonIndex: drawn.isEmpty
              ? null
              : document.surfaces[drawn.first].skinIndex,
        ),
      );

      for (var k = 1; k < drawn.length; k++) {
        final surface = document.surfaces[drawn[k]];
        project = project.added(
          (int childId) => ModelObject(
            id: childId,
            name: surface.name ?? '$name ${k + 1}',
            geometry: ImportedGeometry(surface.mesh),
            transform: Matrix4.identity(),
            parent: id,
            materialSlots: _slotsOf(surface),
            skeletonIndex: surface.skinIndex,
          ),
        );
      }

      // Reversed, so that popping the stack visits them in document order.
      for (final int child in node.children.reversed) {
        pending.add((child, id));
      }
    }
  }

  for (final int root in document.roots.reversed) {
    pending.add((root, null));
  }
  drain();

  // A node no root reaches is geometry the engine would never draw, and a
  // person who opened the file to look at it would be told nothing. It comes
  // in at the top level instead, where it can be seen and deleted.
  for (var i = 0; i < nodes.length; i++) {
    if (taken[i]) continue;
    pending.add((i, null));
    drain();
  }

  project = project.copyWith(
    skeletons: _skeletonsOf(document.skins, objectIdOfNode),
    clips: _clipsOf(document.animations, objectIdOfNode),
  );

  if (options.scale != 1.0 || options.upAxis == UpAxis.z) {
    // Scale in the file's own axes first, then reorient — unit conversion
    // and "which way is up" are independent facts about the file, and doing
    // them in this order means a mis-set axis never scales a rotation term
    // meant for translation alone.
    var adjustment = Matrix4.identity();
    if (options.scale != 1.0) {
      adjustment = adjustment.multiplied(
        Matrix4.diagonal3Values(options.scale, options.scale, options.scale),
      );
    }
    if (options.upAxis == UpAxis.z) {
      adjustment = adjustment.multiplied(Matrix4.rotationX(-math.pi / 2));
    }
    for (final ModelObject root in project.objects.where(
      (ModelObject o) => o.parent == null,
    )) {
      project = project.withObject(
        root.copyWith(transform: adjustment.multiplied(root.transform)),
      );
    }
  }

  return project;
}

/// A tally of what an import actually produced, for a screen that wants to say
/// "312 objects, 4 materials" before anyone opens the outliner to count.
final class ImportCounts {
  const ImportCounts({
    required this.objects,
    required this.materials,
    required this.images,
    required this.triangles,
  });

  final int objects;
  final int materials;
  final int images;
  final int triangles;

  @override
  bool operator ==(Object other) =>
      other is ImportCounts &&
      other.objects == objects &&
      other.materials == materials &&
      other.images == images &&
      other.triangles == triangles;

  @override
  int get hashCode => Object.hash(objects, materials, images, triangles);

  @override
  String toString() =>
      'ImportCounts(objects: $objects, materials: $materials, '
      'images: $images, triangles: $triangles)';
}

/// What [importReportOf] found, beyond the project itself.
///
/// **`fromModelDocument` stays exactly what it was** — a plain
/// `ModelDocument -> ModelProject` function, with call sites already wired to
/// it — because widening its return type would have meant touching every one
/// of them, including `apps/flutter3d_modeler/lib/main.dart`, on a file this
/// session was asked not to edit. `importReportOf` wraps it instead: the same
/// project, plus [issues] and [counts] for a caller that wants them, so
/// nothing that already calls `fromModelDocument` has to change.
final class ImportReport {
  const ImportReport({
    required this.project,
    required this.issues,
    required this.counts,
  });

  final ModelProject project;

  /// The decoder's own [ModelDocument.warnings], passed through verbatim — an
  /// ignored extension or a skipped primitive is the decoder's finding, not
  /// this function's, and rephrasing it here would be a second chance to get
  /// the wording wrong.
  final List<String> issues;

  final ImportCounts counts;
}

/// [fromModelDocument], with the decoder's warnings and a tally of what came
/// in alongside the project it produces.
ImportReport importReportOf(
  ModelDocument document, {
  ImportOptions options = const ImportOptions(),
}) {
  final project = fromModelDocument(document, options: options);
  return ImportReport(
    project: project,
    issues: List<String>.unmodifiable(document.warnings),
    counts: ImportCounts(
      objects: project.objects.length,
      materials: project.materials.length,
      images: project.images.length,
      triangles: project.objects.fold(
        0,
        (int sum, ModelObject o) => sum + o.geometry.triangleCount,
      ),
    ),
  );
}

/// [skins] retargeted from node indices onto the object ids
/// [objectIdOfNode] assigned them — `anim-03`'s own row.
///
/// **Never drops a skeleton.** A surface's own `skinIndex` addresses this
/// list positionally, the same reason `_decodeMaterials` never drops a
/// material in the glTF loader: dropping one here would shift every skin
/// after it onto the wrong surface. A joint this walk never reached — which
/// should not happen for a well-formed file, since every node the document
/// names becomes an object — reads as object id `-1` rather than throwing;
/// nothing in this project can hold that id, so a lookup against it fails
/// loudly wherever it is actually read rather than here, off in an importer
/// that has no context to explain the failure with.
List<ProjectSkeleton> _skeletonsOf(
  List<ModelSkin> skins,
  Map<int, int> objectIdOfNode,
) => <ProjectSkeleton>[
  for (final ModelSkin skin in skins)
    ProjectSkeleton(
      name: skin.name,
      joints: <int>[
        for (final int node in skin.joints) objectIdOfNode[node] ?? -1,
      ],
      inverseBindMatrices: skin.inverseBindMatrices,
      skeletonRoot: skin.skeletonRoot == null
          ? null
          : objectIdOfNode[skin.skeletonRoot!],
    ),
];

/// [animations] retargeted the same way [_skeletonsOf] retargets a skin: a
/// track naming a node index the walk never reached (out of range, or a
/// document malformed enough that `objectIdOfNode` has no entry for it) is
/// dropped rather than kept under a fabricated id — a track is one entry in
/// a clip, not a positional slot anything else addresses, so dropping one
/// costs nothing downstream the way dropping a skeleton would.
List<ProjectClip> _clipsOf(
  List<AnimationClip> animations,
  Map<int, int> objectIdOfNode,
) => <ProjectClip>[
  for (final AnimationClip clip in animations)
    ProjectClip(
      name: clip.name,
      extras: clip.extras,
      tracks: <ProjectTrack>[
        for (final AnimationTrack track in clip.tracks)
          if (objectIdOfNode[track.nodeIndex] case final int objectId)
            ProjectTrack(objectId: objectId, track: track),
      ],
    ),
];

/// The slot list an imported surface arrives with.
///
/// Empty when the file named no material, which is not the same as naming
/// material zero: a surface with no material is drawn in the viewport's default
/// and written back out with none, and turning that into a slot would paint it
/// with whichever material happened to be first in the file.
List<int> _slotsOf(ModelSurface surface) => switch (surface.materialIndex) {
  final int index when index >= 0 => <int>[index],
  _ => const <int>[],
};

/// The mesh a piece of geometry draws as.
///
/// A parametric shape is rebuilt from its parameters, which is the only place
/// its triangles exist; an edited mesh converts through the one conversion
/// `flutter3d_mesh` has, tangents and all; an imported one goes out as it came
/// in. Converting that last case to a standard layout so every surface matched
/// would either drop attributes the file brought or invent zeros for ones it
/// did not, and the container stores a layout per mesh precisely so it does not
/// have to.
///
/// **[shapeSet]'s keys ride along as [MorphTarget]s, on the edited case only.**
/// A shape key is authored against an `EditMesh`'s own vertex ids — `mesh-61`'s
/// row, and [ShapeKey.grownTo]/[remappedBy] track exactly that mesh's edits —
/// so there is no vertex a parametric or imported geometry's shape key could
/// mean. [MeshLayoutPlan] is rebuilt here rather than reused from
/// [EditMesh.toMeshData] — which keeps its own plan private — but built with
/// the identical defaults that call already used, so [shapeKeyMorphTargets]'s
/// own `gpuVertexToVertex` lines up with the vertices [mesh] just wrote.
MeshData _meshOf(Geometry geometry, ShapeSet shapeSet) {
  final mesh = switch (geometry) {
    ParametricGeometry(:final shape) => shape.drawn.build(),
    EditedGeometry(:final mesh) => mesh.toMeshData(),
    ImportedGeometry(:final MeshData data) => data,
    SocketGeometry() => _nothing,
  };
  if (shapeSet.isEmpty) return mesh;
  if (geometry is! EditedGeometry) return mesh;
  final plan = MeshLayoutPlan()..build(geometry.mesh);
  return mesh.withMorphTargets(
    shapeKeyMorphTargets(plan, geometry.mesh, shapeSet.keys),
  );
}

/// Whether recomposing [translation], [rotation] and [scale] gives [matrix]
/// back.
///
/// Element by element against an absolute tolerance rather than a relative one:
/// these are doubles composed and decomposed once, where a well-formed TRS
/// round-trips to about 1e-15, so anything a thousandth of a unit out is a
/// matrix that is not a TRS at all. A NaN from a decomposed zero scale fails
/// every comparison, which is the answer wanted.
bool _matchesComposed(
  Matrix4 matrix,
  Vector3 translation,
  Quaternion rotation,
  Vector3 scale,
) {
  final composed = Matrix4.compose(translation, rotation, scale);
  for (var i = 0; i < 16; i++) {
    final apart = (composed.storage[i] - matrix.storage[i]).abs();
    // Negated rather than `apart > 1e-4`, so that a NaN — which loses every
    // comparison it is in — answers "these do not match" instead of "they do".
    if (!(apart <= 1e-4)) return false;
  }
  return true;
}

String? _nameOfFirst(ModelDocument document, List<int> surfaces) =>
    surfaces.isEmpty ? null : document.surfaces[surfaces.first].name;

/// What an object with nothing in it holds.
///
/// One instance for all of them: `MeshData` is read-only once built, and both
/// `F3dWriter` and the uploader deduplicate meshes by identity, so a project of
/// forty groups writes one empty mesh rather than forty.
final MeshData _nothing = MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List(0),
  indices: Uint32List(0),
);
