/// The one graphics device of the app.
///
/// **Opened once and lent to every page.** A browser hands a page a small,
/// fixed number of GL contexts, and a page that opened its own device would use
/// one up on every visit; the software fallback would draw at a size of its own
/// each time. The holder opens the device the first time somebody asks and
/// keeps the answer, and a test hands it a device of its own.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

/// Opens the app's device on first use and lends the same one to every page
/// after.
final class DeviceHolder {
  /// A holder that opens a 1280 by 720 device through `openDevice`, or calls
  /// [open] instead, for a test that brings its own device.
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
  /// A scope lending [holder] to everything under [child].
  const DeviceScope({super.key, required this.holder, required super.child});

  /// The holder every page under this scope borrows its device from.
  final DeviceHolder holder;

  /// The holder of the nearest [DeviceScope] above [context]. Asserts there is
  /// one; the app puts it above every page.
  static DeviceHolder of(BuildContext context) {
    final DeviceScope? scope = context
        .getInheritedWidgetOfExactType<DeviceScope>();
    assert(scope != null, 'no DeviceScope above this widget');
    return scope!.holder;
  }

  @override
  bool updateShouldNotify(DeviceScope oldWidget) => holder != oldWidget.holder;
}
