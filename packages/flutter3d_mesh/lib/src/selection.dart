/// What is selected, and the walks that turn one selection into another.
///
/// **A selection is a value, not a flag on the mesh.** Marking elements inside
/// `EditMesh` would put it in the journal, so undoing a move would also undo
/// the click that set it up, and two viewports of one document could not
/// disagree about what is highlighted. So a selection is sorted numbers, an
/// element level and an active element, and every operation here returns a new
/// one.
///
/// **Sorted numbers rather than a set.** A selection is read far more often
/// than it is changed — every frame, by the overlay, once per element — so what
/// matters is that `contains` is a binary search over one `Int32List` rather
/// than a hash lookup through a boxed `int`, and that handing the whole thing
/// to an isolate is handing over one buffer.
///
/// **Everything converts through vertices.** Asking for the faces of an edge
/// selection means asking which faces have all their corners selected, and the
/// same rule gives the edges of a face selection and the faces of a vertex one.
/// One rule is worth having even where a special case would be a little
/// sharper: a person selecting a region and switching levels expects the region
/// to survive, and three separate rules is three places for it not to.
library;

import 'dart:typed_data';

import 'edit_mesh.dart';

/// Which kind of element a selection holds.
///
/// Machinery: these are the three things a half-edge mesh is made of that a
/// person can point at, and a fourth would be a different data structure rather
/// than a value somebody adds. Named in `boundaryEnumExempt` for that reason,
/// which is decision Б7 of `doc/model-editor-plan.md`.
enum ElementLevel { vertex, edge, face }

/// The elements a person has picked, at one level.
final class Selection {
  const Selection._(this.level, this.ids, this.active);

  /// Nothing selected.
  factory Selection.empty(ElementLevel level) =>
      Selection._(level, _noIds, EditMesh.none);

  /// The elements [ids] name, sorted and with the duplicates gone.
  ///
  /// [active] is the one a person picked last — what a tool that needs a single
  /// element reads, and what an overlay draws differently. It is kept only if
  /// it is in the selection.
  factory Selection.of(
    ElementLevel level,
    Iterable<int> ids, {
    int active = EditMesh.none,
  }) {
    final unique = ids.toSet().toList(growable: false)..sort();
    final sorted = Int32List.fromList(unique);
    return Selection._(
      level,
      sorted,
      _has(sorted, active) ? active : EditMesh.none,
    );
  }

  /// Every face carrying [slot].
  ///
  /// What "select all faces with this material" is, and what an exporter uses
  /// to ask which faces belong in which drawable mesh.
  factory Selection.byMaterialSlot(EditMesh mesh, int slot) =>
      Selection.of(ElementLevel.face, <int>[
        for (var face = 0; face < mesh.faceSlotCount; face++)
          if (mesh.isFaceAlive(face) && mesh.materialSlotOf(face) == slot) face,
      ]);

  /// The edges in line with the one [halfEdge] lies on.
  ///
  /// **A loop runs along edges; a ring runs across them.** This one steps from
  /// vertex to vertex, taking the edge opposite the one it arrived on — which
  /// only means anything where four edges meet. At a vertex of any other
  /// valency there is no opposite edge and the loop stops, which is why a cube,
  /// whose every corner joins three edges, has no loops longer than one edge.
  /// A grid or a torus, where every vertex joins four, loops all the way round.
  factory Selection.edgeLoop(EditMesh mesh, int halfEdge) {
    final found = <int>{mesh.edgeOf(halfEdge)};
    _walkLoop(mesh, halfEdge, found);
    // And the other way, which is the same walk from the other end.
    if (mesh.hasLiveTwin(halfEdge)) {
      _walkLoop(mesh, mesh.twinOf(halfEdge), found);
    }
    return Selection.of(
      ElementLevel.edge,
      found,
      active: mesh.edgeOf(halfEdge),
    );
  }

  /// The edges across the strip of quads the one [halfEdge] lies on runs
  /// through.
  ///
  /// **Only quads have an opposite edge**, and that is the whole of the walk:
  /// step over the face to the edge two along, cross to the face behind it, and
  /// again. A triangle or an n-gon has no edge across from any of its own, so
  /// the ring stops there — which is what keeps a loop cut from wandering into
  /// a triangle fan and cutting something nobody asked for.
  factory Selection.edgeRing(EditMesh mesh, int halfEdge) {
    final found = <int>{mesh.edgeOf(halfEdge)};
    _walkRing(mesh, halfEdge, found);
    if (mesh.hasLiveTwin(halfEdge)) {
      _walkRing(mesh, mesh.twinOf(halfEdge), found);
    }
    return Selection.of(
      ElementLevel.edge,
      found,
      active: mesh.edgeOf(halfEdge),
    );
  }

