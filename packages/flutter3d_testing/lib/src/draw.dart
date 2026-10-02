import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'render_frame.dart';

/// Draws [subject] once through [renderer] and reads the frame back.
///
/// **Not exported: the two callers are [renderFrame], which builds a device per
/// frame, and `testReplay`, which keeps one for a whole run.** A replay cannot
/// take a fresh device per golden — the level it stepped was uploaded to the
/// first one — so the half that is the same in both lives here rather than
/// twice.
Future<RenderedFrame> drawOnce({
  required GraphicsDevice device,
  required Renderer renderer,
  required FrameSubject subject,
  required int width,
  required int height,
  RenderSettings settings = const RenderSettings(),
  Vector4? clearColor,
}) async {
  final result = renderer.render(
    width: width,
    height: height,
    scene: subject.scene,
    views: <RenderView>[
      RenderView(
        camera: subject.camera,
        clearColor: clearColor ?? Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: settings,
  );

  final pixels = await device.readPixels(result.frame);
  if (pixels == null) {
    throw StateError(
      'the frame could not be read back from the software device, which has '
      'nothing to be busy with and no driver to blame',
    );
  }
  return (
    pixels: pixels.buffer.asUint8List(),
    width: width,
    height: height,
    drawCalls: result.drawCalls,
  );
}
