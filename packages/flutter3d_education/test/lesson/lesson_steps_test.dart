import 'dart:convert';

import 'package:flutter3d_education/lesson.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _level(String json) =>
    Level.fromJson(jsonDecode(json) as Map<String, Object?>);

void main() {
  group('orderedSteps', () {
    test('resolves names in the order the sequence names them', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-2", "caption": "second", "at": [0,0,0]},
  {"type": "edu_step", "name": "step-1", "caption": "first", "at": [0,0,0]},
  {"type": "edu_sequence", "name": "seq", "steps": ["step-1", "step-2"]}
]}
''');
      final steps = orderedSteps(level, 'seq');
      expect(steps.map((s) => s.name), <String>['step-1', 'step-2']);
      expect(steps.map((s) => s.string('caption')), <String>[
        'first',
        'second',
      ]);
    });

    test('skips a name the sequence lists but no entity carries', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-1", "at": [0,0,0]},
  {"type": "edu_sequence", "name": "seq", "steps": ["step-1", "step-missing"]}
]}
''');
      expect(orderedSteps(level, 'seq').map((s) => s.name), <String>['step-1']);
    });

    test('an unknown sequence name, or an entity that is no sequence, '
        'resolves to no steps', () {
      final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "step-1", "at": [0,0,0]}
]}
''');
      expect(orderedSteps(level, 'nope'), isEmpty);
      expect(orderedSteps(level, 'step-1'), isEmpty);
    });
  });

  test('firstLessonSteps plays the first sequence, and none without one', () {
    final level = _level('''
{"entities": [
  {"type": "edu_step", "name": "a", "at": [0,0,0]},
  {"type": "edu_step", "name": "b", "at": [0,0,0]},
  {"type": "edu_sequence", "name": "first", "steps": ["b", "a"]},
  {"type": "edu_sequence", "name": "second", "steps": ["a"]}
]}
''');
    expect(firstLessonSteps(level).map((s) => s.name), <String>['b', 'a']);
    expect(firstLessonSteps(_level('{"entities": []}')), isEmpty);
  });
}
