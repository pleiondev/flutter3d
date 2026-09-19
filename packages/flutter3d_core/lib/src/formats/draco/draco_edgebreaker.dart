/// Edgebreaker connectivity — the half of `gfx-82n` that real files need.
///
/// **What the encoder writes unless told otherwise.** Sequential connectivity
/// is three indices a face; edgebreaker is about two *bits* a face, and every
/// exporter that reaches for Draco reaches for it to get that. The encoder
/// walks the surface one triangle at a time and writes, for each, one of five
/// letters saying how the triangle it just entered touches what it has already
/// seen: **C** — the tip vertex is new and interior; **R** and **L** — the
/// face to the right or the left is already done; **E** — both are, the walk
/// ends here; **S** — neither is, the walk *splits* and one branch waits on a
/// stack. No vertex index is ever written. The letters are enough, because a
/// decoder replaying them builds the same surface in the same order.
///
/// **Replayed backwards.** The reference decoder reads the letters in reverse
/// and grows the mesh from the *last* face the encoder visited, which turns
/// every letter into a purely local operation on an open boundary: C closes a
/// fan round a vertex, R and L glue a new face to one edge and make one new
/// vertex, E drops a free triangle, S sews two boundaries together. That is
/// the loop in [_decodeSymbols], transcribed from
/// `mesh_edgebreaker_decoder_impl.cc` operation for operation — the order the
/// corners of each new face are numbered in is part of the format, since the
/// attributes that follow are stored in an order derived from it.
///
/// **Two ways of storing the letters, both decoded.** The *standard* traversal
/// packs them as one or three bits each. The *valence* traversal — what the
/// encoder switches to below speed five on a mesh of a thousand faces, and so
/// what Blender writes at its default compression level — entropy-codes them
/// in six contexts chosen by how many faces already meet at the vertex the
/// walk is about to turn round, because a vertex that already has six faces is
/// about to be closed and one that has two is not. The third, *predictive*, was
/// retired before bitstream 2.2 and is refused by name.
///
/// **Bitstream 2.2 only, and it says so.** Earlier 2.x streams lay the same
/// data out differently — the split events after the symbols rather than
/// before, the start faces as raw bits — and nothing has written one since
/// 2017. Supporting them would be a second decoder checked against no file.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';
import 'draco_corner_table.dart';

/// What the connectivity section decodes to.
final class EdgebreakerConnectivity {
  const EdgebreakerConnectivity({
    required this.corners,
    required this.attributeTables,
    required this.cornerToPoint,
    required this.pointCount,
  });

  final CornerTable corners;

  /// One per *attribute data* the stream declares — a connectivity with seams,
  /// for whichever attribute decoder later claims it by index.
  final List<AttributeCornerTable> attributeTables;

  /// The point at each corner, which is the index buffer.
  ///
  /// **A point is not a vertex.** A vertex is a place on the surface; a point
  /// is a distinct combination of attribute values, which is what a GPU calls
  /// a vertex. Where a UV seam runs through a position vertex that one vertex
  /// is two points, and this is where they are told apart.
  final Uint32List cornerToPoint;
  final int pointCount;
}

Never _fail(String message) => throw DracoException(message);

/// The five letters, as the bit patterns the standard traversal stores.
const int _topologyC = 0;
const int _topologyS = 1;
const int _topologyL = 3;
const int _topologyR = 5;
const int _topologyE = 7;

/// `edge_breaker_symbol_to_topology_id`: the valence traversal numbers the
/// letters 0 to 4 for its entropy coder rather than storing the bit patterns.
const List<int> _symbolToTopology = <int>[
  _topologyC,
  _topologyS,
  _topologyL,
  _topologyR,
  _topologyE,
];

/// A face a split left waiting, and which of its two free edges the other
/// branch will come back to.
final class _TopologySplit {
  const _TopologySplit({
    required this.sourceSymbol,
    required this.splitSymbol,
    required this.rightEdge,
  });
  final int sourceSymbol;
  final int splitSymbol;
  final bool rightEdge;
}

