/// Boolean union, subtraction and intersection over two closed meshes, by
/// the BSP algorithm `csg.js` popularised — Evan Wallace's own recipe, not a
/// different one: split each solid's polygons against the other's binary
/// space partition, keep or discard by which side of the other solid they
/// land on, and stitch the survivors back into a mesh.
///
/// **`CsgNode` walks its own tree on an explicit stack, never by calling
/// itself.** `build`, `invert`, `clipTo` and `clipPolygons` are all
/// naturally recursive in the reference algorithm; each one here is the same
/// algorithm over a `List` doing the recursion's own job, because a
/// duplicated or adversarial mesh can build a BSP tree deep enough to
/// overflow a native call stack long before it reaches [maxPolygons] wide
/// enough to refuse on its own account. `clipPolygons` collects into a flat
/// output list rather than concatenating each level's own return value —
/// sound because a polygon set has no order to preserve, and because the
/// original's own `if (this.front) … else front` / `if (this.back) …  else
/// back = []` asymmetry (front is *kept* with no further structure to say
/// otherwise; back is *discarded*) survives unchanged as "add to the output
/// directly" versus "drop it" at exactly the same two branches.
///
/// **`CsgPlane` and `CsgPolygon` are immutable; `CsgNode.invert` replaces
/// list entries rather than mutating a polygon in place**, the choice this
/// repository's own style makes everywhere else a value can be replaced
/// instead of changed.
///
/// **What a coplanar polygon does.** Splitting classifies every vertex
/// against [CsgTolerance.eps] of the plane; a polygon landing exactly on it
/// is coplanar, not spanning, and [CsgResult.warnings] counts how many of
/// those `build` ever saw — a real, if rare, source of ambiguity (which side
/// a face flush with the other solid's own surface belongs to depends on
/// which way its own normal happens to point relative to that plane), worth
/// naming rather than resolving silently and moving on. It does not stop the
/// operation: the classic algorithm was never in danger of crashing on this
/// case, only of answering a question that had two defensible answers.
///
/// **[maxPolygons] is checked once, against the two inputs' own triangle
/// counts, before any splitting starts** — not against the tree's own
/// working set as it grows, which a single pass over the input cannot know
/// in advance and a running check would cost as much as the splitting
/// itself to police accurately. A mesh already over budget refuses before
/// doing any work; one that explodes during splitting is not caught by this
/// and is a real, open gap.
///
/// **The volume this hands back is correct; the mesh it sits in is not
/// always closed.** [_fromPolygons] welds the split pieces back into one
/// mesh by vertex position alone, the same [mergeByDistance] every other
/// whole-mesh rebuild in this package already uses — and that is not always
/// enough here. A cutting plane can split one of two triangles that used to
/// share an edge and leave the other whole, so the shared edge ends up cut
/// on one side and uncut on the other: a T-junction, where one long edge
/// faces two shorter ones rather than a single matching twin, which no
/// amount of vertex welding closes because nothing has split the long edge
/// to match. It is a real property of reconstructing a polygon soup into a
/// manifold mesh, not a defect particular to this file — `csg.js` itself
/// has the same one — and it costs nothing a volume asks about: each
/// triangle's own divergence-theorem contribution is correct regardless of
/// which edge of it has a twin, which is why [EditMesh.signedVolume] on the
/// result is trustworthy even on the runs where
/// [EditMesh.eulerCharacteristic] is not 2. Splitting the long side of a
/// T-junction to close it is a real, open gap — mesh-47's own acceptance
/// asks for a volume within a tolerance, not a watertight result, and this
/// gives the first honestly.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'merge.dart';
import 'selection.dart';
import 'triangulate.dart';

/// A plane, as the unit [normal] and the distance [w] along it from the
/// origin — a point `p` lies on the plane exactly when `normal·p == w`.
final class CsgPlane {
  const CsgPlane(this.normal, this.w);

  factory CsgPlane.fromPoints(Vector3 a, Vector3 b, Vector3 c) {
    final normal = (b - a).cross(c - a).normalized();
    return CsgPlane(normal, normal.dot(a));
  }

  final Vector3 normal;
  final double w;

  CsgPlane get flipped => CsgPlane(-normal, -w);
}

/// One convex, planar face — always a triangle or a piece a plane split one
/// into — carrying [materialSlot] through the operation the way a face's
/// own slot survives every other whole-mesh rebuild in this package.
final class CsgPolygon {
  const CsgPolygon(this.vertices, this.plane, this.materialSlot);

  final List<Vector3> vertices;
  final CsgPlane plane;
  final int materialSlot;

