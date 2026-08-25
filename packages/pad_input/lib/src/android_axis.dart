/// The `MotionEvent` axis numbers this package reads.
///
/// Named rather than inlined because three of them are the whole difficulty of
/// Android: see `AndroidPadState` on the triggers and the hat.
abstract final class AndroidAxis {
  static const int x = 0;
  static const int y = 1;
  static const int z = 11;
  static const int rz = 14;
  static const int hatX = 15;
  static const int hatY = 16;
  static const int leftTrigger = 17;
  static const int rightTrigger = 18;
  static const int gas = 22;
  static const int brake = 23;

  /// Everything worth asking a device for, so the native side sends one list
  /// and never has to be edited again when a mapping changes.
  static const List<int> all = <int>[
    x,
    y,
    z,
    rz,
    hatX,
    hatY,
    leftTrigger,
    rightTrigger,
    gas,
    brake,
  ];
}
