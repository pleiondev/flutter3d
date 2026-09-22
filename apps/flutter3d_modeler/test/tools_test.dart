/// `ui-40d`'s own row: `AnimationSubmode`, the tools each of its four
/// values answers with, and the tool-id space they share with every other
/// mode and sub-mode. And `ux-18`'s own: a description for every one of them.
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
    test('pose gets select, key, deleteKey and autoRig', () {
      final ids = <String>[
        for (final ModelerTool t in toolsFor(
          ModelerMode.animation,
          animation: AnimationSubmode.pose,
        ))
          t.id,
      ];
      expect(ids, <String>[
        'pose.select',
        'pose.key',
        'pose.deleteKey',
        'pose.autoRig',
      ]);
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

  group("ux-18's own acceptance: a description for every tool", () {
    /// Every tool the application offers, once each — the object and mesh
    /// rails, and all four of the animation sub-mode rails.
    ///
    /// Built from [ModelerMode.values] rather than listed, so a mode that
    /// becomes [ModelerMode.ready] later arrives here without anybody
    /// remembering to add it: the whole point of a table nothing else
    /// duplicates.
    List<ModelerTool> everyTool() {
      final seen = <String>{};
      return <ModelerTool>[
        for (final ModelerMode mode in ModelerMode.values)
          for (final AnimationSubmode submode in AnimationSubmode.values)
            for (final ModelerTool tool in toolsFor(mode, animation: submode))
              if (seen.add(tool.id)) tool,
      ];
    }

    test('there are tools to check at all', () {
      // A guard on the guards below: a `toolsFor` that started answering
      // empty would make every one of them pass over nothing.
      expect(everyTool().length, greaterThan(30));
    });

    test('every tool has one', () {
      for (final ModelerTool tool in everyTool()) {
        expect(
          tool.about.trim(),
          isNotEmpty,
          reason: '${tool.id} has no description — see ModelerTool.about',
        );
      }
    });

    test('and it is a sentence rather than a second label', () {
      // **The failure this catches is mechanical, which is why a test can
      // catch it.** No test can judge prose; what the review actually found
      // was buttons added with a name and no explanation, and every check
      // here is something a sentence written in five seconds fails.
      for (final ModelerTool tool in everyTool()) {
        final String about = tool.about;
        expect(
          about,
          endsWith('.'),
          reason: '${tool.id}: a description is a sentence and ends in a stop',
        );
        expect(
          about.length,
          greaterThan(24),
          reason: '${tool.id}: too short to be saying anything',
        );
        // Long enough to explain, short enough for a tooltip and for the
        // phone sheet's own three-line row.
        expect(
          about.length,
          lessThan(150),
          reason: '${tool.id}: too long for a tooltip',
        );
        expect(
          about.toLowerCase(),
          isNot(equals('${tool.label.toLowerCase()}.')),
          reason: '${tool.id}: the description only repeats the label',
        );
        expect(
          about[0],
          equals(about[0].toUpperCase()),
          reason: '${tool.id}: a sentence starts with a capital',
        );
      }
    });

    test('no two tools are described the same way', () {
      final descriptions = <String, String>{};
      for (final ModelerTool tool in everyTool()) {
        final String? already = descriptions[tool.about];
        expect(
          already,
          isNull,
          reason:
              '${tool.id} and $already share a description, so at least one '
              'of them is not being explained',
        );
        descriptions[tool.about] = tool.id;
      }
    });

    test('and none of them names a key, which a person can rebind', () {
      // `keymap.dart` lets every one of these be rebound, and the rail
      // already prints the live binding beside the name. A sentence naming a
      // letter would be the one part of the tooltip that can go stale.
      for (final ModelerTool tool in everyTool()) {
        expect(
          tool.about.toLowerCase(),
          isNot(contains('press ')),
          reason: '${tool.id}: the live shortcut is already in the tooltip',
        );
      }
    });
  });
}