  CsgPolygon get flipped => CsgPolygon(
    vertices.reversed.toList(growable: false),
    plane.flipped,
    materialSlot,
  );
}

const int _coplanar = 0;
const int _front = 1;
const int _back = 2;
const int _spanning = 3;

/// One node of a binary space partition: the plane it splits by, the
/// polygons that landed exactly on that plane, and the front/back subtrees
/// for everything that did not.
///
/// See the library doc comment for why every method here walks its own tree
/// on an explicit stack.
final class CsgNode {
  CsgNode();

  CsgPlane? plane;
  List<CsgPolygon> polygons = <CsgPolygon>[];
  CsgNode? front;
  CsgNode? back;

  /// A tree of the same shape, sharing every [CsgPlane] and [CsgPolygon] —
  /// both immutable — but none of the `List`s or nodes themselves, so
  /// mutating one tree's own [polygons] can never reach the other's.
  CsgNode clone() {
    final root = CsgNode();
    final stack = <(CsgNode, CsgNode)>[(this, root)];
    while (stack.isNotEmpty) {
      final (original, target) = stack.removeLast();
      target.plane = original.plane;
      target.polygons = List<CsgPolygon>.of(original.polygons);
      if (original.front != null) {
        target.front = CsgNode();
        stack.add((original.front!, target.front!));
      }
      if (original.back != null) {
        target.back = CsgNode();
        stack.add((original.back!, target.back!));
      }
    }
    return root;
  }

  /// Builds this node's own tree from [initialPolygons]: the first polygon
  /// (of whichever list a stack frame is holding) fixes that frame's own
  /// splitting plane if the node does not have one yet, everything coplanar
  /// with it joins [polygons] directly, and everything else queues for the
  /// front or back child a further frame builds.
  void build(List<CsgPolygon> initialPolygons, CsgTolerance tolerance) {
    final stack = <(CsgNode, List<CsgPolygon>)>[(this, initialPolygons)];
    while (stack.isNotEmpty) {
      final (node, polys) = stack.removeLast();
      if (polys.isEmpty) continue;
      node.plane ??= polys.first.plane;
      final front = <CsgPolygon>[];
      final back = <CsgPolygon>[];
      for (final polygon in polys) {
        _splitPolygon(
          node.plane!,
          polygon,
          node.polygons,
          node.polygons,
          front,
          back,
          tolerance,
        );
      }
      if (front.isNotEmpty) {
        node.front ??= CsgNode();
        stack.add((node.front!, front));
      }
      if (back.isNotEmpty) {
        node.back ??= CsgNode();
        stack.add((node.back!, back));
      }
    }
  }

  /// Flips every polygon this tree holds and swaps every node's own front
  /// and back — the solid this tree describes, seen from inside out.
  void invert() {
    final stack = <CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      for (var i = 0; i < node.polygons.length; i++) {
        node.polygons[i] = node.polygons[i].flipped;
      }
      final plane = node.plane;
      if (plane != null) node.plane = plane.flipped;
      final front = node.front;
      node.front = node.back;
      node.back = front;
      if (node.front != null) stack.add(node.front!);
      if (node.back != null) stack.add(node.back!);
    }
  }

  /// [polygons], kept where this tree's own planes say they are in front
  /// with nothing further to ask, discarded where a plane says back and
  /// there is no further tree to ask either — the two base cases every leaf
  /// of the recursive original returns, collected directly into one flat
  /// list rather than combined level by level, which a polygon set has no
  /// order to need.
  List<CsgPolygon> clipPolygons(
    List<CsgPolygon> polygons,
    CsgTolerance tolerance,
  ) {
    final output = <CsgPolygon>[];
    final stack = <(CsgNode, List<CsgPolygon>)>[(this, polygons)];
    while (stack.isNotEmpty) {
      final (node, polys) = stack.removeLast();
      final plane = node.plane;
      if (plane == null) {
        output.addAll(polys);
        continue;
      }
      final front = <CsgPolygon>[];
      final back = <CsgPolygon>[];
      for (final polygon in polys) {
        _splitPolygon(plane, polygon, front, back, front, back, tolerance);
      }
      if (node.front != null) {
        stack.add((node.front!, front));
      } else {
        output.addAll(front);
      }
      if (node.back != null) {
        stack.add((node.back!, back));
      }
      // No `else` for back: matches the original's own `back = []`.
    }
    return output;
  }

  /// Clips every node's own [polygons] in this tree against [other]'s.
  void clipTo(CsgNode other, CsgTolerance tolerance) {
    final stack = <CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      node.polygons = other.clipPolygons(node.polygons, tolerance);
      if (node.front != null) stack.add(node.front!);
      if (node.back != null) stack.add(node.back!);
    }
  }

  /// Every polygon this tree holds, at every node.
  List<CsgPolygon> allPolygons() {
    final output = <CsgPolygon>[];
    final stack = <CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      output.addAll(node.polygons);
      if (node.front != null) stack.add(node.front!);
      if (node.back != null) stack.add(node.back!);
    }
    return output;
  }
}

