/// Every pass the renderer opens carries the name of the graph node that
/// opened it — `H2`.
///
///     flutter test test/pass_label_test.dart
///
/// The label is what a GPU debugger shows and what
/// `GraphicsDevice.onGpuTimings` reports a pass by. A pass without one is a
/// row nobody can place, and a pass labelled with a name the frame result does
/// not know is a timing that cannot be joined to its CPU half.
library;

import 'package:flutter3d/flutter3d.dart';
// The parity fixtures are the engine's own test scene, not its API.
// ignore: implementation_imports
import 'package:flutter3d_core/src/engine/render/parity_scene.dart';
import 'package:flutter3d_hardware/testing.dart';
// The generated uniform tables are shared by the engine and its backends,
// released together, and are nobody else's API since 1.0.
// ignore: implementation_imports
import 'package:flutter3d_shaders/internal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final which in ParityScene.values) {
    test('the ${which.name} fixture labels every pass by its node', () {
      // Mutation: drop `label: _passLabel` from `drawFullscreen`. Every
      // post-processing pass comes back unlabelled.
      final device = FakeBackend(stageBindings: stageBindings);
      final renderer = Renderer.create(device: device);
      final built = buildParityScene(device, which: which);
      final frame = renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );

      final nodes = <String>{for (final pass in frame.passes) pass.name};
      final labels = <String?>[
        for (final pass in device.passes) pass.descriptor.label,
      ];
      expect(labels, isNotEmpty);
      expect(labels, everyElement(isNotNull), reason: '$labels');
      expect(
        labels.toSet().difference(nodes),
        isEmpty,
        reason: 'labels the frame result does not name as a pass',
      );
    });
  }

  test('a device answers the reserved half of the contract with its '
      'fallbacks', () {
    // 0.8.0 declares what the cycle will build and builds none of it. The
    // answer every device gives is the one that makes a caller take its
    // fallback, and a creator that is asked anyway says so by name.
    final device = FakeBackend();
    expect(device.features.has(DeviceFeature.gpuTimestamps), isFalse);
    expect(device.features.has(DeviceFeature.compute), isFalse);
    expect(
      device.features.has(DeviceFeature.float32Filterable) &&
          device.features.has(DeviceFeature.float32Renderable),
      isFalse,
    );
    expect(device.features.has(DeviceFeature.independentBlend), isFalse);
    expect(device.hdrOutputFormats, isEmpty);
    expect(device.beginComputePass, throwsA(isA<UnsupportedCapability>()));
  });
}
