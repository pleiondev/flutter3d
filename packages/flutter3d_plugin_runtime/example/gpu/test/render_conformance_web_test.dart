/// The sample plugin's render checks on the two browser backends.
///
///     flutter test --platform chrome test/render_conformance_web_test.dart
///
/// After `dart run tool/build_bundle.dart`, which compiles the plugin's lit
/// model into the bundle each backend loads: GLSL ES 3.00 for WebGL2, WGSL
/// with its reflection for WebGPU. The WebGPU half needs a browser that
/// hands out an adapter, which headless Chrome on a CI runner does not.
///
/// **The bundle is fetched, not loaded from the asset bundle.** The browser
/// test server serves `test/` and no application assets, and
/// `rootBundle.load` waits for an answer that never comes; the tool writes a
/// copy beside this file for that reason.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';
import 'package:flutter3d_plugin_runtime_example_gpu/plugin_render_harness.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// The bundle, fetched once for every device.
final Future<ByteData> _bundle = () async {
  final response = await web.window
      .fetch('/acme_sample.f3dshaders'.toJS)
      .toDart;
  if (!response.ok) {
    throw StateError(
      'no test/acme_sample.f3dshaders (${response.status}): run '
      'dart run tool/build_bundle.dart first',
    );
  }
  return ByteData.view((await response.arrayBuffer().toDart).toDart);
}();

Future<ShaderLibrary> _stages(GraphicsDevice device) async =>
    acmeSampleStages(device, await _bundle);

void main() {
  group('WebGL2', () {
    runPluginRenderConformance(
      AcmeSamplePlugin.new,
      backend: 'webgl',
      points: acmeSamplePoints,
      device: () => WebGlDevice.open(width: 32, height: 32),
      materials: _stages,
    );
  });

  group('WebGPU', () {
    runPluginRenderConformance(
      AcmeSamplePlugin.new,
      backend: 'webgpu',
      points: acmeSamplePoints,
      device: () => WebGpuDevice.open(width: 32, height: 32),
      materials: _stages,
    );
  });
}
