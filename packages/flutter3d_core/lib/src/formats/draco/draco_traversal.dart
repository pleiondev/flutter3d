/// The order an edgebreaker mesh stores its attribute values in — `gfx-82n`.
///
/// **Not vertex order, because there is no vertex order.** Edgebreaker never
/// numbers vertices; they come into being as the connectivity is replayed. So
/// the encoder stores values in the order a *second* walk over the finished
/// surface first reaches each vertex, and the decoder repeats that walk to
/// learn which value belongs where. The walk is part of the format: it has to
/// turn the same way at every face or every value after the first difference
/// lands on the wrong vertex, and the mesh still decodes — into noise.
///
/// The walk is also what makes prediction possible. It visits a vertex only
/// after the two others on some face it shares, so by the time a value is
/// decoded there is usually a finished triangle across an edge to predict it
/// from, which is the parallelogram rule in `draco_prediction.dart`.
///
/// Follows `compression/mesh/traverser/depth_first_traverser.h`,
/// `max_prediction_degree_traverser.h` and
/// `mesh_attribute_indices_encoding_observer.h`.
library;

import 'dart:typed_data';

import 'draco_buffer.dart';
import 'draco_corner_table.dart';

/// What a walk leaves behind — `MeshAttributeIndicesEncodingData`.
final class AttributeSequence {
  AttributeSequence._(this.table, int vertexSlots)
    : vertexToValue = Int32List(vertexSlots),
      _valueToCorner = Int32List(table.vertexCount);

  /// The connectivity the walk ran over, which is the one a predictor for
  /// these values must use too: the mesh's own for an attribute stored per
  /// vertex, the attribute's seamed one for an attribute stored per corner.
  final CornerTopology table;

  /// Which stored value a vertex of [table] has. Zero for a vertex the walk
  /// never reached, as in the reference — only an isolated vertex is never
  /// reached, and no corner names one.
  final Int32List vertexToValue;

  final Int32List _valueToCorner;
  int _valueCount = 0;

  int get valueCount => _valueCount;

  /// A corner at the vertex the [value]-th stored value belongs to — the
  /// corner the walk arrived by, so the face behind it is already decoded.
  int cornerOf(int value) => _valueToCorner[value];

  void _visit(int vertex, int corner) {
    _valueToCorner[_valueCount] = corner;
    vertexToValue[vertex] = _valueCount++;
  }
}

/// `MESH_TRAVERSAL_DEPTH_FIRST`: keep turning right, and remember the left.
///
/// [vertexSlots] sizes [AttributeSequence.vertexToValue]; the reference sizes
/// it for the larger of the mesh's and the attribute's vertex counts, because
/// the same record may be walked with either table.
AttributeSequence traverseDepthFirst(CornerTopology table, int vertexSlots) {
  final sequence = AttributeSequence._(table, vertexSlots);
  final faceVisited = List<bool>.filled(table.faceCount, false);
  final vertexVisited = List<bool>.filled(table.vertexCount, false);

  bool visitedFaceOf(int corner) =>
      corner == dracoInvalid || faceVisited[corner ~/ 3];

  void visitVertex(int vertex, int corner) {
    if (vertex == dracoInvalid) {
      throw const DracoException('a face names a vertex that does not exist');
    }
    if (vertexVisited[vertex]) return;
    vertexVisited[vertex] = true;
    sequence._visit(vertex, corner);
  }

  final stack = <int>[];
  for (var start = 0; start < table.cornerCount; start += 3) {
    if (faceVisited[start ~/ 3]) continue;

    // The first face of a component has no face behind it, so its two base
    // vertices are taken on faith before the walk proper starts at the tip.
    stack
      ..clear()
      ..add(start);
    visitVertex(table.vertex(table.next(start)), table.next(start));
    visitVertex(table.vertex(table.previous(start)), table.previous(start));

    while (stack.isNotEmpty) {
      var corner = stack.last;
      if (visitedFaceOf(corner)) {
        stack.removeLast();
        continue;
      }
      while (true) {
        faceVisited[corner ~/ 3] = true;
        final vertex = table.vertex(corner);
        if (vertex == dracoInvalid) {
          throw const DracoException(
            'a face names a vertex that does not exist',
          );
        }
        if (!vertexVisited[vertex]) {
          final onBoundary = table.isOnBoundary(vertex);
          visitVertex(vertex, corner);
          // A new interior vertex means the walk is circling it: the face to
          // the right is unvisited by construction, so go there.
          if (!onBoundary) {
            corner = table.rightCorner(corner);
            continue;
          }
        }
        final right = table.rightCorner(corner);
        final left = table.leftCorner(corner);
        final rightVisited = visitedFaceOf(right);
        final leftVisited = visitedFaceOf(left);
        if (rightVisited && leftVisited) {
          stack.removeLast();
          break;
        }
        if (rightVisited) {
          corner = left;
        } else if (leftVisited) {
          corner = right;
        } else {
          // A fork: right first, left when that branch is exhausted.
          stack
            ..last = left
            ..add(right);
          break;
        }
      }
    }
  }
  return sequence;
}

