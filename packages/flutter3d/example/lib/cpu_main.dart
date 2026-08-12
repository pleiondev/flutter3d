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
/// The scene is `buildParityScene`, the same fixture the comparison uses, so
/// what is on screen here is exactly what the grid is checking. A demo with its
/// own scene would be a third transcription of the same intent, which is the
/// thing that fixture exists to avoid.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

/// Small on purpose. A software rasteriser costs pixels linearly, and the point
/// of this entry point is to watch it move rather than to fill a display —
/// `BoxFit.contain` scales it up to whatever the window is.
const int _width = 320;
const int _height = 240;

void main() => runApp(const CpuApp());

class CpuApp extends StatefulWidget {
  const CpuApp({super.key});

  @override
  State<CpuApp> createState() => _CpuAppState();
}

class _CpuAppState extends State<CpuApp> with SingleTickerProviderStateMixin {
  late final CpuDevice _device;
  late final Renderer _renderer;
  late final Scene _scene;
  late final CameraNode _camera;
  late final Ticker _ticker;

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
    final built = buildParityScene(_device, which: ParityScene.plain);
    _scene = built.scene;
    _camera = built.camera;

    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    // The camera orbits rather than the spheres rotating: a sphere turning on
    // its axis is invisible, which is a thing this project has already
    // discovered by watching one and seeing nothing.
    _angle = elapsed.inMilliseconds / 3000.0;
    const radius = 4.2;
    _camera
      ..setPosition(radius * math.sin(_angle), 0.4, radius * math.cos(_angle))
      ..lookAt(Vector3(0.0, 0.2, 0.0));

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: Stack(
            children: <Widget>[
              Center(child: _frame ?? const Text('rendering…')),
              Positioned(
                left: 16,
                top: 16,
                child: Text(
                  'flutter3d_cpu — no GPU\n'
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
      );
}
