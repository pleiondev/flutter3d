import 'package:flutter3d_kinds/flutter3d_kinds.dart';
import 'package:flutter3d_kinds_board/flutter3d_kinds_board.dart';

final class Strict extends Judge {
  @override
  void judge(Match match, int score) {
    print('$match $score');
  }
}

void heard(String what, int times) {}

Bell bell() => Bell(onRing: heard);

// The board's `Unit`, which `flutter3d_kinds`'s unit of measurement shadows.
bool ours(Unit unit) => unit.side == 0;

int fire(Tool tool) => tool.run(1, 2);

// 1.0's call already, which the rewrite of the old one leaves alone.
int again(Tool tool) => tool.run(const Shift(1, 2));
