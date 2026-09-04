import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:vector_math/vector_math.dart';

/// What a test hands back: the scene to draw and the camera to draw it from.
typedef FrameSubject = ({Scene scene, CameraNode camera});

/// A drawn frame and the size it was drawn at.
///
/// **The size travels with the pixels**, because RGBA bytes do not carry it and
/// recording a reference image needs it. A caller that had to remember its own
/// width would be one refactor away from recording a golden at the wrong shape,
/// which compares as a rendering failure.
typedef RenderedFrame = ({Uint8List pixels, int width, int height});

/// Builds the subject, given the device its meshes have to be uploaded to.
typedef FrameBuilder = FrameSubject Function(FrameRequest request);

/// What a [FrameBuilder] is told about the frame it is building.
///
/// One object rather than a bare device, so that telling a builder the size it
/// is drawing at, or which backend it is on, does not break every builder
/// anybody has written. See `AssetRequest` in the engine for the same shape and
/// the same reason.
final class FrameRequest {
  const FrameRequest(this.device);

  /// Where meshes and textures have to be uploaded.
  final GraphicsDevice device;
}

/// One frame, drawn with no GPU, as RGBA bytes.
///
/// [build] is handed a software device and returns the scene and camera. It is a
/// callback rather than two arguments because meshes and textures have to be
/// uploaded to *this* device: a scene built earlier against another one holds
/// handles this renderer cannot draw.
///
/// [settings] defaults to the engine's own, which is what a game runs with.
/// Turning tone mapping off is the usual reason to pass one — a test comparing a
/// material's colour against a number wants what the shader wrote, not what a
/// curve made of it.
///
/// The pixels are RGBA, four per byte group, row zero at the top. That last is worth
/// stating because it is the one convention a backend can get wrong invisibly:
/// a mirrored frame compares as a rendering failure rather than as a flip.
Future<RenderedFrame> renderFrame({
  required int width,
  required int height,
  required FrameBuilder build,
  RenderSettings settings = const RenderSettings(),
  Vector4? clearColor,
}) async {
  final kit = cpuTestDevice(width: width, height: height);
  final subject = build(FrameRequest(kit.device));

  // The renderer is built here rather than by the caller, and by the caller in
  // `cpuTestDevice`'s own documentation, because the reason that helper stops
  // short does not apply to this package: it may depend on the engine, and a
  // test that had to spell three fallback textures would be back where it
  // started.
  final renderer = Renderer.create(
    device: kit.device,
    fallbackAlbedo: kit.albedo,
    fallbackNormal: kit.normal,
  );

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

  final pixels = await kit.device.readPixels(result.frame);
  if (pixels == null) {
    throw StateError(
      'the frame could not be read back from the software device, which has '
      'nothing to be busy with and no driver to blame',
    );
  }
  return (pixels: pixels.buffer.asUint8List(), width: width, height: height);
}
