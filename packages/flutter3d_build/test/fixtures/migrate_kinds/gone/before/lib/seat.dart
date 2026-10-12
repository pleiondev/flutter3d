import 'package:flutter3d_kinds/flutter3d_kinds.dart' hide Seat;
import 'package:flutter3d_kinds/tools.dart';

final Seat seat = Seat();

final class Cart with Wheel {
  @override
  bool get rolling => true;
}