  static final Int32List _noIds = Int32List(0);

  /// Which kind of element these numbers are.
  final ElementLevel level;

  /// The elements, ascending. A vertex or a face is its own number; an edge is
  /// the half-edge [EditMesh.edgeOf] chose for it.
  final Int32List ids;

  /// The element a person picked last, or [EditMesh.none].
  final int active;

  int get length => ids.length;
  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;

  /// Whether [id] is selected, by binary search.
  bool contains(int id) => _has(ids, id);

  /// The same elements with [id] as the active one, if it is one of them.
  Selection withActive(int id) =>
      Selection._(level, ids, _has(ids, id) ? id : EditMesh.none);

  /// The same level, different elements — keeping the active one if it survived.
  Selection withIds(Iterable<int> replacement) =>
      Selection.of(level, replacement, active: active);

  Selection union(Selection other) => withIds(<int>[...ids, ...other.ids]);

  Selection difference(Selection other) => withIds(<int>[
    for (final id in ids)
      if (!other.contains(id)) id,
  ]);

  Selection intersection(Selection other) => withIds(<int>[
    for (final id in ids)
      if (other.contains(id)) id,
  ]);

  /// The elements in one or the other but not both, which is what a click with
  /// the modifier held down does.
  Selection toggle(Selection other) => withIds(<int>[
    for (final id in ids)
      if (!other.contains(id)) id,
    for (final id in other.ids)
      if (!contains(id)) id,
  ]);

  /// The same region read at another [level].
  ///
  /// Going down — to vertices — takes everything the selection touches. Going
  /// up takes only the elements every one of whose vertices is selected, so a
  /// region stays a region rather than spilling over its own edge.
  Selection convertedTo(EditMesh mesh, ElementLevel level) {
    if (level == this.level) return this;
    final vertices = _verticesOf(mesh, this);
    if (level == ElementLevel.vertex) {
      return Selection.of(level, <int>[
        for (var v = 0; v < vertices.length; v++)
          if (vertices[v]) v,
      ], active: active);
    }
    final found = <int>[];
    _forEachElement(mesh, level, (int id) {
      var whole = true;
      _forEachVertexOf(mesh, level, id, (int vertex) {
        if (!vertices[vertex]) whole = false;
      });
      if (whole) found.add(id);
    });
    return Selection.of(level, found, active: active);
  }

  /// The selection plus everything touching it.
  ///
  /// **Touching means sharing a vertex, at every level.** A face selection
  /// grown on a grid becomes the three-by-three block around it rather than the
  /// plus shape sharing an edge would give — which is what "select more" means
  /// to somebody widening a region by hand, and what makes growing and
  /// shrinking undo each other.
  Selection grown(EditMesh mesh) {
    final vertices = _verticesOf(mesh, this);
    if (level == ElementLevel.vertex) {
      final found = <int>[
        for (var v = 0; v < vertices.length; v++)
          if (vertices[v]) v,
      ];
      _forEachLiveHalfEdge(mesh, (int half) {
        final from = mesh.originOf(half);
        final to = mesh.originOf(mesh.nextOf(half));
        if (vertices[from] && !vertices[to]) found.add(to);
        if (vertices[to] && !vertices[from]) found.add(from);
      });
      return withIds(found);
    }
    final found = <int>[];
    _forEachElement(mesh, level, (int id) {
      var touches = false;
      _forEachVertexOf(mesh, level, id, (int vertex) {
        if (vertices[vertex]) touches = true;
      });
      if (touches) found.add(id);
    });
    return withIds(found);
  }

  /// The selection minus everything on its edge.
  ///
  /// An element stays only when everything touching it is selected too, which
  /// is the same relation [grown] uses read the other way round.
  Selection shrunk(EditMesh mesh) {
    if (isEmpty) return this;
    if (level == ElementLevel.vertex) {
      final inside = Uint8List(mesh.vertexSlotCount);
      for (final id in ids) {
        inside[id] = 1;
      }
      final exposed = Uint8List(mesh.vertexSlotCount);
      _forEachLiveHalfEdge(mesh, (int half) {
        final from = mesh.originOf(half);
        final to = mesh.originOf(mesh.nextOf(half));
        if (inside[from] == 0) exposed[to] = 1;
        if (inside[to] == 0) exposed[from] = 1;
      });
      return withIds(<int>[
        for (final id in ids)
          if (exposed[id] == 0) id,
      ]);
    }

    // A vertex is exposed when some element of this level that is *not*
    // selected stands on it. Anything of ours touching an exposed vertex is on
    // the border and goes.
    final exposed = Uint8List(mesh.vertexSlotCount);
    _forEachElement(mesh, level, (int id) {
      if (contains(id)) return;
      _forEachVertexOf(mesh, level, id, (int vertex) => exposed[vertex] = 1);
    });
    return withIds(<int>[
      for (final id in ids)
        if (!_touchesExposed(mesh, level, id, exposed)) id,
    ]);
  }

