// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// The values, their names in order, the name of one, and `byName`.
typedef _OpenSet = (
  List<Object>,
  List<String>,
  String Function(Object),
  Object? Function(String),
);

void main() {
  final sets = <String, _OpenSet>{
    'AnimationInterpolation': (
      AnimationInterpolation.values,
      <String>['step', 'linear', 'cubicSpline'],
      (v) => (v as AnimationInterpolation).name,
      AnimationInterpolation.byName,
    ),
    'AnimationPath': (
      AnimationPath.values,
      <String>['translation', 'rotation', 'scale', 'weights', 'pointer'],
      (v) => (v as AnimationPath).name,
      AnimationPath.byName,
    ),
    'AnimationPointerProperty': (
      AnimationPointerProperty.values,
      <String>[
        'baseColor',
        'emissiveStrength',
        'roughness',
        'metallic',
        'textureOffset',
        'lightColor',
        'lightIntensity',
      ],
      (v) => (v as AnimationPointerProperty).name,
      AnimationPointerProperty.byName,
    ),
    'AnimationPointerTarget': (
      AnimationPointerTarget.values,
      <String>['material', 'light'],
      (v) => (v as AnimationPointerTarget).name,
      AnimationPointerTarget.byName,
    ),
    'AnimationWrap': (
      AnimationWrap.values,
      <String>['once', 'loop', 'pingPong'],
      (v) => (v as AnimationWrap).name,
      AnimationWrap.byName,
    ),
    'MaterialMap': (
      MaterialMap.values,
      <String>[
        'baseColor',
        'metallicRoughness',
        'normal',
        'occlusion',
        'emissive',
      ],
      (v) => (v as MaterialMap).name,
      MaterialMap.byName,
    ),
    'ModelWriteFormat': (
      ModelWriteFormat.values,
      <String>['glb', 'obj', 'f3d', 'stl', 'stlAscii'],
      (v) => (v as ModelWriteFormat).name,
      ModelWriteFormat.byName,
    ),
    'ObjNormals': (
      ObjNormals.values,
      <String>['smooth', 'flat', 'none'],
      (v) => (v as ObjNormals).name,
      ObjNormals.byName,
    ),
    'ReactiveShape': (
      ReactiveShape.values,
      <String>['disc', 'gaussian', 'sprite'],
      (v) => (v as ReactiveShape).name,
      ReactiveShape.byName,
    ),
    'ResourceOrigin': (
      ResourceOrigin.values,
      <String>['drawn', 'kept'],
      (v) => (v as ResourceOrigin).name,
      ResourceOrigin.byName,
    ),
    'SplatColorSpace': (
      SplatColorSpace.values,
      <String>['srgb', 'linear'],
      (v) => (v as SplatColorSpace).name,
      SplatColorSpace.byName,
    ),
    'SplatComposite': (
      SplatComposite.values,
      <String>['automatic', 'sorted', 'hashed'],
      (v) => (v as SplatComposite).name,
      SplatComposite.byName,
    ),
    'StlNormals': (
      StlNormals.values,
      <String>['fromFile', 'recomputed'],
      (v) => (v as StlNormals).name,
      StlNormals.byName,
    ),
    'SurfaceAlphaMode': (
      SurfaceAlphaMode.values,
      <String>['opaque', 'mask', 'blend'],
      (v) => (v as SurfaceAlphaMode).name,
      SurfaceAlphaMode.byName,
    ),
    'TemporalClip': (
      TemporalClip.values,
      <String>['aabb', 'kdop8', 'kdop16', 'kdop32'],
      (v) => (v as TemporalClip).name,
      TemporalClip.byName,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf, byName))
      in sets.entries) {
    test('$type is an open class that keeps its wire names', () {
      expect(values.map(nameOf), names);
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect(
          value.toString(),
          '$type.${nameOf(value)}',
          reason: 'toString prints what the enum printed',
        );
        expect(byName(nameOf(value)), same(value));
      }
      expect(byName('not-a-$type'), isNull);
    });
  }
}
