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

  /// Reads a mesh back from [bytes].
  ///
  /// See [toBytes] for the format. A section this version does not know is
  /// skipped by the length it declares, so a file written by a later one still
  /// loads — with whatever that section carried missing, which is the honest
  /// half of forward compatibility and the reason the length is written down.
  factory EditMesh.fromBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 8 || data.getUint32(0, Endian.little) != _magic) {
      throw ArgumentError(
        'not an editable mesh: the first four bytes are not '
        'the ones this format starts with',
      );
    }
    final version = data.getUint32(4, Endian.little);
    if (version > _version) {
      throw ArgumentError(
        'this mesh was written by version $version and this is version '
        '$_version, which cannot read it',
      );
    }

    var vertexSlots = 0;
    var faceSlots = 0;
    var halfEdgeSlots = 0;
    final ints = <String, Int32List>{};
    final floats = <String, Float32List>{};

    var at = 8;
    while (at + 8 <= bytes.length) {
      final tag = String.fromCharCodes(bytes, at, at + 4);
      final length = data.getUint32(at + 4, Endian.little);
      final payload = at + 8;
      if (payload + length > bytes.length) {
        throw ArgumentError(
          'section $tag says it is $length bytes and the '
          'file ends before that',
        );
      }
      if (tag == _sizes) {
        vertexSlots = data.getInt32(payload, Endian.little);
        faceSlots = data.getInt32(payload + 4, Endian.little);
        halfEdgeSlots = data.getInt32(payload + 8, Endian.little);
      } else if (_intSections.contains(tag)) {
        ints[tag] = _readInts(data, payload, length);
      } else if (_floatSections.contains(tag)) {
        floats[tag] = _readFloats(data, payload, length);
      }
      // Rounded up, which is what the padding is for: every section starts on
      // a boundary, so a reader that skipped one lands on the next tag rather
      // than three bytes into it.
      at = payload + ((length + 3) & ~3);
    }

    Int32List need(String tag, int count) {
      final found = ints[tag];
      if (found == null || found.length != count) {
        throw ArgumentError('section $tag is missing or the wrong size');
      }
      return found;
    }

    final mesh = EditMesh._(
      JournalledFloats.of(floats[_positions_] ?? Float32List(vertexSlots * 3)),
      JournalledInts.of(need(_origins, halfEdgeSlots)),
      JournalledInts.of(need(_nexts, halfEdgeSlots)),
      JournalledInts.of(need(_twins, halfEdgeSlots)),
      JournalledInts.of(need(_halfEdgeFaces, halfEdgeSlots)),
      JournalledInts.of(need(_faceHalfEdges, faceSlots)),
      JournalledInts.of(need(_outgoings, vertexSlots)),
      JournalledInts.of(need(_vertexAlives, vertexSlots)),
      JournalledInts.of(need(_faceAlives, faceSlots)),
    );
    mesh._uv0 = _layerOf(floats[_uvs]);
    mesh._colour = _layerOf(floats[_colours]);
    mesh._weights = _layerOf(floats[_weightsTag]);
    mesh._joints = _layerOf(floats[_jointsTag]);
    mesh._crease = _layerOf(floats[_creases]);
    mesh._edgeFlags = _intLayerOf(ints[_edgeFlagsTag]);
    mesh._faceFlags = _intLayerOf(ints[_faceFlagsTag]);
    mesh._materialSlot = _intLayerOf(ints[_materialSlots]);
    mesh._recount();
    return mesh;
  }

  /// What an index means when there is nothing there: a half-edge on a
  /// boundary has no twin, a deleted element has no successor.
  static const int none = -1;

  // The byte format. Four characters and a length per section, so a reader
  // that does not know a tag can step over it — see [toBytes].
  static const int _magic = 0x4D443346; // 'F3DM', little-endian
  static const int _version = 1;
  static const String _sizes = 'SIZE';
  static const String _positions_ = 'POSI';
  static const String _origins = 'ORIG';
  static const String _nexts = 'NEXT';
  static const String _twins = 'TWIN';
  static const String _halfEdgeFaces = 'HEFA';
  static const String _faceHalfEdges = 'FAHE';
  static const String _outgoings = 'OUTG';
  static const String _vertexAlives = 'VALV';
  static const String _faceAlives = 'FALV';
  static const String _uvs = 'UV0 ';
  static const String _colours = 'COLR';
  static const String _weightsTag = 'WGHT';
  static const String _jointsTag = 'JNTS';
  static const String _creases = 'CRES';
  static const String _edgeFlagsTag = 'EFLG';
  static const String _faceFlagsTag = 'FFLG';
  static const String _materialSlots = 'MSLT';

  static const Set<String> _intSections = <String>{
    _origins,
    _nexts,
    _twins,
    _halfEdgeFaces,
    _faceHalfEdges,
    _outgoings,
    _vertexAlives,
    _faceAlives,
    _edgeFlagsTag,
    _faceFlagsTag,
    _materialSlots,
  };
  static const Set<String> _floatSections = <String>{
    _positions_,
    _uvs,
    _colours,
    _weightsTag,
    _jointsTag,
    _creases,
  };

  static Int32List _readInts(ByteData data, int at, int length) {
    final out = Int32List(length ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt32(at + i * 4, Endian.little);
    }
    return out;
  }

  static Float32List _readFloats(ByteData data, int at, int length) {
    final out = Float32List(length ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getFloat32(at + i * 4, Endian.little);
    }
    return out;
  }

  static JournalledFloats? _layerOf(Float32List? values) =>
      values == null ? null : JournalledFloats.of(values);

  static JournalledInts? _intLayerOf(Int32List? values) =>
      values == null ? null : JournalledInts.of(values);

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

  /// Whether there is a live face on the other side of [halfEdge].
  ///
  /// Not the same question as "does it have a twin": deleting a face leaves
  /// the twins on the far side pointing into it, because that is what an undo
  /// needs to put it back. Everything that walks the surface has to ask this
  /// one instead, and [edgeCount] already did before there was a name for it.
  bool hasLiveTwin(int halfEdge) {
    final twin = _twin[halfEdge];
    if (twin == none) return false;
    final face = _halfEdgeFace[twin];
    return face != none && _faceAlive[face] != 0;
  }

  /// The half-edge that stands for the whole edge [halfEdge] lies on.
  ///
  /// **An edge is not stored, so one of its two half-edges has to be it.** A
  /// selection holds numbers and has to hold the same number whichever side an
  /// edge was picked from, so the smaller of the pair is the edge; a half-edge
  /// with nothing live behind it is an edge on its own.
  int edgeOf(int halfEdge) {
    if (!hasLiveTwin(halfEdge)) return halfEdge;
    final twin = _twin[halfEdge];
    return halfEdge < twin ? halfEdge : twin;
  }

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

  /// How many slots each array held before the open step, and before each of
  /// the steps behind it.
  ///
  /// **Growth is the one thing the journals do not record.** A step that added
  /// a vertex is undone by there being one vertex fewer, which is a count
  /// rather than a value — see [JournalledFloats.grow]. Three numbers per step
  /// is what that costs, and keeping them here rather than in nine arrays is
  /// what keeps them from disagreeing.
  final List<int> _undoSlots = <int>[];
  final List<int> _redoSlots = <int>[];
  int _openVertexSlots = 0;
  int _openFaceSlots = 0;
  int _openHalfEdgeSlots = 0;

  /// Opens a step of history. Every edit until [endStep] is one undo away.
  void beginStep() {
    _wrote = false;
    _inStep = true;
    _openVertexSlots = _vertexSlots;
    _openFaceSlots = _faceSlots;
    _openHalfEdgeSlots = _halfEdgeSlots;
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
    if (wrote) {
      _undoSlots.addAll(<int>[
        _openVertexSlots,
        _openFaceSlots,
        _openHalfEdgeSlots,
      ]);
      _redoSlots.clear();
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
    _redoSlots.addAll(<int>[_vertexSlots, _faceSlots, _halfEdgeSlots]);
    _halfEdgeSlots = _undoSlots.removeLast();
    _faceSlots = _undoSlots.removeLast();
    _vertexSlots = _undoSlots.removeLast();
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
    _undoSlots.addAll(<int>[_vertexSlots, _faceSlots, _halfEdgeSlots]);
    _halfEdgeSlots = _redoSlots.removeLast();
    _faceSlots = _redoSlots.removeLast();
    _vertexSlots = _redoSlots.removeLast();
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
    _undoSlots.clear();
    _redoSlots.clear();
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

  // ------------------------------------------------------------------ growth

  /// Adds a vertex at [at] and returns its number.
  ///
  /// **The arrays grow; the numbering does not shift.** Everything a caller is
  /// holding — a selection, an id an agent was given, a row of a layout plan —
  /// still means what it did. Undoing the step takes the slot count back, which
  /// is what makes the vertex go away without anything else moving.
  int addVertex(Vector3 at) {
    _wrote = true;
    final vertex = _vertexSlots++;
    _positions.grow(_vertexSlots * 3);
    _outgoing.grow(_vertexSlots, fill: none);
    _vertexAlive.grow(_vertexSlots);
    _weights?.grow(_vertexSlots * 4);
    _joints?.grow(_vertexSlots * 4);

    _positions
      ..write(vertex * 3, at.x)
      ..write(vertex * 3 + 1, at.y)
      ..write(vertex * 3 + 2, at.z);
    _outgoing.write(vertex, none);
    _vertexAlive.write(vertex, 1);
    _liveVertices++;
    return vertex;
  }

  /// Adds a face over [loop] and returns its number. Its half-edges are
  /// numbered consecutively from what [halfEdgeSlotCount] read before the call.
  ///
  /// **The twins are the caller's to name**, through [weldTwins], and this is
  /// the one place the package asks that of anybody. `EditMeshBuilder` finds
  /// them with a hash of vertex pairs, which is right when a whole mesh is
  /// being built and wrong here: an operation adding four walls to an extrusion
  /// already knows which half-edge each one meets, and a map over every edge of
  /// the document to rediscover it would cost more than the operation.
  int addFace(List<int> loop) {
    if (loop.length < 3) {
      throw ArgumentError('a face of ${loop.length} vertices');
    }
    final face = _newFace();
    final first = _newHalfEdges(loop.length);

    for (var i = 0; i < loop.length; i++) {
      final half = first + i;
      _origin.write(half, loop[i]);
      _next.write(half, first + (i + 1) % loop.length);
      _twin.write(half, none);
      _halfEdgeFace.write(half, face);
      final out = _outgoing[loop[i]];
      if (out == none) _outgoing.write(loop[i], half);
    }
    _faceHalfEdge.write(face, first);
    _faceAlive.write(face, 1);
    _liveFaces++;
    return face;
  }

  /// Reserves [count] consecutive half-edge slots and returns the first.
  int _newHalfEdges(int count) {
    _wrote = true;
    final first = _halfEdgeSlots;
    _halfEdgeSlots += count;
    _origin.grow(_halfEdgeSlots);
    _next.grow(_halfEdgeSlots);
    _twin.grow(_halfEdgeSlots, fill: none);
    _halfEdgeFace.grow(_halfEdgeSlots, fill: none);
    _uv0?.grow(_halfEdgeSlots * 2);
    _colour?.grow(_halfEdgeSlots * 4);
    _crease?.grow(_halfEdgeSlots);
    _edgeFlags?.grow(_halfEdgeSlots);
    return first;
  }

  /// Reserves a face slot and returns it. Nothing is on its loop yet.
  int _newFace() {
    _wrote = true;
    final face = _faceSlots++;
    _faceHalfEdge.grow(_faceSlots);
    _faceAlive.grow(_faceSlots);
    _faceFlags?.grow(_faceSlots);
    _materialSlot?.grow(_faceSlots);
    return face;
  }

  /// Puts a vertex on the edge [halfEdge] lies on and returns it.
  ///
  /// **The faces on either side gain a corner; nothing is cut in two.** A
  /// four-sided face beside a split edge becomes a five-sided one, and that is
  /// the honest intermediate state — a loop cut is this on every edge of a ring
  /// followed by [splitFace] through each of the faces between them, and doing
  /// the two at once would make an operation that cannot be reused.
  ///
  /// [factor] runs from the vertex [halfEdge] starts at towards the one it ends
  /// at, so the direction the caller asks in is the direction it gets. The
  /// corner attributes on both sides are interpolated to match, and the skin
  /// weights are the vertex's own — a vertex put half way along an edge belongs
  /// half to each end's bones.
  int splitEdge(int halfEdge, {double factor = 0.5}) {
    final face = _halfEdgeFace[halfEdge];
    if (face == none || _faceAlive[face] == 0) return none;

    final from = _origin[halfEdge];
    final ahead = _next[halfEdge];
    final to = _origin[ahead];
    final middle = addVertex(
      positionOf(from) * (1 - factor) + positionOf(to) * factor,
    );

    final far = _newHalfEdges(1);
    _origin.write(far, middle);
    _next.write(far, ahead);
    _halfEdgeFace.write(far, face);
    _twin.write(far, none);
    _next.write(halfEdge, far);
    if (_uv0 != null || _colour != null) {
      setCorner(
        far,
        CornerAttributes.lerp(cornerOf(halfEdge), cornerOf(ahead), factor),
      );
    }
    _carryEdgeAttributes(halfEdge, far);

    final twin = _twin[halfEdge];
    if (twin != none && _halfEdgeFace[twin] != none) {
      final behind = _halfEdgeFace[twin];
      final beyond = _next[twin];
      final back = _newHalfEdges(1);
      _origin.write(back, middle);
      _next.write(back, beyond);
      _halfEdgeFace.write(back, behind);
      _next.write(twin, back);
      if (_uv0 != null || _colour != null) {
        setCorner(
          back,
          CornerAttributes.lerp(cornerOf(twin), cornerOf(beyond), 1 - factor),
        );
      }
      _carryEdgeAttributes(twin, back);
      // The near halves face each other, and so do the far ones.
      _twin.write(halfEdge, back);
      _twin.write(back, halfEdge);
      _twin.write(far, twin);
      _twin.write(twin, far);
    }

    if (_weights != null || _joints != null) {
      setSkin(middle, VertexAttributes.lerp(skinOf(from), skinOf(to), factor));
    }
    _outgoing.write(middle, far);
    return middle;
  }

  /// Copies the sharpness and crease of [from] onto [to], which is the other
  /// half of the edge it was just cut from.
  void _carryEdgeAttributes(int from, int to) {
    if (_crease case final JournalledFloats layer) {
      layer.write(to, layer[from]);
    }
    if (_edgeFlags case final JournalledInts layer) {
      layer.write(to, layer[from]);
    }
  }

  /// Cuts [face] in two along the line between the corners [from] and [to]
  /// start at, and returns the new face.
  ///
  /// Both must be on [face]'s loop and neither next to the other: a cut between
  /// neighbours would leave a side with two corners, which is not a face.
  int splitFace(int face, int from, int to) {
    if (_faceAlive[face] == 0) return none;
    if (from == to || _next[from] == to || _next[to] == from) return none;
    if (_halfEdgeFace[from] != face || _halfEdgeFace[to] != face) return none;

    final beforeFrom = _prevOf(from);
    final beforeTo = _prevOf(to);
    final made = _newFace();
    final diagonal = _newHalfEdges(2);
    final back = diagonal;
    final forth = diagonal + 1;

    // One side keeps the face and closes through `back`; the other is new and
    // closes through `forth`.
    _origin.write(back, _origin[to]);
    _next.write(back, from);
    _halfEdgeFace.write(back, face);
    _next.write(beforeTo, back);

    _origin.write(forth, _origin[from]);
    _next.write(forth, to);
    _halfEdgeFace.write(forth, made);
    _next.write(beforeFrom, forth);

    _twin.write(back, forth);
    _twin.write(forth, back);

    var walk = to;
    do {
      _halfEdgeFace.write(walk, made);
      walk = _next[walk];
    } while (walk != to);

    _faceHalfEdge.write(face, from);
    _faceHalfEdge.write(made, to);
    _faceAlive.write(made, 1);
    _liveFaces++;

    if (_materialSlot != null) setMaterialSlot(made, materialSlotOf(face));
    if (_faceFlags != null) {
      setFaceFlag(made, FaceFlags.smooth, on: faceHas(face, FaceFlags.smooth));
    }
    if (_uv0 != null || _colour != null) {
      setCorner(back, cornerOf(to));
      setCorner(forth, cornerOf(from));
    }
    return made;
  }

  /// Makes [a] and [b] the two sides of one edge.
  ///
  /// Whatever either of them was twinned to is let go first, so an operation
  /// that detaches a region and sews a wall into the gap does not leave the
  /// half-edge on the far side pointing at something that has moved on.
  void weldTwins(int a, int b) {
    _wrote = true;
    final wasA = _twin[a];
    final wasB = _twin[b];
    if (wasA != none && wasA != b) _twin.write(wasA, none);
    if (wasB != none && wasB != a) _twin.write(wasB, none);
    _twin.write(a, b);
    _twin.write(b, a);
  }

  /// Lets go of whatever was on the other side of [halfEdge], leaving it on a
  /// boundary.
  ///
  /// What an operation calls when it takes a piece of the surface away from
  /// its neighbours without moving it — `splitSelection` — and the one write
  /// that turns a shared edge into two rims.
  void cutTwin(int halfEdge) {
    final twin = _twin[halfEdge];
    if (twin == none) return;
    _wrote = true;
    _twin.write(twin, none);
    _twin.write(halfEdge, none);
  }

  /// Points [vertex] at [halfEdge] as its way into the mesh.
  ///
  /// What an operation calls after rewiring a loop out from under a vertex.
  /// [validate] asks that the half-edge starts there; what it cannot ask is
  /// that the half-edge is still on a live loop, so an operation that moves one
  /// says where the vertex goes instead.
  void setOutgoing(int vertex, int halfEdge) {
    _wrote = true;
    _outgoing.write(vertex, halfEdge);
  }

  /// Makes [halfEdge] start at [vertex].
  void setOrigin(int halfEdge, int vertex) {
    _wrote = true;
    _origin.write(halfEdge, vertex);
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
  /// A caller that deletes faces calls [repairVertexLinks] once afterwards: a
  /// vertex whose way into the mesh was a half-edge of a face that has just
  /// died needs a new one, and finding it per face would be a walk over the
  /// mesh per face.
  void deleteFace(int face) {
    if (_faceAlive[face] == 0) return;
    _wrote = true;
    _faceAlive.write(face, 0);
    _liveFaces--;
  }

  /// Points every vertex at a half-edge that is still on a live loop.
  ///
  /// **What deleting faces leaves behind, and what nothing else catches.**
  /// [validate] asks that a vertex's half-edge starts there, which a dead one
  /// still does; what it cannot ask is that a walk from it goes anywhere. A
  /// vertex left pointing into a deleted face is invisible until somebody
  /// walks the fan around it — a normal, a loop, a selection grown by one —
  /// and then it walks into nothing.
  ///
  /// One pass over the half-edges rather than a search per vertex, which is
  /// why it is a separate call: `deleteSelection` kills a hundred faces and
  /// pays for this once.
  void repairVertexLinks() {
    _wrote = true;
    final alive = Int32List(_vertexSlots)..fillRange(0, _vertexSlots, none);
    for (var face = 0; face < _faceSlots; face++) {
      if (_faceAlive[face] == 0) continue;
      forEachHalfEdge(face, (int half) {
        alive[_origin[half]] = half;
      });
    }
    for (var vertex = 0; vertex < _vertexSlots; vertex++) {
      if (_vertexAlive[vertex] == 0) continue;
      final out = _outgoing[vertex];
      final onALiveLoop =
          out != none &&
          _origin[out] == vertex &&
          _halfEdgeFace[out] != none &&
          _faceAlive[_halfEdgeFace[out]] != 0;
      // Written only when it has to be, so a delete of one face does not put
      // every vertex of the mesh into the step.
      if (!onALiveLoop) _outgoing.write(vertex, alive[vertex]);
    }
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

  // -------------------------------------------------------------- dissolving

  /// The half-edge before [halfEdge] on its own loop.
  ///
  /// Walked rather than stored: a loop is singly linked, and a back link per
  /// half-edge is four bytes each to answer a question only the operations that
  /// rewire a loop ever ask — of a face with five corners, once.
  int _prevOf(int halfEdge) {
    var walk = halfEdge;
    var guard = _halfEdgeSlots;
    while (_next[walk] != halfEdge) {
      walk = _next[walk];
      if (--guard < 0) {
        throw StateError('the loop through $halfEdge does not close');
      }
    }
    return walk;
  }

  /// Removes the edge [halfEdge] lies on, so the two faces it separated become
  /// one. Returns whether it happened.
  ///
  /// **The edge goes; its vertices stay.** That is what makes this the operation
  /// that turns a triangulated import back into quads: dissolving the six
  /// diagonals of a triangulated box leaves the eight corners exactly where they
  /// were and six four-sided faces where there were twelve triangles. Deleting
  /// the edge instead would take the faces with it.
  ///
  /// Refused rather than half-done in three cases, each of which would leave a
  /// loop that does not describe a polygon: an edge with nothing live behind it
  /// — dissolving it would have to delete the one face it has, which is
  /// `mesh-26`'s job; an edge whose two sides are the same face, where removing
  /// it splits the face or opens a hole; and two faces that meet along more than
  /// this one edge, where merging leaves a slit down the middle of the result.
  bool dissolveEdge(int halfEdge) {
    final gone = edgeOf(halfEdge);
    if (!hasLiveTwin(gone)) return false;
    final twin = _twin[gone];
    final keep = _halfEdgeFace[gone];
    final absorbed = _halfEdgeFace[twin];
    if (keep == none || absorbed == none || keep == absorbed) return false;
    // The merged loop is both loops with one half-edge dropped from each.
    if (_valencyOf(keep) + _valencyOf(absorbed) - 2 < 3) return false;

    var meetings = 0;
    forEachHalfEdge(keep, (int half) {
      if (hasLiveTwin(half) && _halfEdgeFace[_twin[half]] == absorbed) {
        meetings++;
      }
    });
    if (meetings != 1) return false;

    final beforeGone = _prevOf(gone);
    final beforeTwin = _prevOf(twin);
    final afterGone = _next[gone];
    final afterTwin = _next[twin];

    _wrote = true;
    // The two loops are cut open at the shared edge and sewn to each other.
    _next.write(beforeGone, afterTwin);
    _next.write(beforeTwin, afterGone);
    _halfEdgeFace.write(gone, none);
    _halfEdgeFace.write(twin, none);

    var walk = afterGone;
    do {
      _halfEdgeFace.write(walk, keep);
      walk = _next[walk];
    } while (walk != afterGone);

    _faceHalfEdge.write(keep, afterGone);
    _faceAlive.write(absorbed, 0);
    _liveFaces--;

    // Both endpoints were pointed at by a half-edge that is now on no loop.
    // `next` of the removed pair starts at exactly those two vertices.
    _outgoing.write(_origin[gone], afterTwin);
    _outgoing.write(_origin[twin], afterGone);
    return true;
  }

  /// Removes [vertex] and every edge at it, so the ring of faces around it
  /// becomes one face. Returns whether it happened.
  ///
  /// **The link of the vertex is the new face.** Four quads round a vertex of a
  /// sheet become one eight-sided face over the eight points that surrounded it;
  /// nothing else moves. What this is for is a vertex somebody put in and no
  /// longer wants — the middle of an over-subdivided patch, the leftover of a
  /// cut that went too far — where deleting it would leave a hole.
  ///
  /// Refused where the ring is not a ring: a vertex on a boundary, whose fan
  /// does not close and so has no surrounding polygon, and a vertex the same
  /// face reaches twice, which is a pinch rather than a fan. The second of
  /// those is a guard the tests do not reach — every pinched vertex they can
  /// build has a boundary somewhere and is refused for that first — so it is
  /// here on the argument rather than on a measurement, and it is cheap.
  ///
  /// What comes out always has at least three corners without being checked
  /// for it: three faces at the least, of at least three corners each, and
  /// every one of them gives up exactly two.
  bool dissolveVertex(int vertex) {
    if (_vertexAlive[vertex] == 0) return false;
    final start = _outgoing[vertex];
    if (start == none) return false;

    // The fan, in rotation order: each half-edge leaves the vertex, and the
    // next one round is the successor of its twin.
    final fan = <int>[];
    final faces = <int>{};
    var walk = start;
    do {
      final face = _halfEdgeFace[walk];
      if (face == none || _faceAlive[face] == 0) return false;
      if (!hasLiveTwin(walk)) return false;
      if (!faces.add(face)) return false;
      fan.add(walk);
      if (fan.length > _halfEdgeSlots) return false;
      walk = _next[_twin[walk]];
    } while (walk != start);
    if (fan.length < 3) return false;

    // Read the whole rewiring before writing any of it: `_prevOf` walks the
    // loops, and a loop half rewired is a loop that does not close.
    final count = fan.length;
    final firstOut = <int>[for (final half in fan) _next[half]];
    final lastIn = <int>[for (final half in fan) _prevOf(_prevOf(half))];

    _wrote = true;
    for (var i = 0; i < count; i++) {
      // What used to run into the vertex now runs into the chain that used to
      // leave it in the previous face round the fan.
      _next.write(lastIn[i], firstOut[(i - 1 + count) % count]);
    }

    final keep = _halfEdgeFace[fan.first];
    for (final half in fan) {
      _halfEdgeFace.write(half, none);
      _halfEdgeFace.write(_twin[half], none);
    }
    walk = firstOut.first;
    do {
      _halfEdgeFace.write(walk, keep);
      walk = _next[walk];
    } while (walk != firstOut.first);

    for (final face in faces) {
      if (face == keep) continue;
      _faceAlive.write(face, 0);
      _liveFaces--;
    }
    _faceHalfEdge.write(keep, firstOut.first);

    for (var i = 0; i < count; i++) {
      _outgoing.write(_origin[firstOut[i]], firstOut[i]);
    }
    _vertexAlive.write(vertex, 0);
    _liveVertices--;
    _outgoing.write(vertex, none);
    return true;
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
    final drawn = MeshData(
      layout: layout,
      vertices: buffer,
      indices: Uint32List.fromList(
        Uint32List.sublistView(plan.indices, 0, plan.triangleCount * 3),
      ),
    );
    // **Tangents, because this is the call that converts once.** A layout that
    // declares a tangent and carries zeros is a model that draws black under a
    // normal map, and every caller of this one — an exporter, a screenshot, a
    // test — would have to know to ask. The plan's own conversion is where a
    // viewport goes, and it is the one that leaves the choice open.
    return layout.has(VertexLayout.tangent)
        ? drawn.withGeneratedTangents()
        : drawn;
  }

  // ------------------------------------------------------------------ bytes

  /// The mesh as bytes, which is what a file holds and what crosses to an
  /// isolate.
  ///
  /// **Sections with a tag and a length, each starting on a boundary of four.**
  /// Eight bytes of header — `F3DM` and a version — and then a run of sections:
  /// four characters, a length, that many bytes, and padding up to the next
  /// multiple of four. A reader steps over a tag it does not know by the length
  /// it declares, which is what lets a later version add a layer without
  /// stopping an earlier one from opening the file. The padding is what makes
  /// stepping over land on a tag rather than inside one.
  ///
  /// Every section *this* version writes is a whole number of four-byte values
  /// long, so the writer's padding never adds a byte and no test here can tell
  /// it from nothing. It is the format's promise rather than today's code: the
  /// first section that carries a name or a comment will need it, and a reader
  /// written now already rounds up — which is the half a test does reach.
  ///
  /// **Little-endian, spelled out rather than viewed.** Handing over a view of
  /// the typed arrays would be faster and would write a different file on a
  /// machine of the other byte order, and a mesh is a document. `mesh-30`'s
  /// isolate transfer is the case where speed matters, and it moves the arrays
  /// themselves rather than going through here.
  ///
  /// **Deterministic**: the same mesh writes the same bytes, because the
  /// sections go in a fixed order and only the layers that exist are written.
  /// A file that changes when nothing did is a file nobody can diff.
  ///
  /// The journal is not in it. What a document does about history across a
  /// save is `doc-08`'s, and the plan's answer is that saving is a boundary
  /// the undo stack does not cross.
  Uint8List toBytes() {
    final sections = <(String, TypedData)>[
      (
        _sizes,
        Int32List.fromList(<int>[_vertexSlots, _faceSlots, _halfEdgeSlots]),
      ),
      (_positions_, _floatsOf(_positions, _vertexSlots * 3)),
      (_origins, _intsOf(_origin, _halfEdgeSlots)),
      (_nexts, _intsOf(_next, _halfEdgeSlots)),
      (_twins, _intsOf(_twin, _halfEdgeSlots)),
      (_halfEdgeFaces, _intsOf(_halfEdgeFace, _halfEdgeSlots)),
      (_faceHalfEdges, _intsOf(_faceHalfEdge, _faceSlots)),
      (_outgoings, _intsOf(_outgoing, _vertexSlots)),
      (_vertexAlives, _intsOf(_vertexAlive, _vertexSlots)),
      (_faceAlives, _intsOf(_faceAlive, _faceSlots)),
      if (_uv0 case final JournalledFloats it)
        (_uvs, _floatsOf(it, _halfEdgeSlots * 2)),
      if (_colour case final JournalledFloats it)
        (_colours, _floatsOf(it, _halfEdgeSlots * 4)),
      if (_weights case final JournalledFloats it)
        (_weightsTag, _floatsOf(it, _vertexSlots * 4)),
      if (_joints case final JournalledFloats it)
        (_jointsTag, _floatsOf(it, _vertexSlots * 4)),
      if (_crease case final JournalledFloats it)
        (_creases, _floatsOf(it, _halfEdgeSlots)),
      if (_edgeFlags case final JournalledInts it)
        (_edgeFlagsTag, _intsOf(it, _halfEdgeSlots)),
      if (_faceFlags case final JournalledInts it)
        (_faceFlagsTag, _intsOf(it, _faceSlots)),
      if (_materialSlot case final JournalledInts it)
        (_materialSlots, _intsOf(it, _faceSlots)),
    ];

    var total = 8;
    for (final (_, payload) in sections) {
      total += 8 + ((payload.lengthInBytes + 3) & ~3);
    }

    final out = Uint8List(total);
    final data = ByteData.sublistView(out);
    data
      ..setUint32(0, _magic, Endian.little)
      ..setUint32(4, _version, Endian.little);

    var at = 8;
    for (final (tag, payload) in sections) {
      out.setRange(at, at + 4, tag.codeUnits);
      data.setUint32(at + 4, payload.lengthInBytes, Endian.little);
      at += 8;
      if (payload is Float32List) {
        for (var i = 0; i < payload.length; i++) {
          data.setFloat32(at + i * 4, payload[i], Endian.little);
        }
      } else if (payload is Int32List) {
        for (var i = 0; i < payload.length; i++) {
          data.setInt32(at + i * 4, payload[i], Endian.little);
        }
      }
      at += (payload.lengthInBytes + 3) & ~3;
    }
    return out;
  }

  Int32List _intsOf(JournalledInts layer, int count) =>
      Int32List.sublistView(layer.values, 0, count);

  Float32List _floatsOf(JournalledFloats layer, int count) =>
      Float32List.sublistView(layer.values, 0, count);

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
          // Which two vertices, only where there is a live face on the other
          // side. A deleted face keeps its links so an undo can put it back —
          // that is what [deleteFace] promises — and an operation that moved a
          // corner of the *living* face since is under no obligation to have
          // moved the dead one's with it. Asking anyway made every split and
          // every extrusion beside a deleted face look broken, which is what a
          // fuzz run over five hundred operations found.
          if (hasLiveTwin(half) &&
              (_origin[_next[half]] != _origin[twin] ||
                  _origin[half] != _origin[_next[twin]])) {
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
