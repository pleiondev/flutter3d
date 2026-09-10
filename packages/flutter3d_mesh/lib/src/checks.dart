/// What is wrong with a mesh, said in a way somebody can act on.
///
/// **Every check names the elements, not just the count.** "Three n-gons" is a
/// number a person can do nothing with; the three faces, selectable and
/// highlightable, is a thing they can look at. So every issue carries the ids
/// and the level they are at, and a viewport turns one into a selection.
///
/// **Nothing here is a failure.** A boundary edge is how a plane is made and a
/// fault in a watertight print; an n-gon is fine in a file and wrong in a
/// engine that only draws triangles. What a check knows is what it found and
/// roughly how much it matters; what to do about it belongs to whoever asked —
/// an export readiness panel, an agent over MCP, a person tidying a scan.
///
/// **Non-manifold edges are not among the checks, and that is the structure
/// rather than an omission.** A half-edge has one twin, so three faces on one
/// edge is a shape this mesh cannot hold: `importMeshData` splits them on the
/// way in and says how often. What *is* representable, and is the thing people
/// mean half the time they say non-manifold, is a vertex where two surfaces
/// meet at a point and nothing else — two boxes touching at a corner — so that
/// is what is checked.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'selection.dart';

/// Roughly how much an issue matters.
///
/// Machinery: three levels is what a panel can show and what a person can
/// triage, and a fourth would be a shade of one of these rather than a new
/// kind of answer. Named in `boundaryEnumExempt` for that reason, which is
/// decision Б7 of `doc/model-editor-plan.md`.
enum IssueSeverity {
  /// Worth knowing. A boundary edge on a plane, an n-gon in a file.
  note,

  /// Probably not what somebody meant. Vertices in the same place, a shell
  /// wound inside out.
  warning,

  /// Will not survive being drawn or written out. A face with no area.
  error,
}

/// A kind of thing a check can find.
///
/// **A value with instances rather than an enum**, and the reason is that the
/// set is open: an exporter adds "this model has no texture coordinates", a
/// printer adds "this shell is not watertight", and neither belongs in a list
/// this package has to know about. The same shape `VertexAttribute` uses next
/// door, for the same reason.
final class MeshIssueKind {
  const MeshIssueKind(this.name, this.severity, this.level);

  /// A stable slug, which is what a report or a tool call carries.
  final String name;

  final IssueSeverity severity;

  /// What the ids of an issue of this kind are.
  final ElementLevel level;

  static const MeshIssueKind ngon = MeshIssueKind(
    'ngon',
    IssueSeverity.note,
    ElementLevel.face,
  );
  static const MeshIssueKind boundaryEdge = MeshIssueKind(
    'boundary-edge',
    IssueSeverity.note,
    ElementLevel.edge,
  );
  static const MeshIssueKind nonManifoldVertex = MeshIssueKind(
    'non-manifold-vertex',
    IssueSeverity.warning,
    ElementLevel.vertex,
  );
  static const MeshIssueKind isolatedVertex = MeshIssueKind(
    'isolated-vertex',
    IssueSeverity.warning,
    ElementLevel.vertex,
  );
  static const MeshIssueKind duplicateVertex = MeshIssueKind(
    'duplicate-vertex',
    IssueSeverity.warning,
    ElementLevel.vertex,
  );
  static const MeshIssueKind invertedShell = MeshIssueKind(
    'inverted-shell',
    IssueSeverity.warning,
    ElementLevel.face,
  );
  static const MeshIssueKind degenerateFace = MeshIssueKind(
    'degenerate-face',
    IssueSeverity.error,
    ElementLevel.face,
  );

  @override
  String toString() => name;
}

/// Something a check found, and where.
final class MeshIssue {
  MeshIssue(this.kind, Iterable<int> ids, this.message)
    : ids = Int32List.fromList(ids.toList(growable: false)..sort());

  final MeshIssueKind kind;

  /// The elements, at [MeshIssueKind.level]. Ascending, so a selection made
  /// from them is one already.
  final Int32List ids;

  /// A sentence for a person, with the count in it.
  final String message;

  IssueSeverity get severity => kind.severity;

  /// The elements as something a viewport can highlight.
  Selection get selection => Selection.of(kind.level, ids);

  @override
  String toString() => '${kind.name}: $message';
}

/// Every question worth asking about a mesh before it goes anywhere.
final class MeshChecks {
  MeshChecks(this.mesh, {double? tolerance})
    : tolerance = tolerance ?? _defaultTolerance(mesh);

  final EditMesh mesh;

  /// The distance under which two vertices are in the same place, and the area
  /// under which a face has none.
  ///
  /// Scaled to the model by default, because a millimetre on a building and a
  /// millimetre on a bolt are not the same question — the same rule the import
  /// welds by.
  final double tolerance;

