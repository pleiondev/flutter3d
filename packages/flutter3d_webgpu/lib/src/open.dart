import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../engine_shaders.dart';
import 'webgpu_device.dart';

/// Opens this backend with the engine's own shaders, or throws with something
/// worth putting on screen.
///
/// **The same shape `openWebGl` has, and for the same reason it was written:**
/// what a browser has to provide is this package's knowledge, not a game's, and
/// three applications that each spelled the requirement out were three copies
/// of one sentence that would still name a limitation on the day it stopped
/// being one.
///
/// What stays with the caller is the size, because the size is a budget: every
/// pixel here is copied into a canvas the browser then scales, so one demo
/// renders at 720p and another — heavier, and honest about it — at 960×540.
/// That is a decision about a particular game, and this package has no way to
/// make it.
///
/// **Asynchronous, which the other three backends are not.**
/// `navigator.gpu.requestAdapter()` and `adapter.requestDevice()` are both
/// promises, so a WebGPU device cannot be built by a constructor. Nothing in
/// `flutter3d_hardware` says how a device is made — the contract starts once
/// one exists — so the `await` is the whole of what this costs anybody.
///
/// Throws a [StateError] rather than returning null, exactly as the WebGL2
/// opener does: a browser without WebGPU is not a case a game can carry on
/// from, and the sentence saying so belongs here rather than in each of them.
/// The two failures it covers are a browser with no `navigator.gpu` at all and
/// one that has it and hands back no adapter — a machine whose GPU is
/// blocklisted, which is the common case on an old driver and looks identical
/// from Dart.
Future<GraphicsDevice> openWebGpu({
  required int width,
  required int height,
}) async {
  final device = await WebGpuDevice.create(
    width: width,
    height: height,
    // WGSL translated from `flutter3d_shaders` by `tool/generate_shaders.dart`,
    // beside the reflection a `GPUShaderModule` cannot be asked for. There is
    // no compiled bundle on this backend either: a browser compiles WGSL
    // itself, so a "bundle" is a table of stages and what a pipeline needs to
    // know about each.
    stages: engineShaders,
  );
  if (device == null) {
    throw StateError(
      'WebGPU is not available in this browser. The engine needs '
      'navigator.gpu and an adapter it will hand out — a browser without '
      'WebGPU, and a machine whose GPU the browser has blocklisted, fail '
      'here the same way.',
    );
  }
  return device;
}
