/// What a test of a game built on this package reaches that the game does
/// not: the opener of the device a game's `Model3dComponent`s share.
///
/// **Not for a game.** The main library has no global to change; a test that
/// needs a software device under its components says so here, and puts the
/// opener back when it is done.
library;

import 'package:flutter3d/flutter3d.dart' show GraphicsDevice;

import 'src/embed/shared_device.dart';

/// Opens the device each game's `Model3dComponent`s share with [open]
/// rather than `flutter3d_app`'s `openDevice`, until the function returned
/// is called, which puts back the opener there was before.
void Function() overrideSharedDeviceOpener(
  Future<GraphicsDevice> Function({required int width, required int height})
  open,
) {
  final before = sharedDeviceOpener;
  sharedDeviceOpener = open;
  return () => sharedDeviceOpener = before;
}