  /// Everything that is wrong, worst first.
  ///
  /// **Sorted by severity and then by name**, so a panel showing the first
  /// three shows the three that matter, and so the same mesh reports the same
  /// order twice.
  List<MeshIssue> all() =>
      <MeshIssue>[
        ?degenerateFaces(),
        ?nonManifoldVertices(),
        ?invertedShells(),
        ?duplicateVertices(),
        ?isolatedVertices(),
        ?ngons(),
        ?boundaryEdges(),
      ]..sort((MeshIssue a, MeshIssue b) {
        final bySeverity = b.severity.index.compareTo(a.severity.index);
        return bySeverity != 0
            ? bySeverity
            : a.kind.name.compareTo(b.kind.name);
      });

  /// Faces with more than four corners.
  MeshIssue? ngons() {
    final found = <int>[
      for (var face = 0; face < mesh.faceSlotCount; face++)
        if (mesh.isFaceAlive(face) && mesh.valencyOf(face) > 4) face,
    ];
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.ngon,
            found,
            '${found.length} faces have more than four corners; a renderer '
            'will cut them into triangles and may not cut them the way you '
            'would',
          );
  }

  /// Edges with nothing on the other side.
  ///
  /// The half-edge is the edge here without being asked: an edge with nothing
  /// live behind it has one side, so the one that found it is the one
  /// `EditMesh.edgeOf` would have chosen.
  MeshIssue? boundaryEdges() {
    final found = <int>[];
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        if (!mesh.hasLiveTwin(half)) found.add(half);
      });
    }
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.boundaryEdge,
            found,
            '${found.length} edges have a face on one side only; the surface '
            'is open there',
          );
  }

  /// Vertices where more than one piece of surface meets at a point.
  ///
  /// **The fan is what says so.** Walking round a vertex from one of its edges
  /// reaches every face at it exactly when the surface there is one sheet;
  /// reaching only some of them means the rest are a second sheet joined at
  /// nothing but this point. That is a shape a subdivision cannot smooth, a
  /// solidify cannot thicken and a printer cannot print.
  MeshIssue? nonManifoldVertices() {
    final fans = _fansPerVertex();
    final found = <int>[
      for (var vertex = 0; vertex < fans.length; vertex++)
        if (fans[vertex] > 1) vertex,
    ];
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.nonManifoldVertex,
            found,
            '${found.length} vertices have more than one piece of surface '
            'meeting at them and joined nowhere else',
          );
  }

  /// Vertices no face uses.
  MeshIssue? isolatedVertices() {
    final used = List<bool>.filled(mesh.vertexSlotCount, false);
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachVertex(face, (int vertex) => used[vertex] = true);
    }
    final found = <int>[
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
        if (mesh.isVertexAlive(vertex) && !used[vertex]) vertex,
    ];
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.isolatedVertex,
            found,
            '${found.length} vertices are not part of any face; they are in '
            'the count, in the bounding box and in nothing you can see',
          );
  }

  /// Faces standing on fewer than three places, or on no area.
  MeshIssue? degenerateFaces() {
    final found = <int>[];
    final area = tolerance * tolerance;
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      final loop = mesh.verticesOf(face);
      // A corner naming a vertex the loop already named pinches the face into
      // a figure of eight, which is not a polygon however much area the two
      // wings add up to.
      if (loop.length < 3 ||
          loop.toSet().length != loop.length ||
          mesh.areaOf(face) <= area) {
        found.add(face);
      }
    }
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.degenerateFace,
            found,
            '${found.length} faces have no area; they have no normal either, '
            'and nothing downstream can do anything sensible with them',
          );
  }

  /// Vertices standing in the same place as another.
  MeshIssue? duplicateVertices() {
    final cells = <int, List<int>>{};
    final found = <int>{};
    final scale = tolerance > 0 ? 1 / tolerance : 0.0;
    final at = Vector3.zero();
    final other = Vector3.zero();

    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      if (!mesh.isVertexAlive(vertex)) continue;
      mesh.positionOf(vertex, at);
      final cx = (at.x * scale).floor();
      final cy = (at.y * scale).floor();
      final cz = (at.z * scale).floor();
      // The twenty-seven cells around, so two points either side of a cell
      // boundary are not missed — the same reason the import searches them.
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dz = -1; dz <= 1; dz++) {
            for (final near
                in cells[_cellKey(cx + dx, cy + dy, cz + dz)] ??
                    const <int>[]) {
              mesh.positionOf(near, other);
              if ((other - at).length <= tolerance) {
                found
                  ..add(near)
                  ..add(vertex);
              }
            }
          }
        }
      }
      cells.putIfAbsent(_cellKey(cx, cy, cz), () => <int>[]).add(vertex);
    }

    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.duplicateVertex,
            found,
            '${found.length} vertices stand in the same place as another and '
            'are not joined to it; the seam between them will not shade or '
            'deform as one',
          );
  }

  /// Closed shells wound the wrong way round.
  ///
  /// **The signed volume is the whole test.** A closed surface encloses a
  /// positive volume when its faces are wound outwards and a negative one when
  /// they are not; an open surface has no inside to be out of, so it is not
  /// asked. What comes back is the faces of every shell that answered
  /// negatively, which is what a person turns round.
  MeshIssue? invertedShells() {
    final found = <int>[];
    for (final shell in _shells()) {
      var closed = true;
      var volume = 0.0;
      for (final face in shell) {
        mesh.forEachHalfEdge(face, (int half) {
          if (!mesh.hasLiveTwin(half)) closed = false;
        });
        volume += _coneOver(face);
      }
      if (closed && volume < 0) found.addAll(shell);
    }
    return found.isEmpty
        ? null
        : MeshIssue(
            MeshIssueKind.invertedShell,
            found,
            '${found.length} faces belong to a closed shell wound inside out; '
            'its normals point in and its volume comes out negative',
          );
  }

  /// `V − E + F` for each island, in the order the islands begin.
  ///
  /// **Not an issue, a fact.** Two for anything shaped like a ball, zero for a
  /// torus, one for a disc — and a number nobody expected is the cheapest
  /// signal that a model is not the shape somebody thinks it is. What it
  /// means is the caller's to say, which is why it is not phrased as a
  /// complaint.
  List<int> eulerByComponent() => <int>[
    for (final shell in _shells()) _eulerOf(shell),
  ];

  /// The islands, joined through vertices — the same relation `Selection` and
  /// `separateComponents` use.
  List<List<int>> _shells() {
    final island = Int32List(mesh.faceSlotCount)
      ..fillRange(0, mesh.faceSlotCount, EditMesh.none);
    final shells = <List<int>>[];
    for (var seed = 0; seed < mesh.faceSlotCount; seed++) {
      if (!mesh.isFaceAlive(seed) || island[seed] != EditMesh.none) continue;
      final reached = Selection.of(ElementLevel.face, <int>[seed]).linked(mesh);
      final id = shells.length;
      shells.add(<int>[]);
      for (final face in reached.ids) {
        island[face] = id;
        shells[id].add(face);
      }
    }
    return shells;
  }

  int _eulerOf(List<int> shell) {
    final vertices = <int>{};
    var paired = 0;
    var boundary = 0;
    final inShell = shell.toSet();
    for (final face in shell) {
      mesh.forEachHalfEdge(face, (int half) {
        vertices.add(mesh.originOf(half));
        if (mesh.hasLiveTwin(half) &&
            inShell.contains(mesh.faceOf(mesh.twinOf(half)))) {
          paired++;
        } else {
          boundary++;
        }
      });
    }
    return vertices.length - (paired ~/ 2 + boundary) + shell.length;
  }

  double _coneOver(int face) {
    final loop = mesh.verticesOf(face);
    if (loop.length < 3) return 0;
    final anchor = mesh.positionOf(loop.first);
    final b = Vector3.zero();
    final c = Vector3.zero();
    var total = 0.0;
    for (var i = 1; i + 1 < loop.length; i++) {
      mesh.positionOf(loop[i], b);
      mesh.positionOf(loop[i + 1], c);
      total += anchor.dot(b.cross(c)) / 6.0;
    }
    return total;
  }

  /// How many separate fans of faces meet at each vertex.
  Int32List _fansPerVertex() {
    final group = Int32List(mesh.halfEdgeSlotCount);
    for (var half = 0; half < group.length; half++) {
      group[half] = half;
    }

    int find(int half) {
      var root = half;
      while (group[root] != root) {
        root = group[root];
      }
      var walk = half;
      while (group[walk] != root) {
        final parent = group[walk];
        group[walk] = root;
        walk = parent;
      }
      return root;
    }

    final counts = Int32List(mesh.vertexSlotCount);
    final roots = <int, Set<int>>{};
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        if (!mesh.hasLiveTwin(half)) return;
        final around = mesh.nextOf(mesh.twinOf(half));
        final a = find(half);
        final b = find(around);
        if (a != b) group[b] = a;
      });
    }
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        roots.putIfAbsent(mesh.originOf(half), () => <int>{}).add(find(half));
      });
    }
    for (final entry in roots.entries) {
      counts[entry.key] = entry.value.length;
    }
    return counts;
  }
}

int _cellKey(int x, int y, int z) =>
    (x & 0x1FFFFF) | ((y & 0x1FFFFF) << 21) | ((z & 0x1FFFFF) << 42);

double _defaultTolerance(EditMesh mesh) {
  var lowest = Vector3.zero();
  var highest = Vector3.zero();
  var seen = false;
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    if (!seen) {
      lowest = Vector3.copy(at);
      highest = Vector3.copy(at);
      seen = true;
      continue;
    }
    Vector3.min(lowest, at, lowest);
    Vector3.max(highest, at, highest);
  }
  return seen ? math.max((highest - lowest).length * 1e-6, 1e-9) : 1e-9;
}
