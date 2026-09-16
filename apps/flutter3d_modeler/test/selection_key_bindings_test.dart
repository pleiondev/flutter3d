import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/selection_key_bindings.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

const _addBox = ModelerTool(
  id: 'object.add',
  label: 'Add a box',
  about: 'Puts a new box at the origin.',
  icon: Icons.add_box_outlined,
  shortcut: LogicalKeyboardKey.keyA,
  group: 'create',
);

const _extrude = ModelerTool(
  id: 'mesh.extrude',
  label: 'Extrude',
  about: 'Pulls new geometry out of the picked faces.',
  icon: Icons.expand,
  shortcut: LogicalKeyboardKey.keyE,
  group: 'mesh',
);

void main() {
  group("view-24n's own acceptance", () {
    test('A selects all when no tool in this mode already claims that key', () {
      var calls = 0;
      final bindings = selectionKeyBindings(
        tools: const <ModelerTool>[_extrude],
        onSelectAll: () => calls++,
        onSelectNone: () {},
        onInvertSelection: () {},
      );
      final activator = bindings.keys.firstWhere(
        (a) => a == const SingleActivator(LogicalKeyboardKey.keyA),
      );
      bindings[activator]!();
      expect(calls, 1);
    });

    test(
      'A is left for object.add in object mode, not offered for select-all',
      () {
        final bindings = selectionKeyBindings(
          tools: const <ModelerTool>[_addBox],
          onSelectAll: () => fail('select-all must not be bound here'),
          onSelectNone: () {},
          onInvertSelection: () {},
        );
        expect(
          bindings.keys,
          isNot(contains(const SingleActivator(LogicalKeyboardKey.keyA))),
        );
      },
    );

    test('Alt+A clears the selection regardless of which tools are active', () {
      var calls = 0;
      final bindings = selectionKeyBindings(
        tools: const <ModelerTool>[_addBox],
        onSelectAll: () {},
        onSelectNone: () => calls++,
        onInvertSelection: () {},
      );
      bindings[const SingleActivator(LogicalKeyboardKey.keyA, alt: true)]!();
      expect(calls, 1);
    });

    test(
      'Ctrl+I inverts the selection regardless of which tools are active',
      () {
        var calls = 0;
        final bindings = selectionKeyBindings(
          tools: const <ModelerTool>[_addBox],
          onSelectAll: () {},
          onSelectNone: () {},
          onInvertSelection: () => calls++,
        );
        bindings[const SingleActivator(
          LogicalKeyboardKey.keyI,
          control: true,
        )]!();
        expect(calls, 1);
      },
    );
  });
}