/// Reads the connectivity, leaving [buffer] at the attribute section.
EdgebreakerConnectivity decodeEdgebreakerConnectivity(DracoBuffer buffer) {
  final traversalType = buffer.readUint8();

  final encodedVertices = buffer.readVarUint();
  final faceCount = buffer.readVarUint();
  final attributeDataCount = buffer.readUint8();
  final symbolCount = buffer.readVarUint();
  final splitSymbolCount = buffer.readVarUint();

  // The same sanity checks the reference makes before allocating anything, for
  // the same reason: every one of these sizes an array.
  if (encodedVertices > faceCount * 3) {
    _fail('more vertices ($encodedVertices) than $faceCount faces can have');
  }
  if (faceCount < symbolCount || faceCount > symbolCount + symbolCount ~/ 3) {
    _fail('$faceCount faces cannot come from $symbolCount symbols');
  }
  if (splitSymbolCount > symbolCount) {
    _fail('more split symbols than symbols');
  }
  if (faceCount > buffer.remaining * 4096) {
    // Not a reference check. An entropy-coded run of one repeated letter costs
    // almost nothing, so there is no honest floor on bytes per face — but a
    // header that claims millions of faces in front of a handful of bytes is a
    // lie told to make the decoder allocate.
    _fail('$faceCount faces do not fit in ${buffer.remaining} bytes');
  }

  final vertexCapacity = encodedVertices + splitSymbolCount;
  final corners = CornerTable(faceCount, vertexCapacity);
  final splits = _decodeTopologySplits(buffer, faceCount);

  final _Traversal traversal = switch (traversalType) {
    0 => _StandardTraversal(buffer, attributeDataCount),
    2 => _ValenceTraversal(buffer, attributeDataCount, corners, vertexCapacity),
    1 => _fail(
      'edgebreaker traversal 1 is the predictive one, which was retired '
      'before bitstream 2.2 and which no current encoder writes',
    ),
    _ => _fail('unknown edgebreaker traversal type $traversalType'),
  };

  final isVertexHole = List<bool>.filled(vertexCapacity, true);
  final connectivityVertices = _decodeSymbols(
    corners: corners,
    traversal: traversal,
    splits: splits,
    symbolCount: symbolCount,
    isVertexHole: isVertexHole,
    removeIsolatedVertices: attributeDataCount == 0,
  );

  // **Seams, one bit an interior edge an attribute.** Each edge is asked about
  // once, from whichever of its two faces comes first; a boundary edge is not
  // asked about at all, since nothing is across it to agree with.
  final seamCorners = <List<int>>[
    for (var i = 0; i < attributeDataCount; i++) <int>[],
  ];
  if (attributeDataCount > 0) {
    for (var first = 0; first < corners.cornerCount; first += 3) {
      for (final corner in <int>[first, first + 1, first + 2]) {
        final across = corners.opposite(corner);
        if (across == dracoInvalid) {
          for (final seams in seamCorners) {
            seams.add(corner);
          }
          continue;
        }
        if (across ~/ 3 < first ~/ 3) continue;
        for (var i = 0; i < attributeDataCount; i++) {
          if (traversal.readAttributeSeam(i)) seamCorners[i].add(corner);
        }
      }
    }
  }

  final attributeTables = <AttributeCornerTable>[
    for (final seams in seamCorners)
      AttributeCornerTable(corners)
        ..addSeams(seams)
        ..recomputeVertices(),
  ];

  final (cornerToPoint, pointCount) = attributeTables.isEmpty
      ? (
          Uint32List.fromList(<int>[
            for (var c = 0; c < corners.cornerCount; c++) corners.vertex(c),
          ]),
          connectivityVertices,
        )
      : _assignPointsToCorners(corners, attributeTables, isVertexHole);

  return EdgebreakerConnectivity(
    corners: corners,
    attributeTables: attributeTables,
    cornerToPoint: cornerToPoint,
    pointCount: pointCount,
  );
}

extension on AttributeCornerTable {
  void addSeams(List<int> corners) {
    for (final corner in corners) {
      addSeamEdge(corner);
    }
  }
}

/// `DecodeHoleAndTopologySplitEvents`, as bitstream 2.2 lays it out.
///
/// **What a split event is for.** An S merges the walk with a branch that was
/// left waiting — but when the surface has a *handle*, the branch it meets is
/// not the one on top of the stack, it is some face from much earlier. The
/// encoder notices and records which face and which of its edges; without
/// these a torus decodes as a sphere with a slit in it.
List<_TopologySplit> _decodeTopologySplits(DracoBuffer buffer, int faceCount) {
  final count = buffer.readVarUint();
  if (count == 0) return const <_TopologySplit>[];
  if (count > faceCount) _fail('more topology splits than faces');

  // Source ids are delta coded against the previous event, split ids against
  // their own source — both small numbers, which is the point.
  final ids = <(int, int)>[];
  var lastSource = 0;
  for (var i = 0; i < count; i++) {
    final source = lastSource + buffer.readVarUint();
    final delta = buffer.readVarUint();
    if (delta > source) _fail('a topology split points before the first face');
    ids.add((source, source - delta));
    lastSource = source;
  }

  buffer.startBitDecoding();
  final splits = <_TopologySplit>[
    for (final (source, split) in ids)
      _TopologySplit(
        sourceSymbol: source,
        splitSymbol: split,
        rightEdge: buffer.readBits(1) == 1,
      ),
  ];
  buffer.endBitDecoding();
  return splits;
}

