import 'package:flutter3d_kinds/flutter3d_kinds.dart';

const View3d wide = View3d(fov: 90, title: 'wide');

View3d close() => View3d(
  title: 'close',
  fov: 30,
  near: 0.01,
);

View3d plain() => const View3d(title: 'plain');

View3d already() => View3d(view: ViewOptions(fov: 1), near: 2);
