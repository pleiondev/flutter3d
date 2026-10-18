/// The `MotionEvent` axis numbers this package reads.
///
/// Named rather than inlined because three of them are the whole difficulty of
/// Android: see `AndroidPadState` on the triggers and the hat.
abstract final class AndroidAxis {
  /// `AXIS_X`: the left stick, horizontal, read as [PadAxis.leftStickX].
  static const int x = 0;

  /// `AXIS_Y`: the left stick, vertical and positive downwards, read as
  /// [PadAxis.leftStickY].
  static const int y = 1;

  /// `AXIS_Z`: the right stick, horizontal, read as [PadAxis.rightStickX].
  static const int z = 11;

  /// `AXIS_RZ`: the right stick, vertical and positive downwards, read as
  /// [PadAxis.rightStickY].
  static const int rz = 14;

  /// `AXIS_HAT_X`: the d-pad as -1, 0 or 1, read as left and right.
  static const int hatX = 15;

  /// `AXIS_HAT_Y`: the d-pad as -1, 0 or 1, read as up and down.
  static const int hatY = 16;

  /// `AXIS_LTRIGGER`: the left trigger from nought to one, preferred over
  /// [brake] when a device reports both.
  static const int leftTrigger = 17;

  /// `AXIS_RTRIGGER`: the right trigger from nought to one, preferred over
  /// [gas] when a device reports both.
  static const int rightTrigger = 18;

  /// `AXIS_GAS`: the right trigger on pads that report it under a wheel's
  /// name, read only when [rightTrigger] is absent.
  static const int gas = 22;

  /// `AXIS_BRAKE`: the left trigger on pads that report it under a wheel's
  /// name, read only when [leftTrigger] is absent.
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
