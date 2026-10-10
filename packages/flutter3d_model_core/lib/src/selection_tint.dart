/// The orange a selected object is drawn in, kept out of the barrel: it is
/// how `renderProject` draws a selection, not something a caller asks for.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;

/// [base] blended 60% of the way to the selection orange, alpha kept.
///
/// The blend is made on the sRGB values, the way a person picks a mix of two
/// swatches and the way it was made when `baseColor` was an sRGB `Vector4`,
/// so a selected object looks as it always did. [base] is linear, so it is
/// encoded first and the mix decoded back.
LinearColor selectionTint(LinearColor base) {
  final srgb = base.toSrgb();
  return LinearColor.fromSrgb(
    srgb.r * 0.4 + 1.0 * 0.6,
    srgb.g * 0.4 + 0.55 * 0.6,
    srgb.b * 0.4 + 0.0 * 0.6,
    base.a,
  );
}
