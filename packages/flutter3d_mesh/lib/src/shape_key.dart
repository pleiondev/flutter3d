import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'layout_plan.dart';

/// A named, full set of absolute vertex positions — a Blender-style shape
/// key — `mesh-61`'s own row.
///
/// **Full positions, not deltas**, per the row's own signature,
/// `ShapeKey(name, positions)`: every vertex the mesh has, at the shape this
/// key wants it at, not the difference from rest. [blend] is where a delta
/// actually gets taken, once, against whichever mesh is doing the blending
/// — the same shape Blender's own Shape Keys panel behaves as, which is the
/// reference this class's name borrows. This is the opposite convention
/// from `MorphTarget` (`flutter3d_geometry`), whose own `positions` field is
/// a *displacement* added to a base — the drawable, GPU-facing shape; this
/// one is the editable, authored shape, and `mesh-62`'s own row is the
/// conversion between the two.
///
/// **Deliberately outside `EditMesh`'s own private layer machinery.**
/// `EditMesh`'s journalled layers (`weights`, `joints`, `uv0`, ...) are a
/// fixed, closed set — see `MeshAttribute`'s own doc comment on why a sixth
/// is not a value somebody adds. A shape key is not fixed in count at all: a
/// face wants as many of these as somebody has sculpted, unbounded, which is
/// exactly the shape a caller-owned `Map<String, ShapeKey>` fits and
/// `EditMesh`'s array-of-fixed-layers does not. [grownTo] and [remappedBy]
/// are how a caller keeps one in step with `EditMesh`'s own growth and
/// compaction without either of them having to know about the other.
final class ShapeKey {
  ShapeKey(this.name, Float32List positions)
    : _positions = Float32List.fromList(positions) {
    if (_positions.length % 3 != 0) {
      throw ArgumentError(
        'positions must be three floats a vertex; got '
        '${_positions.length}, not a multiple of three.',
      );
    }
  }

  final String name;
  final Float32List _positions;

  int get vertexCount => _positions.length ~/ 3;

  /// Every vertex this key stores, three floats each, in one copy — for a
  /// caller (project-file persistence) that needs the whole array rather
  /// than one vertex at a time through [positionOf]. A copy, not a view
  /// over the same buffer, so nothing outside this class can mutate a key
  /// without going through [setPosition].
  Float32List get positions => Float32List.fromList(_positions);

  Vector3 positionOf(int vertex) => Vector3(
    _positions[vertex * 3],
    _positions[vertex * 3 + 1],
    _positions[vertex * 3 + 2],
  );

  void setPosition(int vertex, Vector3 position) {
    _positions[vertex * 3] = position.x;
    _positions[vertex * 3 + 1] = position.y;
    _positions[vertex * 3 + 2] = position.z;
  }

  /// This key, extended to [mesh]'s current slot count —
  /// `mesh-61`'s own "split применяется ко всем ключам": a vertex a
  /// topology edit (a loop cut, an extrusion) added since this key was
  /// captured reads, in this key, as wherever [mesh] itself currently has
  /// it. This key simply does not move a vertex it has never heard of,
  /// until somebody sculpts it there on purpose — the same "a layer that
  /// was never written answers with a neutral value" rule
  /// `attributes.dart`'s own doc comment states for every other per-vertex
  /// layer in this package.
  ///
  /// [EditMesh.vertexSlotCount], not [EditMesh.vertexCount]: this key is
  /// indexed by vertex *id*, which a tombstoned-but-not-yet-compacted
  /// vertex still holds a slot for, and [EditMesh.vertexCount] counts only
  /// the living.
  ///
  /// Returns this same instance, unchanged, when there is nothing to grow
  /// — the ordinary case, checked so a caller can call this after every
  /// edit without allocating a new key for a mesh that added nothing.
  ShapeKey grownTo(EditMesh mesh) {
    if (vertexCount >= mesh.vertexSlotCount) return this;
    final grown = Float32List(mesh.vertexSlotCount * 3);
    grown.setRange(0, _positions.length, _positions);
    final position = Vector3.zero();
    for (var v = vertexCount; v < mesh.vertexSlotCount; v++) {
      mesh.positionOf(v, position);
      grown[v * 3] = position.x;
      grown[v * 3 + 1] = position.y;
      grown[v * 3 + 2] = position.z;
    }
    return ShapeKey(name, grown);
  }

  /// This key reindexed the way [EditMesh.compact]'s own [IdRemap] says: a
  /// vertex the compaction dropped drops out of this key too, and a
  /// survivor lands at its new number — the other half of [grownTo], for
  /// the moment `EditMesh`'s own numbering changes instead of only
  /// growing.
  ///
  /// A vertex [remap] names past this key's own [vertexCount] — one added
  /// to the mesh after this key was last grown, so this key never learned
  /// about it — is skipped rather than read out of range; call [grownTo]
  /// first if that vertex's own position (not zero) is what should survive
  /// the remap.
  ShapeKey remappedBy(IdRemap remap) {
    var survivors = 0;
    for (final to in remap.vertices) {
      if (to != EditMesh.none) survivors++;
    }
    final result = Float32List(survivors * 3);
    for (var old = 0; old < remap.vertices.length; old++) {
      final to = remap.vertices[old];
      if (to == EditMesh.none || old >= vertexCount) continue;
      result[to * 3] = _positions[old * 3];
      result[to * 3 + 1] = _positions[old * 3 + 1];
      result[to * 3 + 2] = _positions[old * 3 + 2];
    }
    return ShapeKey(name, result);
  }

