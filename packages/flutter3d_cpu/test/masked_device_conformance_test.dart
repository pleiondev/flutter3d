/// The capability honesty check through a feature mask over the software
/// rasteriser: each feature it has, taken away, is refused by its own name
/// and nothing else moves.
///
/// What a `MaskedDevice` promises is what a backend promises, so the
/// conformance suite's own check is the test of it. Run on the CPU because
/// it has the most features of any backend and needs no GPU: every one it
/// reports is masked in turn, which is the fallback branch of each, run on
/// this machine.
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart'
    show ConformanceDeclinedException, capabilityChecks;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show MaskedDevice;
import 'package:test/test.dart';

CpuDevice _cpu() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// What a feature cannot be taken away without, on this device: the
/// probes of the features beside it reach it through another call. A
/// storage buffer is `compute`'s or a render stage's, so taking compute
/// away leaves the buffer to `renderStageStorage` unless that goes too;
/// and every buffer is made by `buffers`, so the features whose probe
/// makes one go with it.
const Map<DeviceFeature, List<DeviceFeature>> _carries =
    <DeviceFeature, List<DeviceFeature>>{
      DeviceFeature.compute: <DeviceFeature>[DeviceFeature.renderStageStorage],
      DeviceFeature.buffers: <DeviceFeature>[
        DeviceFeature.compute,
        DeviceFeature.renderStageStorage,
        DeviceFeature.indirectDispatch,
      ],
    };

Future<void> _honest(GraphicsDevice device) async {
  final check = capabilityChecks.single;
  try {
    await check.run(device);
  } on ConformanceDeclinedException catch (declined) {
    fail('the honesty check declined: ${declined.reason}');
  }
}

void main() {
  test('the mask over nothing is as honest as the device', () async {
    // Mutation: a mask that forwards a gated call wrongly, or reports a
    // limit it should not, fails here before any feature is masked.
    final device = MaskedDevice(
      _cpu(),
      disabledFeatures: const <DeviceFeature>[],
    );
    await _honest(device);
    device.dispose();
  });

  for (final feature in _cpu().features.all) {
    test('without ${feature.name}, the report is still honest', () async {
      // Mutation: drop any one gate from MaskedDevice, and the feature it
      // guards is "not reported, and its call succeeded anyway".
      final device = MaskedDevice(
        _cpu(),
        disabledFeatures: <DeviceFeature>[feature, ...?_carries[feature]],
      );
      expect(device.features.has(feature), isFalse);
      await _honest(device);
      device.dispose();
    });
  }
}
