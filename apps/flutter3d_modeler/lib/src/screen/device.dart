/// `_ModelerScreenState`'s own device-swap half of `ui-20`.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: [_reopenDeviceIfStale] reaches `_device`,
/// `mounted`, `_state` and `_cubit` directly, and a `part` is what lets it
/// keep doing that as an `extension` method rather than turning every one
/// of those into a parameter or a public setter. See
/// `renderer_scene_pass.dart` in `flutter3d_core` for the same split, over a
/// much larger class.
part of 'modeler_screen.dart';

extension _DeviceHandling on _ModelerScreenState {
  /// Swaps in a device sized for [width]/[height]/[devicePixelRatio] when the
  /// current one no longer fits — a viewport grown past a fixed-resolution
  /// canvas, or a display moved to a different pixel ratio. See
  /// `deviceStaleForViewport` and `ModelerCubit.redeviced` (`ui-20`).
  Future<void> _reopenDeviceIfStale(
    int width,
    int height,
    double devicePixelRatio,
  ) async {
    if (_reopeningDevice) return;
    if (!kFixedResolution) return;
    final now = _state;
    if (now is! ModelerReady) return;
    if (!deviceStaleForViewport(
      lastWidth: _deviceWidth,
      lastHeight: _deviceHeight,
      lastDevicePixelRatio: _deviceDevicePixelRatio,
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
    )) {
      return;
    }
    _reopeningDevice = true;
    try {
      final newDevice = await openDevice(width: width, height: height);
      if (!mounted) {
        return;
      }
      final opened = await openProject(now.history.project, device: newDevice);
      if (!mounted) {
        return;
      }
      _device = newDevice;
      _deviceWidth = width;
      _deviceHeight = height;
      _deviceDevicePixelRatio = devicePixelRatio;
      _cubit.redeviced(
        renderer: Renderer.create(device: newDevice),
        stage: opened.stage,
      );
    } finally {
      _reopeningDevice = false;
    }
  }
}
