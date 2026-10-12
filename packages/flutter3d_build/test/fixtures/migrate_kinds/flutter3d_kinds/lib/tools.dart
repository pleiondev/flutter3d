/// 0.8: `Wrench` came with `flutter3d_kinds.dart`; it is here since.
library;

final class Wrench {
  const Wrench();
}

/// 0.8 had two `Seat`s; this one is `ToolSeat` since.
final class ToolSeat {
  ToolSeat();
}

/// 0.8: `bool get rolling`; `isRolling` since.
abstract base mixin class Wheel {
  bool get isRolling;
}
