/// A mesh with its topology still in it: faces of any valency, and half-edges
/// that know what is next to what.
///
/// **Why this is not `MeshData`.** That one describes a finished mesh —
/// vertices in the order a GPU wants them, with a corner duplicated once per
/// face normal meeting there — and every question a modeller asks is about what
/// that arrangement threw away: which faces share this edge, what ring does this
/// edge belong to, what is the loop around this face. So editing needs the other
/// representation, and drawing needs this one converted.
///
/// **Six arrays and no objects.** A half-edge knows its origin vertex, the next
/// half-edge around its face, its twin across the edge, and the face it belongs
/// to; a vertex knows one half-edge leaving it; a face knows one half-edge on
/// its loop. All of it is `Int32List` and `Float32List` through
/// [JournalledInts] and [JournalledFloats], so an edit is recorded and can be
/// taken back, and a read is an array read.
///
/// **Deletion is a tombstone, not a hole.** Removing a face from the middle of
/// the arrays would renumber everything after it, and every selection, every
/// undo record and every id an agent is holding would be pointing at something
/// else. So a deleted element is marked dead and skipped; [compact] is what
/// closes the gaps, and it hands back the [IdRemap] that says where everything
/// went.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'journal.dart';
import 'layout_plan.dart';
import 'normals.dart';

/// Where an element went when the mesh was compacted, or [EditMesh.none] where
/// it was dropped.
final class IdRemap {
  const IdRemap({required this.vertices, required this.faces});

  /// Old vertex number to new, indexed by the old one.
  final Int32List vertices;

  /// Old face number to new.
  final Int32List faces;
}

/// An editable mesh.
final class EditMesh {
  EditMesh._(
    this._positions,
    this._origin,
    this._next,
    this._twin,
    this._halfEdgeFace,
    this._faceHalfEdge,
    this._outgoing,
    this._vertexAlive,
    this._faceAlive,
  ) : _vertexSlots = _outgoing.length,
      _faceSlots = _faceHalfEdge.length,
      _halfEdgeSlots = _origin.length;

  /// An empty mesh, ready to be built into.
  factory EditMesh.empty() => EditMesh._(
    JournalledFloats(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
    JournalledInts(0),
  );

  /// Builds a mesh from points and faces, each face a list of point indices
  /// wound counter-clockwise seen from outside.
  factory EditMesh.fromFaces(List<Vector3> points, List<List<int>> faces) {
    final builder = EditMeshBuilder();
    for (final point in points) {
      builder.addVertex(point);
    }
    for (final face in faces) {
      builder.addFace(face);
    }
    return builder.build();
  }

  /// An axis-aligned box of [size], centred on the origin, as six quads.
  ///
  /// Quads and not triangles, which is the whole reason this exists beside
  /// `CuboidShape`: that one builds what a GPU draws — twenty-four vertices,
  /// because a corner carries three different normals — and a loop cut through
  /// a triangulated cube has nothing to cut along.
  factory EditMesh.cuboid({Vector3? size}) {
    final half = (size ?? Vector3(1, 1, 1)) * 0.5;
    return EditMesh.fromFaces(
      <Vector3>[
        Vector3(-half.x, -half.y, -half.z),
        Vector3(half.x, -half.y, -half.z),
        Vector3(half.x, half.y, -half.z),
        Vector3(-half.x, half.y, -half.z),
        Vector3(-half.x, -half.y, half.z),
        Vector3(half.x, -half.y, half.z),
        Vector3(half.x, half.y, half.z),
        Vector3(-half.x, half.y, half.z),
      ],
      <List<int>>[
        <int>[4, 5, 6, 7], // +Z
        <int>[1, 0, 3, 2], // −Z
        <int>[5, 1, 2, 6], // +X
        <int>[0, 4, 7, 3], // −X
        <int>[3, 7, 6, 2], // +Y
        <int>[0, 1, 5, 4], // −Y
      ],
    );
  }

  /// What an index means when there is nothing there: a half-edge on a
  /// boundary has no twin, a deleted element has no successor.
  static const int none = -1;

  final JournalledFloats _positions;
  final JournalledInts _origin;
  final JournalledInts _next;
  final JournalledInts _twin;
  final JournalledInts _halfEdgeFace;
  final JournalledInts _faceHalfEdge;
  final JournalledInts _outgoing;

  // Tombstones. One int per element rather than a bitset: the arrays are
  // already int32 and a bitset would save four megabytes on a mesh where the
  // positions alone are twenty-four, in exchange for a shift and a mask on the
  // hottest test in every walk.
  final JournalledInts _vertexAlive;
  final JournalledInts _faceAlive;

  // The attribute layers, each null until something writes to it. See
  // `attributes.dart` for why a layer nobody entered should not cost anything,
  // and `_layerFor` for how a late arrival stays level with the journal.
  JournalledFloats? _uv0; // 2 per half-edge
  JournalledFloats? _colour; // 4 per half-edge
  JournalledFloats? _weights; // 4 per vertex
  JournalledFloats? _joints; // 4 per vertex, indices held as floats
  JournalledFloats? _crease; // 1 per half-edge, mirrored onto the twin
  JournalledInts? _edgeFlags; // 1 per half-edge, mirrored onto the twin
  JournalledInts? _faceFlags; // 1 per face
  JournalledInts? _materialSlot; // 1 per face

  int _vertexSlots;
  int _faceSlots;
  int _halfEdgeSlots;

  int _liveVertices = 0;
  int _liveFaces = 0;

  /// Slots the arrays hold, live and dead. What a walk iterates over.
  ///
  /// A caller that iterates — a viewport building an overlay, an exporter
  /// walking faces, a test — needs the slot count rather than the live one,
  /// because a tombstone leaves a gap and the numbers on either side of it do
  /// not move.
  int get vertexSlotCount => _vertexSlots;
  int get faceSlotCount => _faceSlots;

  /// Half-edge slots, live and dead.
  ///
  /// What a caller sizes a per-half-edge array against — `mesh-19`'s selection
  /// bitsets, a viewport's overlay buffers — and the bound a walk guarding
  /// against a loop that does not close counts up to.
  int get halfEdgeSlotCount => _halfEdgeSlots;

  /// Elements that are actually there.
  int get vertexCount => _liveVertices;
  int get faceCount => _liveFaces;

  /// Whether the slot holds something.
  ///
  /// Asked by everything that iterates over slots and by everything that was
  /// handed an id earlier: a selection made before a delete, an undo record, an
  /// agent naming a face over MCP. The alternative — letting a caller read a
  /// dead element and get plausible-looking numbers out of it — is the failure
  /// tombstones exist to make impossible to reach by accident.
  bool isVertexAlive(int vertex) => _vertexAlive[vertex] != 0;
  bool isFaceAlive(int face) => _faceAlive[face] != 0;

  /// Half-edges of live faces. A dead face's half-edges are dead with it.
  int get halfEdgeCount {
    var count = 0;
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      count += _valencyOf(face);
    }
    return count;
  }

