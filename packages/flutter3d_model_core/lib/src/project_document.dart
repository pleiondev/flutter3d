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

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';

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
/// forearm and a hand under it — and it is what an imported node with no mesh
/// comes back as. Dropping it would reparent its children onto the world and
/// move the model; giving it a surface with no triangles would put an empty
/// draw call in the file that every consumer downstream has to guard against
/// for the sake of a thing that draws nothing.
///
/// Materials are not written, because a [ModelProject] has no material table
/// yet: [ModelObject.materialSlots] indexes one that does not exist, and a
/// surface pointing at material 2 of an empty list is a dangling index rather
/// than a colour. When the table arrives this is where an object splits into
/// one surface per slot — `EditMesh.toMeshData` already takes a `materialSlot`
/// for exactly that — since a draw call has one material.
ModelDocument toModelDocument(ModelProject project) {
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
    final mesh = _meshOf(object.geometry);

    final surfaceIndex = mesh.vertexCount == 0 ? null : surfaces.length;
    if (surfaceIndex != null) {
      surfaces.add(
        ModelSurface(
          name: object.name,
          mesh: mesh,
          transform: placement.clone(),
          // A mirrored object — a scale of −1 on one axis, which is how a
          // modeller makes the other glove — reverses on-screen winding, and
          // backface culling then discards exactly the faces meant to be seen.
          // The renderer flips for it when the surface says so.
          flipWinding: placement.determinant() < 0.0,
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

  return _ProjectDocument(
    surfaces: surfaces,
    nodes: nodes,
    roots: roots,
    warnings: warnings,
  );
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
/// The profile does not come back, because a file does not record one: a
/// project is measured against the machine it is being built for, and that
/// belongs to the workspace rather than to the model.
ModelProject fromModelDocument(ModelDocument document) {
  final nodes = document.nodes;
  final taken = List<bool>.filled(nodes.length, false);
  final pending = <(int node, int? parent)>[];

  var project = const ModelProject();

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
      project = project.added(
        (int newId) => ModelObject(
          id: newId,
          name: name,
          geometry: ImportedGeometry(
            drawn.isEmpty ? _nothing : document.surfaces[drawn.first].mesh,
          ),
          transform: node.toMatrix(),
          parent: parentId,
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

  return project;
}

/// The mesh a piece of geometry draws as.
///
/// A parametric shape is rebuilt from its parameters, which is the only place
/// its triangles exist; an edited mesh converts through the one conversion
/// `flutter3d_mesh` has, tangents and all; an imported one goes out as it came
/// in. Converting that last case to a standard layout so every surface matched
/// would either drop attributes the file brought or invent zeros for ones it
/// did not, and the container stores a layout per mesh precisely so it does not
/// have to.
MeshData _meshOf(Geometry geometry) => switch (geometry) {
  ParametricGeometry(:final shape) => shape.drawn.build(),
  EditedGeometry(:final mesh) => mesh.toMeshData(),
  ImportedGeometry(:final MeshData data) => data,
};

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

/// A project seen as a decoded model.
///
/// Private, and constructed only by [toModelDocument]: the fields have to agree
/// with each other — a node's surface indices, a root list that covers every
/// node exactly once — and there is no second caller who could be trusted to
/// build one by hand.
final class _ProjectDocument extends ModelDocument {
  _ProjectDocument({
    required this.surfaces,
    required this.nodes,
    required this.roots,
    required this.warnings,
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<ModelNode> nodes;

  @override
  final List<int> roots;

  @override
  final List<String> warnings;

  @override
  List<SurfaceMaterial> get materials => const <SurfaceMaterial>[];

  @override
  List<EncodedImage> get images => const <EncodedImage>[];

  @override
  String toString() =>
      '_ProjectDocument(${surfaces.length} surfaces, ${nodes.length} nodes, '
      '$triangleCount triangles)';
}
