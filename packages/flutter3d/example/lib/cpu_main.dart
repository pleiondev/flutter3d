/// The engine running live on the software backend.
///
///     flutter run -d macos -t lib/cpu_main.dart
///
/// No GPU anywhere in the picture: every triangle is rasterised in Dart, every
/// fragment shaded by a Dart class, and the finished pixels handed to Flutter
/// as an image. This is the entry point that shows what
/// `test/engine_parity_test.dart` can only assert about — and, more usefully,
/// what the numbers cannot say at all: how fast it is, and whether it looks
/// right while it moves.
///
/// Two scenes, switched with the space bar.
///
/// `buildParityScene` is the fixture the comparison grid checks, so what is on
/// screen in that mode is exactly what the tests assert about — a demo with its
/// own scene would be a third transcription of one intent, which is the thing
/// that fixture exists to avoid.
///
/// The other is a torus, a cone and a box, and it exists because the fixture
/// cannot ask the question it asks. Two spheres are convex: every pixel of them
/// is a single surface, so a depth buffer that did nothing at all would draw
/// them correctly. A torus occludes itself — the near side of the tube covers
/// the far side of the same mesh — and the box has flat faces that meet at
/// hard edges, which is where a normal that is being interpolated when it
/// should not be shows up immediately.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'cpu_shapes_scene.dart';

/// Small on purpose. A software rasteriser costs pixels linearly, and the point
/// of this entry point is to watch it move rather than to fill a display —
/// `BoxFit.contain` scales it up to whatever the window is.
/// Overridable so a release run can be asked what a real window costs:
///
///     flutter run --release -d macos -t lib/cpu_main.dart \
///       --dart-define=cpuWidth=960 --dart-define=cpuHeight=720
const int _width = int.fromEnvironment('cpuWidth', defaultValue: 320);
const int _height = int.fromEnvironment('cpuHeight', defaultValue: 240);

void main() => runApp(const CpuApp());

class CpuApp extends StatefulWidget {
  const CpuApp({super.key});

  @override
  State<CpuApp> createState() => _CpuAppState();
}

class _CpuAppState extends State<CpuApp> with SingleTickerProviderStateMixin {
  late final CpuDevice _device;
  late final Renderer _renderer;
  late final Ticker _ticker;
  late Scene _scene;
  late CameraNode _camera;

  /// False for the two spheres the grid checks, true for the shapes that can
  /// fail in ways two spheres cannot.
  bool _shapes = false;

  final FocusNode _focus = FocusNode();

  Widget? _frame;
  double _angle = 0.0;

  /// Milliseconds for the last frame, smoothed. Reported because it is the one
  /// number that separates this backend from the other two by orders of
  /// magnitude, and nothing on screen would otherwise say so.
  double _smoothed = 0.0;
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    _renderer = Renderer.create(
      device: _device,
      fallbackAlbedo: _texel(255, 255, 255),
      fallbackNormal: _texel(128, 128, 255),
    );
    _load();
    _ticker = createTicker(_tick)..start();
  }

  void _load() {
    final built = _shapes
        ? buildShapesScene(_device)
        : buildParityScene(_device, which: ParityScene.plain);
    _scene = built.scene;
    _camera = built.camera;
  }

  void _tick(Duration elapsed) {
    // The camera orbits rather than the spheres rotating: a sphere turning on
    // its axis is invisible, which is a thing this project has already
    // discovered by watching one and seeing nothing.
    _angle = elapsed.inMilliseconds / 3000.0;
    const radius = 4.2;
    _camera
      ..setPosition(radius * math.sin(_angle), 0.4, radius * math.cos(_angle))
      ..lookAt(Vector3(0.0, _shapes ? 0.0 : 0.2, 0.0));

    final started = DateTime.now();
    final result = _renderer.render(
      width: _width,
      height: _height,
      scene: _scene,
      views: <RenderView>[RenderView(camera: _camera)],
      settings: paritySettingsFor(ParityScene.plain),
    );
    final ms = DateTime.now().difference(started).inMicroseconds / 1000.0;

    setState(() {
      _frame = _device.present(result.frame, fit: BoxFit.contain);
      _smoothed = _frames == 0 ? ms : _smoothed * 0.9 + ms * 0.1;
      _frames++;
    });
    // Printed as well as shown, so a release run can be measured from a log
    // rather than from a photograph of a screen.
    if (_frames % 60 == 0) {
      // ignore: avoid_print
      print('cpu ${_width}x$_height: ${_smoothed.toStringAsFixed(1)} ms/frame '
          '(${(1000 / _smoothed).round()} fps), '
          '${_shapes ? 'shapes' : 'parity'}');
    }
  }

  TextureHandle _texel(int r, int g, int b) => _device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(<int>[r, g, b, 255])),
      )!;

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (KeyEvent event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.space) {
              setState(() {
                _shapes = !_shapes;
                _load();
              });
            }
          },
          child: Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: Stack(
            children: <Widget>[
              Center(child: _frame ?? const Text('rendering…')),
              Positioned(
                left: 16,
                top: 16,
                child: Text(
                  'flutter3d_cpu — no GPU  ·  space to switch\n'
                  '${_shapes ? 'torus, cone, box' : 'the parity fixture'}\n'
                  '$_width x $_height\n'
                  '${_smoothed.toStringAsFixed(1)} ms/frame '
                  '(${_smoothed <= 0 ? 0 : (1000 / _smoothed).round()} fps)',
                  style: const TextStyle(
                    color: Color(0xFFBBBBBB),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      );
}
