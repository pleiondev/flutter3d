/// What is in a project, said the way an outliner or an agent's `list` tool
/// wants it: an id and a name, not a walk of the whole document.
///
/// **One small type rather than four, because the shape a listing wants is
/// the same shape every time.** An outliner row and an MCP `list` tool
/// response both want "what do I call this and what do I point back at it
/// with", and a `ModelObject`, a `ProjectMaterial` or a skeleton that does not
/// exist yet all answer that the same way. Handing back the full domain object
/// instead would mean an agent walking `SurfaceMaterial`'s dozen fields to
/// find the one it is allowed to ask for by name.
library;

import 'modifier_slot.dart';
import 'project.dart';
import 'project_morphs.dart';

/// One row of a listing: what to call it, and the id a later command —
/// [AssignMaterial], [SetParametric], an MCP tool's `id` argument — addresses
/// it by.
final class Listed {
  const Listed({
    required this.id,
    required this.name,
    this.kind,
    this.parent,
    this.version,
    this.transform,
    this.materials = const <int>[],
    this.about = const <String, Object?>{},
  });

  final int id;
  final String name;

  /// What kind of thing this is, in one word — `parametric`, `mesh`,
  /// `imported` for an object — or null when a listing has only one kind and
  /// saying it on every row would be noise.
  final String? kind;

  /// What this hangs under, by id — `ux-19`. Null at the top level, and for
  /// every listing that is not a hierarchy.
  ///
  /// **Without it a listing is a flat list of things that are not flat.** An
  /// agent reading the old listing saw six objects and no way to tell which
  /// three were wheels of the fourth, so `setParent` was the one command it
  /// could neither check nor undo by eye.
  final int? parent;

  /// [ModelObject.version] — bumped by every change, so an agent that read a
  /// mesh once can tell whether the thing it is about to edit is still the
  /// thing it read. Null for rows that are not objects.
  final int? version;

  /// Sixteen numbers, column-major — `Matrix4.storage` — or null for a row
  /// with no transform of its own. Whole rather than a position, because an
  /// object an agent has rotated is not described by where its origin is.
  final List<double>? transform;

  /// Which material row each of this object's own slots indexes, in slot
  /// order. Empty for an object nobody has painted, and for every row that is
  /// not an object.
  final List<int> materials;

  /// Whatever else a row of this kind carries: a skeleton's joint count, a
  /// clip's track count, a shape key's current weight, whether a modifier is
  /// switched on. A map rather than a field per kind, because there is one
  /// such fact per listing and five listings — five fields, four of them null
  /// on every row, is a worse trade than one map that is empty on most.
  final Map<String, Object?> about;

  /// This row as a client reads it — what [structuredContent] on a tool
  /// result carries, so an agent parses numbers rather than the sentence
  /// [toString] builds.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (kind != null) 'kind': kind,
    if (parent != null) 'parent': parent,
    if (version != null) 'version': version,
    if (transform != null) 'transform': transform,
    if (materials.isNotEmpty) 'materials': materials,
    ...about,
  };

  @override
  String toString() => kind == null ? '$name ($id)' : '$name ($id, $kind)';
}

/// Every object in [project], in the order the outliner shows them.
///
/// **Stable between calls on an unchanged project, and each object exactly
/// once** — the two things `doc-18` asks for — because both fall out of
/// walking `ModelProject.objects` itself rather than a map or a set keyed by
/// anything: the list is already in that order and already has no object
/// twice.
///
/// **Every row carries its parent, its transform, its materials and its
/// version** (`ux-19`). The three-field row this used to return was enough to
/// name an object and nothing else: an agent that wanted to know where the
/// thing it had just made had landed, or whether the mesh it read a minute ago
/// had moved under it, had no call that would say — and the review found it
/// guessing instead.
List<Listed> contentsOf(ModelProject project) => <Listed>[
  for (final ModelObject object in project.objects)
    Listed(
      id: object.id,
      name: object.name,
      kind: switch (object.geometry) {
        ParametricGeometry() => 'parametric',
        EditedGeometry() => 'mesh',
        ImportedGeometry() => 'imported',
        SocketGeometry() => 'socket',
      },
      parent: object.parent,
      version: object.version,
      transform: object.transform.storage.toList(),
      materials: object.materialSlots,
      about: <String, Object?>{
        if (object.geometry case EditedGeometry(:final mesh))
          ...<String, Object?>{
            'vertices': mesh.vertexCount,
            'edges': mesh.edgeCount,
            'faces': mesh.faceCount,
          },
        if (object.skeletonIndex case final int skeleton) 'skeleton': skeleton,
        if (object.shapeSet.keys.isNotEmpty)
          'shapes': object.shapeSet.keys.length,
        if (object.modifiers.isNotEmpty) 'modifiers': object.modifiers.length,
        if (!object.visible) 'hidden': true,
        if (object.locked) 'locked': true,
      },
    ),
];

