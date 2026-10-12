import 'package:flutter3d_kinds/flutter3d_kinds.dart';
import 'package:flutter3d_kinds/roster.dart';

const Object shade = Shade();

final List<Object> both = <Object>[const Shade(), KindShade()];

Table rows() => Board.table()..rows.add(2);

final LinearColor sky = srgbColor(0.2, 0.4, 0.8);
final LinearColor dusk = srgbColor(0.9, 0.5, 0.3, 0.5);

bool jumped(List<Object> events) => events.has<int>();

bool touching(Mode mode) => Mode.touch || mode.touch;

int later() {
  final total = 1 +
      oldHelperGone();
  return total + Roster.size;
}
