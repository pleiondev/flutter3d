/// A modeller-style overlay drawn against the scene depth buffer.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MeshOverlayDemo extends ShowcaseDemo {
  static const double _viewportHeight = 720;

  late final MeshOverlay _overlay;
  bool _vertices = true;
  bool _face = true;
  bool _through = true;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.2
      ..pitch = 0.28
      ..yaw = 0.62;
  }

  @override
  Scene build(DemoContext context) {
    // #region contributor
    _overlay = context.renderer.addContributor(
      MeshOverlay(
        vertexShader: context.renderer.debugLineVertexShader,
        fragmentShader: context.renderer.debugLineFragmentShader,
      ),
    );
    // #endregion contributor

    // #region surface
    final MeshNode cube = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(2.0)).build(),
      ),
      Material(
        name: 'editable surface',
        baseColor: Vector4(0.16, 0.32, 0.52, 1.0),
        roughness: 0.58,
      ),
      name: 'editable cube',
    );
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.45, 0.52, 0.68)
      ..ambientIntensity = 0.16
      ..add(cube)
      ..add(
        LightNode(name: 'key', intensity: 3.6)
          ..setLocalForward(Vector3(-0.45, -0.8, -0.35)),
      );
    // #endregion surface
    _rebuild(context);
    return scene;
  }

  // #region camera
  void _rebuild(DemoContext context) {
    final Matrix4 cameraWorld = context.camera.worldMatrix;
    final values = cameraWorld.storage;
    final Vector3 right = Vector3(values[0], values[1], values[2]);
    final Vector3 up = Vector3(values[4], values[5], values[6]);
    final double fov =
        context.camera.projection.verticalFieldOfView ?? math.pi / 4;
    _overlay
      ..clear()
      ..lookFrom(
        eye: context.camera.readWorldPosition(),
        right: right,
        up: up,
        pixel: 2.0 * math.tan(fov * 0.5) / _viewportHeight,
      );
    _writeGeometry();
  }
  // #endregion camera

  // #region batches
  void _writeGeometry() {
    final List<Vector3> corners = <Vector3>[
      for (final double z in <double>[-1, 1])
        for (final double y in <double>[-1, 1])
          for (final double x in <double>[-1, 1]) Vector3(x, y, z),
    ];
    final Vector4 edgeColour = Vector4(0.2, 0.82, 1.0, 1.0);
    for (final (int a, int b) in <(int, int)>[
      (0, 1),
      (0, 2),
      (1, 3),
      (2, 3),
      (4, 5),
      (4, 6),
      (5, 7),
      (6, 7),
      (0, 4),
      (1, 5),
      (2, 6),
      (3, 7),
    ]) {
      _overlay.edge(corners[a], corners[b], edgeColour);
    }
    if (_vertices) {
      for (final Vector3 corner in corners) {
        _overlay.point(corner, Vector4(1.0, 0.72, 0.12, 1.0), size: 11);
      }
    }
    if (_face) {
      final Vector4 selected = Vector4(0.2, 1.0, 0.45, 1.0);
      _overlay
        ..wash(corners[4], corners[5], corners[7], selected)
        ..wash(corners[4], corners[7], corners[6], selected)
        ..ribbon(corners[4], corners[7], selected, width: 5);
    }
    if (_through) {
      _overlay.throughGeometry(() {
        _overlay
          ..edge(
            Vector3(-1.6, 0.0, 0.0),
            Vector3(1.6, 0.0, 0.0),
            Vector4(0.78, 0.42, 1.0, 1.0),
          )
          ..ribbon(
            Vector3(0.0, -1.6, 0.0),
            Vector3(0.0, 1.6, 0.0),
            Vector4(0.78, 0.42, 1.0, 1.0),
            width: 7,
          )
          ..point(Vector3(0.0, 1.6, 0.0), Vector4(0.78, 0.42, 1.0, 1.0));
      });
    }
  }
  // #endregion batches

  @override
  void update(DemoContext context, double dt) => _rebuild(context);

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    // #region controls
    ToggleControl(
      'Vertex handles',
      value: () => _vertices,
      onChanged: (bool value) => _vertices = value,
    ),
    ToggleControl(
      'Selected face',
      value: () => _face,
      onChanged: (bool value) => _face = value,
    ),
    ToggleControl(
      'Through-mesh gizmo',
      value: () => _through,
      onChanged: (bool value) => _through = value,
    ),
    // #endregion controls
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_overlay.lines.vertexCount != 24 ||
        _overlay.handles.vertexCount != 54 ||
        _overlay.fill.vertexCount != 6 ||
        _overlay.linesThrough.isEmpty ||
        _overlay.handlesThrough.isEmpty ||
        frame.drawCalls < 6) {
      throw StateError('the mesh overlay batches did not reach the frame');
    }
    // #endregion check
  }
}
