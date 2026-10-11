/// The null backend, held to what `flutter3d_hardware` requires.
///
///     dart test test/conformance_test.dart
///
/// **Every check but the shader tier.** This device draws nothing, so the
/// checks that read back a drawn picture are a backend's next step, not
/// this one's: everything else (clears, uploads, readback, copies, the
/// capability report held true both ways, and every refusal) passes or
/// declines saying why.
library;

import 'package:flutter3d_backend_null/flutter3d_backend_null.dart';
import 'package:flutter3d_conformance/flutter3d_conformance.dart';

void main() => runDeviceConformance(
  backend: NullDevice.name,
  makeDevice: NullDevice.open,
  checks: conformanceChecks.where((c) => !shaderChecks.contains(c)).toList(),
);
