import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final class Ear extends Sensor {
  final List<String> heard = <String>[];

  @override
  void sense(Sensing sensing) {
    final what = sensing.what;
    final loud = sensing.loud;
    if (loud) heard.add(what);
  }
}

final class Nose extends Sensor {
  double total = 0;

  @override
  void sense(Sensing sensing) {
    final amount = sensing.amount;
    total += amount;
  }
}

final class Eye extends Sensor {
  final List<String> seen = <String>[];

  @override
  void sense(Sensing sensing) {}
}

final class Log extends Sensor {
  final List<String> lines = <String>[];

  @override
  void sense(Sensing sensing) {
    final what = sensing.what;
    final amount = sensing.amount;
    lines.add('$what at $amount');
  }
}

void ring(Sensor sensor) {
  sensor.sense(Sensing(what: 'bell', amount: 2, loud: true));
  sensor.sense(Sensing(what: 'hum', amount: 0.5));
}