/// Where the letters come from, and the side channels that ride with them.
abstract base class _Traversal {
  /// Start faces first, then one seam stream per attribute data: both
  /// traversals store them in this order and with this coder.
  void readSideChannels(DracoBuffer buffer, int attributeDataCount) {
    _startFaces = RAnsBitDecoder(buffer);
    _attributeSeams = <RAnsBitDecoder>[
      for (var i = 0; i < attributeDataCount; i++) RAnsBitDecoder(buffer),
    ];
  }

  late final RAnsBitDecoder _startFaces;
  late final List<RAnsBitDecoder> _attributeSeams;

  int readSymbol();

  /// Whether a component's first face was interior, and so not among the
  /// letters: a closed surface has one face no walk ever *entered*.
  bool readStartFaceIsInterior() => _startFaces.readBit();

  bool readAttributeSeam(int attribute) => _attributeSeams[attribute].readBit();

  void newActiveCorner(int corner) {}
  void mergeVertices(int destination, int source) {}
}

/// `MeshEdgebreakerTraversalDecoder`: one bit for C, three for the rest.
final class _StandardTraversal extends _Traversal {
  _StandardTraversal(DracoBuffer buffer, int attributeDataCount) {
    // The symbols are a bit run with its length in front, and everything else
    // starts after it — so they get a cursor of their own, and the main one
    // steps over them.
    final size = buffer.readVarUint();
    if (size > buffer.remaining) _fail('the symbol run runs past the end');
    _symbols = DracoBuffer(buffer.bytes, buffer.position)..startBitDecoding();
    buffer.position += size;
    readSideChannels(buffer, attributeDataCount);
  }

  late final DracoBuffer _symbols;

  @override
  int readSymbol() {
    final first = _symbols.readBits(1);
    return first == _topologyC ? first : first | (_symbols.readBits(2) << 1);
  }
}

/// `MeshEdgebreakerTraversalValenceDecoder`.
///
/// The letter is drawn from one of six pre-decoded runs, picked by the valence
/// — clamped to 2..7 — of the vertex the walk turns round next. The decoder
/// therefore has to keep the same running count of faces per vertex the
/// encoder kept, updated per letter in [newActiveCorner]; get one increment
/// wrong and every later letter comes from the wrong run.
final class _ValenceTraversal extends _Traversal {
  _ValenceTraversal(
    DracoBuffer buffer,
    int attributeDataCount,
    this._corners,
    int vertexCapacity,
  ) : _valences = Int32List(vertexCapacity) {
    readSideChannels(buffer, attributeDataCount);
    for (var context = 0; context <= _maxValence - _minValence; context++) {
      final count = buffer.readVarUint();
      if (count > _corners.faceCount) {
        _fail('a valence context holds more symbols than there are faces');
      }
      final symbols = count > 0
          ? decodeSymbols(buffer, count, 1)
          : Uint32List(0);
      _contextSymbols.add(symbols);
      // Read from the back: the encoder wrote them in its order, and this
      // replays the walk in reverse.
      _contextCursor.add(count);
    }
  }

  static const int _minValence = 2;
  static const int _maxValence = 7;

  final CornerTable _corners;
  final Int32List _valences;
  final List<Uint32List> _contextSymbols = <Uint32List>[];
  final List<int> _contextCursor = <int>[];
  int _lastSymbol = dracoInvalid;
  int _activeContext = dracoInvalid;

  @override
  int readSymbol() {
    // Before any face exists there is no vertex to take a valence from, and
    // the first letter of a reversed walk is always an E.
    if (_activeContext == dracoInvalid) return _lastSymbol = _topologyE;
    final at = --_contextCursor[_activeContext];
    if (at < 0) _fail('a valence context ran out of symbols');
    final symbol = _contextSymbols[_activeContext][at];
    if (symbol > 4) _fail('valence symbol $symbol is not one of the five');
    return _lastSymbol = _symbolToTopology[symbol];
  }

