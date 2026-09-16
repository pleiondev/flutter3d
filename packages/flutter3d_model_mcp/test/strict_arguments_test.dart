/// `ux-43`: an argument that is wrong is refused by name, and every number a
/// tool takes says what it is a number of.
///
/// **A wrong argument used to be a silent one.** `select {ids: [1]}` was
/// accepted, did nothing, and answered "nothing selected"; the caller had
/// spelled `objects` wrong and had no way to find that out. And a field
/// called `size` with no unit beside it is a field an agent has to guess at —
/// metres, centimetres, or whatever the last model happened to be in.
///
///     dart test test/strict_arguments_test.dart
library;

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

/// A field whose own name already says what its number is: an id, an index,
/// or the object a call is aimed at.
///
/// **Exempt because the name is the unit.** "How many of what" is the
/// question this whole check exists to answer, and `clipIndex` answers it
/// before the description starts. `size`, `margin`, `factor` and `angle` do
/// not, which is the point.
bool _namesItsOwnUnit(String field) {
  final String name = field.toLowerCase();
  return name == 'object' ||
      name == 'objects' ||
      name == 'id' ||
      name == 'ids' ||
      name.endsWith('id') ||
      name.endsWith('ids') ||
      name.endsWith('index') ||
      name.endsWith('indices');
}

/// What a number can be a number *of*. A numeric field whose description
/// carries none of these is a field somebody has to guess at.
const List<String> _units = <String>[
  'metre',
  'radian',
  'degree',
  'second',
  'fps',
  'frame',
  'pixel',
  'percent',
  'fraction',
  '0..1',
  '0 and 1',
  'id',
  'ids',
  'index',
  'indices',
  'row',
  'slot',
  'count',
  'how many',
  'times',
  'level',
  'weight',
  'proportion',
  'multiplier',
  'scale',
  'version',
  'port',
  'seed',
  'unitless',
  'no unit',
  // A track's own units depend on what it animates, and saying so is an
  // answer: `describe`'s own track rows say which.
  'own units',
  'direction',
];

/// Every tool this server offers, including the ones that draw.
List<Tool> _tools() => <Tool>[
  for (final OfferedTool<ModelSession, Answer> it in modelTools) it.tool,
];

Iterable<(String, String, Schema)> _numericFields(Tool tool) sync* {
  final Map<String, Schema> properties =
      tool.inputSchema.properties ?? const <String, Schema>{};
  for (final MapEntry<String, Schema> field in properties.entries) {
    final Map<String, Object?> raw = field.value as Map<String, Object?>;
    final Object? type = raw['type'];
    if (type == 'number' || type == 'integer') {
      yield (tool.name, field.key, field.value);
    } else if (type == 'array') {
      final Object? items = raw['items'];
      final Object? itemType = items is Map ? items['type'] : null;
      if (itemType == 'number' || itemType == 'integer') {
        yield (tool.name, field.key, field.value);
      }
    }
  }
}

void main() {
  group('ux-43: every number says what it is a number of', () {
    test('no numeric field is left without a unit', () {
      final naked = <String>[];
      for (final Tool tool in _tools()) {
        for (final (String name, String field, Schema schema)
            in _numericFields(tool)) {
          if (_namesItsOwnUnit(field)) continue;
          final String said =
              ((schema as Map<String, Object?>)['description'] as String? ?? '')
                  .toLowerCase();
          if (_units.any(said.contains)) continue;
          naked.add('$name.$field');
        }
      }
      // Mutation: let a number go without saying what it counts. `size` in
      // what, `margin` in what, `angle` in degrees or radians — every one of
      // those is a call an agent makes twice.
      expect(
        naked,
        isEmpty,
        reason:
            '${naked.length} numeric fields say no unit: ${naked.join(', ')}',
      );
    });
  });

  group('ux-43: a wrong argument is refused by name', () {
    Tool named(String name) =>
        _tools().firstWhere((Tool it) => it.name == name);

    test('a key the tool does not take names itself, and what it does take',
        () {
      final String? refused = refuseArguments(named('select'), <String, Object?>{
        'ids': <int>[1],
      });
      expect(refused, isNotNull);
      expect(refused, contains('"ids"'));
      expect(refused, contains('objects'));
    });

    test('a value outside an enum lists the values, and quotes what came', () {
      final String? refused = refuseArguments(
        named('makeGameReady'),
        <String, Object?>{'profile': 'potato'},
      );
      expect(refused, contains('desktop'));
      expect(refused, contains('mobile'));
      expect(refused, contains('web'));
      expect(refused, contains('"potato"'));
    });

    test('a value of the wrong shape says which shape it wanted', () {
      final String? refused = refuseArguments(named('rename'), <String, Object?>{
        'id': 'one',
        'to': 'a name',
      });
      expect(refused, contains('"id"'));
      expect(refused, contains('whole number'));
      expect(refused, contains('"one"'));
    });

    test('a vector of the wrong length says how many it takes', () {
      final String? refused = refuseArguments(
        named('moveBy'),
        <String, Object?>{
          'by': <double>[1, 2],
        },
      );
      expect(refused, contains('"by"'));
      expect(refused, contains('3'));
    });

    test('a missing required argument says which one', () {
      final String? refused = refuseArguments(
        named('rename'),
        <String, Object?>{'id': 1},
      );
      expect(refused, isNotNull);
      expect(refused, contains('to'));
    });

    test('a call that is right is not refused', () {
      expect(
        refuseArguments(named('rename'), <String, Object?>{
          'id': 1,
          'to': 'a name',
        }),
        isNull,
      );
      // And a tool with no arguments takes none, rather than taking anything.
      expect(refuseArguments(named('list'), const <String, Object?>{}), isNull);
      expect(
        refuseArguments(named('list'), <String, Object?>{'id': 1}),
        contains('"id"'),
      );
    });
  });

  group('ux-43: one word for one thing', () {
    test('a cuboid is a box, whichever of its two names arrives', () {
      // The project format has written `cuboid` since the first file it
      // saved; the menu has said `box` for as long. An agent that read a
      // `.f3dproj` and asked for another one of those was refused for
      // spelling it the way the file did.
      final ModelCommand? read = modelCommandFromJson(<String, Object?>{
        'name': 'addPrimitive',
        'kind': 'cuboid',
      });
      expect(read, isA<AddPrimitive>());
      expect((read! as AddPrimitive).kind, 'box');
      // And the tool offers both, so it is discoverable rather than folklore.
      final Tool tool = _tools().firstWhere((Tool it) => it.name == 'addPrimitive');
      final Object? kind = tool.inputSchema.properties!['kind'];
      expect((kind! as Map<String, Object?>)['enum'], contains('cuboid'));
      expect((kind as Map<String, Object?>)['enum'], contains('box'));
    });
  });

  group('ux-43: a removal that shifts indices says so', () {
    test('every index-addressed removal warns in its own sentence', () {
      // Mutation: say "remove a material" and leave it there. The review
      // watched an agent delete material 1 and then paint with material 2,
      // which was a different material by then.
      for (final ModelCommand command in <ModelCommand>[
        const RemoveMaterial(1),
        const RemoveLight(1),
        const DeleteShape(id: 1, shapeIndex: 1),
        const RemoveShapeDriver(id: 1, index: 1),
        const RemoveJoint(skeletonIndex: 0, jointIndex: 1),
      ]) {
        expect(
          command.says,
          contains('shifts down by one'),
          reason: command.name,
        );
        expect(command.says, contains('1'), reason: command.name);
      }
    });
  });
}
