import 'package:flutter3d_kinds/flutter3d_kinds.dart';
import 'dart:math' show pi;

final Vector4 warm = Vector4(1.0, 0.8, 0.6, 1.0);

Lamp porch() => Lamp(glow: LinearColor.fromSrgb(0.9, 0.42, 0.28, 1.0), beam: 45.0 * pi / 180);

Lamp hall(double degrees) =>
    Lamp(glow: LinearColor.fromSrgb(warm.x, warm.y, warm.z, warm.w), beam: (degrees + 15.0) * pi / 180)..glow = LinearColor.fromSrgb(warm.x, warm.y, warm.z, warm.w);

Lamp cellar() => Lamp.tinted(LinearColor(0.1, 0.2, 0.3));

void dim(Lamp lamp) {
  // TODO(flutter3d-1.0): `glow` is a `LinearColor` assigned whole: `Vector4(r, g, b, a)` is `LinearColor.fromSrgb(r, g, b, a)`, and `.x` is `.r`. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Lamp-glow
  lamp.glow = warm * 0.5;
  print(lamp.glow.r);
}

Lamp relit(Lamp? old) => Lamp(glow: old?.glow ?? LinearColor.fromSrgb(0.5, 0.5, 0.5, 1.0));

Lamp mended() => Lamp.tinted(LinearColor(0.1, 0.2, 0.3));

void shine(Vector3 colour) {}

void glowing(Lamp lamp) => shine(lamp.glow.toVector3());

Vector3 seen(Lamp lamp) {
  final Vector3 c = lamp.glow.toVector3();
  return c;
}
