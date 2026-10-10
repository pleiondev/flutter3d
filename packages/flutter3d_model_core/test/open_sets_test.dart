// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
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
    'AuditCheck': (
      AuditCheck.values,
      <String>['units', 'pivot', 'readiness', 'materials', 'mesh'],
      (v) => (v as AuditCheck).name,
      AuditCheck.byName,
    ),
    'ExportFormat': (
      ExportFormat.values,
      <String>['f3d', 'obj', 'glb', 'stl', 'stlAscii', 'usdz'],
      (v) => (v as ExportFormat).name,
      ExportFormat.byName,
    ),
    'ExportSeverity': (
      ExportSeverity.values,
      <String>['warning', 'error'],
      (v) => (v as ExportSeverity).name,
      ExportSeverity.byName,
    ),
    'OriginPlacement': (
      OriginPlacement.values,
      <String>['boundsCenter', 'boundsBottom', 'worldOrigin'],
      (v) => (v as OriginPlacement).name,
      OriginPlacement.byName,
    ),
    'ProfileTarget': (
      ProfileTarget.values,
      <String>['desktop', 'mobile', 'web'],
      (v) => (v as ProfileTarget).name,
      ProfileTarget.byName,
    ),
    'ResizeFilter': (
      ResizeFilter.values,
      <String>['box', 'bilinear'],
      (v) => (v as ResizeFilter).name,
      ResizeFilter.byName,
    ),
    'SelectionMode': (
      SelectionMode.values,
      <String>['object', 'mesh'],
      (v) => (v as SelectionMode).name,
      SelectionMode.byName,
    ),
    'StepAuthor': (
      StepAuthor.values,
      <String>['person', 'agent'],
      (v) => (v as StepAuthor).name,
      StepAuthor.byName,
    ),
    'TextureBlendMode': (
      TextureBlendMode.values,
      <String>['normal', 'multiply', 'add', 'screen'],
      (v) => (v as TextureBlendMode).name,
      TextureBlendMode.byName,
    ),
    'TextureEncoding': (
      TextureEncoding.values,
      <String>['png', 'ktx2'],
      (v) => (v as TextureEncoding).name,
      TextureEncoding.byName,
    ),
    'TextureFileFormat': (
      TextureFileFormat.values,
      <String>['rgba8', 'bc1', 'bc3', 'bc7', 'etc2Rgba8', 'astc4x4', 'other'],
      (v) => (v as TextureFileFormat).name,
      TextureFileFormat.byName,
    ),
    'TextureValueType': (
      TextureValueType.values,
      <String>['color', 'scalar'],
      (v) => (v as TextureValueType).name,
      TextureValueType.byName,
    ),
    'TransformPivot': (
      TransformPivot.values,
      <String>['median', 'individual'],
      (v) => (v as TransformPivot).name,
      TransformPivot.byName,
    ),
    'TransformSpace': (
      TransformSpace.values,
      <String>['global', 'local'],
      (v) => (v as TransformSpace).name,
      TransformSpace.byName,
    ),
    'UpAxis': (
      UpAxis.values,
      <String>['y', 'z'],
      (v) => (v as UpAxis).name,
      UpAxis.byName,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf, byName))
      in sets.entries) {
    test('$type is an open class that keeps its wire names', () {
      expect(values.map(nameOf), names);
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect('$value', '$type.${nameOf(value)}');
        expect(byName(nameOf(value)), same(value));
      }
      expect(byName('not-a-$type'), isNull);
    });
  }
}