/// How close to a [CsgPlane] a vertex counts as lying on it, and how many
/// polygons landed there — the coplanar detector the plan's own row names.
final class CsgTolerance {
  CsgTolerance(this.eps);

  final double eps;

  /// Bumped once per polygon [CsgNode.build] or [CsgNode.clipPolygons]
  /// classifies as lying exactly on the plane it is being tested against.
  int coplanarCount = 0;
}

/// Classifies [polygon] against [plane] within [tolerance], and sorts it (or
/// the up to two pieces a spanning polygon splits into) into whichever of
/// [coplanarFront]/[coplanarBack]/[front]/[back] it belongs in — the same
/// four-way split `csg.js`'s own `Plane.splitPolygon` makes, including the
/// linear interpolation a spanning edge needs for the two new vertices its
/// own crossing adds.
void _splitPolygon(
  CsgPlane plane,
  CsgPolygon polygon,
  List<CsgPolygon> coplanarFront,
  List<CsgPolygon> coplanarBack,
  List<CsgPolygon> front,
  List<CsgPolygon> back,
  CsgTolerance tolerance,
) {
  final n = polygon.vertices.length;
  var polygonType = 0;
  final types = List<int>.filled(n, _coplanar);
  for (var i = 0; i < n; i++) {
    final t = plane.normal.dot(polygon.vertices[i]) - plane.w;
    final type = t < -tolerance.eps
        ? _back
        : t > tolerance.eps
        ? _front
        : _coplanar;
    types[i] = type;
    polygonType |= type;
  }

  switch (polygonType) {
    case _coplanar:
      tolerance.coplanarCount++;
      (plane.normal.dot(polygon.plane.normal) > 0
              ? coplanarFront
              : coplanarBack)
          .add(polygon);
    case _front:
      front.add(polygon);
    case _back:
      back.add(polygon);
    default: // _spanning
      final f = <Vector3>[];
      final b = <Vector3>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final ti = types[i];
        final tj = types[j];
        final vi = polygon.vertices[i];
        final vj = polygon.vertices[j];
        if (ti != _back) f.add(vi);
        if (ti != _front) b.add(vi);
        if ((ti | tj) == _spanning) {
          final denom = plane.normal.dot(vj - vi);
          final t = (plane.w - plane.normal.dot(vi)) / denom;
          final crossing = vi + (vj - vi).scaled(t);
          f.add(crossing);
          b.add(crossing);
        }
      }
      if (f.length >= 3) {
        front.add(CsgPolygon(f, polygon.plane, polygon.materialSlot));
      }
      if (b.length >= 3) {
        back.add(CsgPolygon(b, polygon.plane, polygon.materialSlot));
      }
  }
}

/// What a boolean answered: the stitched-together [mesh] and
/// [CsgTolerance.coplanarCount] from both solids' own build passes, as a
/// human sentence rather than a bare number — see the library doc comment
/// for what a coplanar polygon means and why it is not refused.
final class CsgResult {
  const CsgResult(this.mesh, this.warnings);

  final EditMesh mesh;
  final List<String> warnings;
}

/// `a ∪ b`: everything either solid covers.
CsgResult? booleanUnion(EditMesh a, EditMesh b, {int maxPolygons = 200000}) =>
    _boolean(a, b, _Op.union, maxPolygons);

/// `a − b`: [a] with whatever [b] covers cut away.
CsgResult? booleanSubtract(
  EditMesh a,
  EditMesh b, {
  int maxPolygons = 200000,
}) => _boolean(a, b, _Op.subtract, maxPolygons);

/// `a ∩ b`: only what both solids cover.
CsgResult? booleanIntersect(
  EditMesh a,
  EditMesh b, {
  int maxPolygons = 200000,
}) => _boolean(a, b, _Op.intersect, maxPolygons);

enum _Op { union, subtract, intersect }