  /// Edges, counting a pair of twins once and a boundary half-edge once.
  int get edgeCount {
    var paired = 0;
    var boundary = 0;
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      final start = _faceHalfEdge[face];
      var half = start;
      do {
        final twin = _twin[half];
        if (twin == none ||
            _halfEdgeFace[twin] == none ||
            _faceAlive[_halfEdgeFace[twin]] == 0) {
          boundary++;
        } else {
          paired++;
        }
        half = _next[half];
      } while (half != start);
    }
    return paired ~/ 2 + boundary;
  }

  /// `V − E + F`, which is 2 for anything shaped like a sphere.
  int get eulerCharacteristic => vertexCount - edgeCount + faceCount;

  int originOf(int halfEdge) => _origin[halfEdge];
  int nextOf(int halfEdge) => _next[halfEdge];
  int twinOf(int halfEdge) => _twin[halfEdge];
  int faceOf(int halfEdge) => _halfEdgeFace[halfEdge];

  /// Some half-edge leaving [vertex], or [none] for a vertex in no face.
  int outgoingOf(int vertex) => _outgoing[vertex];

  /// Some half-edge on the loop of [face].
  ///
  /// Where a caller that wants to walk a loop by hand starts — `mesh-19`'s edge
  /// loops and rings step from a half-edge rather than from a face, and so does
  /// anything that needs the loop's *order* rather than its members.
  int halfEdgeOf(int face) => _faceHalfEdge[face];

  /// The position of [vertex], written into [out] when one is given.
  ///
  /// **The out parameter is not premature.** Every operation here reads
  /// positions per vertex per step; allocating a `Vector3` for each is what
  /// turned the spike's `signedVolume` into thirty-seven milliseconds on 200
  /// 000 faces.
  Vector3 positionOf(int vertex, [Vector3? out]) => (out ?? Vector3.zero())
    ..setValues(
      _positions[vertex * 3],
      _positions[vertex * 3 + 1],
      _positions[vertex * 3 + 2],
    );

  /// The raw positions: three floats per vertex slot.
  ///
  /// Read-only by convention, for the reason [JournalledFloats.values] gives —
  /// a conversion or a bounds pass must not pay for a copy. Writes go through
  /// [moveVertex] so history records them.
  Float32List get positions => _positions.values;

  /// Calls [visit] for every half-edge of [face], in winding order.
  ///
  /// **A callback rather than an `Iterable`.** A sync* generator allocates an
  /// iterator per call, and these loops are walked once per face per operation:
  /// on a 100 000-face mesh that is 100 000 allocations to answer a question
  /// about winding.
  void forEachHalfEdge(int face, void Function(int halfEdge) visit) {
    final start = _faceHalfEdge[face];
    if (start == none) return;
    var half = start;
    do {
      visit(half);
      half = _next[half];
    } while (half != start);
  }

  /// Calls [visit] for every vertex of [face], in winding order.
  void forEachVertex(int face, void Function(int vertex) visit) =>
      forEachHalfEdge(face, (int half) => visit(_origin[half]));

  /// The vertices of [face] as a list — for callers that need one, and not for
  /// the loops that run per face.
  List<int> verticesOf(int face) {
    final out = <int>[];
    forEachVertex(face, out.add);
    return out;
  }

  int _valencyOf(int face) {
    var count = 0;
    forEachHalfEdge(face, (_) => count++);
    return count;
  }

  /// How many half-edges [face] has.
  int valencyOf(int face) => _valencyOf(face);

  // ----------------------------------------------------------------- layers

  /// Whether a layer holds anything at all.
  ///
  /// What a conversion asks before spending bytes on it, and what a caller
  /// checking whether a model carried UVs asks: a mesh with no layer is a mesh
  /// nobody has textured, which is different from one textured at the origin.
  bool hasLayer(MeshDomain domain, MeshAttribute attribute) =>
      _existingLayer(domain, attribute) != null;

  Object? _existingLayer(MeshDomain domain, MeshAttribute attribute) =>
      switch ((domain, attribute)) {
        (MeshDomain.corner, MeshAttribute.uv0) => _uv0,
        (MeshDomain.corner, MeshAttribute.colour) => _colour,
        (MeshDomain.vertex, MeshAttribute.weights) => _weights,
        (MeshDomain.vertex, MeshAttribute.joints) => _joints,
        (MeshDomain.edge, MeshAttribute.crease) => _crease,
        (MeshDomain.edge, MeshAttribute.flags) => _edgeFlags,
        (MeshDomain.face, MeshAttribute.flags) => _faceFlags,
        (MeshDomain.face, MeshAttribute.materialSlot) => _materialSlot,
        _ => null,
      };

  /// A layer of floats, created the first time it is written to.
  ///
  /// **Padded to the journal's depth on arrival.** Every array in the mesh
  /// carries one step per edit — see [endStep] — and a layer that appears forty
  /// edits in has nothing to say about the first forty. An empty step is what
  /// "nothing to say" is spelled as, and without them an undo would take the
  /// other arrays back a version and leave this one where it is.
  JournalledFloats _floatLayer(
    JournalledFloats? existing,
    int count,
    double fill,
    void Function(JournalledFloats) store,
  ) {
    if (existing != null) return existing;
    final layer = JournalledFloats(count);
    if (fill != 0) layer.values.fillRange(0, count, fill);
    layer.padSteps(undoDepth);
    // A layer created inside an open step joins it, so an undo of that step
    // takes its writes back with everything else.
    if (_inStep) layer.beginStep();
    store(layer);
    return layer;
  }

  JournalledInts _intLayer(
    JournalledInts? existing,
    int count,
    void Function(JournalledInts) store,
  ) {
    if (existing != null) return existing;
    final layer = JournalledInts(count)..padSteps(undoDepth);
    if (_inStep) layer.beginStep();
    store(layer);
    return layer;
  }

  /// The texture coordinate at [halfEdge], or the origin where none was set.
  Vector2 uvOf(int halfEdge, [Vector2? out]) {
    final layer = _uv0;
    final result = out ?? Vector2.zero();
    if (layer == null) return result..setZero();
    return result..setValues(layer[halfEdge * 2], layer[halfEdge * 2 + 1]);
  }

  /// Sets the texture coordinate at [halfEdge].
  ///
  /// Per corner rather than per vertex, which is what makes a seam possible:
  /// the two faces meeting along one can put the same vertex in two places on
  /// the texture.
  void setUv(int halfEdge, Vector2 uv) {
    _wrote = true;
    final layer = _floatLayer(
      _uv0,
      _halfEdgeSlots * 2,
      0,
      (JournalledFloats it) => _uv0 = it,
    );
    layer
      ..write(halfEdge * 2, uv.x)
      ..write(halfEdge * 2 + 1, uv.y);
  }

  /// The colour at [halfEdge], white where none was set.
  Vector4 colourOf(int halfEdge, [Vector4? out]) {
    final layer = _colour;
    final result = out ?? Vector4.zero();
    if (layer == null) return result..setFrom(kNeutralColor);
    return result..setValues(
      layer[halfEdge * 4],
      layer[halfEdge * 4 + 1],
      layer[halfEdge * 4 + 2],
      layer[halfEdge * 4 + 3],
    );
  }

  /// Sets the colour at [halfEdge].
  void setColour(int halfEdge, Vector4 colour) {
    _wrote = true;
    final layer = _floatLayer(
      _colour,
      _halfEdgeSlots * 4,
      1, // white, so corners nobody painted stay neutral rather than black
      (JournalledFloats it) => _colour = it,
    );
    for (var i = 0; i < 4; i++) {
      layer.write(halfEdge * 4 + i, colour[i]);
    }
  }

  /// Everything [halfEdge] carries as a corner.
  CornerAttributes cornerOf(int halfEdge) =>
      CornerAttributes(uv: uvOf(halfEdge), colour: colourOf(halfEdge));

  /// Writes [attributes] onto [halfEdge], touching only the layers that exist
  /// or that the values differ from their neutral in.
  ///
  /// **The condition is what keeps a copy from creating layers.** An extrusion
  /// copies corners onto the new side quads; on a mesh with no UVs at all, that
  /// would otherwise allocate a UV layer full of zeroes because the copy wrote
  /// the neutral value it had just read.
  void setCorner(int halfEdge, CornerAttributes attributes) {
    if (_uv0 != null || attributes.uv.x != 0 || attributes.uv.y != 0) {
      setUv(halfEdge, attributes.uv);
    }
    if (_colour != null || attributes.colour != kNeutralColor) {
      setColour(halfEdge, attributes.colour);
    }
  }

  /// The skin binding at [vertex]: the first joint at full weight where none
  /// was set, which is what an unskinned vertex means to the shader.
  VertexAttributes skinOf(int vertex) {
    final joints = _joints;
    final weights = _weights;
    if (joints == null && weights == null) return VertexAttributes();
    return VertexAttributes(
      joints: joints == null
          ? Vector4.copy(kNeutralJoints)
          : Vector4(
              joints[vertex * 4],
              joints[vertex * 4 + 1],
              joints[vertex * 4 + 2],
              joints[vertex * 4 + 3],
            ),
      weights: weights == null
          ? Vector4.copy(kNeutralWeights)
          : Vector4(
              weights[vertex * 4],
              weights[vertex * 4 + 1],
              weights[vertex * 4 + 2],
              weights[vertex * 4 + 3],
            ),
    );
  }

  /// Sets the skin binding at [vertex].
  ///
  /// What an import writes when a `.glb` carried a skin (`doc-11`), and what
  /// the weight brush a caller paints with writes per stroke (`anim-09`).
  void setSkin(int vertex, VertexAttributes skin) {
    _wrote = true;
    final joints = _floatLayer(
      _joints,
      _vertexSlots * 4,
      0,
      (JournalledFloats it) => _joints = it,
    );
    final weights = _floatLayer(
      _weights,
      _vertexSlots * 4,
      0,
      (JournalledFloats it) => _weights = it,
    );
    for (var i = 0; i < 4; i++) {
      joints.write(vertex * 4 + i, skin.joints[i]);
      weights.write(vertex * 4 + i, skin.weights[i]);
    }
  }

  /// Whether [halfEdge]'s edge carries [flag] — one of [EdgeFlags].
  bool edgeHas(int halfEdge, int flag) {
    final layer = _edgeFlags;
    return layer != null && layer[halfEdge] & flag != 0;
  }

  /// Sets or clears [flag] on the edge [halfEdge] is half of.
  ///
  /// **Written to both halves.** Sharpness is a property of the edge, and the
  /// two half-edges are two views of it; storing it on one would make the
  /// answer depend on which side a caller happened to walk in from, and that
  /// bug shows up as a crease that appears from one direction only.
  void setEdgeFlag(int halfEdge, int flag, {required bool on}) {
    _wrote = true;
    final layer = _intLayer(
      _edgeFlags,
      _halfEdgeSlots,
      (JournalledInts it) => _edgeFlags = it,
    );
    void put(int half) {
      final was = layer[half];
      layer.write(half, on ? was | flag : was & ~flag);
    }

    put(halfEdge);
    final twin = _twin[halfEdge];
    if (twin != none) put(twin);
  }

  /// How hard the crease along [halfEdge]'s edge is; zero where none was set.
  double creaseOf(int halfEdge) => _crease?[halfEdge] ?? 0;

  /// Sets the crease weight on the edge [halfEdge] is half of, both halves.
  ///
  /// Read by Catmull-Clark (`mesh-45`), where a weight of one holds an edge
  /// through every level of subdivision; a caller sets it from the inspector or
  /// carries it in from a format that has one.
  void setCrease(int halfEdge, double weight) {
    _wrote = true;
    final layer = _floatLayer(
      _crease,
      _halfEdgeSlots,
      0,
      (JournalledFloats it) => _crease = it,
    );
    layer.write(halfEdge, weight);
    final twin = _twin[halfEdge];
    if (twin != none) layer.write(twin, weight);
  }

  /// Which material [face] uses; slot zero where none was set.
  int materialSlotOf(int face) => _materialSlot?[face] ?? 0;

  /// Puts [face] in material slot [slot].
  void setMaterialSlot(int face, int slot) {
    _wrote = true;
    _intLayer(
      _materialSlot,
      _faceSlots,
      (JournalledInts it) => _materialSlot = it,
    ).write(face, slot);
  }

  /// Whether [face] carries [flag] — one of [FaceFlags].
  bool faceHas(int face, int flag) {
    final layer = _faceFlags;
    return layer != null && layer[face] & flag != 0;
  }

  /// Sets or clears [flag] on [face].
  void setFaceFlag(int face, int flag, {required bool on}) {
    _wrote = true;
    final layer = _intLayer(
      _faceFlags,
      _faceSlots,
      (JournalledInts it) => _faceFlags = it,
    );
    final was = layer[face];
    layer.write(face, on ? was | flag : was & ~flag);
  }

  /// Every layer that exists, for the walks that have to touch all of them.
  Iterable<JournalledFloats> get _floatLayers => <JournalledFloats>[
    if (_uv0 case final JournalledFloats it) it,
    if (_colour case final JournalledFloats it) it,
    if (_weights case final JournalledFloats it) it,
    if (_joints case final JournalledFloats it) it,
    if (_crease case final JournalledFloats it) it,
  ];

  Iterable<JournalledInts> get _intLayers => <JournalledInts>[
    if (_edgeFlags case final JournalledInts it) it,
    if (_faceFlags case final JournalledInts it) it,
    if (_materialSlot case final JournalledInts it) it,
  ];

  // ------------------------------------------------------------------ edits

  /// Whether the open step has written anything.
  ///
  /// Kept here rather than asked of the arrays, because the question is "did
  /// this edit do anything", and nine arrays each answering for themselves is
  /// nine answers to one question.
  bool _wrote = false;

  /// Whether a step is open, which a layer created mid-step has to know.
  bool _inStep = false;

  /// The layout plan, and the normals inside it. Made on the first conversion
  /// rather than with the mesh: a document that is only being read never asks.
  MeshLayoutPlan? _plan;

  /// Opens a step of history. Every edit until [endStep] is one undo away.
  void beginStep() {
    _wrote = false;
    _inStep = true;
    _positions.beginStep();
    _origin.beginStep();
    _next.beginStep();
    _twin.beginStep();
    _halfEdgeFace.beginStep();
    _faceHalfEdge.beginStep();
    _outgoing.beginStep();
    _vertexAlive.beginStep();
    _faceAlive.beginStep();
    for (final layer in _floatLayers) {
      layer.beginStep();
    }
    for (final layer in _intLayers) {
      layer.beginStep();
    }
  }

  /// Closes the step. Returns whether anything was written.
  ///
  /// **All nine arrays get a step, or none of them does.** An edit that moved a
  /// vertex wrote to `positions` and nothing else; an edit that deleted a face
  /// wrote to `faceAlive` and nothing else. If the empty ones dropped their
  /// step, the arrays would sit at different depths and one undo would take
  /// positions back a version while leaving the topology where it was. So a
  /// step that wrote anything is recorded everywhere, empty where it has to be,
  /// and a step that wrote nothing is recorded nowhere.
  bool endStep() {
    final wrote = _wrote;
    _positions.endStep(keepEmpty: wrote);
    _origin.endStep(keepEmpty: wrote);
    _next.endStep(keepEmpty: wrote);
    _twin.endStep(keepEmpty: wrote);
    _halfEdgeFace.endStep(keepEmpty: wrote);
    _faceHalfEdge.endStep(keepEmpty: wrote);
    _outgoing.endStep(keepEmpty: wrote);
    _vertexAlive.endStep(keepEmpty: wrote);
    _faceAlive.endStep(keepEmpty: wrote);
    for (final layer in _floatLayers) {
      layer.endStep(keepEmpty: wrote);
    }
    for (final layer in _intLayers) {
      layer.endStep(keepEmpty: wrote);
    }
    _wrote = false;
    _inStep = false;
    return wrote;
  }

  /// Takes the last step back, counts and all.
  bool undo() {
    // Any array answers, because every step is in all of them — see [endStep].
    if (_faceAlive.undoDepth == 0) return false;
    _positions.undo();
    _origin.undo();
    _next.undo();
    _twin.undo();
    _halfEdgeFace.undo();
    _faceHalfEdge.undo();
    _outgoing.undo();
    _vertexAlive.undo();
    _faceAlive.undo();
    for (final layer in _floatLayers) {
      layer.undo();
    }
    for (final layer in _intLayers) {
      layer.undo();
    }
    _recount();
    return true;
  }

  /// Puts the last undone step back.
  bool redo() {
    if (_faceAlive.redoDepth == 0) return false;
    _positions.redo();
    _origin.redo();
    _next.redo();
    _twin.redo();
    _halfEdgeFace.redo();
    _faceHalfEdge.redo();
    _outgoing.redo();
    _vertexAlive.redo();
    _faceAlive.redo();
    for (final layer in _floatLayers) {
      layer.redo();
    }
    for (final layer in _intLayers) {
      layer.redo();
    }
    _recount();
    return true;
  }

  /// How many steps can be taken back.
  int get undoDepth => _faceAlive.undoDepth;

  /// Forgets every step, keeping the mesh as it is.
  ///
  /// **What an import calls, and what saving will.** The mesh a file produced
  /// is a document's starting point: there is nothing before it to go back to,
  /// and a history holding "the state before the model existed" is a step that
  /// empties the viewport. `compact` is the other side of the same rule — see
  /// its note on why a renumbered mesh cannot carry the old journal either.
  void clearJournal() {
    _positions.clearJournal();
    _origin.clearJournal();
    _next.clearJournal();
    _twin.clearJournal();
    _halfEdgeFace.clearJournal();
    _faceHalfEdge.clearJournal();
    _outgoing.clearJournal();
    _vertexAlive.clearJournal();
    _faceAlive.clearJournal();
    for (final layer in _floatLayers) {
      layer.clearJournal();
    }
    for (final layer in _intLayers) {
      layer.clearJournal();
    }
  }

  /// Bytes every journal holds together.
  int get journalBytes =>
      _positions.journalBytes +
      _origin.journalBytes +
      _next.journalBytes +
      _twin.journalBytes +
      _halfEdgeFace.journalBytes +
      _faceHalfEdge.journalBytes +
      _outgoing.journalBytes +
      _vertexAlive.journalBytes +
      _faceAlive.journalBytes;

  /// The live counts, recomputed from the tombstones.
  ///
  /// Called after an undo rather than journalled alongside: a count is derived
  /// from the flags, and a derived value in the journal is a second answer that
  /// can disagree with the first.
  void _recount() {
    var vertices = 0;
    for (var i = 0; i < _vertexSlots; i++) {
      if (_vertexAlive[i] != 0) vertices++;
    }
    var faces = 0;
    for (var i = 0; i < _faceSlots; i++) {
      if (_faceAlive[i] != 0) faces++;
    }
    _liveVertices = vertices;
    _liveFaces = faces;
  }

  /// Moves [vertex] to [to], recording where it was.
  void moveVertex(int vertex, Vector3 to) {
    _wrote = true;
    _positions
      ..write(vertex * 3, to.x)
      ..write(vertex * 3 + 1, to.y)
      ..write(vertex * 3 + 2, to.z);
  }

  /// Marks [face] dead, along with the half-edges on its loop.
  ///
  /// The twins on the other side keep pointing at these half-edges and become
  /// boundary edges by the test [edgeCount] uses: a twin whose face is dead is
  /// a twin with nothing behind it. Rewiring them to [none] instead would lose
  /// the information an undo needs to put the face back.
  void deleteFace(int face) {
    if (_faceAlive[face] == 0) return;
    _wrote = true;
    _faceAlive.write(face, 0);
    _liveFaces--;
  }

  /// Marks [vertex] dead. Its faces must be gone first.
  void deleteVertex(int vertex) {
    if (_vertexAlive[vertex] == 0) return;
    _wrote = true;
    _vertexAlive.write(vertex, 0);
    _liveVertices--;
  }

  // -------------------------------------------------------------- compaction

  /// Closes the gaps the tombstones left, and says where everything went.
  ///
  /// **A new mesh rather than a shuffle in place, and the journal is why.** The
  /// old mesh's history is a set of indices into arrays whose numbering is
  /// about to change; replaying one against compacted arrays would move the
  /// wrong vertices. So compaction produces a mesh with no history, and the
  /// caller — `doc-08` — decides what that means for undo. The plan says it
  /// means the same thing as saving: a boundary the stack does not cross.
  (EditMesh, IdRemap) compact() {
    final vertexMap = Int32List(_vertexSlots)..fillRange(0, _vertexSlots, none);
    final faceMap = Int32List(_faceSlots)..fillRange(0, _faceSlots, none);

    final builder = EditMeshBuilder();
    final position = Vector3.zero();
    for (var vertex = 0; vertex < _vertexSlots; vertex++) {
      if (_vertexAlive[vertex] == 0) continue;
      vertexMap[vertex] = builder.addVertex(positionOf(vertex, position));
    }
    final loop = <int>[];
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      loop.clear();
      forEachVertex(face, (int vertex) => loop.add(vertexMap[vertex]));
      faceMap[face] = builder.addFace(loop);
    }
    return (builder.build(), IdRemap(vertices: vertexMap, faces: faceMap));
  }

  // ------------------------------------------------------------- measurements

  /// The face's normal by Newell's method, which is the one that answers for a
  /// quad whose four points are not quite in a plane.
  Vector3 normalOf(int face, [Vector3? out]) {
    final normal = (out ?? Vector3.zero())..setZero();
    forEachHalfEdge(face, (int half) {
      final from = _origin[half] * 3;
      final to = _origin[_next[half]] * 3;
      final cx = _positions[from];
      final cy = _positions[from + 1];
      final cz = _positions[from + 2];
      final ax = _positions[to];
      final ay = _positions[to + 1];
      final az = _positions[to + 2];
      normal
        ..x += (cy - ay) * (cz + az)
        ..y += (cz - az) * (cx + ax)
        ..z += (cx - ax) * (cy + ay);
    });
    final length = normal.length;
    if (length == 0) return normal..setValues(0, 1, 0);
    return normal..scale(1 / length);
  }

  /// The area of [face], summed over the fan its normal projects onto.
  double areaOf(int face) {
    final loop = verticesOf(face);
    if (loop.length < 3) return 0;
    final anchor = positionOf(loop.first);
    final b = Vector3.zero();
    final c = Vector3.zero();
    var total = 0.0;
    for (var i = 1; i + 1 < loop.length; i++) {
      positionOf(loop[i], b);
      positionOf(loop[i + 1], c);
      b.sub(anchor);
      c.sub(anchor);
      total += b.cross(c).length * 0.5;
    }
    return total;
  }

  /// The volume the surface encloses, signed by winding.
  double get signedVolume {
    var total = 0.0;
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      total += _volumeOf(face);
    }
    return total;
  }

  /// Every live face as a list of vertex numbers.
  List<List<int>> faces() => <List<int>>[
    for (var face = 0; face < _faceSlots; face++)
      if (_faceAlive[face] != 0) verticesOf(face),
  ];

  /// Pushes [face] out along its own normal by [distance], walling in the gap.
  ///
  /// **Rebuilt rather than rewired, and it is the one operation still shaped
  /// like the spike.** `mesh-23` does it in place; what is here is enough to
  /// measure the pipeline and to give the viewport something to draw, and it
  /// returns a fresh mesh rather than editing this one.
  EditMesh extrudeFace(int face, double distance) {
    final loop = verticesOf(face);
    final offset = normalOf(face)..scale(distance);

    final points = <Vector3>[
      for (var vertex = 0; vertex < _vertexSlots; vertex++)
        if (_vertexAlive[vertex] != 0) positionOf(vertex),
    ];
    final base = points.length;
    final lifted = <int>[for (var i = 0; i < loop.length; i++) base + i];
    for (final vertex in loop) {
      points.add(positionOf(vertex)..add(offset));
    }

    final rebuilt = <List<int>>[
      for (var f = 0; f < _faceSlots; f++)
        if (_faceAlive[f] != 0 && f != face) verticesOf(f),
      lifted,
      for (var i = 0; i < loop.length; i++)
        <int>[
          loop[i],
          loop[(i + 1) % loop.length],
          lifted[(i + 1) % loop.length],
          lifted[i],
        ],
    ];
    return EditMesh.fromFaces(points, rebuilt);
  }

  // ------------------------------------------------------------ orientation

  /// Turns every face round, so the surface points the other way.
  ///
  /// **The loops are reversed, not the normals.** A normal is not stored — it
  /// is the winding, read back — so a mesh that "has its normals flipped" is a
  /// mesh whose faces are wound the other way, and anything that pretended
  /// otherwise would disagree with the exporter, the raycast and the volume.
  ///
  /// Every face at once, because a half-edge and its twin have to run in
  /// opposite directions: turning one face and leaving its neighbour would put
  /// two half-edges along the same edge pointing the same way, which is the one
  /// arrangement this structure cannot hold. Turning a selection round is
  /// [makeConsistent]'s side of the problem, and it works per island for the
  /// same reason.
  void flipNormals() {
    _flipFaces(<int>[
      for (var face = 0; face < _faceSlots; face++)
        if (_faceAlive[face] != 0) face,
    ]);
  }

  /// Winds every closed island outwards, and says whether anything turned.
  ///
  /// **Closed islands only, and that is not a shortcut.** "Outwards" is the
  /// direction away from an inside, and a surface with a boundary — a plane, a
  /// cylinder with no caps, half a scanned head — has no inside for a normal to
  /// point out of. Guessing one from the camera or from the first face is how a
  /// model comes back from a round trip with half its faces inverted, so an
  /// open island is left exactly as it was.
  ///
  /// Islands are handled apart because their windings are independent: a file
  /// can hold a correct body and a mirrored hand, and a mesh-wide sign would
  /// have to average them.
  bool makeConsistent() {
    final island = Int32List(_faceSlots)..fillRange(0, _faceSlots, none);
    final members = <List<int>>[];
    final open = <bool>[];
    final volume = <double>[];
    final stack = <int>[];

    for (var seed = 0; seed < _faceSlots; seed++) {
      if (_faceAlive[seed] == 0 || island[seed] != none) continue;
      final id = members.length;
      members.add(<int>[]);
      open.add(false);
      volume.add(0);
      island[seed] = id;
      stack
        ..clear()
        ..add(seed);
      while (stack.isNotEmpty) {
        final face = stack.removeLast();
        members[id].add(face);
        volume[id] += _volumeOf(face);
        forEachHalfEdge(face, (int half) {
          final twin = _twin[half];
          final other = twin == none ? none : _halfEdgeFace[twin];
          if (other == none || _faceAlive[other] == 0) {
            open[id] = true;
            return;
          }
          if (island[other] != none) return;
          island[other] = id;
          stack.add(other);
        });
      }
    }

    var turned = false;
    for (var id = 0; id < members.length; id++) {
      if (open[id] || volume[id] >= 0) continue;
      _flipFaces(members[id]);
      turned = true;
    }
    return turned;
  }

  /// The volume of the cone from the origin over one face, signed by winding.
  double _volumeOf(int face) {
    final loop = verticesOf(face);
    if (loop.length < 3) return 0;
    final anchor = positionOf(loop.first);
    final b = Vector3.zero();
    final c = Vector3.zero();
    var total = 0.0;
    for (var i = 1; i + 1 < loop.length; i++) {
      positionOf(loop[i], b);
      positionOf(loop[i + 1], c);
      total += anchor.dot(b.cross(c)) / 6.0;
    }
    return total;
  }

  /// Reverses the loops of [faces], which must be a set no edge crosses out of.
  void _flipFaces(List<int> faces) {
    if (faces.isEmpty) return;
    _wrote = true;
    final loop = <int>[];
    final origins = <int>[];
    for (final face in faces) {
      loop.clear();
      origins.clear();
      forEachHalfEdge(face, loop.add);
      final count = loop.length;
      for (var i = 0; i < count; i++) {
        origins.add(_origin[loop[i]]);
      }
      // A corner attribute belongs to the vertex the half-edge starts at, and
      // that vertex is about to become the one it used to end at. So the UVs
      // and colours travel one step round the loop with it; an edge attribute
      // does not, because the half-edge still lies on the same edge.
      _rotateCorners(loop, _uv0, 2);
      _rotateCorners(loop, _colour, 4);
      for (var i = 0; i < count; i++) {
        _origin.write(loop[i], origins[(i + 1) % count]);
        _next.write(loop[i], loop[(i - 1 + count) % count]);
      }
    }

    // Every vertex on a turned face is now pointed at by a half-edge that
    // starts somewhere else — the one invariant `validate` catches and nothing
    // else would, until a walk around a vertex went off into another face.
    for (var half = 0; half < _halfEdgeSlots; half++) {
      final face = _halfEdgeFace[half];
      if (face == none || _faceAlive[face] == 0) continue;
      final vertex = _origin[half];
      final out = _outgoing[vertex];
      if (out == none || _origin[out] != vertex) _outgoing.write(vertex, half);
    }
  }

  /// Moves each corner value on [loop] one step towards the front of the loop.
  void _rotateCorners(List<int> loop, JournalledFloats? layer, int width) {
    if (layer == null) return;
    final count = loop.length;
    _rotated.clear();
    for (var i = 0; i < count; i++) {
      for (var c = 0; c < width; c++) {
        _rotated.add(layer[loop[i] * width + c]);
      }
    }
    for (var i = 0; i < count; i++) {
      final from = ((i + 1) % count) * width;
      for (var c = 0; c < width; c++) {
        layer.write(loop[i] * width + c, _rotated[from + c]);
      }
    }
  }

  final List<double> _rotated = <double>[];

  /// The mesh a renderer can draw.
  ///
  /// **Planned and then filled, in one call, throwing the plan away.** A
  /// caller that converts once — an exporter, a test, a screenshot — wants
  /// exactly this. A caller that converts every frame while somebody drags a
  /// vertex wants to keep the plan and call [MeshLayoutPlan.fillVerticesOf],
  /// and the whole reason [MeshLayoutPlan] is a class it can hold is that this
  /// convenience cannot do that for it.
  ///
  /// With [materialSlot] given, only the faces carrying it are converted: a
  /// draw call has one material, so a model with three is three meshes.
  MeshData toMeshData({
    VertexLayout layout = VertexLayout.standard,
    double smoothAngle = MeshNormals.defaultSmoothAngle,
    int? materialSlot,
  }) {
    final plan = _plan ??= MeshLayoutPlan();
    plan.build(
      this,
      layout: layout,
      smoothAngle: smoothAngle,
      materialSlot: materialSlot,
    );
    // Copies rather than the plan's own buffers. The plan is kept on the mesh
    // so its working arrays are not remade every conversion, and that is
    // exactly why what goes out cannot be them: the next call would write over
    // a mesh the caller is still holding.
    final buffer = Float32List(plan.vertexCount * plan.floatsPerVertex);
    plan.fillVertices(this, buffer);
    return MeshData(
      layout: layout,
      vertices: buffer,
      indices: Uint32List.fromList(
        Uint32List.sublistView(plan.indices, 0, plan.triangleCount * 3),
      ),
    );
  }

  /// Throws unless the arrays agree with each other.
  ///
  /// **The invariants, not the shape.** Every one of these has been broken by
  /// an operation in some modeller: a `next` that leaves the face it started
  /// in, a twin that is not mutual, an `outgoing` left pointing at a half-edge
  /// that now starts somewhere else. Each is silent until a loop walk runs
  /// forever or a picked edge belongs to the wrong face.
  void validate() {
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      var walked = 0;
      final start = _faceHalfEdge[face];
      if (start == none) {
        throw StateError('live face $face has no half-edge');
      }
      var half = start;
      do {
        if (_halfEdgeFace[half] != face) {
          throw StateError(
            'half-edge $half is on face $face\'s loop and '
            'belongs to ${_halfEdgeFace[half]}',
          );
        }
        final twin = _twin[half];
        if (twin != none) {
          if (_twin[twin] != half) {
            throw StateError(
              'half-edge $half twins $twin, which twins '
              '${_twin[twin]}',
            );
          }
          if (_origin[_next[half]] != _origin[twin] ||
              _origin[half] != _origin[_next[twin]]) {
            throw StateError(
              'half-edge $half and its twin do not run between '
              'the same two vertices',
            );
          }
        }
        if (_vertexAlive[_origin[half]] == 0) {
          throw StateError(
            'half-edge $half starts at dead vertex '
            '${_origin[half]}',
          );
        }
        walked++;
        if (walked > _halfEdgeSlots) {
          throw StateError('the loop of face $face does not close');
        }
        half = _next[half];
      } while (half != start);
      if (walked < 3) throw StateError('face $face has $walked half-edges');
    }

    for (var vertex = 0; vertex < _vertexSlots; vertex++) {
      if (_vertexAlive[vertex] == 0) continue;
      final out = _outgoing[vertex];
      if (out == none) continue; // a vertex in no face is allowed
      if (_origin[out] != vertex) {
        throw StateError('outgoing of $vertex starts at ${_origin[out]}');
      }
    }
  }
}

