import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../geometry/mesh_geometry.dart';
import 'mesh_node.dart';

/// One mesh drawn many times in one call, each copy with a transform and a
/// colour of its own.
///
/// **A thousand nodes is a thousand draws; this is one.** Grass, rubble, a
/// crowd, the pillars of a hall — the same geometry at many places is the
/// commonest shape a scene has, and drawing it one node at a time spends a
/// pipeline bind, six uniform writes and a draw on every copy. The particle
/// system has drawn its embers this way since it existed; this is the same
/// path for ordinary meshes.
///
/// ## What an instance is
///
/// A transform **in the node's space** and a colour that multiplies the
/// vertex colour. Relative to the node rather than to the world, so the
/// batch moves with its node the way a child would, and moving a batch of a
/// thousand costs one uniform write. Sixteen floats each: three rows of a 3x4
/// affine matrix — the bottom row of one is always `(0, 0, 0, 1)`, and a
/// quarter of the buffer would be spent saying so — and an RGBA colour.
///
/// ## What it is not, yet
///
/// * **Culled as one.** The batch's bounds are the union of its instances'
///   and the frustum test is one sphere around them, so a field that
///   straddles the horizon is drawn whole. Per-instance culling is a CPU pass
///   that costs more than it saves on a small batch, which is why other
///   engines make it opt-in; it is not here until a scene asks.
/// * **Uniform scale per instance.** A rotation and a uniform scale keep a
///   normal a normal; a non-uniform instance scale skews the lighting, and
///   the vertex stage says so rather than paying an inverse transpose per
///   vertex.
/// * **No skinning.** A skinned mesh has its own vertex stage and layout, and
///   a skinned batch would be a third.
/// * **Sorted as one.** A translucent batch sorts by the node, not by each
///   instance, so overlapping translucent instances may draw in the wrong
///   order within the batch.
/// * **Picked as a box.** A ray hits the batch's bounds, not the instances.
final class InstancedMeshNode extends MeshNode {
  InstancedMeshNode(
    super.mesh,
    super.material, {
    required int capacity,
    super.name,
  }) : assert(capacity > 0, 'a batch of nothing draws nothing'),
       _capacity = capacity,
       _data = Float32List(capacity * floatsPerInstance) {
    // Every slot starts as the identity with a white tint, so an instance
    // whose transform was never set draws where the node is rather than
    // collapsed to a point by a matrix of zeros.
    for (var i = 0; i < capacity; i++) {
      final at = i * floatsPerInstance;
      _data[at] = 1.0;
      _data[at + 5] = 1.0;
      _data[at + 10] = 1.0;
      _data[at + 12] = 1.0;
      _data[at + 13] = 1.0;
      _data[at + 14] = 1.0;
      _data[at + 15] = 1.0;
    }
  }

  /// Floats one instance occupies: three rows of the transform, then RGBA.
  static const int floatsPerInstance = 16;

  /// Bytes one instance occupies.
  static const int strideInBytes = floatsPerInstance * 4;

  final int _capacity;
  final Float32List _data;
  int _count = 0;
  int _dataVersion = 0;

  /// How many instances the buffer can hold. Fixed at construction, because
  /// growing means reallocating, and a caller that knows its field is a
  /// caller that can size it.
  int get capacity => _capacity;

  /// How many instances are drawn, never more than [capacity].
  int get count => _count;

  set count(int value) {
    if (value < 0 || value > _capacity) {
      throw RangeError.range(value, 0, _capacity, 'count');
    }
    if (value == _count) return;
    _count = value;
    _touched();
  }

  /// Bumped on every write, so a reader can tell whether anything changed.
  int get dataVersion => _dataVersion;

  /// The whole buffer, [capacity] instances of [floatsPerInstance] floats.
  ///
  /// For bulk writes — a field regenerated each frame — where a call per
  /// instance would be the cost. Call [markInstancesChanged] afterwards, or
  /// the bounds and a static shadow will describe the field as it was.
  Float32List get instanceData => _data;

  /// The drawn instances as bytes, for binding as the per-instance slot.
  ByteData get instanceBytes =>
      ByteData.sublistView(_data, 0, _count * floatsPerInstance);

  /// Places instance [index] with [transform], in the node's space.
  void setTransform(int index, Matrix4 transform) {
    _check(index);
    final at = index * floatsPerInstance;
    final s = transform.storage;
    // Rows from a column-major matrix: row r of column c is storage[c * 4 + r].
    _data[at] = s[0];
    _data[at + 1] = s[4];
    _data[at + 2] = s[8];
    _data[at + 3] = s[12];
    _data[at + 4] = s[1];
    _data[at + 5] = s[5];
    _data[at + 6] = s[9];
    _data[at + 7] = s[13];
    _data[at + 8] = s[2];
    _data[at + 9] = s[6];
    _data[at + 10] = s[10];
    _data[at + 11] = s[14];
    _touched();
  }