  /// Everything joined to the selection by a chain of edges.
  ///
  /// One breadth-first walk over the vertices rather than growing until nothing
  /// changes: growing takes a pass over the mesh per step, and the number of
  /// steps is the width of the island, so a lattice somebody selected one
  /// vertex of would cost hundreds of passes.
  Selection linked(EditMesh mesh) {
    if (isEmpty) return this;
    final reached = _verticesOf(mesh, this);
    final neighbours = _VertexNeighbours(mesh);
    final queue = <int>[
      for (var v = 0; v < reached.length; v++)
        if (reached[v]) v,
    ];
    while (queue.isNotEmpty) {
      final vertex = queue.removeLast();
      neighbours.forEach(vertex, (int other) {
        if (reached[other]) return;
        reached[other] = true;
        queue.add(other);
      });
    }
    if (level == ElementLevel.vertex) {
      return withIds(<int>[
        for (var v = 0; v < reached.length; v++)
          if (reached[v]) v,
      ]);
    }
    final found = <int>[];
    _forEachElement(mesh, level, (int id) {
      var touches = false;
      _forEachVertexOf(mesh, level, id, (int vertex) {
        if (reached[vertex]) touches = true;
      });
      if (touches) found.add(id);
    });
    return withIds(found);
  }

  /// The edges around the outside of the selected faces.
  ///
  /// **The border of a region, not the border of the mesh.** An edge is on it
  /// when the face on one side is selected and the face on the other is not —
  /// and an edge with nothing on the other side at all counts, because the
  /// outside of the mesh is as much outside the region as a neighbouring face
  /// is. `mesh-27` is where "which edges have no face behind them" lives, and
  /// it is a different question.
  ///
  /// A selection at another level is read as faces first, so a handful of
  /// vertices that do not fill a face has no boundary rather than a wrong one.
  Selection boundary(EditMesh mesh) {
    final faces = convertedTo(mesh, ElementLevel.face);
    final found = <int>[];
    for (final face in faces.ids) {
      mesh.forEachHalfEdge(face, (int half) {
        final twin = mesh.twinOf(half);
        final behind = mesh.hasLiveTwin(half)
            ? mesh.faceOf(twin)
            : EditMesh.none;
        if (behind == EditMesh.none || !faces.contains(behind)) {
          found.add(mesh.edgeOf(half));
        }
      });
    }
    return Selection.of(ElementLevel.edge, found);
  }

  @override
  String toString() =>
      'Selection(${level.name}, ${ids.length} selected, active $active)';
}

/// Whether [id] is in the ascending [ids].
bool _has(Int32List ids, int id) {
  if (id == EditMesh.none) return false;
  var low = 0;
  var high = ids.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final at = ids[middle];
    if (at == id) return true;
    if (at < id) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return false;
}

/// Every vertex the selection stands on, as a flag per vertex slot.
List<bool> _verticesOf(EditMesh mesh, Selection selection) {
  final marked = List<bool>.filled(mesh.vertexSlotCount, false);
  for (final id in selection.ids) {
    _forEachVertexOf(mesh, selection.level, id, (int vertex) {
      marked[vertex] = true;
    });
  }
  return marked;
}

void _forEachVertexOf(
  EditMesh mesh,
  ElementLevel level,
  int id,
  void Function(int vertex) visit,
) {
  switch (level) {
    case ElementLevel.vertex:
      visit(id);
    case ElementLevel.edge:
      visit(mesh.originOf(id));
      visit(mesh.originOf(mesh.nextOf(id)));
    case ElementLevel.face:
      mesh.forEachVertex(id, visit);
  }
}

bool _touchesExposed(
  EditMesh mesh,
  ElementLevel level,
  int id,
  Uint8List exposed,
) {
  var touches = false;
  _forEachVertexOf(mesh, level, id, (int vertex) {
    if (exposed[vertex] != 0) touches = true;
  });
  return touches;
}

