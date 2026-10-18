/// What `GpuRenderBackend` reports on `GraphicsDevice.lost`.
///
/// **Only the device's own `dispose`, because that is all there is to see.**
/// flutter_gpu has no signal for a context that goes — no callback when the
/// Metal or Vulkan device is reset, no error a submit can be asked for — so
/// the one loss this backend can report is the one it causes. Reported as
/// `DeviceLossReason.destroyed`, the way every backend reports it, so that a
/// caller listening on whatever it opened learns of a teardown here as it
/// would on the web. When flutter_gpu grows a loss signal, it goes in here.
///
/// Its own file so that `flutter test` can hold it: the device needs Impeller
/// to open, and the state it delegates to does not.
library;

import 'dart:async';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The loss state of one `GpuRenderBackend`.
final class GpuDeviceLoss {
  /// The changes of [isLost], as `GraphicsDevice.lost` promises them.
  Stream<DeviceLoss> get lost => _lost.stream;

  /// Whether [dispose] has run.
  bool get isLost => _isLost;
  bool _isLost = false;

  final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast();

  /// Marks the device lost and sends one `DeviceLossReason.destroyed`, then
  /// closes [lost]. A second call is a teardown run twice and says nothing.
  void dispose() {
    if (_isLost) return;
    _isLost = true;
    _lost
      ..add(
        const DeviceLoss(
          reason: DeviceLossReason.destroyed,
          message: 'the Impeller device was disposed',
        ),
      )
      ..close();
  }
}
