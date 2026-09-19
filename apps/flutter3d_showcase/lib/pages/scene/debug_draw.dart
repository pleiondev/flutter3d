/// Built-in overlays for inspecting a scene while it runs.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DebugDrawDemo extends ShowcaseDemo {
  bool _bounds = true;
  bool _normals = true;
  bool _axes = true;
  bool _lights = true;
  bool _skeleton = true;
  late final Skeleton _rig;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.2
      ..pitch = 0.24
      ..yaw = 0.55;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region model
    final MeshData bodyData = const CapsuleShape(
      radius: 0.58,
      height: 1.4,
      segments: 20,
      rings: 6,
    ).build(layout: VertexLayout.skinned);
    final MeshNode body = MeshNode(
      DeviceMesh.upload(context.device, bodyData),
      Material(
        name: 'blue body',
        baseColor: Vector4(0.12, 0.42, 0.78, 1.0),
        roughness: 0.48,
      ),
      name: 'inspected capsule',
    )..setPosition(0.0, 1.25, 0.0);
    // #endregion model

    // #region rig
    final SceneNode hip = SceneNode(name: 'hip')..setPosition(0.0, 0.45, 0.0);
    final SceneNode chest = SceneNode(name: 'chest')
      ..setPosition(0.0, 0.8, 0.0);
    final SceneNode head = SceneNode(name: 'head')
      ..setPosition(0.25, 0.72, 0.0);
    hip.add(chest);
    chest.add(head);
    _rig = Skeleton(
      name: 'three-joint rig',
      joints: <SceneNode>[hip, chest, head],
      inverseBindMatrices: <Matrix4>[
        Matrix4.copy(hip.worldMatrix)..invert(),
        Matrix4.copy(chest.worldMatrix)..invert(),
        Matrix4.copy(head.worldMatrix)..invert(),
      ],
    );
    body.skeleton = _rig;
    // #endregion rig

    // #region scene
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.38, 0.46, 0.62)
      ..ambientIntensity = 0.14
      ..add(hip)
      ..add(body)
      ..add(
        LightNode(
          type: LightType.point,
          intensity: 14.0,
          range: 8.0,
          name: 'debugged light',
        )..setPosition(-2.2, 3.2, 2.0),
      );
    // #endregion scene
    return scene;
  }

  // #region options
  DebugDrawOptions get _debug => DebugDrawOptions(
    bounds: _bounds,
    normals: _normals,
    axes: _axes,
    lightGizmos: _lights,
    skeletons: _skeleton,
    normalLength: 0.18,
  );

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(debug: _debug);
  // #endregion options

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    // #region controls
    ToggleControl(
      'Bounds',
      value: () => _bounds,
      onChanged: (bool value) => _bounds = value,
    ),
    ToggleControl(
      'Normals',
      value: () => _normals,
      onChanged: (bool value) => _normals = value,
    ),
    ToggleControl(
      'World axes',
      value: () => _axes,
      onChanged: (bool value) => _axes = value,
    ),
    ToggleControl(
      'Light gizmo',
      value: () => _lights,
      onChanged: (bool value) => _lights = value,
    ),
    ToggleControl(
      'Skeleton',
      value: () => _skeleton,
      onChanged: (bool value) => _skeleton = value,
    ),
    // #endregion controls
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_debug.anyEnabled ||
        _rig.jointCount != 3 ||
        frame.debugLines <= 15 ||
        frame.drawCalls < 2) {
      throw StateError('the requested debug overlays were not drawn');
    }
    // #endregion check
  }
}
