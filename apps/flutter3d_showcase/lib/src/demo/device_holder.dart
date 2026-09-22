/// The one graphics device of the app.
///
/// **Opened once and lent to every page.** A browser hands a page a small,
/// fixed number of GL contexts, and a page that opened its own device would use
/// one up on every visit; the software fallback would draw at a size of its own
/// each time. The holder opens the device the first time somebody asks and
/// keeps the answer, and a test hands it a device of its own.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';

final class DeviceHolder {
  DeviceHolder({Future<GraphicsDevice> Function()? open})
    : _open = open ?? (() => openDevice(width: 1280, height: 720));

  final Future<GraphicsDevice> Function() _open;
  Future<GraphicsDevice>? _device;

  /// Through `openDevice` rather than by naming a backend: Impeller or WebGL
  /// for the build, and the software rasteriser at run time when flutter_gpu
  /// will not start.
  Future<GraphicsDevice> get device => _device ??= _open();
}

/// Makes the [DeviceHolder] reachable from any page.
final class DeviceScope extends InheritedWidget {
  const DeviceScope({super.key, required this.holder, required super.child});

  final DeviceHolder holder;

  static DeviceHolder of(BuildContext context) {
    final DeviceScope? scope = context
        .getInheritedWidgetOfExactType<DeviceScope>();
    assert(scope != null, 'no DeviceScope above this widget');
    return scope!.holder;
  }

  @override
  bool updateShouldNotify(DeviceScope oldWidget) => holder != oldWidget.holder;
}
