/// `ColorField`: a swatch, a hex box, HSV, `Alpha` only at four channels,
/// `linear` moving all of them together — moved here verbatim from
/// `apps/flutter3d_modeler`, `ui-27`'s own P0.
///
///     flutter test test/color_field_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  required List<double> value,
  required int channels,
  bool linear = false,
  ValueChanged<List<double>>? onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ColorField(
        value: value,
        channels: channels,
        linear: linear,
        onChanged: onChanged ?? (List<double> _) {},
      ),
    ),
  ),
);

void main() {
  group('the sRGB transfer function', () {
    test('mid-grey encodes and decodes at the standard threshold', () {
      // The acceptance's own number: a linear value that reads 0.214 to
      // three places is 128/255 decoded back through the same formula, and
      // re-encoding it lands on exactly 127.5 — which rounds up, not down.
      // Mutation: swap the encode branch's `1.055 * pow(c, 1/2.4) - 0.055`
      // for a bare `pow`, or drop the 12.92 linear segment below the
      // threshold. Both move this off 128 by enough that the hex test below
      // catches it too, but this is where the number itself is pinned.
      const double linear = 0.21404114048223255;
      expect(linear, closeTo(0.214, 5e-4));
      final double encoded = ColorField.encodeSrgb(linear);
      expect(encoded * 255, closeTo(127.5, 1e-6));
    });

    test('encode and decode are inverses away from the threshold', () {
      for (final double c in <double>[0.0, 0.02, 0.214, 0.5, 0.831, 1.0]) {
        expect(
          ColorField.decodeSrgb(ColorField.encodeSrgb(c)),
          closeTo(c, 1e-6),
          reason: '$c',
        );
      }
    });
  });

  group('hex', () {
    test('a linear grey of roughly 0.214 shows as #808080', () {
      // The row's own acceptance, stated as a widget-level fact rather than
      // just the transfer function above: three linear components feeding
      // the field print as the sRGB approximation, not the raw linear
      // number reinterpreted as a byte (which would print as #363636).
      const double linear = 0.21404114048223255;
      final String hex = ColorField.hexOf(<double>[
        ColorField.encodeSrgb(linear),
        ColorField.encodeSrgb(linear),
        ColorField.encodeSrgb(linear),
      ]);
      expect(hex, '#808080');
    });

    test('hexOf and parseHex round-trip a colour', () {
      const List<double> srgb = <double>[0.373, 0.831, 0.894];
      final String hex = ColorField.hexOf(srgb);
      final List<double>? parsed = ColorField.parseHex(hex);
      expect(parsed, isNotNull);
      for (var i = 0; i < 3; i++) {
        // A byte is a 256th of the range: the round trip cannot promise
        // more than that back.
        expect(parsed![i], closeTo(srgb[i], 1 / 255));
      }
    });

    test('parseHex accepts no leading # and rejects the wrong length', () {
      expect(ColorField.parseHex('5FD4E4'), isNotNull);
      expect(ColorField.parseHex('#5FD4E4'), isNotNull);
      expect(ColorField.parseHex('#5FD4'), isNull);
      expect(ColorField.parseHex('not a colour'), isNull);
    });
  });

  group('HSV', () {
    test('round-trips an ordinary colour', () {
      const double r = 0.373, g = 0.831, b = 0.894;
      final hsv = ColorField.rgbToHsv(r, g, b);
      final (double gotR, double gotG, double gotB) = ColorField.hsvToRgb(
        hsv.hue,
        hsv.saturation,
        hsv.value,
      );
      expect(gotR, closeTo(r, 1e-9));
      expect(gotG, closeTo(g, 1e-9));
      expect(gotB, closeTo(b, 1e-9));
    });

    test('grey has zero saturation', () {
      final hsv = ColorField.rgbToHsv(0.5, 0.5, 0.5);
      expect(hsv.saturation, 0);
      expect(hsv.value, closeTo(0.5, 1e-9));
    });
  });

  group('channels == 4', () {
    testWidgets('shows an alpha slider', (WidgetTester tester) async {
      await show(tester, value: <double>[1, 0, 0, 0.5], channels: 4);

      // Swatch's hex field plus four sliders (H, S, V, A).
      expect(find.byType(Slider), findsNWidgets(4));
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('dragging the alpha slider reports the new alpha alone', (
      WidgetTester tester,
    ) async {
      List<double>? reported;
      await show(
        tester,
        value: <double>[1, 0, 0, 1.0],
        channels: 4,
        onChanged: (List<double> next) => reported = next,
      );

      final alphaSlider = find.byType(Slider).at(3);
      await tester.drag(alphaSlider, const Offset(-80, 0));

      expect(reported, isNotNull);
      expect(reported![0], closeTo(1, 1e-6));
      expect(reported![1], closeTo(0, 1e-6));
      expect(reported![2], closeTo(0, 1e-6));
      expect(reported![3], lessThan(1.0));
    });
  });

  group('channels == 3', () {
    testWidgets('has no alpha control anywhere in the tree', (
      WidgetTester tester,
    ) async {
      await show(tester, value: <double>[0.373, 0.831, 0.894], channels: 3);

      // Not a disabled fourth slider — no fourth slider at all, and no 'A'
      // label sitting beside one.
      expect(find.byType(Slider), findsNWidgets(3));
      expect(find.text('A'), findsNothing);
    });
  });

  group('linear', () {
    testWidgets('a linear value shows its sRGB approximation in hex', (
      WidgetTester tester,
    ) async {
      const double linear = 0.21404114048223255;
      await show(
        tester,
        value: <double>[linear, linear, linear],
        channels: 3,
        linear: true,
      );

      expect(find.text('#808080'), findsOneWidget);
    });

    testWidgets('editing the hex field reports a linear value back', (
      WidgetTester tester,
    ) async {
      List<double>? reported;
      await show(
        tester,
        value: <double>[0, 0, 0],
        channels: 3,
        linear: true,
        onChanged: (List<double> next) => reported = next,
      );

      await tester.enterText(find.byType(TextField), '#808080');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      // The document gets the linear number back, not the sRGB byte reread
      // as a fraction (0.50196…) — mutation: skip the decode on the way out
      // and this fails at 0.502 against roughly 0.216.
      for (final double c in reported!) {
        expect(c, closeTo(0.21586050011389926, 1e-6));
      }
    });

    testWidgets('a non-linear value of the same numbers shows a darker hex', (
      WidgetTester tester,
    ) async {
      // The same triple, read as already-encoded sRGB instead: hex is a
      // plain 0..1-to-byte mapping with no transfer function in between.
      const double value = 0.21404114048223255;
      await show(tester, value: <double>[value, value, value], channels: 3);

      expect(find.text('#373737'), findsOneWidget);
    });
  });
}
