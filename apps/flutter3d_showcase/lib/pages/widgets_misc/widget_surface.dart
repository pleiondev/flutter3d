/// A live Flutter widget drawn as a mesh in the scene: a plane whose texture
/// is the widget's own pixels, redrawn when the widget changes.
///
/// Quoted by `widget_surface.md` and shown whole in the Source tab.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final class WidgetSurfaceDemo extends ShowcaseDemo {
  late final WidgetSurface _surface;

  @override
  Scene build(DemoContext context) {
    // A widget surface renders a widget off the visible tree, which needs a
    // binding to exist. `runApp` has already made one by the time a real
    // session opens this page; idempotent here for the software-device test
    // that builds a page directly.
    WidgetsFlutterBinding.ensureInitialized();

    // #region surface
    _surface = WidgetSurface(
      device: context.device,
      width: 1.5,
      height: 1.0,
      child: const ColoredBox(color: Color(0xFF3355AA)),
    )..setPosition(Vector3(0, 0, 0));
    // #endregion surface

    final floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(4, 0.2, 4)).build(),
      ),
      f3d.Material(name: 'floor', baseColor: Vector4(0.5, 0.5, 0.5, 1.0)),
    )..setPosition(0, -1, 0);
    return Scene()
      ..add(_surface.node)
      ..add(floor)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region tick
    // Called once a game frame; redraws only when the widget's own pixels
    // have changed since the last call.
    unawaited(_surface.tick());
    // #endregion tick
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the widget surface was not drawn');
    }
    // #region hit
    // A point in the middle of the surface's own plane maps back to the
    // middle of its UV space.
    final uv = _surface.uvAt(Vector3.zero());
    // #endregion hit
    if (uv == null ||
        (uv.dx - 0.5).abs() > 0.01 ||
        (uv.dy - 0.5).abs() > 0.01) {
      throw StateError(
        'the plane\'s own centre should map to uv (0.5, 0.5), '
        'got $uv',
      );
    }
  }
}
