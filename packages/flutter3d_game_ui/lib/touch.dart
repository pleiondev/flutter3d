/// Touch controls for a game on a device with no keyboard, on the input layer
/// of `flutter3d_game`: every control writes the same `InputState` a key or a
/// pad button does, so the game cannot tell which it was.
///
/// * [TouchControls] — a stick, a cluster of buttons, a row of switches,
///   numbered slots and a switch in the corner, placed by how often each is
///   wanted;
/// * [TouchDrive] — a steering band and pedals laid out for a vehicle, with
///   one button in the far corner;
///
/// and the pieces they are built from, for a game that lays out its own:
///
/// * [TouchStick] — two analogue axes under a thumb;
/// * [SteeringBand] — one analogue axis under a sliding thumb;
/// * [TouchButton] — an action held down while a finger is on it, round or
///   a pedal ([TouchButton.pedal]), labelled for a screen reader;
/// * [TouchToggle] — a control that is set rather than held;
/// * [TouchSlots] — the numbered slots as buttons, with [TouchSlot];
/// * [TouchAction] — one labelled button, as a layout takes it.
///
/// One widget for each job: the stick-and-row layout and the one with slots
/// and a corner were two widgets until 1.0.0-rc.1, and so were the round
/// button and the pedal.
library;

export 'src/touch/steering_band.dart';
export 'src/touch/touch_action.dart';
export 'src/touch/touch_button.dart';
export 'src/touch/touch_controls.dart';
export 'src/touch/touch_drive.dart';
export 'src/touch/touch_slots.dart';
export 'src/touch/touch_stick.dart';
export 'src/touch/touch_toggle.dart';
