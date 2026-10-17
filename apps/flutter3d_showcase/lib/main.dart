/// Every capability of the engine on a page of its own.
///
///     flutter run -d macos
///     flutter run -d chrome
///
/// The pages are in `lib/pages/`, one file and one guide each, and the list they
/// are shown from is in `lib/catalog/`. See `README.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics;
import 'package:flutter3d_showcase/src/shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The physics every page runs on, chosen once: the core, which the
  // browser fetches as WebAssembly, or the reference where it will not
  // start.
  await preparePhysics();
  runApp(const ShowcaseApp());
}
