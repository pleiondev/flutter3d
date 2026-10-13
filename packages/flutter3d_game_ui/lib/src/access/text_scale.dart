import 'package:flutter/widgets.dart';

/// [width] logical pixels, grown as the platform's text size grows text of
/// [fontSize]: the width of a column measured for a label at the size it
/// was written at.
///
/// **A fixed column of text is a column that clips.** A label column wide
/// enough for `RECORD` at thirteen points is not wide enough for it at
/// twenty-six, and the player who asked their phone for larger text is the
/// one who reads `RECO`. So a column measured for its text grows with it,
/// by the same scaler the text takes.
double textScaledWidth(
  BuildContext context,
  double width, {

  /// The size the column was measured at, in logical pixels.
  double fontSize = 14.0,
}) => MediaQuery.textScalerOf(context).scale(fontSize) / fontSize * width;
