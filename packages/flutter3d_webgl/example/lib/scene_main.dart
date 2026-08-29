/// The engine's own renderer, drawing through the WebGL2 backend.
///
/// Everything above the device is the ordinary `flutter3d` frame: a `Scene`, a
/// `CameraNode`, a `RenderView`, `Renderer.render`. The only line that knows
/// which backend is underneath is the one that builds the device.
///
/// This is the claim the split was made for, so it is worth stating precisely
/// what would count as failing it: not a compile error, which would be caught
/// by the analyser, but a frame that comes back the clear colour, or a shape
/// with the wrong winding, or shading that differs from the Impeller build.
/// Those are what a second backend gets wrong, and only running it shows them.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

void main() => runApp(const SceneApp());

class SceneApp extends StatefulWidget {
  const SceneApp({super.key});

  @override
  State<SceneApp> createState() => _SceneAppState();
}

class _SceneAppState extends State<SceneApp>
    with SingleTickerProviderStateMixin {
  static const int _width = 480;
  static const int _height = 360;

  String _status = 'starting';
  String _diagnostic = '';
  Widget? _frame;

  // Kept between frames: building the scene once and redrawing is what a real
  // application does, and it is also the experiment. The first attempt blitted
  // once, during the build that returned the view — before the platform view
  // had put the canvas in the document. Attaching or resizing a canvas resets
  // its drawing buffer, so the one frame drawn was the one frame thrown away.
  WebGlDevice? _device;
  Renderer? _renderer;
  Scene? _scene;
  CameraNode? _camera;
  Ticker? _ticker;
  double _spin = 0.0;
  MeshNode? _ball;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _draw());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    // The renderer before the device, because the renderer releases its
    // targets *through* the device; then the device deletes everything it
    // still tracks and loses the GL context. Skipping this leaked every
    // texture, buffer and shader for the life of the tab — the platform-view
    // registry pins the canvas regardless, but the GPU side is ours to free.
    _renderer?.dispose();
    _device?.dispose();
    super.dispose();
  }

  /// Redraws and re-presents. Called every tick, so the canvas holds a frame
  /// drawn after it was attached rather than before.
  void _tick(Duration elapsed) {
    final device = _device;
    final renderer = _renderer;
    final scene = _scene;
    final camera = _camera;
    if (device == null || renderer == null || scene == null || camera == null) {
      return;
    }
    _spin += 0.02;
    _ball?.setRotationYawPitchRoll(_spin, 0.0, 0.0);
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
    );
    final view = device.present(result.frame, fit: BoxFit.contain);
    final state = device.debugCanvasState();
    setState(() {
      _frame = view;
      _diagnostic = state;
    });
  }

  void _draw() {
    final log = StringBuffer();
    void say(String line) {
      log.writeln(line);
      // ignore: avoid_print
      print(line);
    }

    try {
      final device = WebGlDevice.create(
        width: _width,
        height: _height,
        sources: engineShaders,
      );
      if (device == null) {
        setState(() => _status = 'FAIL  no WebGL2 context');
        return;
      }
      say('PASS  device');

      // One opaque white texel each. The renderer binds these wherever a
      // material leaves a slot empty, and a sampler bound to nothing is a
      // crash on either backend.
      final white = _require(
        device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(
            Uint8List.fromList(<int>[255, 255, 255, 255]),
          ),
        ),
        'white texel',
      );
      final flat = _require(
        device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(
            Uint8List.fromList(<int>[128, 128, 255, 255]),
          ),
        ),
        'flat normal texel',
      );
      say('PASS  fallback textures');

      final renderer = Renderer.create(
        device: device,
        fallbackAlbedo: white,
        fallbackNormal: flat,
      );
      say('PASS  renderer, ${engineShaders.names.length} shaders resolved');

      final scene = Scene();
      final mesh = DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 32, rings: 16).build(),
      );
      final ball = MeshNode(
        mesh,
        Material(
          name: 'ball',
          baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
          lighting: LightingModel.lambert,
        ),
        name: 'ball',
      );
      scene.root.add(ball);
      _ball = ball;
      final light = LightNode(name: 'key', type: LightType.directional)
        ..intensity = 3.0;
      light.setPosition(2.0, 3.0, 2.0);
      light.lookAt(Vector3.zero());
      scene.root.add(light);

      final camera = CameraNode(name: 'eye');
      camera.setPosition(0.0, 0.0, 4.0);
      camera.lookAt(Vector3.zero());
      scene.root.add(camera);
      say(
        'PASS  scene: ${scene.meshes.length} mesh, ${scene.lights.length} light',
      );

      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      say(
        'PASS  frame: ${result.drawCalls} draws, ${result.pipelines} pipelines',
      );

      _device = device;
      _renderer = renderer;
      _scene = scene;
      _camera = camera;
      setState(() {
        _status = '$log=== A FRAME WAS DRAWN ===';
        _frame = device.present(result.frame, fit: BoxFit.contain);
      });
      // From here the canvas is in the document, so every later frame is drawn
      // into a buffer that survives to be composited.
      _ticker = createTicker(_tick)..start();
      // ignore: avoid_print
      print('=== A FRAME WAS DRAWN ===');
    } catch (error, stack) {
      say('FAIL  $error');
      // ignore: avoid_print
      print(stack);
      setState(() => _status = log.toString());
    }
  }

  /// A texture the frame cannot do without, or a message naming which.
  static TextureHandle _require(TextureHandle? texture, String what) =>
      texture ?? (throw StateError('the device would not make the $what'));

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Column(
        children: <Widget>[
          if (_frame != null) SizedBox(width: 480, height: 360, child: _frame),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                '$_status\n$_diagnostic',
                style: const TextStyle(
                  color: Color(0xFFDDDDDD),
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
