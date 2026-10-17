/// What the playground makes of the text in its editor, held still: the two
/// samples read and draw, and text that does not read says where.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_playground/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sample level reads, its prefabs expanded', () {
    final reading = readDocument(sampleLevel);
    expect(reading.problems, isEmpty);
    final level = reading.level!;
    expect(level.brushes, hasLength(4));
    // Three entities, and two lamp posts of two entities each.
    expect(level.entities, hasLength(7));
    expect(level.entities.where((e) => e.type == 'prefab'), isEmpty);
  });

  test('a prefab on its own is drawn as one instance at the origin', () {
    final reading = readDocument(samplePrefab);
    expect(reading.problems, isEmpty);
    expect(reading.level!.entities.map((e) => e.type), <String>[
      'post',
      'arm',
      'arm',
      'lamp',
    ]);
  });

  test('text that is not JSON says the line and the column', () {
    final broken = sampleLevel.replaceFirst('"courtyard",', '"courtyard"');
    final reading = readDocument(broken);
    expect(reading.level, isNull);
    final problem = reading.problems.single;
    expect(problem.isError, isTrue);
    // The missing comma is noticed where the next key starts.
    expect(problem.line, 5);
    expect('$problem', startsWith('line 5, column 3:'));
  });

  test('JSON that is not a level says what is wrong with it', () {
    final reading = readDocument('{"format": "f3d.level", "version": 99}');
    expect(reading.level, isNull);
    expect(reading.problems.single.isError, isTrue);
    expect(reading.problems.single.line, isNull);

    expect(readDocument('[1, 2]').problems.single.message, contains('object'));
  });

  test('an instance of a prefab nobody wrote is refused by name', () {
    final reading = readDocument(
      sampleLevel.replaceFirst(
        '"prefab": "lamp_post" } },',
        '"prefab": "lamp_pots" } },',
      ),
    );
    expect(reading.level, isNull);
    expect('${reading.problems}', contains('lamp_pots'));
  });

  test('the sample level draws: its brushes, a marker an entity, its lamp', () {
    final device = cpuTestDevice(width: 16, height: 9).device;
    final level = readDocument(sampleLevel).level!;
    final scene = playgroundScene(level, device);
    final markers = scene.meshes.where(
      (MeshNode m) => level.entities.any((e) => (e.name ?? e.type) == m.name),
    );
    expect(markers, hasLength(7));
    expect(scene.meshes.length, greaterThan(7), reason: 'no brushes drawn');
    expect(scene.lights, hasLength(1), reason: 'the level brought its lamp');
  });

  test('a prefab with no light of its own is lit by a sun', () {
    final device = cpuTestDevice(width: 16, height: 9).device;
    final scene = playgroundScene(readDocument(samplePrefab).level!, device);
    expect(scene.lights.map((LightNode l) => l.name), <String?>['sun']);
  });

  test('an entity type is one colour, the same every time', () {
    expect(markerColor('lamp'), markerColor('lamp'));
    expect(markerColor('lamp'), isNot(markerColor('post')));
  });
}
