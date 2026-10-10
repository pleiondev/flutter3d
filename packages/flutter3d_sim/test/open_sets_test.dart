// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
    'ActionKind': (
      ActionKind.values,
      <String>['button', 'axis', 'dualAxis'],
      (v) => (v as ActionKind).name,
      ActionKind.byName,
    ),
    'BehaviorStatus': (
      BehaviorStatus.values,
      <String>['success', 'failure', 'running'],
      (v) => (v as BehaviorStatus).name,
      BehaviorStatus.byName,
    ),
    'LevelIssueSeverity': (
      LevelIssueSeverity.values,
      <String>['error', 'warning'],
      (v) => (v as LevelIssueSeverity).name,
      LevelIssueSeverity.byName,
    ),
    'SaveResolution': (
      SaveResolution.values,
      <String>['inSync', 'keepLocal', 'takeRemote', 'ask'],
      (v) => (v as SaveResolution).name,
      SaveResolution.byName,
    ),
    'ShadowCasting': (
      ShadowCasting.values,
      <String>['on', 'off', 'doubleSided', 'shadowsOnly'],
      (v) => (v as ShadowCasting).name,
      ShadowCasting.byName,
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
