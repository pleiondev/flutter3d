import 'package:flutter3d/flutter3d.dart';

import 'render_frame.dart';

/// Draws [subject] once through [renderer] on [device] and reads the frame
/// back.
///
/// **The layer under [renderFrame] and `testReplay`, for a test that holds
/// its own device.** [renderFrame] opens a device per frame and `testReplay`
/// one for a whole run; a test that draws many frames on one device it
/// opened itself — a GPU backend's golden suite, an outside backend's frame
/// test — builds a [Renderer] on it once and calls this per frame. The
/// device and the renderer stay the caller's: nothing here disposes either.
///
/// [subject]'s meshes and textures must have been uploaded to [device], and
/// [renderer] made on it. The pixels are RGBA, row zero at the top, as
/// [renderFrame]'s are.
Future<RenderedFrame> drawOnce({
  required GraphicsDevice device,
  required Renderer renderer,
  required FrameSubject subject,
  required int width,
  required int height,
  RenderSettings settings = const RenderSettings(),
  LinearColor? clearColor,
}) async {
  final result = renderer.render(
    width: width,
    height: height,
    scene: subject.scene,
    views: <RenderView>[
      RenderView(
        camera: subject.camera,
        clearColor: clearColor ?? LinearColor.black,
      ),
    ],
    settings: settings,
  );

  final pixels = await device.readback(result.frame);
  return RenderedFrame(
    pixels: pixels.buffer.asUint8List(),
    width: width,
    height: height,
    drawCalls: result.drawCalls,
  );
}
