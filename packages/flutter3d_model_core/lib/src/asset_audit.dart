/// What is wrong with an asset somebody else made, before it goes into a game.
///
/// **`ExportReadiness` asks whether a project can leave; this asks whether an
/// asset that arrived is fit to use.** A generator, a download or another
/// tool's exporter hands over files that load perfectly and are still wrong
/// in ways a readiness check has no reason to look for: a character a hundred
/// and eighty metres tall because the file was in centimetres, a crate whose
/// origin is a metre to one side of it so it floats when placed, "Material"
/// and "Material.001" painting the same grey as two draw calls, a triangle
/// that stood on two coincident vertices and a fin glued to an edge two faces
/// already share. Each of those is cheap to find and expensive to find late —
/// in a level, through a camera, on somebody else's machine.
///
/// **Nothing here reimplements a check.** Budgets and every structural issue
/// an export would raise are `ExportReadiness`, carried whole; the mesh counts
/// are the `ImportReport` `importMeshData` already returns when it rebuilds
/// topology, which is the same weld `repair` would run. What is new is the
/// two measurements no other check makes — the overall size and where the
/// origin sits against the bounds — and the duplicate-material grouping,
/// which reads `material_key.dart`'s key with the name left out.
///
/// **It measures and does not change anything.** Repairing is a session's
/// business (`flutter3d_model_mcp`'s `audit` with `repair`), because it is a
/// run of commands that has to land as one undo step, and an audit that could
/// also edit would be an audit nobody could call just to look.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'describe.dart';
import 'material_key.dart';
import 'project.dart';
import 'readiness.dart';
import 'world_transform.dart';

/// The smallest overall size, in metres, that reads as an asset in metres: a
/// centimetre. Anything smaller is a unit mistake far more often than a model
/// of a grain of sand.
const double assetMinSize = 0.01;

/// The largest overall size, in metres, that reads as one asset: a hundred
/// metres, a large building. A file past it was almost always written in
/// centimetres or millimetres and read as metres.
const double assetMaxSize = 100.0;

/// Which of the audit's questions a finding answers.
enum AuditCheck {
  /// The overall size is outside [assetMinSize]…[assetMaxSize].
  units,

  /// The origin is away from the base centre of the bounds.
  pivot,

  /// An `ExportReadiness` issue: a budget, an empty mesh, a pinch.
  readiness,

  /// Two or more materials identical but for their names.
  materials,

  /// What rebuilding an imported mesh's topology had to decide.
  mesh,
}

/// One thing wrong with an asset, in a sentence with its numbers in it.
final class AuditFinding {
  const AuditFinding(this.check, this.message);

  final AuditCheck check;
  final String message;

  @override
  String toString() => '${check.name}: $message';
}

/// What rebuilding one imported object's topology had to decide — the counts
/// from `importMeshData`'s own `ImportReport`, at its default weld.
final class MeshAudit {
  const MeshAudit({
    required this.object,
    required this.degenerate,
    required this.nonManifold,
    required this.flipped,
  });

  final ModelObject object;

  /// Triangles that name one vertex twice once coincident vertices are
  /// welded — no area, no normal, and dropped by the weld.
  final int degenerate;

  /// Edges with a third face on them, which the weld splits.
  final int nonManifold;

  /// Faces wound against their neighbours, which the weld turns round.
  final int flipped;
}

/// Everything [AssetAudit.of] measured and what it made of it.
final class AssetAudit {
  const AssetAudit._({
    required this.bounds,
    required this.duplicateMaterials,
    required this.meshes,
    required this.readiness,
    required this.findings,
  });

