/// The corner table — how Draco holds a triangle mesh while it decodes one.
///
/// **Three corners a face, and everything else is arithmetic on them.** Corner
/// `c` belongs to face `c ~/ 3`; the next corner round that face is `c + 1`
/// unless that leaves the face, and the only stored topology is which corner
/// sits *opposite* across each edge. Walking round a vertex, finding the two
/// neighbouring faces, asking whether a vertex is on a boundary — all of it is
/// `next`, `previous` and `opposite` composed, which is why the edgebreaker
/// decoder can build a mesh one face at a time by writing two arrays.
///
/// Follows `mesh/corner_table.h` and `mesh/mesh_attribute_corner_table.cc` in
/// the reference decoder. Only what decoding touches is here: the reference
/// also builds a table *from* faces, breaks non-manifold edges and caches
/// valences, and an encoder needs those where a decoder does not.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';

/// No corner, no vertex, no face. The reference spells it `kInvalid…Index`;
/// every navigation call passes it through, which is what lets a walk off the
/// edge of the mesh end a loop rather than index out of it.
const int dracoInvalid = -1;

/// What the traversers and the predictors need from a table.
///
/// Two things implement it and they disagree on purpose: [CornerTable] is the
/// mesh as the positions see it, and [AttributeCornerTable] is the same faces
/// with some edges declared *seams*, across which `opposite` answers "nothing".
/// A UV island ends at a seam even though the surface carries on, and a
/// predictor that reached across one would predict a texture coordinate from
/// the far side of the atlas.
abstract base class CornerTopology {
  int get vertexCount;
  int get faceCount;
  int get cornerCount => faceCount * 3;

  int opposite(int corner);
  int vertex(int corner);
  int leftMostCorner(int vertex);

  int next(int corner) => corner == dracoInvalid
      ? dracoInvalid
      : (corner % 3 == 2 ? corner - 2 : corner + 1);

  int previous(int corner) => corner == dracoInvalid
      ? dracoInvalid
      : (corner % 3 == 0 ? corner + 2 : corner - 1);

  /// The corner at the same vertex in the face to the right, or
  /// [dracoInvalid] past a boundary.
  int swingRight(int corner) => previous(opposite(previous(corner)));

  /// The corner at the same vertex in the face to the left.
  int swingLeft(int corner) => next(opposite(next(corner)));

  /// The tip of the face across the edge to the left of [corner].
  int leftCorner(int corner) => opposite(previous(corner));

  int rightCorner(int corner) => opposite(next(corner));

  /// Whether [vertex]'s fan of faces is open. The left-most corner is kept
  /// left-most exactly so that this is one swing rather than a walk.
  bool isOnBoundary(int vertex) =>
      swingLeft(leftMostCorner(vertex)) == dracoInvalid;
}

/// The mesh's own connectivity, written one face at a time by the edgebreaker
/// decoder.
final class CornerTable extends CornerTopology {
  /// An empty table of [faceCount] faces: no corner has a vertex yet, no edge
  /// has anything across it, and there are no vertices until [addVertex] makes
  /// them — `CornerTable::Reset`.
  CornerTable(this.faceCount, int vertexCapacity)
    : _cornerToVertex = Int32List(faceCount * 3)
        ..fillRange(0, faceCount * 3, dracoInvalid),
      _opposite = Int32List(faceCount * 3)
        ..fillRange(0, faceCount * 3, dracoInvalid),
      _vertexCorners = Int32List(vertexCapacity);

  @override
  final int faceCount;

  final Int32List _cornerToVertex;
  final Int32List _opposite;

  /// Sized for the most vertices the stream says it can make. The reference
  /// grows a vector; here the bound is known before the first symbol is read —
  /// the encoded vertices plus one per split — and outgrowing it means the
  /// stream lied, which [addVertex] turns into a refusal.
  final Int32List _vertexCorners;
  int _vertexCount = 0;

  @override
  int get vertexCount => _vertexCount;

  @override
  int opposite(int corner) =>
      corner == dracoInvalid ? dracoInvalid : _opposite[corner];

  @override
  int vertex(int corner) =>
      corner == dracoInvalid ? dracoInvalid : _cornerToVertex[corner];

  @override
  int leftMostCorner(int vertex) => _vertexCorners[vertex];

  int addVertex() {
    if (_vertexCount >= _vertexCorners.length) {
      throw const DracoException(
        'the connectivity makes more vertices than the stream declared',
      );
    }
    _vertexCorners[_vertexCount] = dracoInvalid;
    return _vertexCount++;
  }

