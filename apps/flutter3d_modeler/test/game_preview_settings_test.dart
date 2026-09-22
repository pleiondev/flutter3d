/// `game_preview_settings.dart`'s own arithmetic: which profile targets get
/// a shadow pass, the fixed sky converted to linear, and [GamePreviewSettings
/// .applyTo]'s own merge.
///
///     flutter test test/game_preview_settings_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/game_preview_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The same IEC 61966-2-1 curve `game_preview_settings.dart` applies,
/// worked out independently here — `weight_gradient_test.dart`'s own
/// discipline — so this is not the same formula checked against itself.
double _linearChannel(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

Vector3 _linearOf(int hex) => Vector3(
  _linearChannel(((hex >> 16) & 0xFF) / 255.0),
  _linearChannel(((hex >> 8) & 0xFF) / 255.0),
  _linearChannel((hex & 0xFF) / 255.0),
);

void _expectClose(Vector3 actual, Vector3 expected, {double eps = 1e-6}) {
  expect(actual.x, closeTo(expected.x, eps));
  expect(actual.y, closeTo(expected.y, eps));
  expect(actual.z, closeTo(expected.z, eps));
}

void main() {
  group('GamePreviewSettings.forProfile', () {
    test('the sky is always on, at the hand-over\'s own zenith and nadir, '
        'converted to linear', () {
      final settings = GamePreviewSettings.forProfile(const ProjectProfile());

      expect(settings.sky.enabled, isTrue);
      _expectClose(settings.sky.resolvedZenith, _linearOf(0x243440));
      _expectClose(settings.sky.resolvedNadir, _linearOf(0x0F181D));
    });

    test('tonemap is always on, regardless of target', () {
      for (final target in ProfileTarget.values) {
        final settings = GamePreviewSettings.forProfile(
          ProjectProfile(target: target),
        );
        expect(settings.render.tonemap, isTrue, reason: '$target');
      }
    });

    test('desktop and web both get a shadow pass', () {
      for (final target in <ProfileTarget>[
        ProfileTarget.desktop,
        ProfileTarget.web,
      ]) {
        final settings = GamePreviewSettings.forProfile(
          ProjectProfile(target: target),
        );
        expect(settings.render.shadows.enabled, isTrue, reason: '$target');
      }
    });

    // `ui-28`/`anim-24`'s own worked example: a handset does not draw a
    // shadow pass at all — a device-target question, not the scene's own
    // `SceneLighting.shadows` toggle, which `GamePreviewSettings` never
    // reads.
    test('mobile gets no shadow pass', () {
      final settings = GamePreviewSettings.forProfile(
        const ProjectProfile(target: ProfileTarget.mobile),
      );
      expect(settings.render.shadows.enabled, isFalse);
    });
  });

  group('GamePreviewSettings.applyTo', () {
    test('folds tonemap, shadows and sky onto the base, keeping everything '
        'else the base already had', () {
      final settings = GamePreviewSettings.forProfile(
        const ProjectProfile(target: ProfileTarget.mobile),
      );
      const base = RenderSettings(
        tonemap: false,
        exposure: 2.5,
        shadows: ShadowSettings(enabled: true, resolution: 2048),
      );

      final merged = settings.applyTo(base);

      expect(merged.tonemap, isTrue);
      expect(merged.shadows.enabled, isFalse);
      // The base's own shadow resolution survives the merge — only
      // `enabled` is this screen's own to decide.
      expect(merged.shadows.resolution, 2048);
      expect(merged.exposure, 2.5, reason: 'lighting is not this file\'s own');
      expect(merged.sky.enabled, isTrue);
    });
  });
}
