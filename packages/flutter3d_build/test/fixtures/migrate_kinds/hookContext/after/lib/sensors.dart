import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final class Ear extends Sensor {
  final List<String> heard = <String>[];

  @override
  void sense(Sensing context) {
    final what = context.what;
    final loud = context.loud;
    if (loud) heard.add(what);
  }
}

final class Nose extends Sensor {
  double total = 0;

  @override
  void sense(Sensing context) {
    final amount = context.amount;
    total += amount;
  }
}

final class Eye extends Sensor {
  @override
  void sense(Sensing context) {}
}

void ring(Sensor sensor) {
  sensor.sense(Sensing(what: 'bell', amount: 2, loud: true));
  sensor.sense(Sensing(what: 'hum', amount: 0.5));
}