  @override
  void newActiveCorner(int corner) {
    final next = _corners.next(corner);
    final previous = _corners.previous(corner);
    final (int tip, int atNext, int atPrevious) = switch (_lastSymbol) {
      _topologyC || _topologyS => (0, 1, 1),
      _topologyR => (1, 1, 2),
      _topologyL => (1, 2, 1),
      _topologyE => (2, 2, 2),
      _ => (0, 0, 0),
    };
    _valences[_corners.vertex(corner)] += tip;
    _valences[_corners.vertex(next)] += atNext;
    _valences[_corners.vertex(previous)] += atPrevious;

    _activeContext =
        _valences[_corners.vertex(next)].clamp(_minValence, _maxValence) -
        _minValence;
  }

  @override
  void mergeVertices(int destination, int source) =>
      _valences[destination] += _valences[source];
}

/// The loop itself — `DecodeConnectivity(int num_symbols)`.
///
/// Returns how many vertices the connectivity ended up with. Mutable state
/// throughout, and honestly so: this is a stack machine writing two arrays.
int _decodeSymbols({
  required CornerTable corners,
  required _Traversal traversal,
  required List<_TopologySplit> splits,
  required int symbolCount,
  required List<bool> isVertexHole,
  required bool removeIsolatedVertices,
}) {
  // The open edges a new face may be attached to, each named by the corner
  // opposite it. Only the top is ever worked on; E pushes, S pops.
  final activeCorners = <int>[];
  // Edges a split event says some *later* S will want, by that S's id.
  final splitActiveCorners = <int, int>{};
  final isolatedVertices = <int>[];
  final pendingSplits = List<_TopologySplit>.of(splits);

  var faces = 0;
  for (var symbolId = 0; symbolId < symbolCount; symbolId++) {
    final corner = 3 * faces++;
    final symbol = traversal.readSymbol();
    var checkTopologySplit = false;

    switch (symbol) {
      case _topologyC:
        // A face between two boundary edges that meet at vertex x, closing
        // x's fan: x stops being a hole.
        if (activeCorners.isEmpty) _fail('a C symbol with nothing to close');
        final cornerA = activeCorners.last;
        final vertexX = corners.vertex(corners.next(cornerA));
        final cornerB = corners.next(corners.leftMostCorner(vertexX));
        if (cornerA == cornerB) _fail('a C symbol closes an edge onto itself');
        if (corners.opposite(cornerA) != dracoInvalid ||
            corners.opposite(cornerB) != dracoInvalid) {
          _fail('a C symbol attaches to an edge that already has a face');
        }
        corners
          ..setOpposites(cornerA, corner + 1)
          ..setOpposites(cornerB, corner + 2);
        final vertexAPrevious = corners.vertex(corners.previous(cornerA));
        final vertexBNext = corners.vertex(corners.next(cornerB));
        if (vertexX == vertexAPrevious || vertexX == vertexBNext) {
          _fail('a C symbol makes a degenerate face');
        }
        corners
          ..mapCornerToVertex(corner, vertexX)
          ..mapCornerToVertex(corner + 1, vertexBNext)
          ..mapCornerToVertex(corner + 2, vertexAPrevious)
          ..setLeftMostCorner(vertexAPrevious, corner + 2);
        isVertexHole[vertexX] = false;
        activeCorners.last = corner;

      case _topologyR || _topologyL:
        // A face hung off one boundary edge, with one new vertex at its tip.
        // Which of the two new edges stays active is the whole difference
        // between the letters.
        if (activeCorners.isEmpty) _fail('an R or L symbol with no open edge');
        final cornerA = activeCorners.last;
        if (corners.opposite(cornerA) != dracoInvalid) {
          _fail('an R or L symbol attaches to an edge that already has a face');
        }
        final (oppositeCorner, cornerL, cornerR) = symbol == _topologyR
            ? (corner + 2, corner + 1, corner)
            : (corner + 1, corner, corner + 2);
        corners.setOpposites(oppositeCorner, cornerA);
        final newVertex = corners.addVertex();
        final vertexR = corners.vertex(corners.previous(cornerA));
        corners
          ..mapCornerToVertex(oppositeCorner, newVertex)
          ..setLeftMostCorner(newVertex, oppositeCorner)
          ..mapCornerToVertex(cornerR, vertexR)
          ..setLeftMostCorner(vertexR, cornerR)
          ..mapCornerToVertex(cornerL, corners.vertex(corners.next(cornerA)));
        activeCorners.last = corner;
        checkTopologySplit = true;

      case _topologyS:
        // A face joining the two newest open boundaries. No new vertex: the
        // two that met become one, and the loser is left isolated.
        if (activeCorners.isEmpty) _fail('an S symbol with nothing to join');
        final cornerB = activeCorners.removeLast();
        final fromSplit = splitActiveCorners[symbolId];
        if (fromSplit != null) activeCorners.add(fromSplit);
        if (activeCorners.isEmpty) _fail('an S symbol with one boundary');
        final cornerA = activeCorners.last;
        if (cornerA == cornerB) _fail('an S symbol joins an edge to itself');
        if (corners.opposite(cornerA) != dracoInvalid ||
            corners.opposite(cornerB) != dracoInvalid) {
          _fail('an S symbol attaches to an edge that already has a face');
        }
        corners
          ..setOpposites(cornerA, corner + 2)
          ..setOpposites(cornerB, corner + 1);
        final vertexP = corners.vertex(corners.previous(cornerA));
        final vertexBPrevious = corners.vertex(corners.previous(cornerB));
        corners
          ..mapCornerToVertex(corner, vertexP)
          ..mapCornerToVertex(corner + 1, corners.vertex(corners.next(cornerA)))
          ..mapCornerToVertex(corner + 2, vertexBPrevious)
          ..setLeftMostCorner(vertexBPrevious, corner + 2);
        final firstN = corners.next(cornerB);
        final vertexN = corners.vertex(firstN);
        traversal.mergeVertices(vertexP, vertexN);
        corners.setLeftMostCorner(vertexP, corners.leftMostCorner(vertexN));
        // Every corner that named n now names p.
        var cornerN = firstN;
        while (cornerN != dracoInvalid) {
          corners.mapCornerToVertex(cornerN, vertexP);
          cornerN = corners.swingLeft(cornerN);
          if (cornerN == firstN) _fail('an S symbol merges a closed fan');
        }
        corners.makeVertexIsolated(vertexN);
        if (removeIsolatedVertices) isolatedVertices.add(vertexN);
        activeCorners.last = corner;

      case _topologyE:
        // A free triangle: three new vertices, and a new open boundary.
        final first = corners.addVertex();
        final second = corners.addVertex();
        final third = corners.addVertex();
        corners
          ..mapCornerToVertex(corner, first)
          ..mapCornerToVertex(corner + 1, second)
          ..mapCornerToVertex(corner + 2, third)
          ..setLeftMostCorner(first, corner)
          ..setLeftMostCorner(second, corner + 1)
          ..setLeftMostCorner(third, corner + 2);
        activeCorners.add(corner);
        checkTopologySplit = true;

      default:
        _fail('edgebreaker symbol $symbol is not one of the five');
    }

    traversal.newActiveCorner(activeCorners.last);

    if (checkTopologySplit) {
      // Events are in the encoder's numbering, which runs the other way.
      final encoderSymbolId = symbolCount - symbolId - 1;
      while (pendingSplits.isNotEmpty) {
        final event = pendingSplits.last;
        if (event.sourceSymbol > encoderSymbolId) {
          _fail('a topology split names a face the walk already passed');
        }
        if (event.sourceSymbol != encoderSymbolId) break;
        pendingSplits.removeLast();
        final top = activeCorners.last;
        splitActiveCorners[symbolCount - event.splitSymbol - 1] =
            event.rightEdge ? corners.next(top) : corners.previous(top);
      }
    }
  }

  // Whatever is still open is where a component's walk began. If it began on
  // an interior face, that face was never a letter and is added now, closing
  // three fans at once.
  while (activeCorners.isNotEmpty) {
    final cornerA = activeCorners.removeLast();
    if (!traversal.readStartFaceIsInterior()) continue;

    if (faces >= corners.faceCount) _fail('more start faces than faces');
    final vertexN = corners.vertex(corners.next(cornerA));
    final cornerB = corners.next(corners.leftMostCorner(vertexN));
    final vertexX = corners.vertex(corners.next(cornerB));
    final cornerC = corners.next(corners.leftMostCorner(vertexX));
    if (cornerA == cornerB || cornerA == cornerC || cornerB == cornerC) {
      _fail('a start face closes an edge onto itself');
    }
    if (corners.opposite(cornerA) != dracoInvalid ||
        corners.opposite(cornerB) != dracoInvalid ||
        corners.opposite(cornerC) != dracoInvalid) {
      _fail('a start face attaches to an edge that already has a face');
    }
    final vertexP = corners.vertex(corners.next(cornerC));
    final corner = 3 * faces++;
    corners
      ..setOpposites(corner, cornerA)
      ..setOpposites(corner + 1, cornerB)
      ..setOpposites(corner + 2, cornerC)
      ..mapCornerToVertex(corner, vertexX)
      ..mapCornerToVertex(corner + 1, vertexP)
      ..mapCornerToVertex(corner + 2, vertexN);
    isVertexHole[vertexX] = false;
    isVertexHole[vertexP] = false;
    isVertexHole[vertexN] = false;
  }
  if (faces != corners.faceCount) {
    _fail(
      'the symbols made $faces faces and the stream declared '
      '${corners.faceCount}',
    );
  }

  // With no attribute connectivity a vertex id *is* the point id, so the
  // vertices that splits left isolated have to go: swap each with the last
  // live vertex and shorten the count.
  var vertexCount = corners.vertexCount;
  for (final isolated in isolatedVertices) {
    var source = vertexCount - 1;
    while (corners.leftMostCorner(source) == dracoInvalid) {
      source = --vertexCount - 1;
    }
    if (source < isolated) continue;

    // Every corner round `source`, left then right — `VertexCornersIterator`.
    final start = corners.leftMostCorner(source);
    var walk = start;
    var goingLeft = true;
    while (walk != dracoInvalid) {
      if (corners.vertex(walk) != source) {
        _fail('a vertex fan names a different vertex part way round');
      }
      corners.mapCornerToVertex(walk, isolated);
      if (goingLeft) {
        walk = corners.swingLeft(walk);
        if (walk == dracoInvalid) {
          walk = corners.swingRight(start);
          goingLeft = false;
        } else if (walk == start) {
          walk = dracoInvalid;
        }
      } else {
        walk = corners.swingRight(walk);
      }
    }
    corners
      ..setLeftMostCorner(isolated, start)
      ..makeVertexIsolated(source);
    isVertexHole[isolated] = isVertexHole[source];
    isVertexHole[source] = false;
    vertexCount--;
  }
  return vertexCount;
}