  /// Audits [project] as one asset: its world bounds, its origin against them,
  /// its materials, its imported meshes and its own profile's readiness.
  factory AssetAudit.of(ModelProject project) {
    final Aabb3? bounds = worldBoundsOf(project);
    final List<List<int>> duplicates = _duplicateMaterials(project);
    final List<MeshAudit> meshes = <MeshAudit>[
      for (final ModelObject object in project.objects)
        if (object.geometry case ImportedGeometry(
          :final data,
        ) when data.triangleCount > 0)
          () {
            final (_, ImportReport report, _) = importMeshData(data);
            return MeshAudit(
              object: object,
              degenerate: report.droppedDegenerate,
              nonManifold: report.splitNonManifold,
              flipped: report.flippedFaces,
            );
          }(),
    ];
    final readiness = ExportReadiness.check(project);
    return AssetAudit._(
      bounds: bounds,
      duplicateMaterials: duplicates,
      meshes: meshes,
      readiness: readiness,
      findings: <AuditFinding>[
        ?_unitsFinding(bounds),
        ?_pivotFinding(bounds),
        for (final List<int> group in duplicates)
          _duplicateFinding(project, group),
        for (final MeshAudit mesh in meshes) ?_meshFinding(mesh),
        for (final ExportIssue issue in readiness.issues)
          AuditFinding(AuditCheck.readiness, issue.toString()),
      ],
    );
  }

  /// The box around every object's geometry, in world space; null for a
  /// project with nothing drawn in it.
  final Aabb3? bounds;

  /// The largest side of [bounds], in metres — what "overall size" means for
  /// the units check. Zero when there are no bounds.
  double get size => switch (bounds) {
    null => 0.0,
    final Aabb3 box => _sizeOf(box),
  };

  /// The middle of the bottom of [bounds]: where an asset that stands on a
  /// floor wants its origin.
  Vector3? get baseCentre => switch (bounds) {
    null => null,
    final Aabb3 box => _baseCentreOf(box),
  };

  /// How far the origin is from [baseCentre], in metres. Zero when there are
  /// no bounds.
  double get pivotDistance => baseCentre?.length ?? 0.0;

  /// Groups of material indices identical but for their names, each group in
  /// table order; empty when every material is its own.
  final List<List<int>> duplicateMaterials;

  /// One entry per imported object with triangles, whether or not its counts
  /// are worth a finding.
  final List<MeshAudit> meshes;

  /// The project's own export check, carried whole.
  final ExportReadiness readiness;

  /// Units, then pivot, materials, meshes and the readiness issues.
  final List<AuditFinding> findings;

  /// Whether nothing was found.
  bool get clean => findings.isEmpty;

  /// The measurements in one line, then each finding on its own.
  String get says {
    final Aabb3? box = bounds;
    final measured = box == null
        ? 'nothing drawn to measure'
        : '${_metres(box.max.x - box.min.x)} × '
              '${_metres(box.max.y - box.min.y)} × '
              '${_metres(box.max.z - box.min.z)}, origin '
              '${_metres(pivotDistance)} from the base centre';
    return <String>[
      measured,
      if (clean)
        'nothing to fix'
      else
        '${findings.length} ${findings.length == 1 ? 'finding' : 'findings'}:',
      for (final AuditFinding finding in findings) '  $finding',
    ].join('\n');
  }

  @override
  String toString() => 'AssetAudit(${findings.length} findings)';
}

/// The box around every object in [project], in world space.
///
/// Every geometry kind contributes what it draws: an edited mesh its live
/// vertices, an imported one its buffer, a parametric shape the mesh it
/// builds. A socket draws nothing and adds nothing. Hidden objects count —
/// an export writes them too.
Aabb3? worldBoundsOf(ModelProject project) {
  final List<Aabb3> boxes = <Aabb3>[
    for (final ModelObject object in project.objects)
      if (_localBoundsOf(object.geometry) case final Aabb3 local)
        Aabb3.copy(local)..transform(worldTransformOf(project, object.id)),
  ];
  return boxes.isEmpty
      ? null
      : boxes
            .skip(1)
            .fold<Aabb3>(
              Aabb3.copy(boxes.first),
              (Aabb3 all, Aabb3 b) => all..hull(b),
            );
}

Aabb3? _localBoundsOf(Geometry geometry) => switch (geometry) {
  EditedGeometry(:final mesh) => boundsOfMesh(mesh),
  ImportedGeometry(:final data) =>
    data.triangleCount == 0 ? null : data.computeBounds(),
  ParametricGeometry(:final shape) => shape.drawn.build().computeBounds(),
  SocketGeometry() => null,
};

/// The origin further from the base centre than this reads as misplaced: a
/// millimetre, or a hundredth of the asset's size when that is more — a
/// building a centimetre off is placed where anybody meant it to be.
double _pivotTolerance(double size) => math.max(0.001, size * 0.01);