/// Every material in [project]'s table, addressed the way [AssignMaterial]
/// and [SetMaterialField] already do: by row.
///
/// An unnamed material — most of them, since nothing requires a name — is
/// listed as `material $row` rather than left blank, because a listing with a
/// blank name is a listing an agent cannot ask a person to pick from.
List<Listed> materialsOf(ModelProject project) => <Listed>[
  for (var i = 0; i < project.materials.length; i++)
    Listed(id: i, name: project.materials[i].surface.name ?? 'material $i'),
];

/// Every skeleton in [project], by the index [ModelObject.skeletonIndex] and
/// every rig command already address one with.
///
/// **Real rows now, not `const []`** (`ux-19`). This returned nothing and said
/// rigging was "phase 3" — true when it was written, and stale since
/// `anim-03` gave [ModelProject] a skeleton list of its own. An agent asked to
/// retarget a clip had to be told an index by a person, because the one call
/// that would have named the skeletons answered that there were none.
List<Listed> skeletonsOf(ModelProject project) => <Listed>[
  for (var i = 0; i < project.skeletons.length; i++)
    Listed(
      id: i,
      name: project.skeletons[i].name ?? 'skeleton $i',
      about: <String, Object?>{
        'joints': project.skeletons[i].joints.length,
        if (project.skeletons[i].skeletonRoot case final int root) 'root': root,
        if (project.skeletons[i].constraints.isNotEmpty)
          'ikChains': project.skeletons[i].constraints.length,
      },
    ),
];

/// Every animation clip in [project], by the index `retargetClip`, `bakeIk`
/// and `bakeDrivers` all take. See [skeletonsOf] for why this stopped being
/// an empty list.
List<Listed> clipsOf(ModelProject project) => <Listed>[
  for (var i = 0; i < project.clips.length; i++)
    Listed(
      id: i,
      name: project.clips[i].name ?? 'clip $i',
      about: <String, Object?>{'tracks': project.clips[i].tracks.length},
    ),
];

/// Every light in [project]'s own scene lighting, by the index
/// [RemoveLight] and [SetLightField] address one with — `ux-19`.
List<Listed> lightsOf(ModelProject project) => <Listed>[
  for (var i = 0; i < project.lighting.lights.length; i++)
    Listed(
      id: i,
      name: 'light $i',
      kind: project.lighting.lights[i].type.name,
      transform: project.lighting.lights[i].transform.storage.toList(),
      about: <String, Object?>{
        'intensity': project.lighting.lights[i].intensity,
        if (project.lighting.lights[i].castsShadow) 'castsShadow': true,
      },
    ),
];

/// [id]'s own shape keys, by the index [SetShapeWeight] and [ShapeDriver]
/// address one with — `ux-19`. Empty for an object with none, and for an id
/// nothing in [project] holds.
List<Listed> shapesOf(ModelProject project, int id) {
  final ShapeSet? shapes = project[id]?.shapeSet;
  if (shapes == null) return const <Listed>[];
  return <Listed>[
    for (var i = 0; i < shapes.keys.length; i++)
      Listed(
        id: i,
        name: shapes.keys[i].name,
        about: <String, Object?>{
          'weight': i < shapes.weights.length ? shapes.weights[i] : 0.0,
        },
      ),
  ];
}

/// [id]'s own modifier stack, top of the list first — the order
/// [ReorderModifier] and [SetModifierField] index it in — with what each one
/// is and whether the picture and the file both run it (`ux-19`).
/// The kind is read out of the modifier's own `toJson` rather than switched
/// on here, so a modifier kind added to `flutter3d_mesh` is listed by name the
/// day it lands instead of the day somebody remembers this file: `kind` is
/// what `modifierFromJson` already reads it back by, so it cannot drift.
List<Listed> modifiersOf(ModelProject project, int id) {
  final List<ModifierSlot>? stack = project[id]?.modifiers;
  if (stack == null) return const <Listed>[];
  return <Listed>[
    for (var i = 0; i < stack.length; i++)
      if (stack[i].modifier.toJson() case final Map<String, Object?> fields)
        Listed(
          id: i,
          name: fields['kind'] as String? ?? 'modifier $i',
          kind: fields['kind'] as String?,
          about: <String, Object?>{
            'enabled': stack[i].enabled,
            'inExport': stack[i].inExport,
            'fields': fields,
          },
        ),
  ];
}
