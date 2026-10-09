import 'package:flutter3d/flutter3d.dart' show LinearColor;
import 'package:vector_math/vector_math.dart' show Vector4;

/// The modeller's palette, written as the sRGB numbers a design names, handed
/// to the engine's overlays, which take linear colours.
extension OverlayInk on Vector4 {
  /// This colour, sRGB-encoded as the palette writes it, as the linear colour
  /// `MeshOverlay` and `DebugDraw` take; each encodes it back to these
  /// numbers on the way to the screen.
  LinearColor get ink => LinearColor.fromSrgb(x, y, z, w);
}
