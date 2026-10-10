/// The quarry's crane: a long-necked beast standing on the quarry's rim,
/// swinging its neck over the pit and lifting stone on a rope from its jaw.
///
/// The physics core's multibody: a fixed body, a torso that turns on it, a
/// neck of four links each bending at its root and a head, every joint in
/// reduced coordinates so the neck cannot come apart however heavy the
/// stone; and the rope a distance joint from the jaw to the stone.
///
/// What is drawn is a sauropod, a skinned model, turning with the torso.
/// Its neck has two bones and the core's has four links, so the bones are
/// laid along the links every frame: the first from the neck's root to as
/// far along the links as the model's first bone reaches along its own
/// neck, the second from there to the head, each stretched or shortened to
/// the span it is given, and the head held level at the neck's tip.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// A neck link's length and radius, m, and how many there are.
const double _neckLength = 1.3, _neckRadius = 0.22;
const int _neckLinks = 4;

/// How fast the neck lifts and the torso turns at most, rad/s, and with
/// what force their muscles drive them.
const double _lift = 0.35, _swing = 0.5, _muscle = 4.0e5;

/// The crane on the quarry's rim at [at], facing [facing] (radians about
/// up, nought along +x), drawn as [beast].
final class DinoCrane {
  DinoCrane(
    this._world,
    GraphicsDevice device,
    Scene scene, {
    required Vector3 at,
    required double facing,
    required ModelAsset beast,
  }) {
    final turn = _turn(Vector3(0, 1, 0), facing);
    Vector3 local(double x, double y, double z) =>
        at + turn.asRotationMatrix().transformed(Vector3(x, y, z));
    // The legs and body: fixed, the multibody's root.
    final root = _world.addBody(
      position: local(0, 1.2, 0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    _world.setShape(root, NativeShape.box(Vector3(1.4, 0.9, 0.7)));
    _world.setOrientation(root, turn);
    _crane = _world.createMultibody(root);
    // The torso, turning about up on the body's back.
    _torsoBody = _world.addBody(position: local(0.6, 2.4, 0), mass: 1800.0);
    _world
      ..setShape(_torsoBody, NativeShape.box(Vector3(0.7, 0.4, 0.5)))
      ..setOrientation(_torsoBody, turn);
    _torso = _world.addLink(
      _crane,
      _torsoBody,
      type: NativeJointType.revolute,
      anchor: local(0.6, 2.1, 0),
      axis: Vector3(0, 1, 0),
    );
    // The neck: links laid along the torso's forward, rising at forty
    // degrees, each bending about the torso's side at its root.
    final side = turn.asRotationMatrix().transformed(Vector3(0, 0, 1));
    final rise = 40.0 * math.pi / 180.0;
    final lean = Portable.sinCos(rise);
    final along = turn.asRotationMatrix().transformed(
      Vector3(lean.cos, lean.sin, 0),
    );
    var root2 = local(1.2, 2.6, 0);
    var parent = _torso;
    final tilt = _turn(side, rise) * turn;
    for (var k = 0; k < _neckLinks; k++) {
      final middle = root2 + along * (0.5 * _neckLength);
      final link = _world.addBody(position: middle, mass: 220.0 - 30.0 * k);
      _world
        ..setShape(
          link,
          NativeShape.capsule(
            _neckRadius * (1.0 - 0.12 * k),
            0.5 * _neckLength - _neckRadius,
          ),
        )
        // A capsule lies along y; turn it to lie along the neck.
        ..setOrientation(link, _between(Vector3(0, 1, 0), along));
      parent = _world.addLink(
        _crane,
        link,
        parent: parent,
        type: NativeJointType.revolute,
        anchor: root2,
        axis: side,
      );
      _world.setLinkLimits(_crane, parent, lower: -0.5, upper: 0.5);
      _neck.add(parent);
      _neckBodies.add(link);
      root2 = root2 + along * _neckLength;
    }
    // The head, held fixed at the neck's tip.
    head = _world.addBody(position: root2 + along * 0.3, mass: 60.0);
    _world
      ..setShape(head, NativeShape.box(Vector3(0.35, 0.2, 0.2)))
      ..setOrientation(head, tilt);
    _world.addLink(
      _crane,
      head,
      parent: parent,
      type: NativeJointType.fixed,
      anchor: root2,
    );
    _beast = SceneNode(name: 'beast');
    scene.add(_beast);
    _pose = _NeckPose.dress(
      beast,
      scene,
      _beast,
      // Where the neck's root is from the torso's middle, in its own frame.
      neckRoot: Vector3(0.6, 0.2, 0.0),
      neckLength: _neckLinks * _neckLength,
    );
    _rope = MeshNode(
      DeviceMesh.upload(
        device,
        const CylinderShape(
          radiusTop: 0.025,
          radiusBottom: 0.025,
          height: 1.0,
        ).build(),
      ),
      RenderMaterial(
        name: 'rope',
        baseColor: LinearColor.fromSrgb(0.55, 0.45, 0.30, 1.0),
        roughness: 0.8,
      ),
      name: 'rope',
    )..isVisible = false;
    scene.add(_rope);
  }

  final NativeWorld _world;
  late final NativeMultibody _crane;
  late final NativeBody _torsoBody;
  late final int _torso;
  final List<int> _neck = <int>[];
  final List<NativeBody> _neckBodies = <NativeBody>[];
  late final SceneNode _beast;
  late final _NeckPose? _pose;
  late final MeshNode _rope;
  late final NativeBody head;

  /// The rope, and what hangs on it.
  NativeJoint? _hold;
  NativeBody? carried;

  /// Where the jaw is.
  Vector3 get jaw => _world.localPositionOf(head);

  /// What the operator asks: [lift] and [swing] from −1 to 1.
  void work({required double lift, required double swing}) {
    _world.setLinkMotor(_crane, _torso, speed: _swing * swing, force: _muscle);
    for (final link in _neck) {
      _world.setLinkMotor(
        _crane,
        link,
        speed: -_lift * lift / _neckLinks,
        force: _muscle,
      );
    }
  }

  /// Takes up the nearest of [stones] within reach of the jaw on the rope,
  /// or lets go of what it carries.
  void grab(List<NativeBody> stones) {
    if (_hold != null) {
      _world.removeJoint(_hold!);
      _hold = null;
      carried = null;
      _rope.isVisible = false;
      return;
    }
    final at = jaw;
    NativeBody? best;
    var nearest = 4.0;
    for (final s in stones) {
      final d = (_world.localPositionOf(s) - at).length;
      if (d < nearest) {
        nearest = d;
        best = s;
      }
    }
    if (best == null) return;
    _hold = _world.createDistanceJoint(
      head,
      best,
      anchorA: at,
      anchorB: _world.localPositionOf(best) + Vector3(0, 0.3, 0),
    );
    carried = best;
    _rope.isVisible = true;
  }

  /// The rope and what hangs on it, by their handles; the neck and its
  /// motors are the world's, and come back with it.
  Map<String, Object?> save() => <String, Object?>{
    'hold': _hold?.raw,
    'carried': carried?.raw,
  };

  /// Back to what [save] wrote, the world already restored under it.
  void restore(Object? saved) {
    final hold = saved is Map ? saved['hold'] : null;
    final stone = saved is Map ? saved['carried'] : null;
    _hold = hold is num ? NativeJoint(hold.toInt()) : null;
    carried = stone is num ? NativeBody(stone.toInt()) : null;
    _rope.isVisible = _hold != null;
  }

  /// The crane drawn where the world has it.
  void update() {
    // The neck's joints, root to tip, off the links' middles and the axes
    // their orientations turn a capsule's y to, as a scene node turns it.
    Vector3 axisOf(NativeBody link) => _world
        .orientationOf(link)
        .asRotationMatrix()
        .transformed(Vector3(0, 1, 0));
    final points = <Vector3>[
      for (final link in _neckBodies)
        _world.localPositionOf(link) - axisOf(link) * (0.5 * _neckLength),
      _world.localPositionOf(_neckBodies.last) +
          axisOf(_neckBodies.last) * (0.5 * _neckLength),
    ];
    // The beast faces the way the neck leaves the torso, whichever way the
    // torso has turned.
    final p = _world.localPositionOf(_torsoBody);
    final ahead = (points.first - p)
      ..y = 0
      ..normalize();
    final side = ahead.cross(Vector3(0, 1, 0));
    _beast.setLocalMatrix(
      Matrix4.columns(
        Vector4(ahead.x, ahead.y, ahead.z, 0),
        Vector4(0, 1, 0, 0),
        Vector4(side.x, side.y, side.z, 0),
        Vector4(p.x, p.y, p.z, 1),
      ),
    );
    _pose?.follow(points);
    final stone = carried;
    if (stone != null) {
      final a = jaw, b = _world.localPositionOf(stone) + Vector3(0, 0.3, 0);
      final span = b - a;
      final length = span.length;
      _rope
        ..setPosition((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        ..setRotation(_between(Vector3(0, 1, 0), span.normalized()))
        ..setScale(1.0, length, 1.0);
    }
  }
}

/// The beast's model on the torso's node, and how its neck is laid along
/// the core's.
final class _NeckPose {
  _NeckPose._(
    this._skin,
    this._mesh,
    this._shoulders,
    this._neck,
    this._head,
    this._reach,
  );

  /// Puts [beast] under [torso], sized so its neck from shoulders to head
  /// is [neckLength] and placed so its shoulders stand at [neckRoot] in the
  /// torso's frame; its +z, the way it faces, along the torso's +x. Every
  /// bone is set to the pose it was skinned in. Null, and the beast stands
  /// as it was modelled, if its skeleton has no shoulders, neck and head.
  static _NeckPose? dress(
    ModelAsset beast,
    Scene scene,
    SceneNode torso, {
    required Vector3 neckRoot,
    required double neckLength,
  }) {
    final placed = SceneNode(name: 'beast placed');
    torso.add(placed);
    final drawn = beast.instantiate(scene, parent: placed, name: 'beast');
    // The file's hide is near black under this sun: a grey-green back and
    // a paler belly, dull as skin is.
    for (final look in drawn.meshes) {
      final material = look.material
        ..metallic = 0.0
        ..roughness = 0.85;
      material.baseColor = material.name == 'Brown'
          ? LinearColor.fromSrgb(0.5, 0.52, 0.4, 1.0)
          : LinearColor.fromSrgb(0.66, 0.6, 0.47, 1.0);
    }
    if (drawn.skeletons.isEmpty || drawn.meshes.isEmpty) return null;
    final skin = drawn.skeletons.first;
    final mesh = drawn.meshes.first;
    int bone(String name) => skin.joints.indexWhere((j) => j.name == name);
    final shoulders = bone('Shoulders'), neck = bone('Neck');
    final head = bone('Head');
    if (shoulders < 0 || neck < 0 || head < 0) return null;
    // Every bone to its skinned pose, parents first. The file's own node
    // pose is a frame of one of its clips, which bends the neck its own
    // way.
    int depth(SceneNode node) {
      var n = 0;
      for (var p = node.parent; p != null; p = p.parent) {
        n++;
      }
      return n;
    }

    final order = List<int>.generate(skin.joints.length, (k) => k)
      ..sort((a, b) => depth(skin.joints[a]).compareTo(depth(skin.joints[b])));
    for (final k in order) {
      _setWorld(
        skin.joints[k],
        mesh.worldMatrix.multiplied(skin.bindPoseOf(k)),
      );
    }
    // Sized and placed off the bones, in the model's own frame (the
    // instance stands at the world's origin until the first update).
    Vector3 at(int k) =>
        mesh.worldMatrix.multiplied(skin.bindPoseOf(k)).getTranslation();
    final first = (at(neck) - at(shoulders)).length;
    final second = (at(head) - at(neck)).length;
    final scale = neckLength / (first + second);
    // The model's (x, y, z) to the torso's (z, y, −x): its +z to +x.
    final s = at(shoulders);
    final offset = neckRoot - Vector3(s.z, s.y, -s.x) * scale;
    placed.setLocalMatrix(
      Matrix4.columns(
        Vector4(0, 0, -scale, 0),
        Vector4(0, scale, 0, 0),
        Vector4(scale, 0, 0, 0),
        Vector4(offset.x, offset.y, offset.z, 1),
      ),
    );
    return _NeckPose._(
      skin,
      mesh,
      shoulders,
      neck,
      head,
      neckLength * first / (first + second),
    );
  }

  final Skeleton _skin;
  final MeshNode _mesh;
  final int _shoulders, _neck, _head;

  /// How far along the core's neck the model's first bone reaches, m.
  final double _reach;

  /// Lays the neck along [points], the core's neck joints root to tip.
  void follow(List<Vector3> points) {
    // The point [_reach] along the links.
    var left = _reach;
    var middle = points.last;
    for (var k = 0; k + 1 < points.length; k++) {
      final span = points[k + 1] - points[k];
      final length = span.length;
      if (left <= length) {
        middle = points[k] + span * (left / length);
        break;
      }
      left -= length;
    }
    final tip = points.last;
    final world = _mesh.worldMatrix;
    Matrix4 bind(int k) => world.multiplied(_skin.bindPoseOf(k));
    final shoulders = bind(_shoulders), neck = bind(_neck);
    final head = bind(_head);
    _lay(_shoulders, shoulders, neck.getTranslation(), points.first, middle);
    _lay(_neck, neck, head.getTranslation(), middle, tip);
    // The head level, or nearly, whichever way the last link points: a
    // beast keeps its eyes on the horizon however it holds its neck.
    final last = tip - points[points.length - 2];
    final ahead = Vector3(last.x, 0.25 * last.y, last.z)..normalize();
    final headAlong = head.getColumn(1).xyz..normalize();
    final turn = _between(headAlong, ahead);
    _setWorld(
      _skin.joints[_head],
      _chain(<Matrix4>[
        Matrix4.translation(tip),
        Matrix4.compose(Vector3.zero(), turn, Vector3.all(1.0)),
        Matrix4.translation(-head.getTranslation()),
        head,
      ]),
    );
  }

  /// Bone [k], skinned at [bind] from its own origin to [end], laid from
  /// [from] to [to]: turned the shortest way and stretched along itself.
  void _lay(int k, Matrix4 bind, Vector3 end, Vector3 from, Vector3 to) {
    final start = bind.getTranslation();
    final was = end - start, wanted = to - from;
    final along = was.normalized();
    final stretch = wanted.length / was.length - 1.0;
    final pull = Matrix4.identity();
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        pull.setEntry(r, c, pull.entry(r, c) + stretch * along[r] * along[c]);
      }
    }
    final turn = _between(along, wanted.normalized());
    _setWorld(
      _skin.joints[k],
      _chain(<Matrix4>[
        Matrix4.translation(from),
        Matrix4.compose(Vector3.zero(), turn, Vector3.all(1.0)),
        pull,
        Matrix4.translation(-start),
        bind,
      ]),
    );
  }

  /// The product of [matrices], the first outermost.
  static Matrix4 _chain(List<Matrix4> matrices) => matrices
      .skip(1)
      .fold(matrices.first.clone(), (sum, next) => sum..multiply(next));

  /// Sets [node]'s own matrix so that its world matrix is [world].
  static void _setWorld(SceneNode node, Matrix4 world) {
    final parent = node.parent;
    node.setLocalMatrix(
      parent == null
          ? world
          : Matrix4.inverted(parent.worldMatrix).multiplied(world),
    );
  }
}

/// A turn of [angle] about the unit [axis], with `Portable`'s sine and
/// cosine: `Quaternion.axisAngle` asks `dart:math`, whose last bits differ
/// between the VM and a browser.
Quaternion _turn(Vector3 axis, double angle) {
  final (:sin, :cos) = Portable.sinCos(angle * 0.5);
  return Quaternion(axis.x * sin, axis.y * sin, axis.z * sin, cos);
}

/// The shortest turn taking [from] onto [to], as `Quaternion.fromTwoVectors`
/// builds it, but with the half angle's sine and cosine taken from the
/// angle's cosine c as √((1 − c)/2) and √((1 + c)/2) rather than through
/// `acos`, which asks `dart:math`: a square root is rounded alike everywhere.
Quaternion _between(Vector3 from, Vector3 to) {
  final a = from.normalized();
  final b = to.normalized();
  final c = a.dot(b);
  if ((1.0 - c).abs() < 0.0005) return Quaternion.identity();
  if ((1.0 + c).abs() < 0.0005) {
    // Half a turn, about any axis square to [from], picked as vector_math
    // picks it.
    final axis = a.cross(
      a.x > a.y && a.x > a.z ? Vector3(0.0, 1.0, 0.0) : Vector3(1.0, 0.0, 0.0),
    )..normalize();
    return Quaternion(axis.x, axis.y, axis.z, 0.0);
  }
  final axis = a.cross(b)..normalize();
  final s = math.sqrt(math.max(0.0, (1.0 - c) * 0.5));
  return Quaternion(
    axis.x * s,
    axis.y * s,
    axis.z * s,
    math.sqrt(math.max(0.0, (1.0 + c) * 0.5)),
  );
}
