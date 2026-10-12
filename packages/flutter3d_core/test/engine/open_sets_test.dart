// Sets that will grow are open classes with constants, not enums: a value
// added in a minor release must not break an exhaustive `switch` outside.
// Each keeps a stable wire name, which is what a file or a tool writes, so a
// rename of a constant never changes a file.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
import 'package:test/test.dart';

void main() {
  final sets = <String, (List<Object>, List<String>, String Function(Object))>{
    'LightType': (
      LightType.values,
      <String>['directional', 'point', 'spot', 'area'],
      (v) => (v as LightType).name,
    ),
    'ShadowCastingMode': (
      ShadowCastingMode.values,
      <String>['on', 'off', 'doubleSided', 'shadowsOnly'],
      (v) => (v as ShadowCastingMode).name,
    ),
    'MaterialAlphaMode': (
      MaterialAlphaMode.values,
      <String>['opaque', 'mask', 'blend', 'hashed'],
      (v) => (v as MaterialAlphaMode).name,
    ),
    'AnimationBlend': (
      AnimationBlend.values,
      <String>['override', 'additive'],
      (v) => (v as AnimationBlend).name,
    ),
    'DiffuseModel': (
      DiffuseModel.values,
      <String>['lambert', 'eon'],
      (v) => (v as DiffuseModel).name,
    ),
    'SortMode': (
      SortMode.values,
      <String>[
        'stateThenDepth',
        'backToFront',
        'frontToBack',
        'manual',
        'none',
      ],
      (v) => (v as SortMode).name,
    ),
    'TangentMethod': (
      TangentMethod.values,
      <String>['mikkTSpace', 'lengyel'],
      (v) => (v as TangentMethod).name,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf))
      in sets.entries) {
    test('$type is an open class with its wire names', () {
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect('$value', '$type.${nameOf(value)}');
      }
      expect(values.map(nameOf), names);
    });
  }
}
