import 'package:flutter/services.dart';

/// `rp-04`'s Dart half of file association: `AppDelegate.swift` calls this
/// channel's `openRun` method with a path the moment macOS hands the app a
/// `.f3drun` — a double-click in Finder, a drop on the dock icon, or a
/// launch-by-file at cold start (buffered on the Swift side until this
/// channel exists, then flushed).
///
/// A method channel rather than a platform view or a plugin package: one
/// method, one direction, and the whole surface fits in the file that
/// declares it — the same reasoning `flutter3d_hardware`'s own channels give
/// for staying plain `MethodChannel` rather than reaching for a generated
/// plugin nobody here would otherwise need.
final class OpenRunChannel {
  OpenRunChannel({required this.onPath})
    : _channel = const MethodChannel(_name) {
    _channel.setMethodCallHandler(_handle);
  }

  static const String _name = 'dev.pleion.flutter3d_editor/openRun';

  final void Function(String path) onPath;
  final MethodChannel _channel;

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'openRun') return;
    final path = call.arguments;
    if (path is String) onPath(path);
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