  /// Reads instance [index]'s transform back into [out].
  void readTransform(int index, Matrix4 out) {
    _check(index);
    final at = index * floatsPerInstance;
    out.setValues(
      _data[at],
      _data[at + 4],
      _data[at + 8],
      0.0, // column 0
      _data[at + 1],
      _data[at + 5],
      _data[at + 9],
      0.0, // column 1
      _data[at + 2],
      _data[at + 6],
      _data[at + 10],
      0.0, // column 2
      _data[at + 3],
      _data[at + 7],
      _data[at + 11],
      1.0, // column 3
    );
  }

  /// Tints instance [index]: multiplied into the vertex colour.
  void setColor(int index, Vector4 color) {
    _check(index);
    final at = index * floatsPerInstance + 12;
    _data[at] = color.x;
    _data[at + 1] = color.y;
    _data[at + 2] = color.z;
    _data[at + 3] = color.w;
    _touched();
  }

  /// Appends an instance and returns its index.
  int addInstance(Matrix4 transform, {Vector4? color}) {
    if (_count >= _capacity) {
      throw StateError(
        'InstancedMeshNode "$name" is full at $capacity instances.',
      );
    }
    final index = _count++;
    setTransform(index, transform);
    if (color != null) setColor(index, color);
    return index;
  }

  /// Says the buffer was written through [instanceData].
  ///
  /// Every writer in this repository goes through [setTransform] and its
  /// neighbours, which say so themselves. This is the other half of
  /// [instanceData]'s bargain, and it is for a caller that filled the whole
  /// buffer at once — a field regenerated per frame — and has to say so, because
  /// nothing watched it happen.
  void markInstancesChanged() => _touched();

  void _check(int index) {
    if (index < 0 || index >= _capacity) {
      throw RangeError.index(index, this, 'index', null, _capacity);
    }
  }

  void _touched() {
    _dataVersion++;
    _localBoundsVersion = -1;
    markBoundsDirty();
    // A static caster's instances are baked into the static shadow atlas, and
    // nothing else would notice them moving — the same trap `castsShadow`'s
    // mode change closes for a single mesh.
    if (shadowIsStatic) scene?.invalidateStaticShadows();
  }

  final Aabb3 _localBounds = Aabb3();
  int _localBoundsVersion = -1;
  MeshGeometry? _localBoundsMesh;

  /// The union of every drawn instance's transformed mesh bounds, in the
  /// node's space.
  ///
  /// Recomputed only when the instances or the mesh change. An empty batch
  /// has the mesh's own bounds, so a node with nothing to draw still frames
  /// and culls like a node.
  @override
  Aabb3 get localBounds {
    if (_localBoundsVersion == _dataVersion && _localBoundsMesh == mesh) {
      return _localBounds;
    }
    _localBoundsVersion = _dataVersion;
    _localBoundsMesh = mesh;
    final local = mesh.bounds;
    if (_count == 0) {
      _localBounds.min.setFrom(local.min);
      _localBounds.max.setFrom(local.max);
      return _localBounds;
    }
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var i = 0; i < _count; i++) {
      final at = i * floatsPerInstance;
      for (var c = 0; c < 8; c++) {
        final x = (c & 1) == 0 ? local.min.x : local.max.x;
        final y = (c & 2) == 0 ? local.min.y : local.max.y;
        final z = (c & 4) == 0 ? local.min.z : local.max.z;
        final wx =
            _data[at] * x +
            _data[at + 1] * y +
            _data[at + 2] * z +
            _data[at + 3];
        final wy =
            _data[at + 4] * x +
            _data[at + 5] * y +
            _data[at + 6] * z +
            _data[at + 7];
        final wz =
            _data[at + 8] * x +
            _data[at + 9] * y +
            _data[at + 10] * z +
            _data[at + 11];
        if (wx < minX) minX = wx;
        if (wy < minY) minY = wy;
        if (wz < minZ) minZ = wz;
        if (wx > maxX) maxX = wx;
        if (wy > maxY) maxY = wy;
        if (wz > maxZ) maxZ = wz;
      }
    }
    _localBounds.min.setValues(minX, minY, minZ);
    _localBounds.max.setValues(maxX, maxY, maxZ);
    return _localBounds;
  }
}
