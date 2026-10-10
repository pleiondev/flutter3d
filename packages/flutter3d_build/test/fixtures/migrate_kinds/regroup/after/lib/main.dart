import 'package:flutter3d_kinds/flutter3d_kinds.dart';

const View3d wide = View3d(view: ViewOptions(fov: 90), title: 'wide');

View3d close() => View3d(
  title: 'close',
  view: ViewOptions(fov: 30, near: 0.01),
);

View3d plain() => const View3d(title: 'plain');

// TODO(flutter3d-1.0): `fov`, `near` of `View3d` moved into `view: ViewOptions(…)` in 1.0.0-rc.1. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-View3d-view
View3d already() => View3d(view: ViewOptions(fov: 1), near: 2);
