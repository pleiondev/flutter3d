/// What the GPU harnesses share: the sample plugin's points in the frame,
/// and its stages as a device loads them from the bundle.
library;

import 'dart:typed_data';

import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';

/// Where `tool/build_bundle.dart` writes the plugin's stages.
const String acmeSampleBundleAsset = 'assets/acme_sample.f3dshaders';

/// The points the sample plugin adds to the frame, as the software
/// rasteriser's suite names them.
final PluginRenderPoints acmeSamplePoints = PluginRenderPoints(
  nodes: const <String>['acme_sample.smear', 'acme_sample.glow streak'],
  litModel: hairModel,
  lightType: tubeLight,
  decal: decalStage,
  velocityReader: 'acme_sample.smear',
  shadows: const SoftSun(),
);

/// The plugin's stages on [device]: its lit model from [bundle], which
/// `tool/build_bundle.dart` compiled for this backend, and its decal stage,
/// which has the engine's decal interface and so is the device's own `Decal`
/// under the plugin's name, as on the software rasteriser.
Future<ShaderLibrary> acmeSampleStages(
  GraphicsDevice device,
  ByteData bundle,
) async => _PluginStages(await device.loadShaders(bundle), device.shaders);

final class _PluginStages with ShaderLibrary {
  _PluginStages(this.loaded, this.engine);

  final ShaderLibrary loaded;
  final ShaderLibrary engine;

  @override
  ShaderHandle? operator [](String name) =>
      name == decalStage.shaderName ? engine['Decal'] : loaded[name];
}