/// `MESH_TRAVERSAL_PREDICTION_DEGREE`: visit next whichever face has the most
/// already-decoded neighbours.
///
/// What the encoder chooses at speed zero. A vertex reached from a face whose
/// other two vertices are known can be predicted by one parallelogram; reached
/// when *two* such faces touch it, by two, averaged. So this walk keeps three
/// stacks by priority and always continues from the best, deferring the
/// vertices it could only predict badly until more of their ring is known.
AttributeSequence traverseByPredictionDegree(
  CornerTopology table,
  int vertexSlots,
) {
  const maxPriority = 3;
  final sequence = AttributeSequence._(table, vertexSlots);
  final faceVisited = List<bool>.filled(table.faceCount, false);
  final vertexVisited = List<bool>.filled(table.vertexCount, false);
  final predictionDegree = Int32List(table.vertexCount);
  final stacks = <List<int>>[for (var i = 0; i < maxPriority; i++) <int>[]];
  var bestPriority = 0;

  bool visitedFaceOf(int corner) =>
      corner == dracoInvalid || faceVisited[corner ~/ 3];

  void visitVertex(int vertex, int corner) {
    if (vertexVisited[vertex]) return;
    vertexVisited[vertex] = true;
    sequence._visit(vertex, corner);
  }

  int popNext() {
    for (var i = bestPriority; i < maxPriority; i++) {
      if (stacks[i].isNotEmpty) {
        bestPriority = i;
        return stacks[i].removeLast();
      }
    }
    return dracoInvalid;
  }

  void push(int corner, int priority) {
    stacks[priority].add(corner);
    if (priority < bestPriority) bestPriority = priority;
  }

  // Asking counts: each time a face offers to reach an unvisited tip, that tip
  // has one more decoded neighbour than before, and the second offer is the
  // one worth taking.
  int priorityOf(int corner) {
    final tip = table.vertex(corner);
    if (vertexVisited[tip]) return 0;
    return ++predictionDegree[tip] > 1 ? 1 : 2;
  }

  if (table.vertexCount == 0) return sequence;
  for (var start = 0; start < table.cornerCount; start += 3) {
    stacks[0].add(start);
    bestPriority = 0;
    visitVertex(table.vertex(table.next(start)), table.next(start));
    visitVertex(table.vertex(table.previous(start)), table.previous(start));
    visitVertex(table.vertex(start), start);

    for (var corner = popNext(); corner != dracoInvalid; corner = popNext()) {
      if (faceVisited[corner ~/ 3]) continue;
      while (true) {
        faceVisited[corner ~/ 3] = true;
        visitVertex(table.vertex(corner), corner);

        final right = table.rightCorner(corner);
        final left = table.leftCorner(corner);
        final rightVisited = visitedFaceOf(right);
        final leftVisited = visitedFaceOf(left);

        if (!leftVisited) {
          final priority = priorityOf(left);
          if (rightVisited && priority <= bestPriority) {
            corner = left;
            continue;
          }
          push(left, priority);
        }
        if (!rightVisited) {
          final priority = priorityOf(right);
          if (priority <= bestPriority) {
            corner = right;
            continue;
          }
          push(right, priority);
        }
        break;
      }
    }
  }
  return sequence;
}
