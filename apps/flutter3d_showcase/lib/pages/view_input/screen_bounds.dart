/// Where a box in the world lands on the glass, as a rectangle a focus ring
/// or a label can use. Three things move about the scene and the rectangle
/// `screenBoundsOfBox` returns for each is drawn over the picture.
///
/// Quoted by `screen_bounds.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final class ScreenBoundsDemo extends ShowcaseDemo {
  int ringed = 3;

  late final CameraNode _camera;
  late final Scene _scene;
  late final MeshNode _cube;
  late final MeshNode _sphere;
  late final MeshNode _pillar;
  double _clock = 0.0;

  static const List<String> _names = <String>['cube', 'sphere', 'pillar'];
  static const List<Color> _colours = <Color>[
    Color(0xFFFFB03B),
    Color(0xFF5CD6FF),
    Color(0xFFFF6B9A),
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.45
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    _camera = context.camera;
    f3d.Material colour(String name, double r, double g, double b) =>
        f3d.Material(
          name: name,
          baseColor: Vector4(r, g, b, 1.0),
          roughness: 0.6,
        );
    _cube = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(1.2)).build(),
      ),
      colour('cube', 0.8, 0.55, 0.3),
      name: 'cube',
    );
    _sphere = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(radius: 0.7).build()),
      colour('sphere', 0.35, 0.65, 0.8),
      name: 'sphere',
    );
    _pillar = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.6, 2.4, 0.6)).build(),
      ),
      colour('pillar', 0.8, 0.4, 0.55),
      name: 'pillar',
    )..setPosition(0.0, 1.2, -1.6);

    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 12.0, depth: 12.0).build(),
          ),
          colour('floor', 0.36, 0.4, 0.38),
          name: 'floor',
        ),
      )
      ..add(_cube)
      ..add(_sphere)
      ..add(_pillar)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    _place();
    return _scene;
  }

  void _place() {
    _cube.setPosition(
      2.4 * math.cos(_clock * 0.6),
      0.6,
      2.4 * math.sin(_clock * 0.6),
    );
    _sphere.setPosition(
      1.4 * math.cos(-_clock * 0.9 + 2.0),
      0.7 + 0.5 * math.sin(_clock * 1.7).abs(),
      1.4 * math.sin(-_clock * 0.9 + 2.0),
    );
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    _place();
  }

  // #region box
  /// What each thing occupies in the world, as the box `screenBoundsOfBox`
  /// takes — the box a culling or picking system would already keep.
  Aabb3 _boxOf(int which) => switch (which) {
    0 => Aabb3.centerAndHalfExtents(
      _cube.readPosition(),
      Vector3(0.6, 0.6, 0.6),
    ),
    1 => Aabb3.centerAndHalfExtents(
      _sphere.readPosition(),
      Vector3(0.7, 0.7, 0.7),
    ),
    _ => Aabb3.centerAndHalfExtents(
      _pillar.readPosition(),
      Vector3(0.3, 1.2, 0.3),
    ),
  };
  // #endregion box

  // #region bounds
  ScreenBounds? _measure(int which, double width, double height) =>
      screenBoundsOfBox(
        _camera.viewProjection(width / height),
        _boxOf(which),
        width: width,
        height: height,
      );
  // #endregion bounds

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Listener(
        onPointerMove: (PointerMoveEvent event) =>
            context.orbit.rotate(event.delta.dx, event.delta.dy),
        onPointerSignal: (PointerSignalEvent event) {
          if (event is PointerScrollEvent) {
            context.orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SceneSurface(
              renderer: context.renderer,
              scene: _scene,
              view: context.view,
              settings: () => const RenderSettings(),
              onBeforeFrame: () =>
                  context.orbit.syncProjectionDepth(context.camera),
              presentFrame: presentFrame,
            ),
            IgnorePointer(child: CustomPaint(painter: _RingPainter(this))),
          ],
        ),
      );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Ring around',
      options: const <String>['cube', 'sphere', 'pillar', 'all three'],
      index: () => ringed,
      onChanged: (int i) => ringed = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the scene was not drawn');
    }
    const double width = 320.0;
    const double height = 180.0;
    final viewProjection = _camera.viewProjection(width / height);
    for (var which = 0; which < 3; which++) {
      final ScreenBounds? bounds = _measure(which, width, height);
      if (bounds == null) {
        throw StateError('${_names[which]} is behind the camera');
      }
      // A real rectangle, and one that holds the point its own centre
      // projects to.
      if (bounds.left >= bounds.right || bounds.top >= bounds.bottom) {
        throw StateError('${_names[which]} got a degenerate rectangle');
      }
      final Vector3 centre = _boxOf(which).center;
      final Vector4 clip = viewProjection.transformed(
        Vector4(centre.x, centre.y, centre.z, 1.0),
      );
      final double x = (clip.x / clip.w * 0.5 + 0.5) * width;
      final double y = (0.5 - clip.y / clip.w * 0.5) * height;
      if (x < bounds.left ||
          x > bounds.right ||
          y < bounds.top ||
          y > bounds.bottom) {
        throw StateError(
          '${_names[which]} is not inside the rectangle its own box gave',
        );
      }
    }
  }
}

/// Draws the rectangles, at whatever size the frame is being shown.
final class _RingPainter extends CustomPainter {
  _RingPainter(this._demo);

  final ScreenBoundsDemo _demo;

  @override
  void paint(Canvas canvas, Size size) {
    final List<int> which = _demo.ringed == 3
        ? const <int>[0, 1, 2]
        : <int>[_demo.ringed];
    for (final int i in which) {
      final ScreenBounds? bounds = _demo._measure(i, size.width, size.height);
      if (bounds == null) continue;
      final Rect rect = Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3.0), const Radius.circular(4.0)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = ScreenBoundsDemo._colours[i],
      );
      final TextPainter label = TextPainter(
        text: TextSpan(
          text:
              '${ScreenBoundsDemo._names[i]}  '
              '${bounds.left.round()},${bounds.top.round()}  '
              '${rect.width.round()}x${rect.height.round()}',
          style: TextStyle(
            color: ScreenBoundsDemo._colours[i],
            fontSize: 11.0,
            fontFamily: 'RobotoMono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rect.left, math.max(rect.top - 20.0, 2.0)));
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => true;
}
