/// Which backend this build draws through.
///
/// **Through `flutter3d_app`, not by naming a backend**, for the reason the
/// template's own note gives: `openDevice` is a compile-time choice between
/// Impeller and WebGL *and* the run-time fallback to the software rasteriser
/// when flutter_gpu will not start. A modeller that named a backend would be a
/// modeller that does not open in a browser — and the browser is a platform of
/// the first version here rather than a later one.
library;

import 'package:flutter3d_app/flutter3d_app.dart' show platformDevices;
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show DeviceRegistry;

export 'package:flutter3d_app/flutter3d_app.dart'
    show fixedResolution, openDevice;

/// The backends the modeller opens its device from and presents its frames
/// through: this platform's, in a registry the application owns.
///
/// One for the application rather than one for the process, which
/// `flutter3d_app` no longer keeps: a test puts a backend that draws nothing
/// in front of the real ones here, and takes it off again in its tear-down.
final DeviceRegistry modelerDevices = platformDevices();
