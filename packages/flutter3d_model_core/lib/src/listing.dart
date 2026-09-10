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

import 'project.dart';

/// One row of a listing: what to call it, and the id a later command —
/// `AssignMaterial`, `SetParametric`, an MCP tool's `id` argument — addresses
/// it by.
final class Listed {
  const Listed({required this.id, required this.name, this.kind});

  final int id;
  final String name;

  /// What kind of thing this is, in one word — `parametric`, `mesh`,
  /// `imported` for an object — or null when a listing has only one kind and
  /// saying it on every row would be noise.
  final String? kind;

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
List<Listed> contentsOf(ModelProject project) => <Listed>[
  for (final ModelObject object in project.objects)
    Listed(
      id: object.id,
      name: object.name,
      kind: switch (object.geometry) {
        ParametricGeometry() => 'parametric',
        EditedGeometry() => 'mesh',
        ImportedGeometry() => 'imported',
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

/// Every skeleton in [project], which is none: rigging is `anim-*`, phase 3,
/// and `ModelProject` has nowhere to keep one yet. Declared now so a caller
/// listing everything a project might hold does not need a special case for
/// the one kind that always comes back empty, and so the day a skeleton lands
/// this only has to stop returning `const []`.
List<Listed> skeletonsOf(ModelProject project) => const <Listed>[];

/// Every animation clip in [project]. See [skeletonsOf]: same phase, same
/// reason, same empty list until it is not.
List<Listed> clipsOf(ModelProject project) => const <Listed>[];