CsgResult? _boolean(EditMesh a, EditMesh b, _Op op, int maxPolygons) {
  final aTriangles = _triangleCount(a);
  final bTriangles = _triangleCount(b);
  if (aTriangles + bTriangles > maxPolygons) return null;

  final tolerance = CsgTolerance(_epsFor(a, b));

  final nodeA = CsgNode()..build(_toPolygons(a), tolerance);
  final nodeB = CsgNode()..build(_toPolygons(b), tolerance);

  switch (op) {
    case _Op.union:
      nodeA.clipTo(nodeB, tolerance);
      nodeB.clipTo(nodeA, tolerance);
      nodeB.invert();
      nodeB.clipTo(nodeA, tolerance);
      nodeB.invert();
      nodeA.build(nodeB.allPolygons(), tolerance);
    case _Op.subtract:
      nodeA.invert();
      nodeA.clipTo(nodeB, tolerance);
      nodeB.clipTo(nodeA, tolerance);
      nodeB.invert();
      nodeB.clipTo(nodeA, tolerance);
      nodeB.invert();
      nodeA.build(nodeB.allPolygons(), tolerance);
      nodeA.invert();
    case _Op.intersect:
      nodeA.invert();
      nodeB.clipTo(nodeA, tolerance);
      nodeB.invert();
      nodeA.clipTo(nodeB, tolerance);
      nodeB.clipTo(nodeA, tolerance);
      nodeA.build(nodeB.allPolygons(), tolerance);
      nodeA.invert();
  }

  final mesh = _fromPolygons(nodeA.allPolygons());
  if (mesh == null) return null;
  final coplanarWarning =
      '${tolerance.coplanarCount} polygon(s) landed exactly on the other '
      "solid's own surface; which side each belongs to was decided by its "
      'own normal, not re-measured';
  return CsgResult(mesh, <String>[
    if (tolerance.coplanarCount > 0) coplanarWarning,
  ]);
}

int _triangleCount(EditMesh mesh) {
  var total = 0;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    total += mesh.valencyOf(face) - 2;
  }
  return total;
}

double _epsFor(EditMesh a, EditMesh b) {
  Vector3? low;
  Vector3? high;
  void expand(EditMesh mesh) {
    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      if (!mesh.isVertexAlive(v)) continue;
      final p = mesh.positionOf(v);
      if (low == null) {
        low = Vector3.copy(p);
        high = Vector3.copy(p);
      } else {
        Vector3.min(low!, p, low!);
        Vector3.max(high!, p, high!);
      }
    }
  }

  expand(a);
  expand(b);
  if (low == null) return 1e-9;
  return math.max((high! - low!).length * 1e-6, 1e-9);
}

/// [mesh], triangulated on a throwaway copy so the original is untouched,
/// as one [CsgPolygon] per triangle — always convex, so every polygon a
/// split later produces from it stays convex too.
List<CsgPolygon> _toPolygons(EditMesh mesh) {
  final copy = EditMesh.fromBytes(mesh.toBytes());
  final faces = <int>[
    for (var f = 0; f < copy.faceSlotCount; f++)
      if (copy.isFaceAlive(f)) f,
  ];
  copy.beginStep();
  triangulateFaces(copy, Selection.of(ElementLevel.face, faces));
  copy.endStep();

  final polygons = <CsgPolygon>[];
  for (var f = 0; f < copy.faceSlotCount; f++) {
    if (!copy.isFaceAlive(f)) continue;
    final vertices = copy.verticesOf(f).map(copy.positionOf).toList();
    final plane = CsgPlane.fromPoints(vertices[0], vertices[1], vertices[2]);
    final slot = copy.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)
        ? copy.materialSlotOf(f)
        : 0;
    polygons.add(CsgPolygon(vertices, plane, slot));
  }
  return polygons;
}

/// [polygons] fan-triangulated (safe: every one is convex — see
/// [_toPolygons]) into a throwaway mesh with a fresh, disconnected set of
/// vertices per triangle, then welded by position the same way every other
/// whole-mesh rebuild in this package welds one — [mergeByDistance], at its
/// own default tolerance. Null if [polygons] is empty, which a boolean
/// between two solids that do not touch at all can genuinely produce for
/// [booleanIntersect].
EditMesh? _fromPolygons(List<CsgPolygon> polygons) {
  if (polygons.isEmpty) return null;
  final builder = EditMeshBuilder();
  final faces = <int>[];
  final slots = <int>[];
  for (final polygon in polygons) {
    final loop = <int>[for (final v in polygon.vertices) builder.addVertex(v)];
    for (var i = 1; i < loop.length - 1; i++) {
      faces.add(builder.addFace(<int>[loop[0], loop[i], loop[i + 1]]));
      slots.add(polygon.materialSlot);
    }
  }

  final mesh = builder.build();
  if (slots.any((int s) => s != 0)) {
    mesh.beginStep();
    for (var i = 0; i < faces.length; i++) {
      mesh.setMaterialSlot(faces[i], slots[i]);
    }
    mesh.endStep();
  }

  final (welded, _) = mergeByDistance(mesh);
  return welded;
}
