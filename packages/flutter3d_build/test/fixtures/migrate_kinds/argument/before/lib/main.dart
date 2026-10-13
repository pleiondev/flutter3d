// dart format off
// What the migration writes, compared byte for byte: not reformatted.
import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final Vector4 warm = Vector4(1.0, 0.8, 0.6, 1.0);

Lamp porch() => Lamp(glow: Vector4(0.9, 0.42, 0.28, 1.0), beamDegrees: 45.0);

Lamp hall(double degrees) =>
    Lamp(glow: warm, beamDegrees: degrees + 15.0)..glow = warm;

Lamp cellar() => Lamp.tinted(Vector3(0.1, 0.2, 0.3));

void dim(Lamp lamp) {
  lamp.glow = warm * 0.5;
  print(lamp.glow.x);
}

Lamp relit(Lamp? old) => Lamp(glow: old?.glow ?? Vector4(0.5, 0.5, 0.5, 1.0));

Lamp mended() => Lamp.tinted(LinearColor(0.1, 0.2, 0.3).toVector3());

void shine(Vector3 colour) {}

void glowing(Lamp lamp) => shine(lamp.glow);

Vector3 seen(Lamp lamp) {
  final Vector3 c = lamp.glow;
  return c;
}
