import 'package:flutter/widgets.dart';

/// The word on a touch control's face, at the platform's text size up to
/// what the face holds.
///
/// **Grown with the player's text size, never cut.** The control is the size
/// of a thumb whatever the text size is, so a label at twice its size is
/// scaled back down to fit the face rather than wrapped into it and clipped:
/// `throttle` stays `throttle`, as large as the pedal allows. Not exported:
/// the buttons, toggles and slots of this library share it.
final class TouchFace extends StatelessWidget {
  /// A face saying [label] in [color] at [fontSize].
  const TouchFace(
    this.label, {
    super.key,
    required this.color,
    required this.fontSize,
    this.fontWeight,
  });

  /// The word on the face, kept on one line and centred.
  final String label;

  /// The word's colour.
  final Color color;

  /// The label's size at the platform's normal text size, in logical pixels.
  final double fontSize;

  /// The word's weight; null for the ambient text style's.
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    ),
  );
}
