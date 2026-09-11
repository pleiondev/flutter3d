/// A modifier as it sits on an object's own list, and the control it wants.
///
///     dart test test/modifier_slot_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('ModifierSlot', () {
    test('round-trips through JSON, enabled included', () {
      final slot = ModifierSlot(
        modifier: ArrayModifier(count: 3, offset: Vector3(1, 0, 0)),
        enabled: false,
      );
      final restored = ModifierSlot.fromJson(slot.toJson());

      expect(restored, isNotNull);
      expect(restored!.enabled, isFalse);
      expect(restored.modifier, isA<ArrayModifier>());
      expect((restored.modifier as ArrayModifier).count, 3);
    });

    test('enabled defaults true and is not silently flipped', () {
      final slot = ModifierSlot(
        modifier: ArrayModifier(count: 1, offset: Vector3(1, 0, 0)),
      );
      expect(slot.enabled, isTrue);
    });

    test('a modifier this build does not know is null, not a refusal', () {
      expect(
        ModifierSlot.fromJson(<String, Object?>{
          'modifier': <String, Object?>{'kind': 'future'},
          'enabled': true,
        }),
        isNull,
      );
    });

    test('missing the enabled field is null, not a guessed default', () {
      expect(
        ModifierSlot.fromJson(<String, Object?>{
          'modifier': ArrayModifier(
            count: 1,
            offset: Vector3(1, 0, 0),
          ).toJson(),
        }),
        isNull,
      );
    });

    test('copyWith replaces only what it is given', () {
      final slot = ModifierSlot(
        modifier: ArrayModifier(count: 1, offset: Vector3(1, 0, 0)),
      );
      final disabled = slot.copyWith(enabled: false);

      expect(disabled.enabled, isFalse);
      expect(disabled.modifier, same(slot.modifier));
    });
  });

  group('hintsForModifier', () {
    test('ArrayModifier hints its own three fields', () {
      final hints = hintsForModifier(
        ArrayModifier(count: 1, offset: Vector3(1, 0, 0)),
      );
      expect(
        hints.keys,
        unorderedEquals(<String>['count', 'offset', 'mergeDistance']),
      );
      expect(hints['count'], isA<IntHint>());
      expect(hints['offset'], isA<Vector3Hint>());
    });

    test('MirrorModifier hints its own four fields', () {
      final hints = hintsForModifier(MirrorModifier(normal: Vector3(1, 0, 0)));
      expect(
        hints.keys,
        unorderedEquals(<String>[
          'normal',
          'mergeDistance',
          'bisect',
          'flipUv',
        ]),
      );
      expect(hints['bisect'], isA<BoolHint>());
      expect(hints['flipUv'], isA<BoolHint>());
    });
  });
}
