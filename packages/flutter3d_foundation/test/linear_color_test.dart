import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('a colour encoded for display', () {
    test('is an SrgbColor, compared by value', () {
      const linear = LinearColor(0.2, 0.5, 1.0, 0.25);
      final SrgbColor shown = linear.toSrgb();
      expect(shown.r, closeTo(LinearColor.linearToSrgb(0.2), 1e-15));
      expect(shown.g, closeTo(LinearColor.linearToSrgb(0.5), 1e-15));
      expect(shown.b, closeTo(1.0, 1e-15));
      expect(shown.a, 0.25);
      expect(shown, linear.toSrgb());
      expect(shown.hashCode, linear.toSrgb().hashCode);
      expect(shown == const SrgbColor(0, 0, 0), isFalse);
    });

    test('decodes back to the light it came from', () {
      const linear = LinearColor(0.2, 0.5, 2.0, 0.75);
      final back = linear.toSrgb().toLinear();
      expect(back.r, closeTo(0.2, 1e-12));
      expect(back.g, closeTo(0.5, 1e-12));
      expect(back.b, closeTo(2.0, 1e-12));
      expect(back.a, 0.75);
    });
  });
}
