import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final class Ear extends Sensor {
  final List<String> heard = <String>[];

  @override
  void sense(String what, double amount, {bool loud = false}) {
    if (loud) heard.add(what);
  }
}

final class Nose extends Sensor {
  double total = 0;

  @override
  void sense(String what, double amount, {bool loud = false}) =>
      total += amount;
}

final class Eye extends Sensor {
  @override
  void sense(String what, double amount, {bool loud = false}) {}
}

void ring(Sensor sensor) {
  sensor.sense('bell', 2, loud: true);
  sensor.sense('hum', 0.5);
}
