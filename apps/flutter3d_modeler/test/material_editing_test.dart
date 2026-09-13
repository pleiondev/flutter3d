/// The material panel's own pure decisions, pulled out of `main.dart` so a
/// plain `test()` can ask them without a `WidgetTester` — the same split
/// `properties_sections_test.dart` already draws.
///
///     flutter test test/material_editing_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/material_editing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject _object({List<int> materialSlots = const <int>[]}) => ModelObject(
  id: 1,
  name: 'thing',
  // A socket has no shape of its own to build — the cheapest `Geometry` a
  // test can construct, and `activeMaterialSlot` never looks at it anyway.
  geometry: const SocketGeometry(),
  transform: Matrix4.identity(),
  materialSlots: materialSlots,
);

void main() {
  group('activeMaterialSlot', () {
    test('an unpainted object has none', () {
      expect(activeMaterialSlot(_object()), isNull);
    });

    test('a painted object answers its first slot', () {
      expect(activeMaterialSlot(_object(materialSlots: <int>[2])), 2);
    });
  });

  group('metallicIsMeaningful', () {
    test("Lambert has no metallic parameter — the panel's own row", () {
      // mat-04's own acceptance: with a Lambert material, the metallic
      // slider is inactive.
      expect(metallicIsMeaningful(LightingModel.lambert), isFalse);
    });

    test('PBR is the one built-in shader that reads it', () {
      expect(metallicIsMeaningful(LightingModel.pbr), isTrue);
    });

    test('unlit has nothing to blend either', () {
      expect(metallicIsMeaningful(LightingModel.unlit), isFalse);
    });
  });

  group('lightingModelOf', () {
    test('an unlit surface shows unlit\'s own controls', () {
      expect(
        lightingModelOf(SurfaceMaterial(unlit: true)),
        LightingModel.unlit,
      );
    });

    test('every other surface shows PBR, matching what actually renders', () {
      // `bindSurfaceMaterial`'s own default: nothing in this project's
      // format names a shader yet, so this is what a material really draws
      // with today.
      expect(lightingModelOf(SurfaceMaterial()), LightingModel.pbr);
    });
  });

  group('indexOfImageBytes', () {
    test('finds a row holding the same bytes', () {
      final images = <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3])),
        EncodedImage(bytes: Uint8List.fromList(<int>[4, 5, 6])),
      ];
      expect(indexOfImageBytes(images, <int>[4, 5, 6]), 1);
    });

    test('answers null when nothing matches', () {
      final images = <EncodedImage>[
        EncodedImage(bytes: Uint8List.fromList(<int>[1])),
      ];
      expect(indexOfImageBytes(images, <int>[9]), isNull);
    });

    test('an empty table matches nothing', () {
      expect(indexOfImageBytes(const <EncodedImage>[], <int>[1]), isNull);
    });
  });
}
