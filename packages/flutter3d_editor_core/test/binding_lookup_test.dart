/// `edu-05`: which properties an `edu_step` binds to a named data source,
/// read straight off a `Level` document per `doc/edu-00-interactive-format.md`
/// §9 — no `"properties"` wrapper, the mistake that document's own §2 names.
///
///     dart test test/binding_lookup_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  group('bindingsInLevel', () {
    test('reads a target back to its source, path and declaring step', () {
      final level = Level.fromJson(
        jsonDecode('''
{"entities": [
  {"type": "edu_data_source", "name": "lathe-broker", "kind": "sampler"},
  {"type": "edu_step", "name": "step-1", "at": [0,0,0],
   "bindings": [
     {"source": "lathe-broker", "path": "temperature",
      "target": "lathe-body.material.emissiveColor"}
   ]}
]}
''')
            as Map<String, Object?>,
      );

      final bindings = bindingsInLevel(level);

      expect(bindings, hasLength(1));
      final binding = bindings['lathe-body.material.emissiveColor']!;
      expect(binding.stepName, 'step-1');
      expect(binding.source, 'lathe-broker');
      expect(binding.path, 'temperature');
    });

    test('a level with no edu_step entities binds nothing', () {
      final level = Level.fromJson(
        jsonDecode('{"entities": [{"type": "door", "name": "d", "at": [0,0,0]}]}')
            as Map<String, Object?>,
      );
      expect(bindingsInLevel(level), isEmpty);
    });

    test('an edu_step with no bindings field is skipped, not thrown', () {
      final level = Level.fromJson(
        jsonDecode('{"entities": [{"type": "edu_step", "name": "s", "at": [0,0,0]}]}')
            as Map<String, Object?>,
      );
      expect(bindingsInLevel(level), isEmpty);
    });

    test('two steps naming the same target — the later one in the '
        'document wins', () {
      final level = Level.fromJson(
        jsonDecode('''
{"entities": [
  {"type": "edu_step", "name": "step-1", "at": [0,0,0],
   "bindings": [{"source": "a", "path": "x", "target": "e.p"}]},
  {"type": "edu_step", "name": "step-2", "at": [0,0,0],
   "bindings": [{"source": "b", "path": "y", "target": "e.p"}]}
]}
''')
            as Map<String, Object?>,
      );

      final binding = bindingsInLevel(level)['e.p']!;
      expect(binding.stepName, 'step-2');
      expect(binding.source, 'b');
    });
  });
}