/// Every live element of [level], once each.
void _forEachElement(
  EditMesh mesh,
  ElementLevel level,
  void Function(int id) visit,
) {
  switch (level) {
    case ElementLevel.vertex:
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        if (mesh.isVertexAlive(vertex)) visit(vertex);
      }
    case ElementLevel.edge:
      _forEachLiveHalfEdge(mesh, (int half) {
        if (mesh.edgeOf(half) == half) visit(half);
      });
    case ElementLevel.face:
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (mesh.isFaceAlive(face)) visit(face);
      }
  }
}

void _forEachLiveHalfEdge(EditMesh mesh, void Function(int half) visit) {
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (mesh.isFaceAlive(face)) mesh.forEachHalfEdge(face, visit);
  }
}

/// The vertices each vertex is joined to, built once for one walk.
///
/// Two flat arrays rather than a list per vertex: a list apiece is an object
/// per vertex of the document to answer a question a click asks once.
final class _VertexNeighbours {
  _VertexNeighbours(EditMesh mesh)
    : _start = Int32List(mesh.vertexSlotCount + 1),
      _values = Int32List(_incidenceCount(mesh)) {
    _forEachLiveHalfEdge(mesh, (int half) {
      _start[mesh.originOf(half) + 1]++;
      _start[mesh.originOf(mesh.nextOf(half)) + 1]++;
    });
    for (var vertex = 0; vertex + 1 < _start.length; vertex++) {
      _start[vertex + 1] += _start[vertex];
    }
    final cursor = Int32List.fromList(_start);
    _forEachLiveHalfEdge(mesh, (int half) {
      final from = mesh.originOf(half);
      final to = mesh.originOf(mesh.nextOf(half));
      _values[cursor[from]++] = to;
      _values[cursor[to]++] = from;
    });
  }

  final Int32List _start;
  final Int32List _values;

  void forEach(int vertex, void Function(int other) visit) {
    for (var at = _start[vertex]; at < _start[vertex + 1]; at++) {
      visit(_values[at]);
    }
  }
}

int _incidenceCount(EditMesh mesh) {
  var count = 0;
  _forEachLiveHalfEdge(mesh, (int _) => count++);
  return count * 2;
}

/// Steps along a loop from [halfEdge], adding each edge it reaches to [found].
void _walkLoop(EditMesh mesh, int halfEdge, Set<int> found) {
  var walking = halfEdge;
  // A loop cannot be longer than the mesh has half-edges, and a walk that
  // reaches that many has found a cycle the visited set should have caught.
  for (var guard = mesh.halfEdgeSlotCount; guard > 0; guard--) {
    final vertex = mesh.originOf(mesh.nextOf(walking));
    if (!mesh.hasLiveTwin(walking)) return;
    final outward = mesh.twinOf(walking);
    if (_fanSize(mesh, outward) != 4) return;
    // Two rotations round a fan of four is the edge opposite the one we came
    // in on. Any other valency has no opposite, which is where the loop ends.
    final across = _rotate(mesh, _rotate(mesh, outward));
    if (across == EditMesh.none) return;
    assert(mesh.originOf(across) == vertex);
    if (!found.add(mesh.edgeOf(across))) return;
    walking = across;
  }
}

/// Steps across a ring from [halfEdge], adding each edge it reaches to [found].
void _walkRing(EditMesh mesh, int halfEdge, Set<int> found) {
  var walking = halfEdge;
  for (var guard = mesh.halfEdgeSlotCount; guard > 0; guard--) {
    final face = mesh.faceOf(walking);
    if (face == EditMesh.none || mesh.valencyOf(face) != 4) return;
    // Two steps round a quad is the edge across from this one.
    final across = mesh.nextOf(mesh.nextOf(walking));
    if (!found.add(mesh.edgeOf(across))) return;
    if (!mesh.hasLiveTwin(across)) return;
    walking = mesh.twinOf(across);
  }
}

/// The next half-edge round the vertex [half] starts at, or [EditMesh.none]
/// where the fan is open.
int _rotate(EditMesh mesh, int half) =>
    mesh.hasLiveTwin(half) ? mesh.nextOf(mesh.twinOf(half)) : EditMesh.none;

/// How many edges meet at the vertex [half] starts at, or -1 if the fan does
/// not close.
int _fanSize(EditMesh mesh, int half) {
  var walking = half;
  var count = 0;
  do {
    count++;
    walking = _rotate(mesh, walking);
    if (walking == EditMesh.none) return -1;
    if (count > mesh.halfEdgeSlotCount) return -1;
  } while (walking != half);
  return count;
}
