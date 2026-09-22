/// Joined lines whose width is measured in screen pixels.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PolylinesDemo extends ShowcaseDemo {
  static const double _viewportWidth = 1280;
  static const double _viewportHeight = 720;

  final List<MeshData> _meshes = <MeshData>[];
  final List<Material> _materials = <Material>[];
  final List<MeshNode> _lines = <MeshNode>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.2
      ..pitch = 0.08
      ..yaw = 0.12;
  }

  @override
  Scene build(DemoContext context) {
    // #region routes
    final List<List<Vector3>> routes = <List<Vector3>>[
      <Vector3>[
        Vector3(-3.2, 1.35, 0.0),
        Vector3(-2.0, 1.75, 0.2),
        Vector3(-0.8, 1.05, -0.1),
        Vector3(0.4, 1.62, 0.15),
        Vector3(1.7, 1.12, -0.05),
        Vector3(3.2, 1.52, 0.1),
      ],
      <Vector3>[
        Vector3(-3.2, 0.25, 0.0),
        Vector3(-2.2, -0.35, 0.15),
        Vector3(-1.0, 0.42, -0.1),
        Vector3(0.0, -0.28, 0.1),
        Vector3(1.25, 0.38, -0.15),
        Vector3(2.15, -0.3, 0.1),
        Vector3(3.2, 0.2, 0.0),
      ],
      <Vector3>[
        Vector3(-3.2, -1.45, 0.0),
        Vector3(-1.9, -0.85, -0.1),
        Vector3(-0.55, -1.62, 0.15),
        Vector3(0.8, -0.92, -0.1),
        Vector3(2.0, -1.55, 0.12),
        Vector3(3.2, -1.05, 0.0),
      ],
    ];
    final List<double> widths = <double>[6, 12, 22];
    final List<Vector4> palette = <Vector4>[
      Vector4(0.12, 0.78, 1.0, 1.0),
      Vector4(0.48, 0.3, 0.96, 1.0),
      Vector4(1.0, 0.34, 0.2, 1.0),
      Vector4(1.0, 0.76, 0.15, 1.0),
    ];
    // #endregion routes

    // #region geometry
    _meshes.clear();
    for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
      final List<Vector3> route = routes[routeIndex];
      _meshes.add(
        buildPolyline(
          route,
          width: widths[routeIndex],
          colours: <Vector4>[
            for (var point = 0; point < route.length; point++)
              palette[(point + routeIndex) % palette.length],
          ],
        ),
      );
    }
    // #endregion geometry

    // #region material
    _materials
      ..clear()
      ..addAll(<Material>[
        for (var i = 0; i < _meshes.length; i++)
          Material.polyline(
            name: 'route ${i + 1}',
            viewportWidth: _viewportWidth,
            viewportHeight: _viewportHeight,
          ),
      ]);
    _lines
      ..clear()
      ..addAll(<MeshNode>[
        for (var i = 0; i < _meshes.length; i++)
          MeshNode(
            DeviceMesh.upload(context.device, _meshes[i]),
            _materials[i],
            name: 'route ${i + 1}',
          ),
      ]);
    // #endregion material

    final Scene scene = Scene();
    for (final MeshNode line in _lines) {
      scene.add(line);
    }
    return scene;
  }

  // #region resize
  void setViewport(double width, double height) {
    for (final Material material in _materials) {
      final viewport = material.polylineViewport!;
      viewport[0] = width;
      viewport[1] = height;
    }
  }
  // #endregion resize

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final bool geometryMatches = _meshes.every(
      (MeshData mesh) =>
          mesh.vertexCount >= 12 &&
          mesh.indexCount == (mesh.vertexCount - 2) * 3,
    );
    final bool viewportsMatch = _materials.every((Material material) {
      final viewport = material.polylineViewport;
      return material.lighting == LightingModel.polyline &&
          viewport != null &&
          viewport[0] == _viewportWidth &&
          viewport[1] == _viewportHeight;
    });
    if (_lines.length != 3 ||
        !geometryMatches ||
        !viewportsMatch ||
        frame.drawCalls < 3) {
      throw StateError('the joined pixel-width routes were not drawn');
    }
    // #endregion check
  }
}