  /// Both directions at once — an edge has two sides and the decoder never
  /// wants only one of them set.
  void setOpposites(int a, int b) {
    _opposite[a] = b;
    _opposite[b] = a;
  }

  void mapCornerToVertex(int corner, int vertex) =>
      _cornerToVertex[corner] = vertex;

  void setLeftMostCorner(int vertex, int corner) =>
      _vertexCorners[vertex] = corner;

  /// A vertex no corner names any more, which is what a split leaves behind
  /// when it merges two vertices into one.
  void makeVertexIsolated(int vertex) => _vertexCorners[vertex] = dracoInvalid;
}

/// The same faces, with seams — `MeshAttributeCornerTable`.
///
/// **An attribute has its own idea of what a vertex is.** A cube has eight
/// positions and twenty-four normals; on the corner table of the positions one
/// vertex is shared by three faces, and for the normals those are three
/// vertices that happen to sit in the same place. The stream says which edges
/// an attribute breaks across, and from those this works out the attribute's
/// own vertices: walk each position vertex's fan, and start a new attribute
/// vertex every time the walk crosses a seam.
final class AttributeCornerTable extends CornerTopology {
  AttributeCornerTable(this.base)
    : _isEdgeOnSeam = List<bool>.filled(base.cornerCount, false),
      _isVertexOnSeam = List<bool>.filled(base.vertexCount, false),
      _cornerToVertex = Int32List(base.cornerCount)
        ..fillRange(0, base.cornerCount, dracoInvalid);

  final CornerTable base;
  final List<bool> _isEdgeOnSeam;
  final List<bool> _isVertexOnSeam;
  final Int32List _cornerToVertex;
  final List<int> _vertexToLeftMostCorner = <int>[];

  @override
  int get vertexCount => _vertexToLeftMostCorner.length;

  @override
  int get faceCount => base.faceCount;

  /// Nothing, across a seam — the one line that makes this a different mesh.
  @override
  int opposite(int corner) => corner == dracoInvalid || _isEdgeOnSeam[corner]
      ? dracoInvalid
      : base.opposite(corner);

  @override
  int vertex(int corner) =>
      corner == dracoInvalid ? dracoInvalid : _cornerToVertex[corner];

  @override
  int leftMostCorner(int vertex) => _vertexToLeftMostCorner[vertex];

  /// Whether the *position* vertex at [corner] touches any seam of this
  /// attribute.
  bool isCornerOnSeam(int corner) => _isVertexOnSeam[base.vertex(corner)];

  /// Declares the edge opposite [corner] a seam, from both of its faces.
  void addSeamEdge(int corner) {
    _markSeam(corner);
    final across = base.opposite(corner);
    if (across != dracoInvalid) _markSeam(across);
  }

  void _markSeam(int corner) {
    _isEdgeOnSeam[corner] = true;
    _isVertexOnSeam[base.vertex(base.next(corner))] = true;
    _isVertexOnSeam[base.vertex(base.previous(corner))] = true;
  }

  /// Works the attribute's vertices out of the seams — `RecomputeVertices`.
  ///
  /// For each position vertex: if it touches a seam, swing left *within the
  /// attribute* until the fan ends, so the walk starts at a seam rather than
  /// in the middle of an island; then swing right round the *mesh's* fan,
  /// opening a new attribute vertex at every seam crossed. The two swings
  /// being on different tables is not a slip — the first must stop at seams
  /// and the second must carry on through them.
  void recomputeVertices() {
    _vertexToLeftMostCorner.clear();
    for (var v = 0; v < base.vertexCount; v++) {
      final c = base.leftMostCorner(v);
      if (c == dracoInvalid) continue;

      var attributeVertex = _vertexToLeftMostCorner.length;
      var firstCorner = c;
      if (_isVertexOnSeam[v]) {
        var walk = swingLeft(firstCorner);
        while (walk != dracoInvalid) {
          firstCorner = walk;
          walk = swingLeft(walk);
          if (walk == c) {
            throw const DracoException(
              'an attribute seam vertex has a closed fan, which a seam '
              'cannot leave behind',
            );
          }
        }
      }
      _cornerToVertex[firstCorner] = attributeVertex;
      _vertexToLeftMostCorner.add(firstCorner);

      var walk = base.swingRight(firstCorner);
      while (walk != dracoInvalid && walk != firstCorner) {
        if (_isEdgeOnSeam[base.next(walk)]) {
          attributeVertex = _vertexToLeftMostCorner.length;
          _vertexToLeftMostCorner.add(walk);
        }
        _cornerToVertex[walk] = attributeVertex;
        walk = base.swingRight(walk);
      }
    }
  }
}