AuditFinding? _unitsFinding(Aabb3? bounds) {
  if (bounds == null) return null;
  final double size = _sizeOf(bounds);
  if (size > assetMaxSize) {
    final (String unit, double factor) = size / 100 <= assetMaxSize
        ? ('cm', 100.0)
        : ('mm', 1000.0);
    return AuditFinding(
      AuditCheck.units,
      'the asset is ${_metres(size)} across, more than the '
      '${_metres(assetMaxSize)} one asset reads as; in $unit it would be '
      '${_metres(size / factor)}, so it was most likely written in $unit and '
      'read as metres — import it again with unit "$unit"',
    );
  }
  if (size < assetMinSize) {
    return AuditFinding(
      AuditCheck.units,
      'the asset is ${_metres(size)} across, less than the '
      '${_metres(assetMinSize)} one asset reads as; scaled by 100 it would be '
      '${_metres(size * 100)} and by 1000 ${_metres(size * 1000)}, so it was '
      'most likely scaled down once too often on its way here',
    );
  }
  return null;
}

AuditFinding? _pivotFinding(Aabb3? bounds) {
  if (bounds == null) return null;
  final Vector3 base = _baseCentreOf(bounds);
  final double distance = base.length;
  if (distance <= _pivotTolerance(_sizeOf(bounds))) return null;
  return AuditFinding(
    AuditCheck.pivot,
    'the origin is ${_metres(distance)} from the middle of the asset\'s base, '
    'at (${_metres(base.x)}, ${_metres(base.y)}, ${_metres(base.z)}); placed '
    'at a point in a level it will stand that far away from it — repair '
    'moves it so its base sits on the origin',
  );
}

Vector3 _baseCentreOf(Aabb3 box) => Vector3(
  (box.min.x + box.max.x) * 0.5,
  box.min.y,
  (box.min.z + box.max.z) * 0.5,
);

double _sizeOf(Aabb3 box) => math.max(
  box.max.x - box.min.x,
  math.max(box.max.y - box.min.y, box.max.z - box.min.z),
);

List<List<int>> _duplicateMaterials(ModelProject project) {
  final Map<String, List<int>> byKey = <String, List<int>>{};
  for (var i = 0; i < project.materials.length; i++) {
    byKey
        .putIfAbsent(
          materialKey(project.materials[i].surface, named: false),
          () => <int>[],
        )
        .add(i);
  }
  return <List<int>>[
    for (final List<int> group in byKey.values)
      if (group.length > 1) group,
  ];
}

AuditFinding _duplicateFinding(ModelProject project, List<int> group) {
  final List<String> named = <String>[
    for (final int i in group)
      project.materials[i].surface.name == null
          ? 'material $i'
          : 'material $i ("${project.materials[i].surface.name}")',
  ];
  return AuditFinding(
    AuditCheck.materials,
    '${named.take(named.length - 1).join(', ')} and ${named.last} are the '
    'same material under '
    '${group.length} names; every object painted with them could share one, '
    'and each extra one is a draw call and a state change for nothing',
  );
}

AuditFinding? _meshFinding(MeshAudit mesh) {
  final List<String> parts = <String>[
    if (mesh.degenerate > 0)
      '${_count(mesh.degenerate, 'triangle')} with no area once welded',
    if (mesh.nonManifold > 0)
      '${_count(mesh.nonManifold, 'edge')} shared by more than two faces',
    if (mesh.flipped > 0)
      '${_count(mesh.flipped, 'face')} wound against its neighbours',
  ];
  if (parts.isEmpty) return null;
  return AuditFinding(
    AuditCheck.mesh,
    '"${mesh.object.name}" has ${parts.join(', ')}; repair rebuilds it as an '
    'editable mesh, whose weld drops a triangle with no area, splits an edge '
    'with a third face on it and turns a face round to agree with its '
    'neighbours',
  );
}

String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// Metres to two decimals, or two significant figures under a centimetre, so
/// a millimetre model does not read as "0.00 m".
String _metres(double value) =>
    '${value.abs() >= 0.01 || value == 0 ? value.toStringAsFixed(2) : value.toStringAsPrecision(2)} m';
