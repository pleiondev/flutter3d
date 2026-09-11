/// What this server offers, held against the list of commands that exists.
///
/// **The drift this file exists to stop has a shape.** `modelCommandNames`
/// lives beside the sealed hierarchy it describes, and a server keeping its
/// own copy is a server that silently cannot call the thirty-ninth command,
/// with nothing to say so until somebody asks for it. So the copy is checked,
/// both ways round, rather than trusted.
library;

import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

void main() {
  Set<String> namesOf(Iterable<ModelTool> tools) =>
      tools.map((ModelTool it) => it.name).toSet();

  test('every model command is offered as a tool', () {
    expect(
      modelCommandNames.toSet().difference(namesOf(modelTools)),
      isEmpty,
      reason:
          'a command exists that this server cannot call, and an agent '
          'reading tools/list has no way to find out that it is missing',
    );
  });

  test('every tool is a command or one of the named session verbs', () {
    const beyondTheCommands = <String>{
      'list',
      'select',
      'undo',
      'redo',
      'check',
      'save',
      'export',
      'import',
      'journal',
      'cleanup',
      'buildFrom',
      'inspect',
    };
    expect(
      namesOf(modelTools).difference(modelCommandNames.toSet()),
      beyondTheCommands,
      reason:
          'a tool was added or dropped that is not one of the document '
          'commands; say what it is here so the set stays a decision',
    );
  });

  test('no tool is offered twice', () {
    expect(namesOf(modelTools), hasLength(modelTools.length));
  });

  test('every tool describes itself in a sentence', () {
    for (final offered in modelTools) {
      expect(
        offered.tool.description,
        isNotNull,
        reason:
            '${offered.name} has no description, so nothing tells an agent '
            'when to call it',
      );
      expect(offered.tool.description!.length, greaterThan(40));
    }
  });

  test(
    'an argument the format cannot read is refused, not defaulted',
    () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final rename = modelTools.firstWhere(
        (ModelTool it) => it.name == 'rename',
      );
      final refused = await rename.run(session, <String, Object?>{
        'id': 'not a number',
        'to': 'anything',
      });
      expect(refused.did, isFalse);
      expect(refused.says, contains('cannot be read'));
    },
  );

  test('a command that runs is recorded, one that refuses is not', () async {
    final session = ModelSession(ModelHistory(const ModelProject()));
    final addPrimitive = modelTools.firstWhere(
      (ModelTool it) => it.name == 'addPrimitive',
    );
    final rename = modelTools.firstWhere((ModelTool it) => it.name == 'rename');

    await addPrimitive.run(session, <String, Object?>{'kind': 'box'});
    // Refuses: there is no object 99 yet.
    await rename.run(session, <String, Object?>{'id': 99, 'to': 'ghost'});

    final journaled = session.journal(
      '${Directory.systemTemp.createTempSync('model_mcp_test').path}/j.jsonl',
    );
    expect(journaled.says, contains('wrote 1 journal lines'));
  });

  group('refusals the skill quotes verbatim', () {
    ModelTool toolNamed(String name) =>
        modelTools.firstWhere((ModelTool it) => it.name == name);

    test('a mesh command on a still-parametric object', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'cylinder'});
      session.select(objects: <int>[1]);
      final refused = await toolNamed(
        'extrude',
      ).run(session, <String, Object?>{'distance': 1.0});
      expect(refused.did, isFalse);
      expect(refused.says, contains('Convert it to a mesh first'));
    });

    test('setParametric on a mesh that has been baked', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'box'});
      await toolNamed('bakeToMesh').run(session, <String, Object?>{'id': 1});
      final refused = await toolNamed('setParametric').run(
        session,
        <String, Object?>{
          'id': 1,
          'to': <String, Object?>{
            'shape': 'cuboid',
            'size': <double>[1, 1, 1],
          },
        },
      );
      expect(refused.did, isFalse);
      expect(refused.says, contains('a mesh has no parameters to set'));
    });

    test('save with no path and none from opening', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final refused = await toolNamed(
        'save',
      ).run(session, const <String, Object?>{});
      expect(refused.did, isFalse);
      expect(refused.says, contains('no path of its own'));
    });

    test(
      'removeMaterial or duplicateMaterial on a row that is not there',
      () async {
        final session = ModelSession(ModelHistory(const ModelProject()));
        final refused = await toolNamed(
          'removeMaterial',
        ).run(session, <String, Object?>{'index': 4});
        expect(refused.did, isFalse);
        expect(refused.says, contains('there is no material 4'));
      },
    );
  });
}
