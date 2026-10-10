import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

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
/// thousand costs one uniform write. In the terms of "Space" in
/// `docs/CONTRACTS.md` that is local space: a batch added at the scene's root
/// with no transform of its own has it equal to scene space, and a tree
/// planted at a `WorldPosition` there goes in at `scene.toScene(at)`. Sixteen floats each: three rows of a 3x4
/// affine matrix — the bottom row of one is always `(0, 0, 0, 1)`, and a
/// quarter of the buffer would be spent saying so — and an RGBA colour.
///
/// A copy can also wear its own morph weights — see [setMorphWeights] — which
/// is how a crowd gets faces rather than one face repeated. Those do not live
/// in the instance record: they are a texture read by instance id, so that the
/// record's size, which is part of the vertex layout, is not paid by every
/// batch in every game for a feature most of them never use.
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

  /// Floats one instance occupies: three rows of the transform, then RGBA,
  /// then four of the game's own — `P8`, see [setInstanceData].
  static const int floatsPerInstance = 20;

  /// Where an instance's own four floats start within its record.
  static const int _dataOffset = 16;

  /// Bytes one instance occupies.
  static const int strideInBytes = floatsPerInstance * 4;

  int _capacity;
  Float32List _data;
  int _count = 0;
  int _dataVersion = 0;

  /// How many instances the buffer can hold.
  ///
  /// Set at construction, because a caller that knows its field is a caller
  /// that can size it, and grown by [ensureCapacity] for the one that cannot —
  /// see there for who that is.
  int get capacity => _capacity;

  /// Grows the buffer to hold at least [wanted] instances, keeping what is in
  /// it.
  ///
  /// **For a caller that does not know its size in advance — `gfx-67n`.** The
  /// automatic batcher is exactly that: it discovers a run of identical draws
  /// while encoding a frame, and the run is as long as the scene and the camera
  /// make it. Growing doubles rather than fitting, so a batch that creeps up by
  /// one a frame reallocates a handful of times rather than every frame.
  void ensureCapacity(int wanted) {
    if (wanted <= _capacity) return;
    var grown = _capacity;
    while (grown < wanted) {
      grown *= 2;
    }

    final data = Float32List(grown * floatsPerInstance);
    data.setRange(0, _capacity * floatsPerInstance, _data);
    for (var i = _capacity; i < grown; i++) {
      final at = i * floatsPerInstance;
      data[at] = 1.0;
      data[at + 5] = 1.0;
      data[at + 10] = 1.0;
      data[at + 12] = 1.0;
      data[at + 13] = 1.0;
      data[at + 14] = 1.0;
      data[at + 15] = 1.0;
    }
    _data = data;

    final weights = _weights;
    if (weights != null) {
      _weights = Float32List(grown * maxMorphTargets)
        ..setRange(0, _capacity * maxMorphTargets, weights);
      // The texture is one row per slot, so a taller buffer is a different
      // texture and the cached one no longer describes it.
      _weightsVersion++;
    }

    _capacity = grown;
    _touched();
  }

  /// Empties the batch without giving up the buffer it has.
  ///
  /// The other half of [ensureCapacity]'s bargain: a batcher that refills the
  /// same node every frame needs to start from nothing, and freeing the buffer
  /// to do it would be the allocation the pool exists to avoid.
  ///
  /// Every handle [acquire] gave out stops being live.
  void clear() {
    for (final holder in _holders) {
      holder?._index = -1;
    }
    _holders.clear();
    if (_count == 0) return;
    _count = 0;
    _touched();
  }

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
  void setColor(int index, LinearColor color) {
    _check(index);
    final at = index * floatsPerInstance + 12;
    _data[at] = color.r;
    _data[at + 1] = color.g;
    _data[at + 2] = color.b;
    _data[at + 3] = color.a;
    _touched();
  }

  /// Gives instance [index] four numbers of the game's own — `P8`.
  ///
  /// **What a material reads as `instance`.** The instanced vertex stage
  /// hands them to the fragment as they are, so a material written in the
  /// language can colour, fade or animate each copy of a batch by a value
  /// only the game knows: a health, a team, a phase. Nought until set, and
  /// nought for every draw that is not instanced.
  void setInstanceData(int index, Vector4 data) {
    _check(index);
    final at = index * floatsPerInstance + _dataOffset;
    _data[at] = data.x;
    _data[at + 1] = data.y;
    _data[at + 2] = data.z;
    _data[at + 3] = data.w;
    _touched();
  }

  /// Reads instance [index]'s own four numbers back into [out].
  void readInstanceData(int index, Vector4 out) {
    _check(index);
    final at = index * floatsPerInstance + _dataOffset;
    out.setValues(_data[at], _data[at + 1], _data[at + 2], _data[at + 3]);
  }

  /// Appends an instance and returns its index.
  ///
  /// Throws when the batch is full: a caller that sized its field and then
  /// overran it has a bug, and growing quietly underneath it would hide the
  /// bug and the reallocation both. [ensureCapacity] is how a caller that
  /// means to grow says so.
  int addInstance(Matrix4 transform, {LinearColor? color, Vector4? data}) {
    if (_count >= _capacity) {
      throw StateError(
        'InstancedMeshNode "$name" is full at $capacity instances.',
      );
    }
    final index = _count++;
    setTransform(index, transform);
    if (color != null) setColor(index, color);
    if (data != null) setInstanceData(index, data);
    return index;
  }

  // ------------------------------------------------------- slots, by handle

  /// The handle holding each drawn slot, where one does.
  final List<InstanceHandle?> _holders = <InstanceHandle?>[];

  /// Takes a slot for something that comes and goes, and returns the handle
  /// that keeps finding it: a shot, a spark, an invader.
  ///
  /// **For a batch whose members leave in any order.** Written by index, a
  /// batch whose middle member left had a hole to fill, and filling it moved
  /// another member to a slot its owner did not know about. [release] fills
  /// the hole with the last slot and tells the last slot's handle where it
  /// went, so an owner holding a handle is never pointed at someone else's.
  ///
  /// Grows the buffer when it is full, the way [ensureCapacity] does: a
  /// batch of things that come and go has no size to name in advance.
  InstanceHandle acquire({
    Matrix4? transform,
    LinearColor color = LinearColor.white,
    Vector4? data,
  }) {
    ensureCapacity(_count + 1);
    final index = _count;
    final handle = InstanceHandle._(this, index);
    while (_holders.length <= index) {
      _holders.add(null);
    }
    _holders[index] = handle;
    count = index + 1;
    setTransform(index, transform ?? Matrix4.identity());
    setColor(index, color);
    // A slot a released member left holds its numbers; the new one starts
    // from nought, as a fresh batch does.
    setInstanceData(index, data ?? Vector4.zero());
    final weights = _weights;
    if (weights != null) {
      weights.fillRange(
        index * maxMorphTargets,
        (index + 1) * maxMorphTargets,
        0.0,
      );
      _weightsVersion++;
    }
    return handle;
  }

  /// Gives [handle]'s slot back: the last drawn slot moves into it, colour
  /// and morph weights with it, and [count] drops by one. Releasing a
  /// handle twice, or one from another batch, is a mistake and throws.
  void release(InstanceHandle handle) {
    if (!identical(handle._batch, this) || !handle.isLive) {
      throw StateError('That instance is not held in "$name".');
    }
    final hole = handle._index;
    final last = _count - 1;
    if (hole != last) {
      _data.setRange(
        hole * floatsPerInstance,
        (hole + 1) * floatsPerInstance,
        _data,
        last * floatsPerInstance,
      );
      final weights = _weights;
      if (weights != null) {
        weights.setRange(
          hole * maxMorphTargets,
          (hole + 1) * maxMorphTargets,
          weights,
          last * maxMorphTargets,
        );
        _weightsVersion++;
      }
      final moved = last < _holders.length ? _holders[last] : null;
      moved?._index = hole;
      _holders[hole] = moved;
    }
    if (last < _holders.length) _holders[last] = null;
    handle._index = -1;
    count = last;
  }

  // ------------------------------------------------- morph weights, per copy

  /// Weights for every slot, `kMorphMax` apiece, or null until one is set.
  ///
  /// Allocated on the first [setMorphWeights] and not before: a batch of grass
  /// should not carry eight floats an instance for a feature it never uses.
  Float32List? _weights;
  int _weightsVersion = 0;
  int _uploadedWeights = -1;
  TextureHandle? _weightsTexture;

  /// The most targets an instance can be given weights for. `kMorphMax` in
  /// `lib/morph.glsl`, and the two have to move together.
  static const int maxMorphTargets = 8;

  /// Texels one instance's weights occupy: four weights to a texel.
  static const int _weightTexels = maxMorphTargets ~/ 4;

  /// Whether any instance has been given weights of its own.
  bool get hasInstanceMorphWeights => _weights != null;

  /// Gives instance [index] its own morph weights.
  ///
  /// **This is what a crowd is for.** A batch shares one mesh and therefore one
  /// set of deltas, and until this existed it shared one *shape* as well: the
  /// weights came from a uniform, which is the same for every instance in the
  /// draw by definition. A thousand villagers could morph, and all thousand
  /// wore the same face.
  ///
  /// Longer than [maxMorphTargets] is truncated and shorter leaves the rest at
  /// nought, on the same terms as `MorphState.setWeights`.
  ///
  /// Costs nothing per frame once set: the texture behind these is rebuilt only
  /// when a weight actually changed. Changing one every frame on every instance
  /// rebuilds it every frame, which is the trade `lib/morph_instanced.glsl`
  /// describes — a texture in this engine is created with its contents and
  /// never written again.
  void setMorphWeights(int index, List<double> weights) {
    _check(index);
    final slots = _weights ??= Float32List(_capacity * maxMorphTargets);
    final at = index * maxMorphTargets;
    var changed = false;
    for (var i = 0; i < maxMorphTargets; i++) {
      final value = i < weights.length ? weights[i] : 0.0;
      if (slots[at + i] != value) {
        slots[at + i] = value;
        changed = true;
      }
    }
    if (changed) _weightsVersion++;
  }

  /// Instance [index]'s weights, as they were set.
  List<double> morphWeightsOf(int index) {
    _check(index);
    final slots = _weights;
    if (slots == null) return const <double>[];
    final at = index * maxMorphTargets;
    return <double>[for (var i = 0; i < maxMorphTargets; i++) slots[at + i]];
  }

  /// The weights as a texture the instanced vertex stage can read, or null when
  /// no instance has any.
  ///
  /// One row per slot and [_weightTexels] texels across, which is the layout
  /// `lib/morph_instanced.glsl` reads. Rebuilt when a weight changed and
  /// returned as it is otherwise — the skip is the whole point, since a texture
  /// cannot be written after it is made and rebuilding one per frame for a
  /// crowd that is not changing would be the cost of a feature nobody used.
  TextureHandle? instanceMorphWeights(GraphicsDevice device) {
    final slots = _weights;
    if (slots == null) return null;
    if (_uploadedWeights == _weightsVersion) return _weightsTexture;

    final previous = _weightsTexture;
    _weightsTexture = device.createTextureFromPixels(
      width: _weightTexels,
      height: _capacity,
      format: TextureFormat.r32g32b32a32Float,
      pixels: ByteData.sublistView(slots),
    );
    _uploadedWeights = _weightsVersion;
    // After the new one is made, not before: a device that refuses the upload
    // leaves the batch drawing the shape it had rather than none at all.
    if (previous != null) device.releaseTexture(previous);
    return _weightsTexture;
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

/// One slot of an [InstancedMeshNode], taken with
/// [InstancedMeshNode.acquire]: it follows its instance when a release
/// elsewhere in the batch moves it.
final class InstanceHandle {
  InstanceHandle._(this._batch, this._index);

  final InstancedMeshNode _batch;
  int _index;

  /// Whether the slot is still this handle's: false once released, or once
  /// the batch was cleared.
  bool get isLive => _index >= 0;

  /// The slot's index in the batch right now; it changes when another
  /// instance is released. Read it at the moment of a write, do not keep it.
  int get index {
    if (!isLive) throw StateError('A released instance has no slot.');
    return _index;
  }

  /// Places the instance, in the batch node's space.
  void setTransform(Matrix4 transform) => _batch.setTransform(index, transform);

  /// Tints the instance.
  void setColor(LinearColor color) => _batch.setColor(index, color);

  /// Gives the instance four numbers of the game's own — see
  /// [InstancedMeshNode.setInstanceData].
  void setData(Vector4 data) => _batch.setInstanceData(index, data);
}
