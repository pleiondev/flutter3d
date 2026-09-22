/// `ux-10`: three keymap presets over one tool table.
///
///     flutter test test/keymap_test.dart
///
/// **What this row is really about is collisions.** The review's own §4.3
/// lays out a keyboard where `A` is "add a box" in object mode so select-all
/// is bound nowhere there, `F` is "flip normals" so nothing frames the
/// selection, and `Delete` does nothing at all. Every one of those is a key
/// spent on the wrong thing rather than a key missing, and the only way to
/// keep three tables honest about that is to ask them.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [keymap] binds [action] to a key with this trigger.
bool binds(
  Keymap keymap,
  ModelerAction action,
  LogicalKeyboardKey trigger, {
  bool meta = false,
  bool control = false,
  bool alt = false,
  bool shift = false,
}) => keymap
    .forAction(action)
    .whereType<SingleActivator>()
    .any(
      (SingleActivator it) =>
          it.trigger == trigger &&
          it.meta == meta &&
          it.control == control &&
          it.alt == alt &&
          it.shift == shift,
    );

/// The key [keymap] arms [toolId] with — `SingleActivator` has no value
/// equality, so a test compares the trigger and the modifiers it cares
/// about rather than the object.
LogicalKeyboardKey? triggerOf(Keymap keymap, String toolId) =>
    (keymap.forTool(toolId) as SingleActivator?)?.trigger;

void main() {
  group('no preset binds one key to two things', () {
    for (final KeymapPreset preset in KeymapPreset.values) {
      for (final bool apple in <bool>[true, false]) {
        test('${preset.id}${apple ? ' on a Mac' : ''}', () {
          final Keymap keymap = keymapFor(preset, apple: apple);

          // Mutation: leave `object.add` on `A` and bind select-all to `A`
          // too, which is what the application had. This names the pair.
          expect(
            keymapCollisions(keymap),
            isEmpty,
            reason: 'two things answer to one key',
          );
        });
      }
    }
  });

  group('the holes the review found are filled, in every preset', () {
    for (final KeymapPreset preset in KeymapPreset.values) {
      final Keymap mac = keymapFor(preset, apple: true);
      final Keymap pc = keymapFor(preset, apple: false);

      test('${preset.id}: a save key exists at all', () {
        // There was none. A modeller without one is a modeller people lose
        // work in, and no amount of autosave makes "save now" unnecessary.
        expect(
          binds(mac, ModelerAction.save, LogicalKeyboardKey.keyS, meta: true),
          isTrue,
        );
        expect(
          binds(pc, ModelerAction.save, LogicalKeyboardKey.keyS, control: true),
          isTrue,
        );
      });

      test('${preset.id}: Delete and Backspace both delete', () {
        // Neither was bound: the only way to delete was `X`, which is one
        // school's answer and nobody else's — and is a letter a hand lands
        // on by accident while reaching for a modal axis.
        expect(
          binds(mac, ModelerAction.delete, LogicalKeyboardKey.delete),
          isTrue,
        );
        expect(
          binds(mac, ModelerAction.delete, LogicalKeyboardKey.backspace),
          isTrue,
        );
      });

      test('${preset.id}: something frames the selection', () {
        expect(mac.forAction(ModelerAction.frameSelection), isNotEmpty);
        expect(mac.forAction(ModelerAction.frameAll), isNotEmpty);
      });

      test('${preset.id}: Tab goes between object and mesh', () {
        expect(
          binds(mac, ModelerAction.toggleObjectMesh, LogicalKeyboardKey.tab),
          isTrue,
        );
      });

      test('${preset.id}: Space plays and pauses', () {
        expect(
          binds(mac, ModelerAction.playPause, LogicalKeyboardKey.space),
          isTrue,
        );
      });

      test('${preset.id}: the numpad sets the three standard views', () {
        expect(mac.forAction(ModelerAction.viewFront), isNotEmpty);
        expect(mac.forAction(ModelerAction.viewSide), isNotEmpty);
        expect(mac.forAction(ModelerAction.viewTop), isNotEmpty);
      });

      test('${preset.id}: select-all is reachable', () {
        expect(mac.forAction(ModelerAction.selectAll), isNotEmpty);
      });
    }
  });

  group('what a preset actually changes', () {
    test('the tool school moves the transforms onto W, E and R', () {
      final Keymap tools = keymapFor(KeymapPreset.toolKeys, apple: true);

      expect(triggerOf(tools, 'object.move'), LogicalKeyboardKey.keyW);
      expect(triggerOf(tools, 'object.rotate'), LogicalKeyboardKey.keyE);
      expect(triggerOf(tools, 'object.scale'), LogicalKeyboardKey.keyR);
      // And extrude gives `E` up rather than fighting rotate for it —
      // which is the collision the presets exist to let both sides win.
      expect(triggerOf(tools, 'mesh.extrude'), LogicalKeyboardKey.keyE);
      expect((tools.forTool('mesh.extrude')! as SingleActivator).shift, isTrue);
    });

    test('the modal school leaves them where this application had them', () {
      final Keymap modal = keymapFor(KeymapPreset.modalKeys, apple: true);

      expect(triggerOf(modal, 'object.move'), LogicalKeyboardKey.keyG);
      expect(triggerOf(modal, 'mesh.extrude'), LogicalKeyboardKey.keyE);
    });

    test('and every preset knows every tool on the rail', () {
      for (final KeymapPreset preset in KeymapPreset.values) {
        final Keymap keymap = keymapFor(preset, apple: true);
        for (final ModelerMode mode in ModelerMode.values) {
          for (final ModelerTool tool in toolsFor(mode)) {
            // Mutation: build a preset as a hand-written table instead of
            // an override over the one in `tools.dart`. A tool added there
            // then has no key in two of the three presets, silently.
            expect(
              keymap.forTool(tool.id),
              isNotNull,
              reason: '${tool.id} has no key under ${preset.id}',
            );
          }
        }
      }
    });
  });

  group('flip normals is off F', () {
    test('because F is what frames, everywhere else in the field', () {
      for (final KeymapPreset preset in KeymapPreset.values) {
        final Keymap keymap = keymapFor(preset, apple: true);

        // Mutation: leave it on `F`. The collision check above then names
        // it against frameSelection in the two presets that bind `F`, and
        // in the third the letter is simply spent on an operation somebody
        // runs a handful of times a model.
        expect(triggerOf(keymap, 'mesh.flip'), LogicalKeyboardKey.keyN);
        expect((keymap.forTool('mesh.flip')! as SingleActivator).alt, isTrue);
      }
    });
  });
}
