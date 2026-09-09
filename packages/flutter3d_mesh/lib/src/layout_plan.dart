/// The arrangement a mesh takes on the way to a GPU, worked out once and kept.
///
/// **The expensive half of a conversion is deciding, not copying.** Turning an
/// `EditMesh` into something drawable means cutting every face into triangles,
/// working out a normal at every corner, and then deciding which corners are
/// the same GPU vertex — and only after all of that does anything get written.
/// Dragging a vertex changes none of those decisions: the topology is what it
/// was, the fans are what they were, and the only thing that moved is a
/// handful of numbers. Measured on a lattice of 200 000 triangles, building
/// the plan is 68 ms, rewriting every row from it is 6 ms, and rewriting the
/// rows of the forty vertices somebody is dragging is 1.3 µs — see
/// `doc/model-editor.md` §6 for the machine and the date. That is the
/// difference between a drag that stutters and a drag that does not.
///
/// So the plan is built once and asked twice: [fillVertices] writes every row
/// against the mesh as it now is, and [fillVerticesOf] writes only the rows of
/// the vertices somebody names. Neither hashes anything — the plan already
/// knows which row belongs to which corner.
///
/// **What invalidates it.** Anything that changes the topology, the flags or
/// the seams: adding or deleting a face, marking an edge sharp, moving a UV
/// onto a different island. Moving a vertex does not, and neither does moving
/// all of them. The plan does not police this, because a check on every fill
/// would cost as much as the fill.
///
/// **Corner normals are the plan's, not the mesh's.** A vertex that moves
/// changes the normals of every face around it, so a partial fill is only as
/// correct as the normals in [normals] — a caller that moved something and
/// wants shading to follow rebuilds those first, and one dragging a whole
/// selection through a gizmo usually does it once at the end.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'normals.dart';
import 'triangulate.dart';

/// How an [EditMesh] maps onto GPU vertices and triangles.
final class MeshLayoutPlan {
  /// The normals the plan was built with, and the ones [fillVertices] writes.
  final MeshNormals normals = MeshNormals();

  final FaceTriangulator _cutter = FaceTriangulator();
  final List<Vector3> _loop = <Vector3>[];

  VertexLayout _layout = VertexLayout.standard;
  int _vertexCount = 0;
  int _triangleCount = 0;
  int _stride = 0;
  bool _fanned = false;

  // Where each attribute sits in a row, or -1. Read once here rather than by
  // name inside the fill, which is a string compare per vertex per frame.
  int _positionAt = -1;
  int _normalAt = -1;
  int _texcoordAt = -1;
  int _colourAt = -1;
  int _jointsAt = -1;
  int _weightsAt = -1;

  Int32List _cornerOf = Int32List(0);
  Int32List _vertexOf = Int32List(0);
  Int32List _rowOfCorner = Int32List(0);
  Int32List _nextInFan = Int32List(0);
  Int32List _firstOfFan = Int32List(0);
  Int32List _faceOfTriangle = Int32List(0);
  Uint32List _indices = Uint32List(0);
  Int32List _rowsStart = Int32List(0);
  Int32List _rowsOfVertex = Int32List(0);

  /// The layout a row is written in.
  VertexLayout get layout => _layout;

  /// How many GPU vertices the plan makes, which is at most one per corner.
  int get vertexCount => _vertexCount;

  /// Floats in one row.
  int get floatsPerVertex => _stride;

  int get triangleCount => _triangleCount;

  /// Three indices per triangle, into the rows.
  Uint32List get indices => _indices;

  /// Which half-edge each row came from.
  Int32List get gpuVertexToCorner => _cornerOf;

  /// Which mesh vertex each row came from.
  ///
  /// What a picked GPU vertex answers with, and what [fillVerticesOf] looks
  /// rows up by.
  Int32List get gpuVertexToVertex => _vertexOf;

  /// Which face each triangle came from.
  ///
  /// **The map a viewport needs and a `MeshData` throws away.** Picking hits a
  /// triangle; selecting, extruding and assigning a material all happen to a
  /// face, and after a five-sided face has been cut into three triangles there
  /// is nothing in the drawable mesh that says they were ever one thing.
  Int32List get triangleToFace => _faceOfTriangle;

  /// Whether any face had to be fanned because it could not be cut properly.
  bool get fannedAnyFace => _fanned;

  /// The row [halfEdge] was put in, or [EditMesh.none] if it is not in the plan.
  int rowOfCorner(int halfEdge) => _rowOfCorner[halfEdge];

