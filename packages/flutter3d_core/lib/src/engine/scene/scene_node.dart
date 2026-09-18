import 'package:vector_math/vector_math.dart';

import '../animation/animation_target.dart' show AnimationTarget;
import 'light_node.dart' show LightChannels;
import 'scene.dart';

/// A node in the scene graph: a name, a place in the hierarchy, and a transform.
///
/// Deliberately narrow. Geometry, cameras and lights are subclasses that add
/// their own payload, which keeps this base from growing into an object that
/// knows about everything.
///
/// ## World transforms are never stale
///
/// three.js and Babylon both need an explicit update pass (`updateMatrixWorld`,
/// `computeWorldMatrix`); forgetting it yields a frame of lag, which is a classic
/// and annoying bug. Instead every node carries a globally unique version stamp,
/// and [worldMatrix] compares its parent's current stamp against the one it last
/// saw. A mismatch means recompute, walking up to resolve ancestors first.
///
/// The consequences are worth spelling out:
///
///  * There is no update pass to forget. A stale world matrix cannot be observed.
///  * Moving a node costs O(1); it does not walk its subtree to set dirty flags.
///  * Version stamps come from one global counter, so they are unique across
///    nodes. That matters on reparenting: a per-node counter could hand the new
///    parent the same number the old one had, and the change would go unnoticed.
///  * [worldVersion] doubles as a cheap invalidation key for anything derived
///    from the transform — world bounds, view matrices, normal matrices.
base class SceneNode implements AnimationTarget {
  SceneNode({this.name});

  String? name;

  /// Monotonic source of version stamps, shared by every node.
  static int _versionCounter = 0;

  /// How many times anything anywhere has been *touched*.
  ///
  /// Distinct from [_versionCounter], which also advances when a matrix is
  /// recomputed. This one moves only when dirt is introduced: a transform set,
  /// a node reparented, added or removed, a visibility flipped, a mesh's own
  /// bounds invalidated. Starts at 1 so that zero is a value no node can have
  /// verified itself at.
  static int _dirtyEpoch = 1;

  /// The counter as a public reading: "has anything anywhere changed since?"
  ///
  /// **What it is for — `gfx-62n`.** The lazy scheme above has one gap that
  /// only shows at scale: there is no way to ask whether a frame needs to
  /// redo work derived from transforms, short of reading every transform,
  /// which is the work. `RenderList` hit this exactly. Keeping its spatial
  /// tree meant repacking every mesh's bounding sphere each frame to find out
  /// whether any had moved, and at 50 000 meshes that pack cost 3.3 ms —
  /// as much as the cull it was there to make unnecessary, so the tree could
  /// not win at any size.
  ///
  /// A reader that holds a previous value and finds it unchanged knows no node
  /// was touched: not moved, not reparented, not added, not removed, not
  /// hidden, and no mesh's own bounds invalidated.
  ///
  /// It over-reports on purpose. Setting a node to the position it already
  /// holds advances it, and so does a move that nothing derived from
  /// transforms cares about, because the alternative is comparing values on
  /// every setter and paying for the comparison always to save a frame
  /// rarely. Over-reporting costs a frame of redone work; under-reporting
  /// draws the wrong picture.
  static int get changeEpoch => _dirtyEpoch;

  /// Advances [changeEpoch] for a change the graph itself cannot see.
  ///
  /// The one caller is `MeshNode.markBoundsDirty`, which is the only way
  /// something a reader derived from the graph goes stale without a transform
  /// being touched.
  static void noteChange() => _dirtyEpoch++;

  /// How many times a [worldMatrix] read has had to walk to the root.
  ///
  /// Here because the saving `gfx-65n` is about is invisible in a picture: a
  /// frame that walks every ancestor of every drawable twice per pass draws
  /// exactly what a frame that walks none of them draws. A count is what a test
  /// can hold to, and what this one holds to is that a second read of an
  /// unmoved node adds nothing.
  static int get ancestorWalks => _ancestorWalks;
  static int _ancestorWalks = 0;

  /// Records that this node's local transform no longer matches its matrix.
  void _markLocalDirty() {
    _localDirty = true;
    _dirtyEpoch++;
  }

  SceneNode? _parent;
  final List<SceneNode> _children = <SceneNode>[];
  Scene? _scene;

  final Vector3 _position = Vector3.zero();
  final Quaternion _rotation = Quaternion.identity();
  final Vector3 _scale = Vector3(1.0, 1.0, 1.0);

  final Matrix4 _localMatrix = Matrix4.identity();
  final Matrix4 _worldMatrix = Matrix4.identity();
  final Matrix4 _inverseWorldMatrix = Matrix4.identity();
  int _inverseWorldVersion = -1;

  bool _localDirty = false;
  int _worldVersion = ++_versionCounter;

  /// The parent's version stamp at the time [_worldMatrix] was computed. Starts
  /// at a value no stamp can equal, so the first read always computes.
  int _seenParentVersion = -1;

  /// The epoch at which [_worldMatrix] was last confirmed current, all the way
  /// to the root. Zero is before the first epoch, so the first read walks.
  int _verifiedEpoch = 0;

  /// Whether this node and its subtree are drawn.
  bool get visible => _visible;

  set visible(bool value) {
    // Hiding a branch changes what [visibleInHierarchy] answers for everything
    // under it, and that answer is cached on the epoch — `gfx-65n`. Guarded on
    // the value because this is the one setter where the comparison is free and
    // the common write is `visible = visible`: `LodGroup` sets every level's
    // flag every frame to pick one.
    if (_visible == value) return;
    _visible = value;
    _dirtyEpoch++;
  }

  bool _visible = true;

  /// Bitmask filtered against a render view's mask, in the manner of three.js
  /// layers. Bit 0 is the default layer.
  int layerMask = 1;

  /// Which light channels this node accepts — `gfx-12n`.
  ///
  /// Met against [LightNode.channels]: a light reaches this node when the two
  /// masks share a bit. Every bit by default, so a scene that has never heard
  /// of channels is lit as it always was.
  ///
  /// **Not inherited down the graph**, unlike [visible]. A channel is a
  /// statement about one surface — the sky dome that the torch must not
  /// reach — and making it inherit would mean a prop parented to a lamp post
  /// silently changing what lights it. A caller who wants a subtree to share
  /// a channel sets it on the subtree, which is a loop they can read.
  int lightChannels = LightChannels.all;

  SceneNode? get parent => _parent;

  /// The scene this node currently belongs to, if any.
  Scene? get scene => _scene;

  List<SceneNode> get children => List<SceneNode>.unmodifiable(_children);

  /// Direct access for internal traversal, avoiding the unmodifiable copy.
  List<SceneNode> get childrenView => _children;

  /// Changes whenever [worldMatrix] changes. Use it as an invalidation key.
  int get worldVersion {
    // Reading the matrix is what refreshes the stamp, so resolve it first.
    worldMatrix;
    return _worldVersion;
  }

  // -------------------------------------------------------------- transform

  @override
  void setPosition(double x, double y, double z) {
    _position.setValues(x, y, z);
    _markLocalDirty();
  }

  void setPositionFrom(Vector3 value) => setPosition(value.x, value.y, value.z);

  void translate(double dx, double dy, double dz) {
    _position.setValues(_position.x + dx, _position.y + dy, _position.z + dz);
    _markLocalDirty();
  }

  @override
  void setRotation(Quaternion value) {
    _rotation.setFrom(value);
    _rotation.normalize();
    _markLocalDirty();
  }

  /// Yaw about Y, then pitch about X, then roll about Z — the order that reads
  /// naturally for cameras and turntables.
  void setRotationYawPitchRoll(double yaw, double pitch, double roll) {
    _rotation.setEuler(yaw, pitch, roll);
    _markLocalDirty();
  }

  @override
  void setScale(double x, double y, double z) {
    _scale.setValues(x, y, z);
    _markLocalDirty();
  }

  void setUniformScale(double value) => setScale(value, value, value);

  /// Replaces the local transform by decomposing a matrix.
  ///
  /// Lossy for shear: the node stores TRS, so a sheared matrix cannot round
  /// trip. glTF `matrix` nodes are decomposed the same way by three.js and
  /// Babylon, and shear in authored assets is vanishingly rare.
  ///
  /// **`_invalidateWorld`, not `_bumpWorld`.** `_localMatrix` is already
  /// current here — [value] was written straight into it — so what is stale
  /// is [_worldMatrix], and [worldMatrix]'s own cache is keyed off
  /// `_seenParentVersion` rather than off [_localDirty], which this method
  /// leaves false. Calling `_bumpWorld` here changed the version stamp
  /// without changing the cached matrix underneath it, and — for a node whose
  /// `worldMatrix` had already been read once, which by the time a second
  /// call to this reaches it, it almost always has — the mismatch this
  /// creates between the version and the matrix it names never repairs
  /// itself, because nothing about the parent has moved and there is nothing
  /// else pending recomputation on the node's own account. A second move of
  /// an object already on screen stayed on screen at its first position; a
  /// third undid nothing either.
  void setLocalMatrix(Matrix4 value) {
    value.decompose(_position, _rotation, _scale);
    _localMatrix.setFrom(value);
    _localDirty = false;
    _invalidateWorld();
  }

  /// Reads the local position into [out] to avoid allocating.
  Vector3 readPosition([Vector3? out]) =>
      (out ?? Vector3.zero())..setFrom(_position);

  Quaternion readRotation([Quaternion? out]) =>
      (out ?? Quaternion.identity())..setFrom(_rotation);

  Vector3 readScale([Vector3? out]) => (out ?? Vector3.zero())..setFrom(_scale);

  Vector3 readWorldPosition([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(m[12], m[13], m[14]);
    return result;
  }

  Matrix4 get localMatrix {
    if (_localDirty) _recomputeLocal();
    return _localMatrix;
  }

  /// The node-to-world transform, always current.
  Matrix4 get worldMatrix {
    // **The read that does not walk — `gfx-65n`.** Everything below is correct
    // and costs an ancestor walk every time, with no early-out, and a frame is
    // made of reads: the inverse, the world bounds and the normal matrix all
    // route through this, and every drawable was paying two full walks a pass.
    //
    // `_dirtyEpoch` advances only when something is *touched* — a transform
    // set, a node reparented, a visibility flipped — and never when a matrix is
    // merely recomputed. So a node that verified itself at the current epoch
    // has an ancestor chain nobody has touched since, and the cached matrix is
    // the answer. What this cannot do is tell one subtree's change from
    // another's: move one node and every node in the scene walks once more.
    // That is the trade, and it is the right way round, because the walk is
    // per read and the change is per move.
    if (_verifiedEpoch == _dirtyEpoch) return _worldMatrix;
    _verifiedEpoch = _dirtyEpoch;
    _ancestorWalks++;

    final parent = _parent;

    if (parent == null) {
      if (_localDirty || _seenParentVersion != 0) {
        if (_localDirty) _recomputeLocal();
        _worldMatrix.setFrom(_localMatrix);
        // 0 marks "no parent", distinct from any real stamp.
        _seenParentVersion = 0;
        _bumpWorld();
      }
      return _worldMatrix;
    }

    // Resolving the parent first means ancestors are refreshed before we read
    // their stamp, so one access repairs the whole chain.
    final parentWorld = parent.worldMatrix;
    if (_localDirty || parent._worldVersion != _seenParentVersion) {
      if (_localDirty) _recomputeLocal();
      _worldMatrix.setFrom(parentWorld);
      _worldMatrix.multiply(_localMatrix);
      _seenParentVersion = parent._worldVersion;
      _bumpWorld();
    }
    return _worldMatrix;
  }

  /// The world-to-node transform, cached on [worldVersion].
  ///
  /// Wanted by anything that works in a node's own space: a camera's view matrix
  /// is this exact thing, and so is the matrix that carries a picking ray into
  /// mesh space, where testing triangles is far cheaper than transforming them.
  Matrix4 get inverseWorldMatrix {
    final version = worldVersion;
    if (version != _inverseWorldVersion) {
      _inverseWorldMatrix.setFrom(_worldMatrix);
      _inverseWorldMatrix.invert();
      _inverseWorldVersion = version;
    }
    return _inverseWorldMatrix;
  }

  void _recomputeLocal() {
    _localMatrix.setFromTranslationRotationScale(_position, _rotation, _scale);
    _localDirty = false;
  }

  void _bumpWorld() {
    _worldVersion = ++_versionCounter;
  }

  /// Forces the next [worldMatrix] read to recompute, used on reparenting.
  void _invalidateWorld() {
    _seenParentVersion = -1;
    _dirtyEpoch++;
  }

  /// Aims the node's local -Z along [direction], expressed in the parent's space.
  ///
  /// -Z is the forward axis for cameras in glTF, three.js and Babylon alike, so
  /// this aims a camera, a spot light or a probe identically.
  ///
  /// Working in parent space is what makes a child of a moving rig easy: a light
  /// parented to a camera gets a fixed local direction here and then follows the
  /// camera for free, with no per-frame work.
  void setLocalForward(Vector3 direction, {Vector3? up}) {
    if (direction.length2 < 1e-12) return;
    setRotation(_rotationFacing(direction, up));
  }

  /// Points the node's local -Z at [target], given in world space.
  ///
  /// The up reference is interpreted in **world** space, which is the convention
  /// every engine uses: a camera aimed at something should stay level with the
  /// world, not with whatever rig it happens to hang from. That is why this is not
  /// simply [setLocalForward] applied to a rotated direction — rotating the
  /// direction into parent space while keeping world up would mix two frames.
  void lookAt(Vector3 target, {Vector3? up}) {
    final direction = target - readWorldPosition();
    if (direction.length2 < 1e-12) return; // already at the target

    final worldRotation = _rotationFacing(direction, up);

    final parent = _parent;
    if (parent == null) {
      setRotation(worldRotation);
      return;
    }
    // The stored rotation is local, so strip the parent's world rotation.
    final parentRotation =
        Quaternion.fromRotation(parent.worldMatrix.getRotation())
          ..normalize()
          ..inverse();
    setRotation(parentRotation * worldRotation);
  }

  /// Rotation whose local -Z points along [direction].
  static Quaternion _rotationFacing(Vector3 direction, Vector3? up) {
    // The rotation's third basis column is +Z, and forward is -Z.
    final zAxis = -direction.normalized();

    var upVector = up ?? Vector3(0.0, 1.0, 0.0);
    var right = upVector.cross(zAxis);
    if (right.length2 < 1e-12) {
      // Up is parallel to forward; any perpendicular axis beats a degenerate
      // basis full of NaN.
      upVector = zAxis.z.abs() < 0.9
          ? Vector3(0.0, 0.0, 1.0)
          : Vector3(1.0, 0.0, 0.0);
      right = upVector.cross(zAxis);
    }
    right.normalize();
    final trueUp = zAxis.cross(right)..normalize();

    return Quaternion.fromRotation(Matrix3.columns(right, trueUp, zAxis))
      ..normalize();
  }

  // -------------------------------------------------------------- hierarchy

  /// Adds [child], keeping its local transform (so it moves with this node).
  void add(SceneNode child) {
    if (child == this) {
      throw ArgumentError('A node cannot be its own child.');
    }
    if (child._isAncestorOf(this)) {
      throw ArgumentError(
        'Adding "${child.name}" here would create a cycle in the graph.',
      );
    }
    if (child._parent == this) return;

    child._parent?._children.remove(child);
    child._parent = this;
    _children.add(child);
    child._invalidateWorld();

    if (child._scene != _scene) child._propagateScene(_scene);
  }

  /// Adds [child] while preserving its current world transform.
  ///
  /// The counterpart to three.js `attach`: use it when reparenting should not
  /// visibly move anything, which is almost always what a user expects when
  /// grouping existing objects.
  void attach(SceneNode child) {
    final childWorld = child.worldMatrix.clone();
    add(child);
    final parentInverse = worldMatrix.clone()..invert();
    child.setLocalMatrix(parentInverse * childWorld);
  }

  void remove(SceneNode child) {
    if (child._parent != this) return;
    _children.remove(child);
    child._parent = null;
    child._invalidateWorld();
    if (child._scene != null) child._propagateScene(null);
  }

  /// Detaches this node from its parent.
  void removeFromParent() => _parent?.remove(this);

  bool _isAncestorOf(SceneNode node) {
    var current = node._parent;
    while (current != null) {
      if (current == this) return true;
      current = current._parent;
    }
    return false;
  }

  /// What this node and everything under it occupies, or null when the subtree
  /// draws nothing.
  ///
  /// **A branch rejected whole — `gfx-66n`.** A node holding a thousand meshes
  /// was a thousand frustum tests, because the only bound in the engine was a
  /// mesh's own. This is the union over the subtree, cached on
  /// [changeEpoch] like every other derived quantity here, so a scene that
  /// nobody touched computes it once and a scene that moved computes it once
  /// more.
  ///
  /// Recursive rather than iterative on purpose: the recursion reads
  /// `subtreeBounds` on each child, so every node on the way down caches its
  /// own answer and the whole tree costs one pass rather than one per node. A
  /// hierarchy deep enough to overflow a stack here is one whose transforms
  /// would have overflowed it first.
  ///
  /// The box is in world space and it is grown by whatever
  /// [MeshNode.frustumCulled] refuses: a subtree holding a node that opted out
  /// of culling answers [subtreeAlwaysDrawn], and a caller that rejects on this
  /// box has to honour that or a sky dome disappears.
  Aabb3? get subtreeBounds {
    if (_subtreeEpoch == _dirtyEpoch) return _subtreeBounds;
    _subtreeEpoch = _dirtyEpoch;
    _subtreeAlwaysDrawn = false;

    Aabb3? box = ownBounds;
    if (box != null) {
      // A fresh box rather than the node's own: the union below writes into it,
      // and a `MeshNode`'s world bounds are the cache the whole engine reads.
      box = Aabb3.copy(box);
      _subtreeAlwaysDrawn = !ownBoundsAreCullable;
    }

    for (var i = 0; i < _children.length; i++) {
      final child = _children[i];
      final childBox = child.subtreeBounds;
      if (child._subtreeAlwaysDrawn) _subtreeAlwaysDrawn = true;
      if (childBox == null) continue;
      if (box == null) {
        box = Aabb3.copy(childBox);
      } else {
        box.hull(childBox);
      }
    }

    return _subtreeBounds = box;
  }

  /// Whether anything in this subtree has opted out of frustum culling.
  ///
  /// Reading it resolves [subtreeBounds], which is what computes it.
  bool get subtreeAlwaysDrawn {
    subtreeBounds;
    return _subtreeAlwaysDrawn;
  }

  /// This node's own contribution to [subtreeBounds], or null when it draws
  /// nothing.
  ///
  /// For `MeshNode` to override, and for nothing else to call: it is the one
  /// piece of "what does this node occupy" that a subclass knows and this class
  /// does not. A plain node occupies nothing — it is a transform with children
  /// under it — which is why the default is null rather than a point at the
  /// origin, a box that would drag every subtree's bound out to meet it.
  Aabb3? get ownBounds => null;

  /// Whether [ownBounds] may be culled.
  ///
  /// For `MeshNode` to override from its own `frustumCulled`, so that a subtree
  /// holding a sky dome or a held weapon cannot be rejected whole. Nothing else
  /// calls it; [subtreeAlwaysDrawn] is the reading a caller wants.
  bool get ownBoundsAreCullable => true;

  Aabb3? _subtreeBounds;
  int _subtreeEpoch = 0;
  bool _subtreeAlwaysDrawn = false;

  /// Walks this node and its descendants.
  ///
  /// Convenient for scene code, but the renderer never uses it: per-frame work
  /// goes through the scene's flat registries instead, so a deep hierarchy costs
  /// nothing at draw time.
  void traverse(void Function(SceneNode node) visit) {
    visit(this);
    for (var i = 0; i < _children.length; i++) {
      _children[i].traverse(visit);
    }
  }

  /// First descendant with a matching name, or null.
  SceneNode? findByName(String target) {
    if (name == target) return this;
    for (var i = 0; i < _children.length; i++) {
      final found = _children[i].findByName(target);
      if (found != null) return found;
    }
    return null;
  }

  /// True when this node and every ancestor is visible.
  bool get visibleInHierarchy {
    // Cached on the epoch for the reason [worldMatrix] is — `gfx-65n`. This one
    // is read from seventeen call sites, and the cull path alone asks it once
    // per mesh per pass, so a deep hierarchy paid a second full ancestor walk
    // on top of the transform's.
    if (_visibleEpoch == _dirtyEpoch) return _visibleCached;
    _visibleEpoch = _dirtyEpoch;

    var current = this;
    while (true) {
      if (!current._visible) return _visibleCached = false;
      final parent = current._parent;
      if (parent == null) return _visibleCached = true;
      current = parent;
    }
  }

  bool _visibleCached = true;
  int _visibleEpoch = 0;

  /// Binds this node's subtree to [scene]. Called by [Scene] for its own root;
  /// user code attaches nodes with [add] instead.
  void bindToScene(Scene? scene) => _propagateScene(scene);

  void _propagateScene(Scene? next) {
    final previous = _scene;
    if (previous == next) return;

    if (previous != null) onDetachedFromScene(previous);
    _scene = next;
    if (next != null) onAttachedToScene(next);

    for (var i = 0; i < _children.length; i++) {
      _children[i]._propagateScene(next);
    }
  }

  /// Hook for subclasses to register themselves in the scene's flat registries.
  ///
  /// Registration happens on attach and detach rather than per frame, which is
  /// what lets the renderer iterate contiguous lists.
  void onAttachedToScene(Scene scene) {}

  void onDetachedFromScene(Scene scene) {}

  @override
  String toString() => '$runtimeType(${name ?? 'unnamed'})';
}
