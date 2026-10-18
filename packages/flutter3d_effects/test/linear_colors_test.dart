import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUpAll(buildBundles);

  test("a blackbody's colour is a LinearColor, its brightest channel one", () {
    final LinearColor ember = Blackbody.color(1500.0);
    expect(ember.r, closeTo(1.0, 1e-12));
    expect(ember.g, lessThan(ember.r));
    expect(ember.a, 1.0);
    // Hotter is whiter.
    expect(Blackbody.color(6500.0).b, greaterThan(ember.b));
  });

  test('something under the sea is given its colour in linear light', () {
    final look = SeabedLook.of(
      ByteData.sublistView(File('assets/seabed.f3dshaders').readAsBytesSync()),
    );
    const coral = LinearColor(0.8, 0.3, 0.2);
    expect(look.under('coral', coral).baseColor, coral);
  });
}
