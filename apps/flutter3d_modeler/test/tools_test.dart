/// `ui-40d`'s own row: `AnimationSubmode`, the tools each of its four
/// values answers with, and the tool-id space they share with every other
/// mode and sub-mode.
///
///     flutter test test/tools_test.dart
library;

import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnimationSubmode', () {
    test('the four values are digit1 through digit4, in enum order', () {
      expect(AnimationSubmode.pose.shortcut, LogicalKeyboardKey.digit1);
      expect(AnimationSubmode.weights.shortcut, LogicalKeyboardKey.digit2);
      expect(AnimationSubmode.retarget.shortcut, LogicalKeyboardKey.digit3);
      expect(AnimationSubmode.morphs.shortcut, LogicalKeyboardKey.digit4);
    });
  });

  group('toolsFor(ModelerMode.animation, animation: …)', () {
    test('pose gets select, key and deleteKey', () {
      final ids = <String>[
        for (final ModelerTool t in toolsFor(
          ModelerMode.animation,
          animation: AnimationSubmode.pose,
        ))
          t.id,
      ];
      expect(ids, <String>['pose.select', 'pose.key', 'pose.deleteKey']);
    });

    test('weights gets paint, assign, mirror and normalize', () {
      final ids = <String>[
        for (final ModelerTool t in toolsFor(
          ModelerMode.animation,
          animation: AnimationSubmode.weights,
        ))
          t.id,
      ];
      expect(ids, <String>[
        'weights.paint',
        'weights.assign',
        'weights.mirror',
        'weights.normalize',
      ]);
    });

    test('retarget gets import, autoMap and apply', () {
      final ids = <String>[
        for (final ModelerTool t in toolsFor(
          ModelerMode.animation,
          animation: AnimationSubmode.retarget,
        ))
          t.id,
      ];
      expect(ids, <String>[
        'retarget.import',
        'retarget.autoMap',
        'retarget.apply',
      ]);
    });

    test('morphs gets add, key and delete', () {
      final ids = <String>[
        for (final ModelerTool t in toolsFor(
          ModelerMode.animation,
          animation: AnimationSubmode.morphs,
        ))
          t.id,
      ];
      expect(ids, <String>['morphs.add', 'morphs.key', 'morphs.delete']);
    });

    test('left null, answers empty — nobody has told the rail which of the '
        'four yet', () {
      expect(toolsFor(ModelerMode.animation).isEmpty, isTrue);
    });
  });

  test('every animation tool id is unique across the whole tool-id space, not '
      'just within animation mode', () {
    final seen = <String>{};
    for (final ModelerMode mode in ModelerMode.values) {
      for (final ModelerTool tool in toolsFor(mode)) {
        expect(seen.add(tool.id), isTrue, reason: '${tool.id} repeats');
      }
    }
    for (final AnimationSubmode submode in AnimationSubmode.values) {
      for (final ModelerTool tool in toolsFor(
        ModelerMode.animation,
        animation: submode,
      )) {
        expect(seen.add(tool.id), isTrue, reason: '${tool.id} repeats');
      }
    }
    expect(seen, isNotEmpty);
  });

  test(
    'every id in kStrokeTools is a real tool id, the weights sub-mode\'s own',
    () {
      final everyId = <String>{
        for (final ModelerMode mode in ModelerMode.values)
          for (final ModelerTool tool in toolsFor(mode)) tool.id,
        for (final AnimationSubmode submode in AnimationSubmode.values)
          for (final ModelerTool tool in toolsFor(
            ModelerMode.animation,
            animation: submode,
          ))
            tool.id,
      };
      expect(kStrokeTools, isNotEmpty);
      for (final String id in kStrokeTools) {
        expect(everyId, contains(id), reason: '$id is not a real tool id');
      }
    },
  );
}
