/// Renders the shared comparison scene through Impeller and prints its grid.
///
///     flutter run -d macos -t lib/parity_main.dart
///
/// The other half of this is `engine_parity_test.dart` in `flutter3d_webgl`,
/// which renders the same scene through WebGL2 and compares. The scene itself
/// is `buildParityScene` in the engine, written once, which is the only reason
/// a difference in the pictures can be attributed to the backends rather than
/// to two transcriptions of the same intent.
///
/// Prints rather than writes a file, so recording the reference is a copy out of
/// the console into a constant — visible in a diff, unlike a binary.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

void main() => runApp(const ParityApp());

class ParityApp extends StatefulWidget {
  const ParityApp({super.key});

  @override
  State<ParityApp> createState() => _ParityAppState();
}

class _ParityAppState extends State<ParityApp> {
  String _report = 'rendering…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final device = GpuRenderBackend.create();
      final white = device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: _texel(255, 255, 255),
      )!;
      final flat = device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: _texel(128, 128, 255),
      )!;
      final renderer = Renderer.create(
        device: device,
        fallbackAlbedo: white,
        fallbackNormal: flat,
      );

      final built = buildParityScene(device);
      final result = renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: kParitySettings,
      );

      final pixels = await device.readPixels(result.frame);
      if (pixels == null) {
        setState(() => _report = 'the frame could not be read back');
        return;
      }
      final grid = parityGrid(
        pixels.buffer.asUint8List(),
        kParityWidth,
        kParityHeight,
      );

      final buffer = StringBuffer('PARITY GRID (paste into the WebGL test)\n');
      for (var row = 0; row < kParityGrid; row++) {
        final slice = grid.sublist(row * kParityGrid, (row + 1) * kParityGrid);
        buffer.writeln('  ${slice.join(', ')},');
      }
      // ignore: avoid_print
      print(buffer);
      setState(() => _report = buffer.toString());
    } catch (error, stack) {
      // ignore: avoid_print
      print('$error\n$stack');
      setState(() => _report = '$error');
    }
  }

  static ByteData _texel(int r, int g, int b) =>
      ByteData.sublistView(Uint8List.fromList(<int>[r, g, b, 255]));

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF111111),
          body: SingleChildScrollView(
            child: Text(
              _report,
              style: const TextStyle(
                color: Color(0xFFDDDDDD),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
}
