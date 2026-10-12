import 'package:flutter3d_kinds/flutter3d_kinds.dart' hide KindSeat;
import 'package:flutter3d_kinds/tools.dart';

final ToolSeat seat = ToolSeat();

final class Cart with Wheel {
  @override
  bool get isRolling => true;
}
