/// A live Flutter widget drawn as a mesh in the scene: a plane whose texture
/// is the widget's own pixels, redrawn when the widget changes. This one is a
/// little console with a clock and a progress bar, standing on a floor.
///
/// Quoted by `widget_surface.md` and shown whole in the Source tab.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final class WidgetSurfaceDemo extends ShowcaseDemo {
  double speed = 1.0;

  late final WidgetSurface _surface;
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0.0);
  bool _uploading = false;

  /// Where the middle of the surface stands, in metres.
  static const double _height = 0.9;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.4
      ..pitch = 0.15
      // At -Z, the side the plane's front faces at yaw zero.
      ..yaw = math.pi + 0.4;
    context.orbit.target.setValues(0.0, _height, 0.0);
  }

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
      width: 1.6,
      height: 1.0,
      // A surface's content lands on its mesh turned half way round, so the
      // widget is turned half way round to meet it. A workaround the
      // pendulum lab applies for the same reason, not a property of the
      // widget: without it the clock reads upside down.
      child: Transform.flip(
        flipX: true,
        flipY: true,
        child: _Console(seconds: _seconds),
      ),
    )..setPosition(Vector3(0.0, _height, 0.0));
    // The plane's front faces -Z at yaw zero, which is where this page's
    // camera stands. Drawn from both sides, so orbiting behind it shows the
    // back of the screen rather than nothing.
    _surface.node.material.doubleSided = true;
    // #endregion surface

    final floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(5, 0.2, 5)).build(),
      ),
      f3d.Material(name: 'floor', baseColor: Vector4(0.4, 0.44, 0.42, 1.0)),
      name: 'floor',
    )..setPosition(0, -0.1, 0);
    // A stand for it, so it reads as a screen and not a card in mid-air.
    final stand = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.12, _height - 0.4, 0.12)).build(),
      ),
      f3d.Material(name: 'stand', baseColor: Vector4(0.25, 0.27, 0.3, 1.0)),
      name: 'stand',
    )..setPosition(0, (_height - 0.4) / 2, 0.06);
    return Scene()
      ..add(_surface.node)
      ..add(floor)
      ..add(stand)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    _seconds.value += dt * speed;
    // #region tick
    // Called once a game frame; redraws only when the widget's own pixels
    // have changed since the last call. One upload at a time: a slow one is
    // not queued behind by another.
    if (!_uploading) {
      _uploading = true;
      unawaited(_surface.tick().whenComplete(() => _uploading = false));
    }
    // #endregion tick
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Clock speed',
      min: 0,
      max: 4,
      value: () => speed,
      onChanged: (double v) => speed = v,
      format: (double v) => '${v.toStringAsFixed(1)}x',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the widget surface was not drawn');
    }
    // #region hit
    // A point in the middle of the surface's own plane maps back to the
    // middle of its UV space.
    final uv = _surface.uvAt(Vector3(0.0, _height, 0.0));
    // #endregion hit
    if (uv == null ||
        (uv.dx - 0.5).abs() > 0.01 ||
        (uv.dy - 0.5).abs() > 0.01) {
      throw StateError(
        'the plane\'s own centre should map to uv (0.5, 0.5), '
        'got $uv',
      );
    }
    // The widget is drawn to the texture as soon as it is built, so the
    // surface has redrawn by the time the clock has moved on.
    _seconds.value += 1.0;
    if (!_surface.pipeline.isDirty) {
      throw StateError('changing what the widget shows should mark it dirty');
    }
  }
}

/// What appears on the surface: a title, a running clock and a bar that fills
/// every four seconds. An ordinary widget tree, drawn off the visible one.
class _Console extends StatelessWidget {
  const _Console({required this.seconds});

  final ValueListenable<double> seconds;

  static const TextStyle _mono = TextStyle(
    fontFamily: 'RobotoMono',
    color: Color(0xFFFFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: seconds,
      builder: (BuildContext context, double t, Widget? _) {
        final int whole = t.floor();
        final String clock =
            '${(whole ~/ 60).toString().padLeft(2, '0')}:'
            '${(whole % 60).toString().padLeft(2, '0')}.'
            '${((t - whole) * 10).floor()}';
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF14204A), Color(0xFF3355AA)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'FLUTTER WIDGET, ON A MESH',
                  style: _mono.copyWith(
                    fontSize: 30,
                    color: const Color(0xFFB8C7FF),
                  ),
                ),
                const Spacer(),
                Text(clock, style: _mono.copyWith(fontSize: 150)),
                const SizedBox(height: 28),
                Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: ((t % 4.0) / 4.0).clamp(0.02, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB03B),
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
