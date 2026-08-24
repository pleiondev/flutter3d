import 'package:vector_math/vector_math.dart';

import '../animation/animation_target.dart' show AnimationTarget;
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

  /// Whether this node and its subtree are drawn.
  bool visible = true;

  /// Bitmask filtered against a render view's mask, in the manner of three.js
  /// layers. Bit 0 is the default layer.
  int layerMask = 1;

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
    _localDirty = true;
  }

  void setPositionFrom(Vector3 value) =>
      setPosition(value.x, value.y, value.z);

  void translate(double dx, double dy, double dz) {
    _position.setValues(
      _position.x + dx,
      _position.y + dy,
      _position.z + dz,
    );
    _localDirty = true;
  }

  @override
  void setRotation(Quaternion value) {
    _rotation.setFrom(value);
    _rotation.normalize();
    _localDirty = true;
  }

  /// Yaw about Y, then pitch about X, then roll about Z — the order that reads
  /// naturally for cameras and turntables.
  void setRotationYawPitchRoll(double yaw, double pitch, double roll) {
    _rotation.setEuler(yaw, pitch, roll);
    _localDirty = true;
  }

  @override
  void setScale(double x, double y, double z) {
    _scale.setValues(x, y, z);
    _localDirty = true;
  }

  void setUniformScale(double value) => setScale(value, value, value);

  /// Replaces the local transform by decomposing a matrix.
  ///
  /// Lossy for shear: the node stores TRS, so a sheared matrix cannot round
  /// trip. glTF `matrix` nodes are decomposed the same way by three.js and
  /// Babylon, and shear in authored assets is vanishingly rare.
  void setLocalMatrix(Matrix4 value) {
    value.decompose(_position, _rotation, _scale);
    _localMatrix.setFrom(value);
    _localDirty = false;
    _bumpWorld();
  }

  /// Reads the local position into [out] to avoid allocating.
  Vector3 readPosition([Vector3? out]) => (out ?? Vector3.zero())
    ..setFrom(_position);

  Quaternion readRotation([Quaternion? out]) =>
      (out ?? Quaternion.identity())..setFrom(_rotation);

  Vector3 readScale([Vector3? out]) => (out ?? Vector3.zero())
    ..setFrom(_scale);

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
    var current = this;
    while (true) {
      if (!current.visible) return false;
      final parent = current._parent;
      if (parent == null) return true;
      current = parent;
    }
  }

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
