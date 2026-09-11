/// `InputPolicy`: `ui-19`'s own routing of a pointer to the camera or to the
/// tool, without Flutter.
///
///     dart test test/input_policy_test.dart
library;

import 'package:flutter3d_modeler/src/input_policy.dart';
import 'package:flutter3d_modeler/src/orbit_gestures.dart' show PointerKind;
import 'package:test/test.dart';

void main() {
  const policy = InputPolicy();

  group('classify', () {
    test('touch in sculpt goes to the camera — the row\'s own worked example', () {
      final intent = policy.classify(
        kind: PointerKind.touch,
        tool: ToolCategory.sculpting,
      );
      expect(intent, isA<CameraInput>());
    });

    test('a mouse strokes at full force — the row\'s own worked example', () {
      final intent = policy.classify(
        kind: PointerKind.mouse,
        tool: ToolCategory.sculpting,
      );
      expect(intent, isA<ToolStroke>());
      expect((intent as ToolStroke).force, 1.0);
      expect(intent.erase, isFalse);
    });

    test('a stylus strokes at its own normalised pressure', () {
      final intent = policy.classify(
        kind: PointerKind.stylus,
        tool: ToolCategory.sculpting,
        pressure: 0.4,
      );
      expect(intent, isA<ToolStroke>());
      expect((intent as ToolStroke).force, 0.4);
    });

    test('an inverted stylus strokes as the eraser, not a different tool', () {
      final intent = policy.classify(
        kind: PointerKind.stylus,
        tool: ToolCategory.sculpting,
        pressure: 0.7,
        inverted: true,
      );
      expect(intent, isA<ToolStroke>());
      expect((intent as ToolStroke).erase, isTrue);
      expect(intent.force, 0.7);
    });

    test('a long touch is offered on its own, not folded into the camera', () {
      final intent = policy.classify(
        kind: PointerKind.touch,
        tool: ToolCategory.sculpting,
        longPress: true,
      );
      expect(intent, isA<LongPressInput>());
    });

    test('a trackpad never reaches the tool', () {
      final intent = policy.classify(
        kind: PointerKind.trackpad,
        tool: ToolCategory.sculpting,
      );
      expect(intent, isA<CameraInput>());
    });
  });

  group('InputPolicy.normalizePressure', () {
    test('a pressure of null reads as full force, not none', () {
      expect(InputPolicy.normalizePressure(null), 1.0);
    });

    test('a pressure already inside 0..1 is passed through', () {
      expect(InputPolicy.normalizePressure(0.25), 0.25);
    });

    test('a pressure over 1 is clamped to it', () {
      expect(InputPolicy.normalizePressure(1.8), 1.0);
    });

    test('a negative pressure is clamped to zero', () {
      expect(InputPolicy.normalizePressure(-0.3), 0.0);
    });
  });

  test('the touch tap target is Material\'s own 48dp guideline', () {
    expect(InputPolicy.touchTapTarget, 48.0);
  });
}