/// Builds an [EditMesh] vertex by vertex and face by face.
///
/// **Separate from the mesh, and the reason is the twin table.** Matching a
/// half-edge with the one going the other way needs a map from a vertex pair to
/// a half-edge, and that map is worth nothing once the mesh is built: keeping
/// it on `EditMesh` would be a hash table per mesh, alive for the life of the
/// document, to answer a question only construction asks.
final class EditMeshBuilder {
  final List<double> _positions = <double>[];
  final List<int> _origin = <int>[];
  final List<int> _next = <int>[];
  final List<int> _twin = <int>[];
  final List<int> _face = <int>[];
  final List<int> _faceHalfEdge = <int>[];
  final List<int> _outgoing = <int>[];

  /// A half-edge by the pair of vertices it runs between, so its twin can find
  /// it. Keyed on `from * 2^32 + to` rather than on a record: an int key is a
  /// hash and a compare, and a record is an allocation per edge.
  final Map<int, int> _byPair = <int, int>{};

  int get vertexCount => _outgoing.length;
  int get faceCount => _faceHalfEdge.length;

  /// Adds a vertex and returns its number.
  int addVertex(Vector3 position) {
    _positions
      ..add(position.x)
      ..add(position.y)
      ..add(position.z);
    _outgoing.add(EditMesh.none);
    return _outgoing.length - 1;
  }

