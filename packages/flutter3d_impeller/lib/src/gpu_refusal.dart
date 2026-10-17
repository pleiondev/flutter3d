/// The refusal this backend gives for a request it cannot honour.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'gpu_capabilities.dart' show impellerBackendName;

/// What [operation] throws for a request this backend has the feature for
/// and still cannot honour — a value flutter_gpu has no spelling for, one a
/// later version names — since 1.0.0-rc.1+2: the HAL's
/// `DeviceResourceException`, where it was an untyped `UnsupportedError`.
DeviceResourceException impellerRefusal(String operation, String reason) =>
    DeviceResourceException(
      operation: operation,
      backend: impellerBackendName,
      reason: reason,
    );
