/// The twenty-eight checks, against a backend with no GPU underneath it.
///
/// This is the only backend that can run them in a plain `flutter test`: the
/// other two need a device, so Impeller runs them from an application and
/// WebGL from a browser. Which makes this suite worth more than its own
/// correctness — it is the first place a change to `flutter3d_conformance`
/// itself gets checked in under a second.
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

void main() {
  runDeviceConformance(
    backend: 'cpu',
    makeDevice: ({required int width, required int height}) => CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    ),
    // Nothing compiled to pack: this backend answers a bundle's names with
    // the Dart stages it already has, which is what the check then holds it
    // to.
    ownShaders: () async => null,
  );
}