  /// Adds a face over [loop], wound counter-clockwise seen from outside.
  ///
  /// A third face on one edge is refused rather than silently kept: repairing
  /// non-manifold input is `mesh-13`'s job, done deliberately and reported, and
  /// dropping a face here would make every count the mesh reports disagree with
  /// what the caller handed over.
  int addFace(List<int> loop) {
    if (loop.length < 3) {
      throw ArgumentError('a face of ${loop.length} vertices');
    }
    final face = _faceHalfEdge.length;
    final first = _origin.length;
    _faceHalfEdge.add(first);

    for (var i = 0; i < loop.length; i++) {
      final from = loop[i];
      final to = loop[(i + 1) % loop.length];
      if (from < 0 || from >= _outgoing.length) {
        throw ArgumentError(
          'face $face names vertex $from, which is not there',
        );
      }
      final index = first + i;

      _origin.add(from);
      _next.add(first + (i + 1) % loop.length);
      _twin.add(EditMesh.none);
      _face.add(face);
      if (_outgoing[from] == EditMesh.none) _outgoing[from] = index;

      final key = from * 0x100000000 + to;
      final opposite = to * 0x100000000 + from;
      final partner = _byPair.remove(opposite);
      if (partner != null) {
        _twin[index] = partner;
        _twin[partner] = index;
      } else if (_byPair.containsKey(key)) {
        throw ArgumentError(
          'the edge $from-$to is used twice the same way round, which is a '
          'third face on one edge rather than two',
        );
      } else {
        _byPair[key] = index;
      }
    }
    return face;
  }

  /// The mesh, with every element alive and no history.
  EditMesh build() {
    final mesh = EditMesh._(
      JournalledFloats.of(Float32List.fromList(_positions)),
      JournalledInts.of(Int32List.fromList(_origin)),
      JournalledInts.of(Int32List.fromList(_next)),
      JournalledInts.of(Int32List.fromList(_twin)),
      JournalledInts.of(Int32List.fromList(_face)),
      JournalledInts.of(Int32List.fromList(_faceHalfEdge)),
      JournalledInts.of(Int32List.fromList(_outgoing)),
      JournalledInts.of(
        Int32List(_outgoing.length)..fillRange(0, _outgoing.length, 1),
      ),
      JournalledInts.of(
        Int32List(_faceHalfEdge.length)..fillRange(0, _faceHalfEdge.length, 1),
      ),
    );
    mesh._recount();
    return mesh;
  }
}