/// `AssignPointsToCorners`: one point per run of corners round a vertex that
/// no attribute breaks.
///
/// Walks each vertex's fan clockwise from somewhere a run is known to *start*
/// — the boundary for an open fan, the first seam of any attribute for a
/// closed one — and opens a new point whenever any attribute's vertex changes
/// between one corner and the next. Starting mid-run would split one point in
/// two, which draws the same and costs a vertex.
(Uint32List, int) _assignPointsToCorners(
  CornerTable corners,
  List<AttributeCornerTable> attributeTables,
  List<bool> isVertexHole,
) {
  final cornerToPoint = Uint32List(corners.cornerCount);
  var points = 0;

  for (var v = 0; v < corners.vertexCount; v++) {
    final leftMost = corners.leftMostCorner(v);
    if (leftMost == dracoInvalid) continue;

    var firstCorner = leftMost;
    if (!isVertexHole[v]) {
      for (final table in attributeTables) {
        if (!table.isCornerOnSeam(leftMost)) continue;
        final attributeVertex = table.vertex(leftMost);
        var walk = corners.swingRight(leftMost);
        var found = false;
        while (walk != leftMost) {
          if (walk == dracoInvalid) {
            _fail('an interior vertex has an open fan');
          }
          if (table.vertex(walk) != attributeVertex) {
            firstCorner = walk;
            found = true;
            break;
          }
          walk = corners.swingRight(walk);
        }
        if (found) break;
      }
    }

    cornerToPoint[firstCorner] = points++;
    var previous = firstCorner;
    var walk = corners.swingRight(firstCorner);
    while (walk != dracoInvalid && walk != firstCorner) {
      final seam = attributeTables.any(
        (table) => table.vertex(walk) != table.vertex(previous),
      );
      cornerToPoint[walk] = seam ? points++ : cornerToPoint[previous];
      previous = walk;
      walk = corners.swingRight(walk);
    }
  }
  return (cornerToPoint, points);
}
