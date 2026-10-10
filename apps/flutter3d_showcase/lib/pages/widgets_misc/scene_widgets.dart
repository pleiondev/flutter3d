/// A scene written as widgets: a light, a material the boxes below it share,
/// a row of boxes and a turning pivot with a ball on it, built into the
/// page's scene by `SceneWidgets.mount` and rebuilt every frame.
///
/// Quoted by `scene_widgets.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class SceneWidgetsDemo extends ShowcaseDemo {
  late final SceneWidgetsMount _mount;

  int _boxes = 3;
  bool _warm = true;
  double _angle = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.4
      ..yaw = 0.3;
    context.orbit.target.setValues(0.0, 0.4, 0.0);
  }

  // #region widgets
  /// The whole scene, as a function of the page's three fields. Nothing here
  /// makes a node: each widget owns one, and a rebuild changes it.
  List<Widget> _children() => <Widget>[
    // Lux: about 14 500, a bright overcast-to-hazy sun.
    Light3D.directional(
      direction: Vector3(-0.4, -0.8, -0.5),
      intensity: 14500.0,
    ),
    Mesh3D(
      shape: CuboidShape(size: Vector3(6.0, 0.2, 3.0)),
      material: _floor,
      position: Vector3(0.0, -0.1, 0.0),
      name: 'floor',
    ),
    Material3D(
      name: 'paint',
      baseColor: _warm
          ? LinearColor.fromSrgb(0.9, 0.45, 0.2, 1.0)
          : LinearColor.fromSrgb(0.2, 0.5, 0.9, 1.0),
      roughness: 0.6,
      children: <Widget>[
        for (var i = 0; i < _boxes; i++)
          Mesh3D(
            key: ValueKey<String>('box $i'),
            shape: CuboidShape(size: Vector3.all(0.6)),
            position: Vector3(-2.2 + i * 0.9, 0.3, -0.6),
            name: 'box $i',
          ),
      ],
    ),
    Node3D(
      name: 'pivot',
      position: Vector3(0.0, 0.0, 0.8),
      rotation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _angle),
      children: <Widget>[
        Mesh3D(
          shape: SphereShape(radius: 0.3, segments: 32, rings: 16),
          material: _ball,
          position: Vector3(1.0, 0.3, 0.0),
          name: 'ball',
        ),
      ],
    ),
  ];
  // #endregion widgets

  final RenderMaterial _floor = RenderMaterial(
    name: 'floor',
    baseColor: LinearColor.fromSrgb(0.4, 0.42, 0.45, 1.0),
    roughness: 0.9,
  );
  final RenderMaterial _ball = RenderMaterial(
    name: 'ball',
    baseColor: LinearColor.fromSrgb(0.85, 0.85, 0.9, 1.0),
    roughness: 0.25,
    metallic: 1.0,
  );

  // #region mount
  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit;
    _mount = SceneWidgets.mount(
      scene: scene,
      renderer: context.renderer,
      device: context.device,
      children: _children(),
    );
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _angle += dt * 0.8;
    // A rebuild, as `setState` would cause under a `Scene3D`: the same nodes,
    // given the widgets' new properties.
    _mount.update(_children());
  }
  // #endregion mount

  @override
  void dispose() => _mount.dispose();

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Boxes',
      min: 1,
      max: 6,
      divisions: 5,
      value: () => _boxes.toDouble(),
      onChanged: (double v) => _boxes = v.round(),
      format: (double v) => '${v.round()}',
    ),
    ToggleControl(
      'Warm paint',
      value: () => _warm,
      onChanged: (bool v) => _warm = v,
    ),
  ];

  List<MeshNode> _meshes(Scene scene) {
    final List<MeshNode> found = <MeshNode>[];
    scene.root.traverse((SceneNode node) {
      if (node is MeshNode) found.add(node);
    });
    return found;
  }

  MeshNode? _named(Scene scene, String name) {
    for (final MeshNode mesh in _meshes(scene)) {
      if (mesh.name == name) return mesh;
    }
    return null;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final List<MeshNode> before = _meshes(scene);
    if (before.length != 2 + _boxes) {
      throw StateError('${before.length} meshes for ${2 + _boxes} widgets');
    }
    final MeshNode first = _named(scene, 'box 0')!;
    final RenderMaterial shared = first.material;
    if (!identical(_named(scene, 'box 1')!.material, shared)) {
      throw StateError('the boxes under one Material3D do not share it');
    }
    // A rebuild with one more box and the other paint: box 0 keeps its node
    // and its material, which changes in place.
    final (int boxes, bool warm) = (_boxes, _warm);
    _boxes = boxes + 1;
    _warm = !warm;
    _mount.update(_children());
    if (!identical(_named(scene, 'box 0'), first) ||
        !identical(first.material, shared) ||
        _named(scene, 'box $boxes') == null ||
        (shared.baseColor.toSrgb().b - (warm ? 0.9 : 0.2)).abs() > 1e-6) {
      throw StateError('a rebuild did not keep and change the nodes it owns');
    }
    // And one box fewer takes that box's node out of the scene.
    _boxes = boxes;
    _warm = warm;
    _mount.update(_children());
    if (_named(scene, 'box $boxes') != null) {
      throw StateError('a box whose widget went is still in the scene');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
