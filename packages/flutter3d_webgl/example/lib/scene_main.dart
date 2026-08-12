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

class _SceneAppState extends State<SceneApp> {
  static const int _width = 480;
  static const int _height = 360;

  String _status = 'starting';
  Widget? _frame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _draw());
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
      final white = _require(device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(<int>[255, 255, 255, 255])),
      ), 'white texel');
      final flat = _require(device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(<int>[128, 128, 255, 255])),
      ), 'flat normal texel');
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
      scene.root.add(
        MeshNode(
          mesh,
          Material(
            name: 'ball',
            baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
            lighting: LightingModel.lambert,
          ),
          name: 'ball',
        ),
      );
      final light = LightNode(name: 'key', type: LightType.directional)
        ..intensity = 3.0;
      light.setPosition(2.0, 3.0, 2.0);
      light.lookAt(Vector3.zero());
      scene.root.add(light);

      final camera = CameraNode(name: 'eye');
      camera.setPosition(0.0, 0.0, 4.0);
      camera.lookAt(Vector3.zero());
      scene.root.add(camera);
      say('PASS  scene: ${scene.meshes.length} mesh, ${scene.lights.length} light');

      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      say('PASS  frame: ${result.drawCalls} draws, ${result.pipelines} pipelines');

      setState(() {
        _status = '$log=== A FRAME WAS DRAWN ===';
        _frame = device.present(result.frame, fit: BoxFit.contain);
      });
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
              if (_frame != null)
                SizedBox(width: 480, height: 360, child: _frame),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _status,
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