  /// [base]'s own current positions, blended with [keys] at [weights]
  /// (index-aligned, and the same length or this throws) — the standard
  /// shape-key formula: each key contributes its own *difference* from
  /// [base], scaled by its weight, summed rather than replacing it
  /// outright, so two keys at half weight each blend toward both
  /// expressions at once instead of only the last one applied winning
  /// outright.
  ///
  /// A key shorter than [base]'s own slot count — one nobody has
  /// [grownTo] since a later edit — contributes nothing to the vertices it
  /// does not cover, the same "no data, no effect" rule [grownTo] itself
  /// states, rather than throwing or reading out of range.
  static Float32List blend(
    EditMesh base,
    List<ShapeKey> keys,
    List<double> weights,
  ) {
    if (keys.length != weights.length) {
      throw ArgumentError(
        '${keys.length} keys but ${weights.length} weights.',
      );
    }

    final slots = base.vertexSlotCount;
    final out = Float32List(slots * 3);
    final position = Vector3.zero();
    for (var v = 0; v < slots; v++) {
      base.positionOf(v, position);
      out[v * 3] = position.x;
      out[v * 3 + 1] = position.y;
      out[v * 3 + 2] = position.z;
    }

    for (var k = 0; k < keys.length; k++) {
      final weight = weights[k];
      if (weight == 0.0) continue;
      final key = keys[k];
      final count = key.vertexCount < slots ? key.vertexCount : slots;
      for (var v = 0; v < count; v++) {
        base.positionOf(v, position);
        out[v * 3] += (key._positions[v * 3] - position.x) * weight;
        out[v * 3 + 1] += (key._positions[v * 3 + 1] - position.y) * weight;
        out[v * 3 + 2] += (key._positions[v * 3 + 2] - position.z) * weight;
      }
    }
    return out;
  }

  @override
  String toString() => 'ShapeKey($name, $vertexCount vertices)';
}

/// [keys] against [base], as [MorphTarget]s sized and ordered for [plan]'s
/// own GPU rows — `mesh-62`'s own row.
///
/// **A delta per GPU row, not per `EditMesh` vertex, and the two counts
/// differ.** A hard edge or a UV seam duplicates one vertex into several
/// rows through [MeshLayoutPlan.gpuVertexToVertex]; every one of those rows
/// has to carry the same delta; or a face would tear apart mid-blend, with
/// one of its corners following the shape and the other staying behind. A
/// [MorphTarget] built to the wrong count — `EditMesh.vertexSlotCount`
/// rather than [MeshLayoutPlan.vertexCount] — is refused by [MeshData]'s own
/// constructor, not by this function: see [MeshData.withMorphTargets]'s
/// `ArgumentError` for a target that does not cover the mesh.
///
/// **A delta, computed here, not read off the key.** [ShapeKey] stores full
/// positions — see its own class comment for why — and [MorphTarget] stores
/// the difference from the base [mesh], the form glTF carries and a shader
/// blends by adding. The subtraction happens once, at export, rather than
/// living in either type permanently.
///
/// Composes with [MeshLayoutPlan.toMeshData] rather than being folded into
/// it, the same way [MeshData.withMorphTargets] already composes with
/// tangent generation: `plan.toMeshData(mesh).withMorphTargets(...)`.
List<MorphTarget> shapeKeyMorphTargets(
  MeshLayoutPlan plan,
  EditMesh mesh,
  List<ShapeKey> keys,
) {
  final gpuVertexToVertex = plan.gpuVertexToVertex;
  final vertexCount = plan.vertexCount;
  return <MorphTarget>[
    for (final key in keys)
      _morphTargetOf(vertexCount, gpuVertexToVertex, mesh, key),
  ];
}

MorphTarget _morphTargetOf(
  int vertexCount,
  Int32List gpuVertexToVertex,
  EditMesh mesh,
  ShapeKey key,
) {
  final deltas = Float32List(vertexCount * 3);
  final base = Vector3.zero();
  for (var g = 0; g < vertexCount; g++) {
    final vertex = gpuVertexToVertex[g];
    mesh.positionOf(vertex, base);
    final shaped = key.positionOf(vertex);
    deltas[g * 3] = shaped.x - base.x;
    deltas[g * 3 + 1] = shaped.y - base.y;
    deltas[g * 3 + 2] = shaped.z - base.z;
  }
  return MorphTarget(vertexCount: vertexCount, positions: deltas, name: key.name);
}
