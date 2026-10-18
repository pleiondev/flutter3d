/// Settings and rectangles compare by value.
///
///     dart test test/engine/settings_equality_test.dart
///
/// A widget that takes these compares the old with the new in
/// `didUpdateWidget`; before they had `==`, two equal settings built on two
/// frames compared unequal and the frame was redone for nothing. Each test
/// names the mutation that would defeat it.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

void main() {
  test('two settings built the same way are equal and hash alike', () {
    // Mutation: drop `==` from `RenderSettings` and the first expectation
    // compares identity, which two constructions never share.
    final a = RenderSettings(exposure: 1.5, stepsOff: <RenderStep>{});
    final b = RenderSettings(exposure: 1.5, stepsOff: <RenderStep>{});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a field that differs makes them unequal', () {
    // Mutation: leave `exposure` out of `RenderSettings.==` and the copy
    // reads as the same settings; the structure rule `a settings class
    // compares every field it holds` names the field too.
    const base = RenderSettings();
    expect(base.copyWith(exposure: 2.0), isNot(base));
    expect(
      base.copyWith(bloom: const BloomSettings(enabled: false)),
      isNot(base),
    );
  });

  test('collections compare by their elements', () {
    // Mutation: compare `stepsOff` with `==` and two equal sets built apart
    // are different settings.
    final a = RenderSettings(stepsOff: <RenderStep>{RenderStep.bloom});
    final b = RenderSettings(stepsOff: <RenderStep>{RenderStep.bloom});
    expect(a, b);
    expect(
      RenderSettings(stepsOff: <RenderStep>{RenderStep.bloom}),
      isNot(const RenderSettings()),
    );
  });

  test('a viewport rectangle is a value', () {
    // Mutation: drop `==` from `ViewportRect` and the two rectangles differ.
    expect(const ViewportRect(0, 0, 0.5, 1), const ViewportRect(0, 0, 0.5, 1));
    expect(
      const ViewportRect(0, 0, 0.5, 1),
      isNot(const ViewportRect(0.5, 0, 0.5, 1)),
    );
  });

  test('an open set finds a value by name and answers null for a stranger', () {
    // Mutation: drop a constant from `TonemapCurve.values` and `byName` no
    // longer finds it; read a later version's name and it must be null.
    for (final curve in TonemapCurve.values) {
      expect(TonemapCurve.byName(curve.name), same(curve));
    }
    expect(TonemapCurve.byName('a curve from a later version'), isNull);
  });
}