  /// Works out the arrangement for [mesh].
  ///
  /// With [materialSlot] given, only faces carrying that slot are planned —
  /// which is how a model with several materials becomes several drawable
  /// meshes over one editable one, since a draw call has one material.
  void build(
    EditMesh mesh, {
    VertexLayout layout = VertexLayout.standard,
    double smoothAngle = MeshNormals.defaultSmoothAngle,
    int? materialSlot,
  }) {
    _layout = layout;
    _stride = layout.floatsPerVertex;
    _positionAt = layout.floatOffsetOf(VertexLayout.position.name);
    _normalAt = layout.floatOffsetOf(VertexLayout.normal.name);
    _texcoordAt = layout.floatOffsetOf(VertexLayout.texcoord.name);
    _colourAt = layout.floatOffsetOf(VertexLayout.color.name);
    _jointsAt = layout.floatOffsetOf(VertexLayout.joints.name);
    _weightsAt = layout.floatOffsetOf(VertexLayout.weights.name);

    normals.build(mesh, smoothAngle: smoothAngle);
    _resize(mesh);
    _countTriangles(mesh, materialSlot);
    _mergeCorners(mesh, materialSlot);
    _cutFaces(mesh, materialSlot);
    _indexRowsByVertex(mesh);
  }

  bool _planned(EditMesh mesh, int face, int? materialSlot) =>
      mesh.isFaceAlive(face) &&
      (materialSlot == null || mesh.materialSlotOf(face) == materialSlot);

  void _resize(EditMesh mesh) {
    final corners = mesh.halfEdgeSlotCount;
    if (_rowOfCorner.length < corners) {
      _rowOfCorner = Int32List(corners);
      _firstOfFan = Int32List(corners);
      _cornerOf = Int32List(corners);
      _vertexOf = Int32List(corners);
      _nextInFan = Int32List(corners);
    }
    _rowOfCorner.fillRange(0, corners, EditMesh.none);
    _firstOfFan.fillRange(0, corners, EditMesh.none);
    _vertexCount = 0;
    _fanned = false;
  }

