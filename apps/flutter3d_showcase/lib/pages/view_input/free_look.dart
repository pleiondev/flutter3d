/// Turning the head from where the camera stands, and walking it there, as
/// opposed to orbiting a point somebody else chose. The posts are laid out
/// again around the camera every frame, so there is always something to walk
/// past.
///
/// Quoted by `free_look.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FreeLookDemo extends ShowcaseDemo {
  bool walkingForward = true;
  double turn = 0.3;

  late final FreeLook _freeLook;
  late Vector3 _targetBefore;
  double _stepSeconds = 0.0;

  late final MeshNode _floor;
  final List<MeshNode> _posts = <MeshNode>[];
  final List<Material> _stones = <Material>[];

  /// Posts a side of the square laid out around the camera, and how far
  /// apart they stand.
  static const int _reach = 4;
  static const double _spacing = 4.0;

  /// Where the eyes are, in metres. Walking goes along the view axis, so a
  /// camera tilted down walks down: level, and at this height, it walks along
  /// the ground.
  static const double _eyeHeight = 1.6;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.0;
    context.orbit.target.y = _eyeHeight;
  }

  @override
  Scene build(DemoContext context) {
    // #region freelook
    _freeLook = FreeLook(context.orbit);
    // #endregion freelook

    Material stone(String name, double r, double g, double b) =>
        Material(name: name, baseColor: Vector4(r, g, b, 1.0), roughness: 0.8);
    _stones.addAll(<Material>[
      stone('grey', 0.65, 0.62, 0.58),
      stone('sand', 0.85, 0.75, 0.5),
      stone('clay', 0.8, 0.45, 0.35),
      stone('moss', 0.45, 0.7, 0.45),
    ]);

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3;
    _floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 80.0, depth: 80.0).build(),
      ),
      stone('floor', 0.3, 0.34, 0.32),
      name: 'floor',
    );
    scene.add(_floor);

    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.5, 2.5, 0.5)).build(),
    );
    for (var i = 0; i < (2 * _reach + 1) * (2 * _reach + 1); i++) {
      final MeshNode node = MeshNode(post, _stones.first, name: 'post $i');
      _posts.add(node);
      scene.add(node);
    }
    scene.add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
    );
    _layOut(context);
    return scene;
  }

  /// Puts every post on the lattice point nearest the camera and beyond, and
  /// colours it by which point that is, so a post keeps its colour as the
  /// camera passes it and a new one arrives ahead.
  void _layOut(DemoContext context) {
    final Vector3 eye = context.camera.readPosition();
    final int cellX = (eye.x / _spacing).round();
    final int cellZ = (eye.z / _spacing).round();
    _floor.setPosition(cellX * _spacing, 0.0, cellZ * _spacing);
    var index = 0;
    for (var i = -_reach; i <= _reach; i++) {
      for (var j = -_reach; j <= _reach; j++) {
        final int x = cellX + i;
        final int z = cellZ + j;
        final MeshNode node = _posts[index++];
        node.setPosition(x * _spacing, 1.25, z * _spacing);
        node.material = _stones[(x * 7 + z * 13).abs() % _stones.length];
        // One the camera is standing inside would fill the frame.
        node.visible =
            (node.readPosition() - Vector3(eye.x, 1.25, eye.z)).length > 1.2;
      }
    }
  }

  // #region walk
  @override
  void update(DemoContext context, double dt) {
    // Back to eye height first: a drag that tilted the view would otherwise
    // have the walk climb or sink, and the camera would leave the floor.
    context.orbit.target.y = _eyeHeight;
    // The head turns with the eye held still; the walk then carries the eye
    // the way the head now faces.
    _freeLook.look(turn * 75.0 * dt, 0.0);
    _targetBefore = context.orbit.target.clone();
    _stepSeconds = dt;
    if (walkingForward) {
      _freeLook.walk(forward: 1.0, seconds: dt);
    }
    _layOut(context);
  }
  // #endregion walk

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Walk forward',
      value: () => walkingForward,
      onChanged: (bool v) => walkingForward = v,
    ),
    SliderControl(
      'Speed',
      min: 0,
      max: 8,
      value: () => _freeLook.metresPerSecond,
      onChanged: (double v) => _freeLook.metresPerSecond = v,
      format: (double v) => '${v.toStringAsFixed(1)} m/s',
    ),
    SliderControl(
      'Turn the head',
      min: -1,
      max: 1,
      value: () => turn,
      onChanged: (double v) => turn = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the posts were not drawn');
    }
    if (!walkingForward) return;
    // walk moves the target by metresPerSecond * seconds along the view
    // axis. The distance actually covered has to match that number exactly,
    // rather than only be nonzero.
    final double moved = (_freeLook.orbit.target - _targetBefore).length;
    final double expected = _freeLook.metresPerSecond * _stepSeconds;
    if ((moved - expected).abs() > 1e-6) {
      throw StateError('walking moved $moved, expected $expected');
    }
    final int standing = _posts.where((MeshNode p) => p.visible).length;
    if (standing < _posts.length - 2) {
      throw StateError('the camera should be standing among the posts');
    }
  }
}