  void _countTriangles(EditMesh mesh, int? materialSlot) {
    var triangles = 0;
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!_planned(mesh, face, materialSlot)) continue;
      triangles += mesh.valencyOf(face) - 2;
    }
    _triangleCount = triangles;
    if (_indices.length < triangles * 3) {
      _indices = Uint32List(triangles * 3);
      _faceOfTriangle = Int32List(triangles);
    }
  }

  /// Decides which corners are one GPU vertex.
  ///
  /// **Two corners merge when they share a normal and everything a row carries
  /// besides it.** The normal is the whole reason a cube needs twenty-four
  /// vertices for eight corners, and the fans [MeshNormals] already worked out
  /// answer that half for free. What is left is the per-corner attributes: a UV
  /// seam runs down a cylinder whose sides are perfectly smooth, and the two
  /// corners either side of it have the same normal and different texture
  /// coordinates, so they cannot be one vertex.
  ///
  /// **No hash table.** The candidates for a corner are the rows already made
  /// for its own fan, which is a handful — six on an ordinary vertex — so they
  /// hang off the fan as a chain and are walked. A map keyed on a normal, a UV
  /// and a colour would be an allocation and a hash per corner of every mesh
  /// that is ever converted, to search a list of six.
  void _mergeCorners(EditMesh mesh, int? materialSlot) {
    final uv = Vector2.zero();
    final other = Vector2.zero();
    final colour = Vector4.zero();
    final otherColour = Vector4.zero();
    final hasUv = mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0);
    final hasColour = mesh.hasLayer(MeshDomain.corner, MeshAttribute.colour);

    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!_planned(mesh, face, materialSlot)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        final fan = normals.groupOf(half);
        if (hasUv) mesh.uvOf(half, uv);
        if (hasColour) mesh.colourOf(half, colour);

        var row = _firstOfFan[fan];
        while (row != EditMesh.none) {
          final against = _cornerOf[row];
          final sameUv =
              !hasUv || (mesh.uvOf(against, other)..sub(uv)).length2 == 0;
          final sameColour =
              !hasColour ||
              (mesh.colourOf(against, otherColour)..sub(colour)).length2 == 0;
          if (sameUv && sameColour) {
            _rowOfCorner[half] = row;
            return;
          }
          row = _nextInFan[row];
        }

        final made = _vertexCount++;
        _cornerOf[made] = half;
        _vertexOf[made] = mesh.originOf(half);
        _nextInFan[made] = _firstOfFan[fan];
        _firstOfFan[fan] = made;
        _rowOfCorner[half] = made;
      });
    }
  }

  void _cutFaces(EditMesh mesh, int? materialSlot) {
    var triangle = 0;
    final corners = <int>[];
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!_planned(mesh, face, materialSlot)) continue;
      corners.clear();
      _loop.clear();
      mesh.forEachHalfEdge(face, (int half) {
        corners.add(_rowOfCorner[half]);
        _loop.add(mesh.positionOf(mesh.originOf(half)));
      });
      _cutter.triangulate(_loop, (int a, int b, int c) {
        _indices[triangle * 3] = corners[a];
        _indices[triangle * 3 + 1] = corners[b];
        _indices[triangle * 3 + 2] = corners[c];
        _faceOfTriangle[triangle] = face;
        triangle++;
      });
      if (_cutter.fannedLastFace) _fanned = true;
    }
    // A face that could not be cut still yields `valency - 2` triangles, so the
    // count worked out ahead of time holds even then.
    assert(triangle == _triangleCount);
  }

  /// Which rows each mesh vertex owns, as a start table over one flat array.
  ///
  /// A list per vertex would be one growable object per vertex of the document,
  /// alive as long as the plan; this is two `Int32List`s and the same answer.
  void _indexRowsByVertex(EditMesh mesh) {
    final vertices = mesh.vertexSlotCount;
    if (_rowsStart.length < vertices + 1) _rowsStart = Int32List(vertices + 1);
    if (_rowsOfVertex.length < _vertexCount) {
      _rowsOfVertex = Int32List(_vertexCount);
    }
    _rowsStart.fillRange(0, vertices + 1, 0);
    for (var row = 0; row < _vertexCount; row++) {
      _rowsStart[_vertexOf[row] + 1]++;
    }
    for (var vertex = 0; vertex < vertices; vertex++) {
      _rowsStart[vertex + 1] += _rowsStart[vertex];
    }
    // Filled with a moving cursor over a copy of the starts, so the starts
    // themselves survive to be read back.
    final cursor = Int32List(vertices);
    for (var vertex = 0; vertex < vertices; vertex++) {
      cursor[vertex] = _rowsStart[vertex];
    }
    for (var row = 0; row < _vertexCount; row++) {
      _rowsOfVertex[cursor[_vertexOf[row]]++] = row;
    }
  }

  /// Writes every row into [into], which must hold [vertexCount] of them.
  void fillVertices(EditMesh mesh, Float32List into) {
    for (var row = 0; row < _vertexCount; row++) {
      _writeRow(mesh, into, row);
    }
  }

  /// Writes only the rows belonging to [vertices], and says how many that was.
  ///
  /// **The point of the plan.** Dragging forty vertices of a 200 000-face mesh
  /// touches forty rows; rebuilding the whole buffer touches six hundred
  /// thousand, and does the merge and the triangulation again on the way.
  int fillVerticesOf(EditMesh mesh, Float32List into, Iterable<int> vertices) {
    var written = 0;
    for (final vertex in vertices) {
      if (vertex < 0 || vertex + 1 >= _rowsStart.length) continue;
      for (var at = _rowsStart[vertex]; at < _rowsStart[vertex + 1]; at++) {
        _writeRow(mesh, into, _rowsOfVertex[at]);
        written++;
      }
    }
    return written;
  }

  void _writeRow(EditMesh mesh, Float32List into, int row) {
    final at = row * _stride;
    final corner = _cornerOf[row];
    final vertex = _vertexOf[row];
    if (_positionAt >= 0) {
      final from = vertex * 3;
      final positions = mesh.positions;
      into[at + _positionAt] = positions[from];
      into[at + _positionAt + 1] = positions[from + 1];
      into[at + _positionAt + 2] = positions[from + 2];
    }
    if (_normalAt >= 0) {
      final corners = normals.cornerNormals;
      into[at + _normalAt] = corners[corner * 3];
      into[at + _normalAt + 1] = corners[corner * 3 + 1];
      into[at + _normalAt + 2] = corners[corner * 3 + 2];
    }
    if (_texcoordAt >= 0) {
      final uv = mesh.uvOf(corner);
      into[at + _texcoordAt] = uv.x;
      into[at + _texcoordAt + 1] = uv.y;
    }
    if (_colourAt >= 0) {
      final colour = mesh.colourOf(corner);
      into[at + _colourAt] = colour.x;
      into[at + _colourAt + 1] = colour.y;
      into[at + _colourAt + 2] = colour.z;
      into[at + _colourAt + 3] = colour.w;
    }
    if (_jointsAt >= 0 || _weightsAt >= 0) {
      final skin = mesh.skinOf(vertex);
      for (var i = 0; i < 4; i++) {
        if (_jointsAt >= 0) into[at + _jointsAt + i] = skin.joints[i];
        if (_weightsAt >= 0) into[at + _weightsAt + i] = skin.weights[i];
      }
    }
  }

  /// A buffer of the right size for [fillVertices], reusing [into] if it fits.
  Float32List rows([Float32List? into]) =>
      into != null && into.length >= _vertexCount * _stride
      ? into
      : Float32List(_vertexCount * _stride);

  /// The drawable mesh this plan describes, filled from [mesh] as it now is.
  ///
  /// Passing [into] reuses a buffer, which is what a viewport redrawing every
  /// frame wants — and it means the `MeshData` handed back last time now holds
  /// the new numbers, so a caller keeping the old one is keeping a view rather
  /// than a copy.
  MeshData toMeshData(EditMesh mesh, {Float32List? into}) {
    final buffer = rows(into);
    fillVertices(mesh, buffer);
    return MeshData(
      layout: _layout,
      vertices: buffer.length == _vertexCount * _stride
          ? buffer
          : Float32List.sublistView(buffer, 0, _vertexCount * _stride),
      indices: _indices.length == _triangleCount * 3
          ? _indices
          : Uint32List.sublistView(_indices, 0, _triangleCount * 3),
    );
  }
}
